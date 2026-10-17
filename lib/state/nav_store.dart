import 'package:flutter/foundation.dart';

import 'package:checkpoint/app/nav_tab.dart';

/// Which bottom-navigation tab is showing. Kept apart from the data stores so a
/// tab switch rebuilds the shell, not every screen.
class NavStore extends ChangeNotifier {
  int _index = NavTab.home;

  int get index => _index;

  void select(int i) {
    if (i == _index) return;
    _index = i;
    notifyListeners();
  }
}
