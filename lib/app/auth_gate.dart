import 'package:flutter/material.dart';

import 'package:checkpoint/state/auth_store.dart';
import 'package:checkpoint/state/store_scope.dart';
import 'package:checkpoint/theme/palette.dart';
import 'package:checkpoint/widgets/empty_state.dart';

/// Read-only overlay. The child stays mounted underneath, so the Library's
/// TabController and scroll state survive logging in and out.
class AuthGate extends StatelessWidget {
  const AuthGate({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final loggedIn = context.watch<AuthStore>().isLoggedIn;
    return Stack(children: [
      Positioned.fill(child: child),
      if (!loggedIn)
        Positioned.fill(
          child: ColoredBox(
            color: Palette.background.withValues(alpha: 0.94),
            child: SafeArea(
              child: EmptyState(
                icon: Icons.lock_outline_rounded,
                title: 'Log in to track games',
                message: 'Log in to build your library, log your hours and search every game on IGDB.',
                actionLabel: 'Log in',
                onAction: () => logIn(context),
              ),
            ),
          ),
        ),
    ]);
  }
}

/// What the "Log in" buttons call: starts Google sign-in and, when it didn't
/// work (cancelled, no browser, a misconfigured client), says why. [AuthStore]
/// only throws, so without this a failed sign-in looks like a dead button.
Future<void> logIn(BuildContext context) async {
  final auth = context.read<AuthStore>();
  final messenger = ScaffoldMessenger.of(context);
  try {
    await auth.logIn();
  } catch (e) {
    debugPrint('Sign-in failed: $e');
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(auth.messageFor(e))));
  }
}
