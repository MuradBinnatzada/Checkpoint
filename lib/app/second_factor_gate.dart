import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show AuthException;

import 'package:checkpoint/services/connection_failure.dart';
import 'package:checkpoint/services/mfa_recovery_failure.dart';
import 'package:checkpoint/state/auth_store.dart';
import 'package:checkpoint/state/store_scope.dart';
import 'package:checkpoint/theme/palette.dart';
import 'package:checkpoint/widgets/one_time_code_field.dart';

/// Covers the whole app with [SecondFactorScreen] while the account that just
/// signed in still owes its two-factor code ([AuthStore.needsSecondFactor]),
/// however it signed in. It wraps the app's Navigator (MaterialApp.builder),
/// so no screen or sheet that was open shows over it. The app stays mounted
/// underneath, signed out, hidden from taps, focus and screen readers.
class SecondFactorGate extends StatelessWidget {
  const SecondFactorGate({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final waiting = context.watch<AuthStore>().needsSecondFactor;
    return Stack(
      fit: StackFit.expand,
      children: [
        ExcludeFocus(
          excluding: waiting,
          child: Offstage(offstage: waiting, child: child),
        ),
        // Its own Navigator: above the app's, the prompt has no Overlay for
        // the text field and the tooltips otherwise. The app's Navigator keeps
        // MaterialApp's HeroController to itself.
        if (waiting)
          HeroControllerScope.none(
            child: Navigator(
              onGenerateRoute: (settings) => MaterialPageRoute<void>(
                settings: settings,
                builder: (_) => const SecondFactorScreen(),
              ),
            ),
          ),
      ],
    );
  }
}

/// Asks for the code from the authenticator app after a sign-in, or signs out.
/// A wrong code says why under the field, worded by [AuthStore.messageFor].
/// "Use a backup code" takes one of the account's backup codes instead, which
/// signs in and turns two-factor authentication off
/// ([AuthStore.redeemBackupCode]); a snack bar says so once the app shows.
class SecondFactorScreen extends StatefulWidget {
  const SecondFactorScreen({super.key});

  @override
  State<SecondFactorScreen> createState() => _SecondFactorScreenState();
}

class _SecondFactorScreenState extends State<SecondFactorScreen> {
  final _code = TextEditingController();
  final _backupCode = TextEditingController();
  bool _usingBackupCode = false;
  bool _verifying = false;
  bool _signingOut = false;
  String? _error;

  bool get _busy => _verifying || _signingOut;

  @override
  void dispose() {
    _code.dispose();
    _backupCode.dispose();
    super.dispose();
  }

  void _switchField() {
    if (_busy) return;
    _code.clear();
    _backupCode.clear();
    setState(() {
      _usingBackupCode = !_usingBackupCode;
      _error = null;
    });
  }

  Future<void> _verify() async {
    if (_usingBackupCode) return _redeem();
    if (_busy) return;
    if (_code.text.length != OneTimeCodeField.length) {
      setState(
        () => _error = 'Enter the 6-digit code from your authenticator app.',
      );
      return;
    }
    final auth = context.read<AuthStore>();
    setState(() {
      _verifying = true;
      _error = null;
    });
    try {
      // Once it is right, the gate takes this screen away.
      await auth.verifySecondFactor(_code.text);
    } catch (e) {
      debugPrint('The two-factor code was not accepted: $e');
      if (!mounted) return;
      _code.clear();
      setState(() => _error = _messageFor(auth, e));
    } finally {
      if (mounted) setState(() => _verifying = false);
    }
  }

  Future<void> _redeem() async {
    if (_busy) return;
    // Read as the server reads it (supabase/functions/_shared/recovery_codes.ts),
    // so a typo is caught here without using up one of the few tries an hour.
    final typed = _backupCode.text.replaceAll(RegExp(r'[\s-]'), '');
    if (typed.length != _BackupCodeField.length) {
      setState(
        () => _error = 'Enter one of your backup codes: 10 letters and digits.',
      );
      return;
    }
    final auth = context.read<AuthStore>();
    final messenger = ScaffoldMessenger.of(context);
    setState(() {
      _verifying = true;
      _error = null;
    });
    try {
      // Once it is used, the gate takes this screen away.
      await auth.redeemBackupCode(_backupCode.text);
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(
            duration: Duration(seconds: 10),
            content: Text(
              'Signed in with a backup code. Two-factor authentication is off '
              'now: turn it on again in Settings > Security.',
            ),
          ),
        );
    } catch (e) {
      debugPrint('The backup code was not accepted: $e');
      if (mounted) setState(() => _error = backupCodeMessage(e));
    } finally {
      if (mounted) setState(() => _verifying = false);
    }
  }

  Future<void> _signOut() async {
    if (_busy) return;
    final auth = context.read<AuthStore>();
    setState(() {
      _signingOut = true;
      _error = null;
    });
    try {
      await auth.logOut();
    } catch (e) {
      debugPrint('Signing out from the two-factor prompt failed: $e');
      if (mounted) setState(() => _error = _messageFor(auth, e));
    } finally {
      if (mounted) setState(() => _signingOut = false);
    }
  }

  static String _messageFor(AuthStore auth, Object e) =>
      e is! AuthException && isConnectionFailure(e)
      ? 'Could not reach the server. Check your connection and try again.'
      : auth.messageFor(e);

  @override
  Widget build(BuildContext context) {
    final email = context.watch<AuthStore>().waitingEmail;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(32),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 400),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Center(
                    child: Container(
                      width: 72,
                      height: 72,
                      decoration: const BoxDecoration(
                        color: Palette.surfaceHigh,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.phonelink_lock_rounded,
                        color: Palette.accent,
                        size: 32,
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'Two-factor authentication',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    _usingBackupCode
                        ? 'Enter one of the backup codes you saved when you '
                              'turned on two-factor authentication'
                              '${email == null ? '' : ' for $email'}. Using '
                              'one signs you in and turns two-factor '
                              'authentication off, so you can set it up again.'
                        : 'Open your authenticator app and enter the code it '
                              'shows for Checkpoint'
                              '${email == null ? '' : ' ($email)'}.',
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Palette.muted, height: 1.35),
                  ),
                  const SizedBox(height: 20),
                  if (_usingBackupCode)
                    _BackupCodeField(
                      key: const ValueKey('backup-code'),
                      controller: _backupCode,
                      enabled: !_busy,
                      errorText: _error,
                      onSubmit: _verify,
                    )
                  else
                    OneTimeCodeField(
                      key: const ValueKey('app-code'),
                      controller: _code,
                      enabled: !_busy,
                      autofocus: true,
                      errorText: _error,
                      onSubmit: _verify,
                    ),
                  const SizedBox(height: 16),
                  FilledButton(
                    onPressed: _busy ? null : _verify,
                    child: _verifying ? const _Spinner() : const Text('Verify'),
                  ),
                  const SizedBox(height: 8),
                  TextButton(
                    onPressed: _busy ? null : _switchField,
                    child: Text(
                      _usingBackupCode
                          ? 'Use your authenticator app'
                          : 'Use a backup code',
                    ),
                  ),
                  TextButton(
                    onPressed: _busy ? null : _signOut,
                    child: _signingOut
                        ? const _Spinner()
                        : const Text('Sign out'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// One of the account's backup codes, `7K3QD-M9XHT` (letters and digits,
/// with or without the dash). [onSubmit] runs on the keyboard's done key.
class _BackupCodeField extends StatelessWidget {
  const _BackupCodeField({
    super.key,
    required this.controller,
    required this.onSubmit,
    required this.enabled,
    this.errorText,
  });

  /// Characters in a code, without the dash.
  static const length = 10;

  final TextEditingController controller;
  final VoidCallback onSubmit;
  final bool enabled;
  final String? errorText;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      enabled: enabled,
      autofocus: true,
      // No suggestions or autocorrect on Android's keyboard.
      keyboardType: TextInputType.visiblePassword,
      textCapitalization: TextCapitalization.characters,
      textInputAction: TextInputAction.done,
      autocorrect: false,
      enableSuggestions: false,
      textAlign: TextAlign.center,
      style: const TextStyle(
        fontFamily: 'monospace',
        fontSize: 20,
        fontWeight: FontWeight.w700,
        letterSpacing: 2,
      ),
      inputFormatters: [
        FilteringTextInputFormatter.allow(RegExp(r'[A-Za-z0-9 -]')),
        LengthLimitingTextInputFormatter(20),
      ],
      decoration: InputDecoration(
        labelText: 'Backup code',
        hintText: 'XXXXX-XXXXX',
        errorText: errorText,
        errorMaxLines: 3,
      ),
      onSubmitted: (_) => onSubmit(),
    );
  }
}

class _Spinner extends StatelessWidget {
  const _Spinner();

  @override
  Widget build(BuildContext context) => const SizedBox(
    width: 18,
    height: 18,
    child: CircularProgressIndicator(strokeWidth: 2),
  );
}
