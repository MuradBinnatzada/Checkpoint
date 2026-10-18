import 'package:flutter/foundation.dart';

import 'package:checkpoint/app/nav_tab.dart';
import 'package:checkpoint/models/filter_options.dart';

/// Which bottom-navigation tab is showing. Kept apart from the data stores so a
/// tab switch rebuilds the shell, not every screen.
///
/// It can also carry filters to the Discover tab (a tag tapped on a game's
/// screen): [switchTab] holds them until [SearchStore], which listens here,
/// takes them with [takeDiscoverFilters]. This store knows no other store.
class NavStore extends ChangeNotifier {
  int _index = NavTab.home;
  FilterOptions? _discoverFilters;

  int get index => _index;

  void select(int i) => switchTab(i);

  /// Shows [tab]. With [discoverFilters], [tab] must be [NavTab.search], and the
  /// Discover tab is opened on those filters instead of what it showed, even when
  /// it is the tab already showing.
  void switchTab(int tab, {FilterOptions? discoverFilters}) {
    assert(discoverFilters == null || tab == NavTab.search);
    if (tab == _index && discoverFilters == null) return;
    _index = tab;
    _discoverFilters = discoverFilters;
    notifyListeners();
  }

  /// The filters the last [switchTab] asked the Discover tab to open on, or null.
  /// Handed over once: the next call answers null.
  FilterOptions? takeDiscoverFilters() {
    final filters = _discoverFilters;
    _discoverFilters = null;
    return filters;
  }
}
