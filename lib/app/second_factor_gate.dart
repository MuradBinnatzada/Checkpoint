import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show AuthException;

import 'package:checkpoint/services/connection_failure.dart';
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
class SecondFactorScreen extends StatefulWidget {
  const SecondFactorScreen({super.key});

  @override
  State<SecondFactorScreen> createState() => _SecondFactorScreenState();
}

class _SecondFactorScreenState extends State<SecondFactorScreen> {
  final _code = TextEditingController();
  bool _verifying = false;
  bool _signingOut = false;
  String? _error;

  bool get _busy => _verifying || _signingOut;

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  Future<void> _verify() async {
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
                    'Open your authenticator app and enter the code it shows '
                    'for Checkpoint${email == null ? '' : ' ($email)'}.',
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Palette.muted, height: 1.35),
                  ),
                  const SizedBox(height: 20),
                  OneTimeCodeField(
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

class _Spinner extends StatelessWidget {
  const _Spinner();

  @override
  Widget build(BuildContext context) => const SizedBox(
    width: 18,
    height: 18,
    child: CircularProgressIndicator(strokeWidth: 2),
  );
}
