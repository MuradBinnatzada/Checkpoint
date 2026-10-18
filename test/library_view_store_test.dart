import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:checkpoint/app/nav_tab.dart';
import 'package:checkpoint/models/game.dart';
import 'package:checkpoint/models/game_attributes.dart';
import 'package:checkpoint/state/auth_store.dart';
import 'package:checkpoint/state/library_attributes_store.dart';
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

  test('the platform filter offers only platforms the library is on', () {
    // testGame: released on PC and PS5, played on PC.
    expect(view.filterOptions(library), [GamePlatform.pc]);
    expect(view.filterOptions(const []), isEmpty);

    // Not yet played anywhere: counted for where it was released.
    final unplayed = testGame('d', status: null);
    expect(view.filterOptions([unplayed]), [GamePlatform.pc, GamePlatform.ps5]);
  });

  test('the active platform filter stays in the menu so it can be seen', () {
    view.setPlatformFilter(GamePlatform.mobile);

    expect(view.filterOptions(library), [GamePlatform.pc, GamePlatform.mobile]);
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

  group('filters on what IGDB says about the games', () {
    late FakeRepository repo;
    late FakeAuthService authService;
    late AuthStore auth;
    late LibraryAttributesStore attributes;

    // Three games with details, one IGDB filled in with nothing, one never.
    final games = [
      testGame('a', title: 'Alpha', genres: ['RPG', 'Adventure']),
      testGame('b', title: 'Bravo', genres: ['Shooter']),
      testGame('c', title: 'Charlie', genres: ['RPG']),
      testGame('d', title: 'Delta', genres: ['RPG']),
      testGame('e', title: 'Echo', genres: ['RPG']),
    ];

    setUp(() async {
      debugPrint = (String? message, {int? wrapWidth}) {};
      SharedPreferences.setMockInitialValues({});
      repo = FakeRepository()
        ..libraryAttributes = {
          'a': const GameAttributes(
            themes: ['Horror', 'Fantasy'],
            gameModes: ['Single player'],
            developers: ['Studio One'],
            publishers: ['Pub'],
            engines: ['Unreal Engine 4'],
          ),
          'b': const GameAttributes(
            themes: ['Horror'],
            gameModes: ['Single player', 'Co-op'],
            perspectives: ['First person'],
            developers: ['Studio Two', 'Studio One'],
          ),
          'c': const GameAttributes(
            themes: ['Fantasy'],
            gameModes: ['Co-op'],
            perspectives: ['Third person'],
            publishers: ['Pub'],
          ),
          'd': const GameAttributes(), // looked up, IGDB has nothing
        };
      authService = FakeAuthService(testUser('u1'));
      auth = AuthStore(authService)..initialize();
      attributes = LibraryAttributesStore(repository: repo, auth: auth)
        ..initialize();
      view = LibraryViewStore(nav: nav, attributes: attributes);
      await attributes.ensureLoaded();
    });

    tearDown(() {
      debugPrint = debugPrintThrottled;
      view.dispose();
      attributes.dispose();
      auth.dispose();
    });

    List<String> shown() => titles(view.visible(games, null));

    test('nothing is filtered until a value is picked', () {
      expect(view.hasFilters, isFalse);
      expect(view.filterCount, 0);
      expect(shown(), ['Alpha', 'Bravo', 'Charlie', 'Delta', 'Echo']);
    });

    test('picking a value shows the games that have it, and only those', () {
      view.toggleFilter(GameAttribute.theme, 'Horror');

      expect(shown(), ['Alpha', 'Bravo']);
      expect(view.isFilterOn(GameAttribute.theme, 'Horror'), isTrue);
      expect(view.isFilterOn(GameAttribute.theme, 'Fantasy'), isFalse);
      expect(view.hasFilters, isTrue);
      expect(view.hasDetailFilters, isTrue);
    });

    test('several values of one attribute show games with any of them', () {
      view.toggleFilter(GameAttribute.theme, 'Horror');
      view.toggleFilter(GameAttribute.theme, 'Fantasy');

      expect(shown(), ['Alpha', 'Bravo', 'Charlie']);
      expect(view.filterValues(GameAttribute.theme), {'Horror', 'Fantasy'});
    });

    test('different attributes (and the platform) all have to match', () {
      view.toggleFilter(GameAttribute.theme, 'Horror');
      view.toggleFilter(GameAttribute.gameMode, 'Co-op');
      expect(shown(), ['Bravo']);

      view.toggleFilter(GameAttribute.theme, 'Horror'); // let go of it
      expect(shown(), ['Bravo', 'Charlie']);

      view.setPlatformFilter(GamePlatform.ps4); // nobody plays on PS4
      expect(shown(), isEmpty);
    });

    test('every IGDB attribute filters: perspective, engine, developer, publisher', () {
      view.toggleFilter(GameAttribute.perspective, 'First person');
      expect(shown(), ['Bravo']);
      view.clearFilters();

      view.toggleFilter(GameAttribute.engine, 'Unreal Engine 4');
      expect(shown(), ['Alpha']);
      view.clearFilters();

      view.toggleFilter(GameAttribute.developer, 'Studio One');
      expect(shown(), ['Alpha', 'Bravo']); // Bravo's second developer
      view.clearFilters();

      view.toggleFilter(GameAttribute.publisher, 'Pub');
      expect(shown(), ['Alpha', 'Charlie']);
    });

    test('the genre filter needs no IGDB details, they are on the game', () {
      view.toggleFilter(GameAttribute.genre, 'RPG');
      expect(shown(), ['Alpha', 'Charlie', 'Delta', 'Echo']); // Echo has no details

      view.toggleFilter(GameAttribute.genre, 'Shooter');
      expect(shown(), ['Alpha', 'Bravo', 'Charlie', 'Delta', 'Echo']);
      expect(view.hasDetailFilters, isFalse);
    });

    test('a game IGDB has no details for yet is left out of a filter on them', () {
      view.toggleFilter(GameAttribute.gameMode, 'Single player');

      expect(shown(), isNot(contains('Echo'))); // never filled in
      expect(shown(), isNot(contains('Delta'))); // filled in, with nothing
    });

    test('count matches what visible returns, filters included', () {
      view.toggleFilter(GameAttribute.theme, 'Fantasy');
      view.toggleFilter(GameAttribute.genre, 'RPG');

      expect(view.count(games, null), view.visible(games, null).length);
      expect(view.count(games, null), 2);
      expect(view.count(games, GameStatus.completed), 0);
    });

    test('options list only values some game has, most common first, with counts', () {
      final themes = view.attributeOptions(GameAttribute.theme, games);

      expect([for (final o in themes) (o.value, o.count)], [
        ('Fantasy', 2),
        ('Horror', 2),
      ]);
      expect(
        [for (final o in view.attributeOptions(GameAttribute.gameMode, games)) o.value],
        ['Co-op', 'Single player'], // 2 and 2: by name
      );
      expect(
        [for (final o in view.attributeOptions(GameAttribute.developer, games)) (o.value, o.count)],
        [('Studio One', 2), ('Studio Two', 1)],
      );
      expect(view.attributeOptions(GameAttribute.engine, const []), isEmpty);
      expect(
        view.attributeOptions(GameAttribute.engine, games).map((o) => o.value),
        ['Unreal Engine 4'], // only the engine some game of the library uses
      );
      expect(
        view.attributeOptions(GameAttribute.genre, games).map((o) => (o.value, o.count)),
        [('RPG', 4), ('Adventure', 1), ('Shooter', 1)],
      );
    });

    test('a value is counted once per game, however often the game lists it', () {
      final twice = [
        testGame('x', genres: ['RPG', 'RPG']),
      ];
      expect(view.attributeOptions(GameAttribute.genre, twice).single.count, 1);
    });

    test('a picked value stays in the options even when no game has it', () {
      view.toggleFilter(GameAttribute.theme, 'Sci-fi');

      final themes = view.attributeOptions(GameAttribute.theme, games);
      expect(themes.map((o) => o.value), contains('Sci-fi'));
      expect(themes.singleWhere((o) => o.value == 'Sci-fi').count, 0);
    });

    test('says how many games have no details yet', () {
      expect(view.gamesWithoutDetails(games), 1); // Echo; Delta was looked up
      expect(view.gamesWithoutDetails(const []), 0);
    });

    test('says nothing about missing details until they are loaded', () async {
      final fresh = LibraryAttributesStore(repository: repo, auth: auth)
        ..initialize();
      final other = LibraryViewStore(attributes: fresh);
      addTearDown(() {
        other.dispose();
        fresh.dispose();
      });

      expect(other.gamesWithoutDetails(games), isNull); // never asked

      // Without any attributes (another member's Library), it is never known.
      final plain = LibraryViewStore();
      addTearDown(plain.dispose);
      expect(plain.gamesWithoutDetails(games), isNull);
    });

    test('let go of one value, one attribute, or everything', () {
      view.toggleFilter(GameAttribute.theme, 'Horror');
      view.toggleFilter(GameAttribute.theme, 'Fantasy');
      view.toggleFilter(GameAttribute.gameMode, 'Co-op');
      view.setPlatformFilter(GamePlatform.pc);
      expect(view.filterCount, 4);

      view.toggleFilter(GameAttribute.theme, 'Horror');
      expect(view.filterCount, 3);

      view.clearFilter(GameAttribute.theme);
      expect(view.filterValues(GameAttribute.theme), isEmpty);
      expect(view.filterCount, 2);

      view.clearFilters();
      expect(view.hasFilters, isFalse);
      expect(view.platformFilter, isNull);
      expect(shown(), hasLength(5));
    });

    test('the values it hands out cannot be used to change the filters', () {
      view.toggleFilter(GameAttribute.theme, 'Horror');

      expect(() => view.filterValues(GameAttribute.theme).add('x'), throwsUnsupportedError);
      expect(view.filterValues(GameAttribute.theme), {'Horror'});
    });

    test('openTab clears the attribute filters with the platform filter', () {
      view.toggleFilter(GameAttribute.theme, 'Horror');
      view.setPlatformFilter(GamePlatform.pc);

      view.openTab(GameStatus.completed);

      expect(view.hasFilters, isFalse);
      expect(view.filterCount, 0);
      expect(nav.index, NavTab.library);
    });

    test('what was picked for one account is dropped when another signs in', () async {
      view.toggleFilter(GameAttribute.theme, 'Horror');
      view.toggleFilter(GameAttribute.genre, 'RPG');
      view.setPlatformFilter(GamePlatform.pc);

      authService.emit(testUser('u2'));
      await pumpEventQueue();

      expect(view.filterValues(GameAttribute.theme), isEmpty);
      expect(view.filterValues(GameAttribute.genre), isEmpty);
      expect(view.platformFilter, GamePlatform.pc); // as before: only the platform stays
    });

    test('listeners hear when the details arrive, so the lists are redrawn', () async {
      repo.libraryAttributes['e'] = const GameAttributes(themes: ['Horror']);
      view.toggleFilter(GameAttribute.theme, 'Horror');
      expect(shown(), ['Alpha', 'Bravo']);
      var notified = 0;
      view.addListener(() => notified++);

      attributes.markStale();
      await attributes.ensureLoaded();

      expect(notified, greaterThan(0));
      expect(shown(), ['Alpha', 'Bravo', 'Echo']);
    });

    test('a view without attributes (another member\'s Library) matches nothing on them', () {
      final plain = LibraryViewStore()..setPlatformFilter(GamePlatform.ps4);
      addTearDown(plain.dispose);

      expect(plain.count(games, null), 0);
      plain.toggleFilter(GameAttribute.theme, 'Horror');
      expect(plain.visible(games, null), isEmpty); // nothing can have it
    });
  });
}
