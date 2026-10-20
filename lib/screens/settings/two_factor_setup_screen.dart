import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show AuthException;
import 'package:url_launcher/url_launcher.dart' show LaunchMode, launchUrl;

import 'package:checkpoint/screens/settings/backup_codes_screen.dart';
import 'package:checkpoint/services/auth_service.dart' show TotpSetup;
import 'package:checkpoint/services/connection_failure.dart';
import 'package:checkpoint/services/mfa_recovery_failure.dart';
import 'package:checkpoint/state/auth_store.dart';
import 'package:checkpoint/state/store_scope.dart';
import 'package:checkpoint/theme/palette.dart';
import 'package:checkpoint/widgets/one_time_code_field.dart';
import 'package:checkpoint/widgets/qr_code_view.dart';

/// Opens [TwoFactorSetupScreen] (Settings > Security). True when two-factor
/// authentication was turned on.
Future<bool> setUpTwoFactor(BuildContext context) async =>
    await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        fullscreenDialog: true,
        builder: (_) => const TwoFactorSetupScreen(),
      ),
    ) ??
    false;

/// Turns two-factor authentication on: adds the account to an authenticator
/// app (a QR code, or the setup key typed in) and checks the first code it
/// shows. Leaving before that drops the unfinished setup, and nothing changes
/// for the account. Once it is on, it makes the account's backup codes and
/// shows them; leaving then keeps two-factor on, with or without codes.
/// Closes itself when the account it was opened for signs out.
class TwoFactorSetupScreen extends StatefulWidget {
  const TwoFactorSetupScreen({super.key});

  @override
  State<TwoFactorSetupScreen> createState() => _TwoFactorSetupScreenState();
}

class _TwoFactorSetupScreenState extends State<TwoFactorSetupScreen> {
  final _code = TextEditingController();
  late final AuthStore _auth;
  late final String? _userId;

  TotpSetup? _setup;
  String? _startError;
  String? _codeError;
  bool _confirming = false;
  bool _turnedOn = false;
  bool _closed = false;

  /// The backup codes made once it is on, or why they could not be.
  List<String>? _codes;
  String? _codesError;
  bool _makingCodes = false;

  /// An authenticator app on this device can take the otpauth link itself.
  static bool get _opensAuthenticatorLinks =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);

  @override
  void initState() {
    super.initState();
    _auth = context.read<AuthStore>();
    _userId = _auth.user?.id;
    _auth.addListener(_closeWhenSignedOut);
    unawaited(_start());
  }

  @override
  void dispose() {
    _auth.removeListener(_closeWhenSignedOut);
    final setup = _setup;
    if (setup != null && !_turnedOn) {
      unawaited(_auth.cancelTwoFactor(setup.factorId));
    }
    _code.dispose();
    super.dispose();
  }

  void _closeWhenSignedOut() {
    if (_auth.user?.id != _userId) _close();
  }

  void _close([bool turnedOn = false]) {
    if (_closed || !mounted) return;
    _closed = true;
    Navigator.of(context).pop(turnedOn);
  }

  Future<void> _start() async {
    setState(() => _startError = null);
    try {
      final setup = await _auth.enrollTwoFactor();
      if (!mounted) {
        unawaited(_auth.cancelTwoFactor(setup.factorId));
        return;
      }
      setState(() => _setup = setup);
    } catch (e) {
      debugPrint('Starting two-factor setup failed: $e');
      if (mounted) setState(() => _startError = _messageFor(e));
    }
  }

  Future<void> _confirm() async {
    final setup = _setup;
    if (setup == null || _confirming) return;
    if (_code.text.length != OneTimeCodeField.length) {
      setState(() => _codeError = 'Enter the 6-digit code the app shows.');
      return;
    }
    setState(() {
      _confirming = true;
      _codeError = null;
    });
    try {
      await _auth.confirmTwoFactor(setup.factorId, _code.text);
      _turnedOn = true;
      if (!mounted) return;
      setState(() => _confirming = false);
      await _makeCodes();
    } catch (e) {
      debugPrint('Confirming two-factor setup failed: $e');
      if (!mounted) return;
      _code.clear();
      setState(() {
        _confirming = false;
        _codeError = _messageFor(e);
      });
    }
  }

  /// Makes the backup codes for the account that just turned it on.
  Future<void> _makeCodes() async {
    setState(() {
      _makingCodes = true;
      _codesError = null;
    });
    try {
      final codes = await _auth.generateBackupCodes();
      if (mounted) setState(() => _codes = codes);
    } catch (e) {
      debugPrint('Making backup codes failed: $e');
      if (mounted) setState(() => _codesError = backupCodesMessage(e));
    } finally {
      if (mounted) setState(() => _makingCodes = false);
    }
  }

  void _showTurnedOn(ScaffoldMessengerState messenger) => messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Text(
          _codes == null
              ? 'Two-factor authentication is on. Make backup codes under '
                    'Settings > Security.'
              : 'Two-factor authentication is on',
        ),
      ),
    );

  /// Leaves once it is on: "I saved them", skipping the codes, or closing.
  void _finish() {
    if (_makingCodes) return;
    _showTurnedOn(ScaffoldMessenger.of(context));
    _close(true);
  }

  String _messageFor(Object e) => e is! AuthException && isConnectionFailure(e)
      ? 'Could not reach the server. Check your connection and try again.'
      : _auth.messageFor(e);

  Future<void> _copyKey(String secret) async {
    final messenger = ScaffoldMessenger.of(context);
    await Clipboard.setData(ClipboardData(text: secret));
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(const SnackBar(content: Text('Setup key copied')));
  }

  Future<void> _openInApp(String uri) async {
    final messenger = ScaffoldMessenger.of(context);
    var opened = false;
    try {
      opened = await launchUrl(
        Uri.parse(uri),
        mode: LaunchMode.externalApplication,
      );
    } catch (e) {
      debugPrint('Opening the authenticator link failed: $e');
    }
    if (opened) return;
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        const SnackBar(
          content: Text(
            'No authenticator app opened it. Enter the setup key in the app instead.',
          ),
        ),
      );
  }

  /// The key in groups of four, easier to type than one long run.
  static String _grouped(String secret) => [
    for (var i = 0; i < secret.length; i += 4)
      secret.substring(i, i + 4 > secret.length ? secret.length : i + 4),
  ].join(' ');

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_confirming && !_turnedOn,
      // Once it is on, closing is "done", and says so.
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && _turnedOn) _finish();
      },
      child: Scaffold(
        appBar: AppBar(title: const Text('Two-factor authentication')),
        body: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: _body(),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// The last step: two-factor is on, and these are the backup codes.
  Widget _codesBody() {
    final codes = _codes;
    final error = _codesError;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Icon(Icons.check_circle_rounded, color: context.palette.success),
            SizedBox(width: 10),
            Expanded(
              child: Text(
                'Two-factor authentication is on',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        const _Step(number: 3, text: 'Save your backup codes.'),
        const SizedBox(height: 12),
        if (codes != null)
          BackupCodesList(codes: codes, onDone: _finish)
        else if (error != null) ...[
          Text(error, style: const TextStyle(height: 1.4)),
          const SizedBox(height: 16),
          OutlinedButton(onPressed: _makeCodes, child: const Text('Try again')),
          const SizedBox(height: 8),
          TextButton(onPressed: _finish, child: const Text('Skip for now')),
        ] else
          const Padding(
            padding: EdgeInsets.all(32),
            child: Center(child: CircularProgressIndicator()),
          ),
      ],
    );
  }

  Widget _body() {
    if (_turnedOn) return _codesBody();
    final setup = _setup;
    final startError = _startError;
    if (startError != null) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(startError, textAlign: TextAlign.center),
          const SizedBox(height: 16),
          OutlinedButton(onPressed: _start, child: const Text('Try again')),
        ],
      );
    }
    if (setup == null) {
      return const Padding(
        padding: EdgeInsets.all(32),
        child: Center(child: CircularProgressIndicator()),
      );
    }

    final muted = TextStyle(color: context.palette.muted, height: 1.4);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Each time you sign in, Checkpoint will also ask for a code from an '
          'authenticator app such as Google Authenticator, Microsoft '
          'Authenticator or 1Password.',
          style: muted,
        ),
        const SizedBox(height: 20),
        const _Step(
          number: 1,
          text: 'Scan this QR code with your authenticator app.',
        ),
        const SizedBox(height: 12),
        Center(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: QrCodeView(
              data: setup.uri,
              label: 'QR code for your authenticator app',
            ),
          ),
        ),
        const SizedBox(height: 12),
        Text(
          "Can't scan it? Enter this setup key instead:",
          style: muted,
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            Expanded(
              child: SelectableText(
                _grouped(setup.secret),
                style: const TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 1,
                ),
              ),
            ),
            IconButton(
              tooltip: 'Copy setup key',
              icon: const Icon(Icons.copy_rounded, size: 20),
              onPressed: () => _copyKey(setup.secret),
            ),
          ],
        ),
        if (_opensAuthenticatorLinks)
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: () => _openInApp(setup.uri),
              icon: const Icon(Icons.open_in_new_rounded, size: 18),
              label: const Text('Open in authenticator app'),
            ),
          ),
        const SizedBox(height: 20),
        const _Step(
          number: 2,
          text: 'Enter the 6-digit code the app shows for Checkpoint.',
        ),
        const SizedBox(height: 12),
        OneTimeCodeField(
          controller: _code,
          enabled: !_confirming,
          errorText: _codeError,
          onSubmit: _confirm,
        ),
        const SizedBox(height: 16),
        FilledButton(
          onPressed: _confirming ? null : _confirm,
          child: _confirming
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Turn on'),
        ),
        const SizedBox(height: 12),
        Text(
          'Turning it on signs your account out on your other devices.',
          style: TextStyle(color: context.palette.muted, fontSize: 12.5, height: 1.4),
        ),
      ],
    );
  }
}

class _Step extends StatelessWidget {
  const _Step({required this.number, required this.text});

  final int number;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        CircleAvatar(
          radius: 11,
          backgroundColor: context.palette.surfaceHigh,
          child: Text(
            '$number',
            style: TextStyle(
              color: context.palette.accent,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(fontWeight: FontWeight.w600, height: 1.4),
          ),
        ),
      ],
    );
  }
}
