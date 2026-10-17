import 'package:flutter/foundation.dart';

import 'package:checkpoint/app/nav_tab.dart';
import 'package:checkpoint/models/game.dart';
import 'package:checkpoint/state/library_state.dart';
import 'package:checkpoint/state/nav_store.dart';

/// How the Library tab is arranged: grid or list, sort, platform filter and the
/// selected status tab. It is screen state only, with no data of its own, so
/// re-sorting rebuilds the Library tab and nothing that merely reads the games.
/// Hand [visible] / [count] the games from [LibraryStore].
///
/// Another member's Library screen makes its own instance, without a [NavStore]:
/// that one has no tab of the app to switch to, so [openTab] is the signed-in
/// member's only.
class LibraryViewStore extends ChangeNotifier {
  LibraryViewStore({this._nav});

  final NavStore? _nav;

  static final _epoch = DateTime.fromMillisecondsSinceEpoch(0);

  LibraryView _view = LibraryView.grid;
  SortField _sortField = SortField.dateAdded;
  bool _sortDescending = true;
  GamePlatform? _platformFilter;

  /// Selected status tab. `null` means "All" (the default).
  GameStatus? _selectedStatus;

  LibraryView get view => _view;
  SortField get sortField => _sortField;
  bool get sortDescending => _sortDescending;
  GamePlatform? get platformFilter => _platformFilter;

  /// Selected status, or `null` when "All" is selected.
  GameStatus? get selectedStatus => _selectedStatus;

  /// Tab index: 0 is the "All" tab, then one tab per [GameStatus].
  int get currentTabIndex => _selectedStatus == null
      ? 0
      : GameStatus.values.indexOf(_selectedStatus!) + 1;

  void setTabIndex(int i) {
    final next = i <= 0 ? null : GameStatus.values[i - 1];
    if (next == _selectedStatus) return;
    _selectedStatus = next;
    notifyListeners();
  }

  /// Jumps to the Library tab on [status] (`null` is "All"), clearing the
  /// platform filter. With [sortBy], also sorts by that field, highest first.
  void openTab(GameStatus? status, {SortField? sortBy}) {
    _selectedStatus = status;
    _platformFilter = null;
    if (sortBy != null) {
      _sortField = sortBy;
      _sortDescending = true;
    }
    notifyListeners();
    _nav?.select(NavTab.library);
  }

  void setView(LibraryView v) {
    _view = v;
    notifyListeners();
  }

  void setSort(SortField f) {
    if (f == _sortField) {
      _sortDescending = !_sortDescending;
    } else {
      _sortField = f;
      _sortDescending = true;
    }
    notifyListeners();
  }

  void setPlatformFilter(GamePlatform? p) {
    _platformFilter = p;
    notifyListeners();
  }

  bool _matchesPlatform(Game g) {
    final p = _platformFilter;
    if (p == null) return true;
    return _isOn(g, p);
  }

  /// A game counts for the platform it was played on, or, until that is chosen,
  /// for the platforms it was released on.
  static bool _isOn(Game g, GamePlatform p) =>
      g.playedOn == p || (g.playedOn == null && g.platforms.contains(p));

  /// The platforms the platform filter should offer: those at least one game of
  /// [library] is on, in [GamePlatform] order, so the menu never lists a platform
  /// that would only show an empty library. The active filter stays listed so it
  /// can still be seen and changed.
  List<GamePlatform> filterOptions(Iterable<Game> library) => [
    for (final p in GamePlatform.values)
      if (p == _platformFilter || library.any((g) => _isOn(g, p))) p,
  ];

  int _compare(Game a, Game b) {
    final c = switch (_sortField) {
      SortField.dateAdded => (a.dateAdded ?? _epoch).compareTo(
        b.dateAdded ?? _epoch,
      ),
      SortField.rating => a.rating.compareTo(b.rating),
      SortField.hoursPlayed => a.hoursPlayed.compareTo(b.hoursPlayed),
      SortField.releaseYear => a.releaseYear.compareTo(b.releaseYear),
    };
    if (c != 0) return _sortDescending ? -c : c;
    return a.title.compareTo(b.title);
  }

  /// The games of [library] with status [s], filtered by platform and sorted;
  /// pass `null` for every status ("All"). The platform filter applies either way.
  List<Game> visible(Iterable<Game> library, GameStatus? s) => [
    for (final g in library)
      if ((s == null || g.status == s) && _matchesPlatform(g)) g,
  ]..sort(_compare);

  /// How many games [visible] would return, without sorting them.
  int count(Iterable<Game> library, GameStatus? s) => library
      .where((g) => (s == null || g.status == s) && _matchesPlatform(g))
      .length;
}
