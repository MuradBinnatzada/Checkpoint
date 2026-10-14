import 'package:flutter/material.dart';

import 'package:checkpoint/app/auth_gate.dart';
import 'package:checkpoint/app/nav_tab.dart';
import 'package:checkpoint/screens/home/home_screen.dart';
import 'package:checkpoint/screens/library/library_screen.dart';
import 'package:checkpoint/screens/profile/profile_screen.dart';
import 'package:checkpoint/screens/search/search_screen.dart';
import 'package:checkpoint/sheets/quick_log_sheet.dart';
import 'package:checkpoint/state/store_scope.dart';

class AppShell extends StatelessWidget {
  const AppShell({super.key});

  static const _screens = <Widget>[
    HomeScreen(),
    SearchScreen(),
    AuthGate(child: LibraryScreen()),
    AuthGate(child: ProfileScreen()),
  ];

  @override
  Widget build(BuildContext context) {
    final store = context.store;
    final navIndex = store.currentBottomNavIndex;
    return PopScope(
      canPop: navIndex == NavTab.home,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) context.actions.setBottomNavIndex(NavTab.home);
      },
      child: Scaffold(
        body: IndexedStack(index: navIndex, children: _screens),
        floatingActionButton: navIndex == NavTab.home && store.isLoggedIn
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
            context.actions.setBottomNavIndex(i);
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
