import 'package:flutter/material.dart';

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
    final loggedIn = context.store.isLoggedIn;
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
                message: 'You can still browse and search. Log in to build your library and log your hours.',
                actionLabel: 'Log in',
                onAction: context.actions.logIn,
              ),
            ),
          ),
        ),
    ]);
  }
}
