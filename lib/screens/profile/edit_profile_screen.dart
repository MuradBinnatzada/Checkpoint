import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

import 'package:checkpoint/state/profile_store.dart';
import 'package:checkpoint/state/store_scope.dart';
import 'package:checkpoint/theme/palette.dart';
import 'package:checkpoint/utils/formatters.dart';

class EditProfileScreen extends StatefulWidget {
  const EditProfileScreen({super.key});

  @override
  State<EditProfileScreen> createState() => _EditProfileScreenState();
}

enum _HandleStatus { idle, checking, available, taken, unknown }

class _EditProfileScreenState extends State<EditProfileScreen> {
  static const _nameMax = 40;
  // Auto-generated handles can be up to 24 chars, so existing users must still
  // pass validation without having to shorten theirs.
  static const _handleMin = 3;
  static const _handleMax = 24;
  static const _bioMax = 160;
  static const _bioMaxLines = 4;
  static const _debounceDelay = Duration(milliseconds: 500);
  static const _errorColor = Colors.redAccent;
  static const _errorStyle = TextStyle(color: _errorColor);
  static final _handlePattern = RegExp(r'^[a-z0-9_]+$');

  final _formKey = GlobalKey<FormState>();
  final _handleFieldKey = GlobalKey<FormFieldState<String>>();
  final _name = TextEditingController();
  final _handle = TextEditingController();
  final _bio = TextEditingController();
  final _picker = ImagePicker();

  bool _initialized = false;
  bool _saving = false;

  String _profileName = '';
  String _originalHandle = '';

  // Live handle check: debounced, with a sequence number so a slow response
  // for an older value can never overwrite the result for the current one.
  Timer? _debounce;
  int _checkSeq = 0;
  _HandleStatus _handleStatus = _HandleStatus.idle;
  String _checkedHandle = '';

  // Avatar: [_avatarUrl] is what's previewed; it's only sent on save when the
  // user actually picked a new photo in this session.
  String? _avatarUrl;
  bool _avatarChanged = false;
  bool _uploadingAvatar = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Seed the fields once from the current profile; later store updates must
    // not overwrite what the user is typing.
    if (_initialized) return;
    _initialized = true;
    final profile = context.watch<ProfileStore>().profile;
    _profileName = profile.name;
    _originalHandle = profile.handle
        .replaceFirst(RegExp(r'^@+'), '')
        .toLowerCase();
    _name.text = profile.name;
    _handle.text = _originalHandle;
    _bio.text = profile.bio ?? '';
    _avatarUrl = profile.avatarUrl;
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _name.dispose();
    _handle.dispose();
    _bio.dispose();
    super.dispose();
  }

  // ---- Validation ----------------------------------------------------------

  String? _validateName(String? value) {
    final v = (value ?? '').trim();
    if (v.isEmpty) return 'Enter a display name';
    if (v.length > _nameMax) return 'Use $_nameMax characters or fewer';
    return null;
  }

  /// Synchronous format rules only (no network).
  String? _handleFormatError(String v) {
    if (v.isEmpty) return 'Enter a username';
    if (v.length < _handleMin) return 'Use at least $_handleMin characters';
    if (v.length > _handleMax) return 'Use $_handleMax characters or fewer';
    if (!_handlePattern.hasMatch(v)) {
      return 'Letters, numbers and underscores only';
    }
    return null;
  }

  String? _validateHandle(String? value) {
    final v = (value ?? '').trim().toLowerCase();
    final formatError = _handleFormatError(v);
    if (formatError != null) return formatError;
    // Result of the async availability check, surfaced through the validator
    // so it renders as the field's regular inline error.
    if (_handleStatus == _HandleStatus.taken && v == _checkedHandle) {
      return '@$v is already taken';
    }
    return null;
  }

  void _revalidateHandle() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _handleFieldKey.currentState?.validate();
    });
  }

  void _onHandleChanged(String value) {
    _debounce?.cancel();
    _checkSeq++; // discard any in-flight check for an older value
    final handle = value.trim();

    // Nothing to look up: unchanged, or not a well-formed handle yet.
    if (handle == _originalHandle || _handleFormatError(handle) != null) {
      setState(() => _handleStatus = _HandleStatus.idle);
      return;
    }

    setState(() => _handleStatus = _HandleStatus.checking);
    _debounce = Timer(_debounceDelay, () => _checkHandle(handle));
  }

  Future<void> _checkHandle(String handle) async {
    if (!mounted) return;
    final actions = context.read<ProfileStore>();
    final seq = ++_checkSeq;
    try {
      final available = await actions.isHandleAvailable(handle);
      if (!mounted || seq != _checkSeq) return;
      setState(() {
        _checkedHandle = handle;
        _handleStatus = available
            ? _HandleStatus.available
            : _HandleStatus.taken;
      });
    } catch (e, st) {
      debugPrint('Handle availability check failed: $e\n$st');
      if (!mounted || seq != _checkSeq) return;
      setState(() => _handleStatus = _HandleStatus.unknown);
    }
    _revalidateHandle();
  }

  // ---- Avatar --------------------------------------------------------------

  Future<void> _pickAvatar() async {
    if (_uploadingAvatar || _saving) return;
    final actions = context.read<ProfileStore>();
    final messenger = ScaffoldMessenger.of(context);

    try {
      final picked = await _picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 1024,
        maxHeight: 1024,
        imageQuality: 85,
      );
      if (picked == null || !mounted) return; // cancelled

      setState(() => _uploadingAvatar = true);
      final url = await actions.uploadAvatar(picked);
      if (!mounted) return;
      setState(() {
        _avatarUrl = url;
        _avatarChanged = true;
        _uploadingAvatar = false;
      });
    } catch (e, st) {
      debugPrint('Avatar pick/upload failed: $e\n$st');
      if (!mounted) return;
      setState(() => _uploadingAvatar = false);
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(
            content: Text('Couldn\'t update your photo. Please try again.'),
          ),
        );
    }
  }

  // ---- Save ----------------------------------------------------------------

  Future<void> _save() async {
    if (_saving || _uploadingAvatar) return;
    _debounce?.cancel();
    if (!(_formKey.currentState?.validate() ?? false)) return;
    FocusScope.of(context).unfocus();

    final actions = context.read<ProfileStore>();
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final handle = _handle.text.trim();

    setState(() => _saving = true);

    // Save can be tapped before the debounced check has run (or finished), so
    // confirm availability here for a changed handle.
    final alreadyVerified =
        _handleStatus == _HandleStatus.available && _checkedHandle == handle;
    if (handle != _originalHandle && !alreadyVerified) {
      _checkSeq++; // drop any in-flight debounced check
      try {
        final available = await actions.isHandleAvailable(handle);
        if (!mounted) return;
        if (!available) {
          setState(() {
            _saving = false;
            _checkedHandle = handle;
            _handleStatus = _HandleStatus.taken;
          });
          _revalidateHandle();
          return;
        }
      } catch (e, st) {
        // Couldn't verify. Carry on: the unique constraint rejects duplicates.
        debugPrint('Handle availability check failed: $e\n$st');
        if (!mounted) return;
      }
    }

    final error = await actions.updateProfile(
      name: _name.text,
      handle: handle,
      bio: _bio.text,
      avatarUrl: _avatarChanged ? _avatarUrl : null,
    );
    if (!mounted) return;

    if (error == null) {
      navigator.pop();
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(const SnackBar(content: Text('Profile updated')));
    } else {
      setState(() => _saving = false);
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(error)));
    }
  }

  // ---- UI ------------------------------------------------------------------

  Widget _buildAvatarPicker(BuildContext context) {
    const radius = 52.0;
    final current = _avatarUrl;
    final url = current != null && current.isNotEmpty ? current : null;
    final canTap = !_uploadingAvatar && !_saving;

    return Semantics(
      button: true,
      label: 'Change profile photo',
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: canTap ? _pickAvatar : null,
        child: Stack(
          children: [
            ListenableBuilder(
              listenable: _name,
              builder: (_, _) {
                final typed = _name.text.trim();
                return CircleAvatar(
                  radius: radius,
                  backgroundColor: Palette.accent,
                  // Drawn over the initials; if it fails to load, the
                  // initials underneath stay visible.
                  foregroundImage: url != null ? CachedNetworkImageProvider(url) : null,
                  onForegroundImageError: url != null
                      ? (error, stackTrace) {}
                      : null,
                  child: Text(
                    initials(typed.isEmpty ? _profileName : typed),
                    style: TextStyle(
                      color: Palette.onAccent,
                      fontWeight: FontWeight.w800,
                      fontSize: radius * 0.76,
                    ),
                  ),
                );
              },
            ),
            if (_uploadingAvatar)
              const Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.black54,
                  ),
                  child: Center(
                    child: SizedBox(
                      width: 26,
                      height: 26,
                      child: CircularProgressIndicator(strokeWidth: 2.5),
                    ),
                  ),
                ),
              ),
            Positioned(
              right: 0,
              bottom: 0,
              child: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Palette.accent,
                  border: Border.all(
                    color: Theme.of(context).scaffoldBackgroundColor,
                    width: 3,
                  ),
                ),
                child: Icon(
                  Icons.camera_alt_rounded,
                  size: 16,
                  color: Palette.onAccent,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget? _handleSuffix() => switch (_handleStatus) {
    _HandleStatus.checking => const Padding(
      padding: EdgeInsets.all(14),
      child: SizedBox(
        width: 18,
        height: 18,
        child: CircularProgressIndicator(strokeWidth: 2),
      ),
    ),
    _HandleStatus.available => Icon(
      Icons.check_circle_rounded,
      color: Palette.success,
    ),
    _HandleStatus.taken => const Icon(Icons.cancel_rounded, color: _errorColor),
    _ => null,
  };

  String _handleHelper() => switch (_handleStatus) {
    _HandleStatus.checking => 'Checking availability…',
    _HandleStatus.available => '@$_checkedHandle is available',
    _HandleStatus.unknown =>
      'Couldn\'t check availability. We\'ll verify when you save.',
    _ => 'Letters, numbers and underscores',
  };

  @override
  Widget build(BuildContext context) {
    final busy = _saving || _uploadingAvatar;

    return Scaffold(
      appBar: AppBar(title: const Text('Edit Profile')),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
              children: [
                Center(child: _buildAvatarPicker(context)),
                const SizedBox(height: 24),
                Form(
                  key: _formKey,
                  autovalidateMode: AutovalidateMode.onUserInteraction,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      TextFormField(
                        controller: _name,
                        enabled: !_saving,
                        textInputAction: TextInputAction.next,
                        textCapitalization: TextCapitalization.words,
                        maxLength: _nameMax,
                        decoration: const InputDecoration(
                          labelText: 'Display name',
                          floatingLabelBehavior: FloatingLabelBehavior.always,
                          counterText: '',
                          errorStyle: _errorStyle,
                        ),
                        validator: _validateName,
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        key: _handleFieldKey,
                        controller: _handle,
                        enabled: !_saving,
                        textInputAction: TextInputAction.next,
                        autocorrect: false,
                        enableSuggestions: false,
                        maxLength: _handleMax,
                        inputFormatters: [
                          FilteringTextInputFormatter.allow(
                            RegExp(r'[A-Za-z0-9_]'),
                          ),
                          const _LowerCaseFormatter(),
                        ],
                        decoration: InputDecoration(
                          labelText: 'Username',
                          // Always floated so the fixed "@" is visible even
                          // while the field is empty and unfocused.
                          floatingLabelBehavior: FloatingLabelBehavior.always,
                          prefixText: '@',
                          prefixStyle: const TextStyle(
                            color: Palette.accent,
                            fontWeight: FontWeight.w700,
                          ),
                          suffixIcon: _handleSuffix(),
                          helperText: _handleHelper(),
                          helperMaxLines: 2,
                          helperStyle: _handleStatus == _HandleStatus.available
                              ? TextStyle(color: Palette.success)
                              : null,
                          errorStyle: _errorStyle,
                          counterText: '',
                        ),
                        validator: _validateHandle,
                        onChanged: _onHandleChanged,
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: _bio,
                        enabled: !_saving,
                        keyboardType: TextInputType.multiline,
                        textInputAction: TextInputAction.newline,
                        textCapitalization: TextCapitalization.sentences,
                        minLines: 1,
                        maxLines: _bioMaxLines,
                        maxLength: _bioMax,
                        inputFormatters: const [_MaxLinesFormatter(_bioMaxLines)],
                        decoration: const InputDecoration(
                          labelText: 'Bio',
                          // Same always-floated label as the Username field,
                          // so all three labels render at the same size.
                          floatingLabelBehavior: FloatingLabelBehavior.always,
                          hintText: 'Write your lore...',
                        ),
                      ),
                      const SizedBox(height: 28),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton(
                          onPressed: busy ? null : _save,
                          child: _saving
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Text('Save'),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Forces input to lowercase. Runs after the allow-list filter, so only ASCII
/// is left and the selection offsets stay valid.
class _LowerCaseFormatter extends TextInputFormatter {
  const _LowerCaseFormatter();

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) => newValue.copyWith(text: newValue.text.toLowerCase());
}

/// Rejects edits that would push the text past [maxLines] hard line breaks.
class _MaxLinesFormatter extends TextInputFormatter {
  const _MaxLinesFormatter(this.maxLines);

  final int maxLines;

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final lines = '\n'.allMatches(newValue.text).length + 1;
    return lines > maxLines ? oldValue : newValue;
  }
}