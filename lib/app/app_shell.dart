import 'package:flutter/material.dart';

import 'package:checkpoint/app/auth_gate.dart';
import 'package:checkpoint/app/nav_tab.dart';
import 'package:checkpoint/app/new_password_screen.dart';
import 'package:checkpoint/screens/home/home_screen.dart';
import 'package:checkpoint/screens/library/library_screen.dart';
import 'package:checkpoint/screens/profile/profile_screen.dart';
import 'package:checkpoint/screens/search/search_screen.dart';
import 'package:checkpoint/sheets/quick_log_sheet.dart';
import 'package:checkpoint/state/auth_store.dart';
import 'package:checkpoint/state/library_store.dart';
import 'package:checkpoint/state/nav_store.dart';
import 'package:checkpoint/state/profile_store.dart';
import 'package:checkpoint/state/store_scope.dart';

class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  static const _screens = <Widget>[
    HomeScreen(),
    SearchScreen(),
    AuthGate(child: LibraryScreen()),
    AuthGate(child: ProfileScreen()),
  ];

  late final AuthStore _auth;
  late final LibraryStore _library;
  late final ProfileStore _profile;

  /// The new password screen a reset link opened is showing.
  bool _askingForPassword = false;

  @override
  void initState() {
    super.initState();
    _auth = context.read<AuthStore>();
    _library = context.read<LibraryStore>();
    _profile = context.read<ProfileStore>();
    _auth.addListener(_askForNewPassword);
    _library.addListener(_showNotices);
    _profile.addListener(_showNotices);
    // The link may have been handled before the shell was built.
    WidgetsBinding.instance.addPostFrameCallback((_) => _askForNewPassword());
  }

  @override
  void dispose() {
    _auth.removeListener(_askForNewPassword);
    _library.removeListener(_showNotices);
    _profile.removeListener(_showNotices);
    super.dispose();
  }

  /// A password reset link signed the user in: asks for the new password over
  /// whatever is open. Closing the screen without saving puts it off.
  Future<void> _askForNewPassword() async {
    if (!mounted || _askingForPassword || !_auth.isRecoveringPassword) return;
    _askingForPassword = true;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        fullscreenDialog: true,
        builder: (_) => const NewPasswordScreen(afterReset: true),
      ),
    );
    _askingForPassword = false;
    _auth.dismissPasswordRecovery();
  }

  /// Tells the user when an edit could not be saved (or was kept for later), from
  /// whichever screen they are on. (This used to be left in the store and only
  /// turned up as the Library tab's error screen.)
  void _showNotices() {
    _show(_library.notice, _library.clearNotice);
    _show(_profile.notice, _profile.clearNotice);
  }

  void _show(String? message, VoidCallback clear) {
    if (message == null) return;
    clear();
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final navIndex = context.watch<NavStore>().index;
    final isLoggedIn = context.watch<AuthStore>().isLoggedIn;
    return PopScope(
      canPop: navIndex == NavTab.home,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) context.read<NavStore>().select(NavTab.home);
      },
      child: Scaffold(
        body: IndexedStack(index: navIndex, children: _screens),
        floatingActionButton: navIndex == NavTab.home && isLoggedIn
            ? FloatingActionButton.extended(
                onPressed: () => showQuickLogSheet(context),
                icon: const Icon(Icons.add_rounded),
                label: const Text('Log Game'),
              )
            : null,
        bottomNavigationBar: NavigationBar(
          selectedIndex: navIndex,
          onDestinationSelected: (i) {
            FocusManager.instance.primaryFocus?.unfocus();
            context.read<NavStore>().select(i);
          },
          destinations: const [
            NavigationDestination(icon: Icon(Icons.home_outlined), selectedIcon: Icon(Icons.home_rounded), label: 'Home'),
            NavigationDestination(icon: Icon(Icons.search_rounded), selectedIcon: Icon(Icons.search_rounded), label: 'Search'),
            NavigationDestination(icon: Icon(Icons.collections_bookmark_outlined), selectedIcon: Icon(Icons.collections_bookmark_rounded), label: 'My Library'),
            NavigationDestination(icon: Icon(Icons.person_outline_rounded), selectedIcon: Icon(Icons.person_rounded), label: 'Profile'),
          ],
        ),
      ),
    );
  }
}
