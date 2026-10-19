import 'package:flutter/material.dart';

import 'package:checkpoint/app/sign_in_panel.dart';
import 'package:checkpoint/state/auth_store.dart';
import 'package:checkpoint/state/store_scope.dart';
import 'package:checkpoint/theme/palette.dart';

/// Sign-in overlay. The child stays mounted underneath, so the Library's
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
            child: const SafeArea(
              child: SignInPanel(
                icon: Icons.lock_outline_rounded,
                title: 'Log in to track games',
                message: 'Log in to build your library, log your hours and search every game on IGDB.',
              ),
            ),
          ),
        ),
    ]);
  }
}

/// What the "Log in" buttons call: opens the sign-in screen (Google, or an
/// email and password), which closes itself once someone is signed in. A
/// failed attempt says why there, so a sign-in never looks like a dead button.
Future<void> logIn(BuildContext context) => Navigator.of(context).push(
      MaterialPageRoute<void>(fullscreenDialog: true, builder: (_) => const SignInScreen()),
    );
