import 'package:flutter_test/flutter_test.dart';

import 'package:checkpoint/app/nav_tab.dart';
import 'package:checkpoint/models/game.dart';
import 'package:checkpoint/state/library_state.dart';
import 'package:checkpoint/state/library_view_store.dart';
import 'package:checkpoint/state/nav_store.dart';

import 'support/fakes.dart';

void main() {
  late NavStore nav;
  late LibraryViewStore view;

  setUp(() {
    nav = NavStore();
    view = LibraryViewStore(nav: nav);
  });

  final library = [
    testGame('a', title: 'Alpha', hours: 5),
    testGame('b', title: 'Bravo', hours: 50, status: GameStatus.completed),
    testGame('c', title: 'Charlie', hours: 20),
  ];

  List<String> titles(List<Game> games) => [for (final g in games) g.title];

  test('lists a status tab sorted, and "All" with every status', () {
    view.setSort(SortField.hoursPlayed); // a new field starts highest first

    expect(titles(view.visible(library, null)), ['Bravo', 'Charlie', 'Alpha']);
    expect(titles(view.visible(library, GameStatus.playing)), ['Charlie', 'Alpha']);

    view.setSort(SortField.hoursPlayed); // the same field flips the direction
    expect(titles(view.visible(library, null)), ['Alpha', 'Charlie', 'Bravo']);
  });

  test('count matches what visible returns, filter included', () {
    expect(view.count(library, null), 3);
    expect(view.count(library, GameStatus.completed), 1);

    view.setPlatformFilter(GamePlatform.ps4);
    expect(view.count(library, null), view.visible(library, null).length);
    expect(view.count(library, null), 0);

    view.setPlatformFilter(GamePlatform.pc);
    expect(view.count(library, null), 3);
  });

  test('tab index 0 is "All", then one tab per status', () {
    expect(view.currentTabIndex, 0);
    expect(view.selectedStatus, isNull);

    view.setTabIndex(GameStatus.values.indexOf(GameStatus.completed) + 1);
    expect(view.selectedStatus, GameStatus.completed);

    view.setTabIndex(0);
    expect(view.selectedStatus, isNull);
  });

  test('openTab selects the tab, clears the platform filter and switches to the Library', () {
    view.setPlatformFilter(GamePlatform.pc);

    view.openTab(GameStatus.completed, sortBy: SortField.hoursPlayed);

    expect(view.selectedStatus, GameStatus.completed);
    expect(view.platformFilter, isNull);
    expect(view.sortField, SortField.hoursPlayed);
    expect(view.sortDescending, isTrue);
    expect(nav.index, NavTab.library);
  });
}
