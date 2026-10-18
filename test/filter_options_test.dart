import 'package:flutter_test/flutter_test.dart';

import 'package:checkpoint/models/filter_options.dart';
import 'package:checkpoint/models/game.dart';
import 'package:checkpoint/models/game_attributes.dart';
import 'package:checkpoint/services/game_api_service.dart';

void main() {
  group('FilterOptions', () {
    test('a value picked twice is let go of, and nothing picked is none', () {
      final horror = FilterOptions.none.toggle(GameAttribute.theme, 'Horror');
      expect(horror.valuesOf(GameAttribute.theme), {'Horror'});
      expect(horror.isEmpty, isFalse);

      final again = horror.toggle(GameAttribute.theme, 'Horror');
      expect(again, FilterOptions.none);
      expect(again.attributes, isEmpty); // no empty set left behind
    });

    test('counts every value and platform, and the year range once', () {
      final filters = FilterOptions(
        attributes: {
          GameAttribute.genre: ['Shooter', 'Puzzle'],
          GameAttribute.gameMode: ['Single player'],
        },
        platforms: [GamePlatform.pc],
        years: const YearRange(from: 2010, to: 2019),
      );
      expect(filters.count, 5);
      expect(filters.hasDetailFilters, isTrue); // the game mode
      expect(
        FilterOptions.only(GameAttribute.genre, 'Shooter').hasDetailFilters,
        isFalse,
      );
    });

    test('the sort is an order, not a filter: clearing keeps it', () {
      final sorted = FilterOptions.none.withSort(DiscoverSort.newest);
      expect(sorted.isEmpty, isTrue);
      expect(sorted.count, 0);

      final cleared = sorted.togglePlatform(GamePlatform.ps5).cleared();
      expect(cleared.isEmpty, isTrue);
      expect(cleared.sort, DiscoverSort.newest);
    });

    test('equal whatever order things were picked in', () {
      final a = FilterOptions.none
          .toggle(GameAttribute.theme, 'Horror')
          .toggle(GameAttribute.theme, 'Fantasy')
          .togglePlatform(GamePlatform.pc)
          .togglePlatform(GamePlatform.ps5);
      final b = FilterOptions(
        platforms: [GamePlatform.ps5, GamePlatform.pc],
        attributes: {
          GameAttribute.theme: ['Fantasy', 'Horror'],
        },
      );
      expect(a, b);
      expect(a.hashCode, b.hashCode);
      expect(a, isNot(b.withSort(DiscoverSort.oldest)));
      expect(a, isNot(b.togglePlatform(GamePlatform.pc)));
    });

    test('what it holds cannot be changed from outside', () {
      final source = {'Horror'};
      final filters = FilterOptions(attributes: {GameAttribute.theme: source});
      source.add('Fantasy');
      expect(filters.valuesOf(GameAttribute.theme), {'Horror'});
      expect(
        () => filters.valuesOf(GameAttribute.theme).add('x'),
        throwsUnsupportedError,
      );
      expect(
        () => filters.platforms.add(GamePlatform.pc),
        throwsUnsupportedError,
      );
    });
  });

  group('YearRange', () {
    test('takes in its years, both ends included, and no unknown year', () {
      const nineties = YearRange.decade(1990);
      expect(nineties.contains(1990), isTrue);
      expect(nineties.contains(1999), isTrue);
      expect(nineties.contains(2000), isFalse);
      expect(nineties.contains(0), isFalse); // the year is not known

      expect(const YearRange(to: 1999).contains(1985), isTrue);
      expect(const YearRange(from: 2020).contains(2026), isTrue);
      expect(YearRange.any.contains(0), isTrue); // not filtered at all
    });

    test('says what it covers', () {
      expect(const YearRange.decade(1990).label, '1990s');
      expect(const YearRange(from: 2015, to: 2015).label, '2015');
      expect(const YearRange(from: 2010, to: 2015).label, '2010–2015');
      expect(const YearRange(from: 2010).label, '2010 or later');
      expect(const YearRange(to: 1999).label, 'Up to 1999');
      expect(YearRange.any.label, '');
    });
  });

  group('CatalogTags', () {
    test('finds a tag by the name IGDB gives it, whatever the case', () {
      expect(CatalogTags.find(GameAttribute.theme, 'Horror')?.igdbId, 19);
      expect(
        CatalogTags.find(GameAttribute.genre, ' role-playing (rpg) ')?.igdbId,
        12,
      );
      expect(
        CatalogTags.find(GameAttribute.gameMode, 'Single player')?.label,
        'Single-player',
      );
      expect(
        CatalogTags.find(GameAttribute.genre, 'Horror'),
        isNull,
      ); // a theme, not a genre
      expect(CatalogTags.find(GameAttribute.engine, 'Unreal Engine'), isNull);
    });

    test('names a value by its short label, or by itself', () {
      expect(
        CatalogTags.labelOf(GameAttribute.genre, 'Role-playing (RPG)'),
        'RPG',
      );
      expect(CatalogTags.labelOf(GameAttribute.theme, 'Horror'), 'Horror');
      expect(
        CatalogTags.labelOf(GameAttribute.developer, 'Studio One'),
        'Studio One',
      );
    });

    test('no list repeats an id or a name', () {
      for (final attribute in CatalogTags.discoverable) {
        final tags = CatalogTags.of(attribute);
        expect(
          {for (final t in tags) t.igdbId},
          hasLength(tags.length),
          reason: '$attribute',
        );
        expect(
          {for (final t in tags) t.name.toLowerCase()},
          hasLength(tags.length),
          reason: '$attribute',
        );
      }
    });
  });

  group('GameApiService.filtersToWire', () {
    test('sends nothing for no filters', () {
      expect(GameApiService.filtersToWire(FilterOptions.none), isEmpty);
      expect(
        GameApiService.filtersToWire(
          FilterOptions.none.withSort(DiscoverSort.topRated),
        ),
        isEmpty,
      );
    });

    test('sends IGDB ids per kind, every IGDB platform of a platform, and the years', () {
      final wire = GameApiService.filtersToWire(
        FilterOptions(
          attributes: {
            GameAttribute.genre: ['Role-playing (RPG)', 'Adventure'],
            GameAttribute.theme: ['Horror'],
            GameAttribute.gameMode: ['Co-operative'],
          },
          platforms: [GamePlatform.pc, GamePlatform.ps5],
          years: const YearRange(from: 2010, to: 2019),
        ),
      );
      expect(wire, {
        'genres': unorderedEquals([12, 31]),
        'themes': [19],
        'game_modes': [3],
        'platforms': unorderedEquals([6, 14, 3, 13, 167, 390]),
        'year': {'from': 2010, 'to': 2019},
      });
    });

    test(
      'leaves out what IGDB has no id for, and an open end of the years',
      () {
        final wire = GameApiService.filtersToWire(
          FilterOptions(
            attributes: {
              GameAttribute.theme: ['Not a theme'],
              GameAttribute.developer: ['Studio One'],
            },
            platforms: [GamePlatform.steamDeck],
            years: const YearRange(to: 1999),
          ),
        );
        expect(wire, {
          'year': {'to': 1999},
        });
      },
    );

    test('Discover offers only platforms IGDB releases games on', () {
      final platforms = GameApiService.discoverPlatforms;
      expect(platforms.first, GamePlatform.pc);
      expect(
        platforms,
        containsAll([GamePlatform.ps5, GamePlatform.nswitch, GamePlatform.ios]),
      );
      for (final p in [
        GamePlatform.steamDeck,
        GamePlatform.emulator,
        GamePlatform.playstation,
        GamePlatform.vr,
      ]) {
        expect(platforms, isNot(contains(p)), reason: p.name);
      }
    });
  });
}
