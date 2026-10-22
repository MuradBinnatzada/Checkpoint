import 'package:flutter/foundation.dart';

import 'package:checkpoint/l10n/l10n.dart';
import 'package:checkpoint/models/game.dart';
import 'package:checkpoint/models/game_attributes.dart';

/// The order of a filtered list on the Discover tab, when there is no search text
/// (IGDB orders a search by relevance). [wireName] is the `sort` the
/// `igdb-handler` Edge Function takes.
enum DiscoverSort {
  popular('popular'),
  topRated('top_rated'),
  newest('newest'),
  oldest('oldest');

  const DiscoverSort(this.wireName);
  final String wireName;

  String get label => switch (this) {
    popular => L10n.current.sortMostPopular,
    topRated => L10n.current.sortHighestRated,
    newest => L10n.current.sortNewest,
    oldest => L10n.current.sortOldest,
  };
}

/// Release years from [from] to [to], both included; a null end is open. A game
/// whose year is not known (0) is in no range but [any].
@immutable
class YearRange {
  const YearRange({this.from, this.to});

  /// The ten years of the decade starting at [start] ("the 1990s").
  const YearRange.decade(int start) : from = start, to = start + 9;

  /// Every year: not filtered.
  static const any = YearRange();

  final int? from;
  final int? to;

  bool get isAny => from == null && to == null;

  bool contains(int year) {
    if (isAny) return true;
    final f = from;
    final t = to;
    return year > 0 && (f == null || year >= f) && (t == null || year <= t);
  }

  /// "1990s", "2015", "2010–2015", "2010 or later", "Up to 1999"; empty for [any].
  String get label {
    final f = from;
    final t = to;
    if (f != null && t != null) {
      if (f == t) return '$f';
      if (f % 10 == 0 && t == f + 9) return L10n.current.yearsDecade(f);
      return '$f–$t';
    }
    if (f != null) return L10n.current.yearsFrom(f);
    if (t != null) return L10n.current.yearsUpTo(t);
    return '';
  }

  @override
  bool operator ==(Object other) =>
      other is YearRange && other.from == from && other.to == to;

  @override
  int get hashCode => Object.hash(from, to);

  @override
  String toString() => 'YearRange($from, $to)';
}

/// What a list of games is narrowed down by: values of the [GameAttribute]s
/// (genres, themes, game modes...), platforms and a release-year range, plus the
/// [sort] of a filtered Discover list. Of one kind a game needs any value picked;
/// the kinds narrow each other down.
///
/// The Discover tab ([SearchStore]) and the Library tab ([LibraryViewStore]) both
/// keep their filters as one of these. The Library sorts with its own controls
/// (date added, hours played...), so it leaves [sort] alone.
///
/// Values are names, as IGDB gives them ("Horror", "Single player"): the
/// Library's come from its games, the Discover tab's from [CatalogTags]. An
/// immutable value: every change makes a new one.
@immutable
class FilterOptions {
  const FilterOptions._(this.attributes, this.platforms, this.years, this.sort);

  factory FilterOptions({
    Map<GameAttribute, Iterable<String>> attributes = const {},
    Iterable<GamePlatform> platforms = const [],
    YearRange years = YearRange.any,
    DiscoverSort sort = DiscoverSort.popular,
  }) => FilterOptions._(
    Map.unmodifiable({
      for (final MapEntry(:key, :value) in attributes.entries)
        if (value.isNotEmpty) key: Set<String>.unmodifiable(value),
    }),
    Set.unmodifiable(platforms),
    years,
    sort,
  );

  /// Just [value] of [attribute]: what tapping a tag on a game's screen opens.
  factory FilterOptions.only(GameAttribute attribute, String value) =>
      FilterOptions(
        attributes: {
          attribute: [value],
        },
      );

  /// Nothing picked, in the default order.
  static const none = FilterOptions._(
    {},
    {},
    YearRange.any,
    DiscoverSort.popular,
  );

  /// The values picked per attribute; an attribute with none picked is not here.
  final Map<GameAttribute, Set<String>> attributes;
  final Set<GamePlatform> platforms;
  final YearRange years;
  final DiscoverSort sort;

  /// The values picked for [attribute], none when it is not filtered.
  Set<String> valuesOf(GameAttribute attribute) =>
      attributes[attribute] ?? const {};

  bool has(GameAttribute attribute, String value) =>
      valuesOf(attribute).contains(value);

  /// Whether nothing narrows the list ([sort] is an order, not a filter).
  bool get isEmpty => attributes.isEmpty && platforms.isEmpty && years.isAny;

  /// How many things are picked: every value, every platform, and the year range.
  int get count =>
      attributes.values.fold(0, (sum, values) => sum + values.length) +
      platforms.length +
      (years.isAny ? 0 : 1);

  /// Whether a value of something only IGDB's details say is picked (a theme,
  /// mode, perspective, engine, developer or publisher). See
  /// [GameAttribute.isFromIgdb].
  bool get hasDetailFilters => attributes.keys.any((a) => a.isFromIgdb);

  /// Picks [value] of [attribute], or lets go of it when it is picked.
  FilterOptions toggle(GameAttribute attribute, String value) {
    final values = {...valuesOf(attribute)};
    if (!values.remove(value)) values.add(value);
    return _with(attributes: {...attributes, attribute: values});
  }

  /// Lets go of every value picked for [attribute].
  FilterOptions clear(GameAttribute attribute) =>
      _with(attributes: {...attributes}..remove(attribute));

  /// Picks [platform], or lets go of it when it is picked.
  FilterOptions togglePlatform(GamePlatform platform) {
    final picked = {...platforms};
    if (!picked.remove(platform)) picked.add(platform);
    return _with(platforms: picked);
  }

  FilterOptions withPlatforms(Iterable<GamePlatform> platforms) =>
      _with(platforms: platforms);

  FilterOptions withYears(YearRange years) => _with(years: years);

  FilterOptions withSort(DiscoverSort sort) => _with(sort: sort);

  /// Nothing picked, in the same order.
  FilterOptions cleared() => FilterOptions(sort: sort);

  FilterOptions _with({
    Map<GameAttribute, Iterable<String>>? attributes,
    Iterable<GamePlatform>? platforms,
    YearRange? years,
    DiscoverSort? sort,
  }) => FilterOptions(
    attributes: attributes ?? this.attributes,
    platforms: platforms ?? this.platforms,
    years: years ?? this.years,
    sort: sort ?? this.sort,
  );

  @override
  bool operator ==(Object other) =>
      other is FilterOptions &&
      other.sort == sort &&
      other.years == years &&
      setEquals(other.platforms, platforms) &&
      other.attributes.length == attributes.length &&
      attributes.entries.every(
        (e) => setEquals(other.attributes[e.key], e.value),
      );

  @override
  int get hashCode => Object.hash(
    sort,
    years,
    Object.hashAllUnordered(platforms),
    Object.hashAllUnordered([
      for (final MapEntry(:key, :value) in attributes.entries)
        Object.hash(key, Object.hashAllUnordered(value)),
    ]),
  );

  @override
  String toString() =>
      'FilterOptions($attributes, $platforms, $years, ${sort.name})';
}

/// A genre, theme or game mode as IGDB files games under it: its [igdbId] (what a
/// Discover filter sends) and its [name] (what IGDB's details say, so what a
/// game's screen shows).
@immutable
class CatalogTag {
  const CatalogTag(this.igdbId, this.name, {this._label});

  final int igdbId;
  final String name;
  final String? _label;

  /// The name on a filter chip, in the app's language: shorter for the long
  /// ones ("RPG").
  String get label => _label == null ? tagName(name) : _shortTagName(L10n.current, name) ?? _label;
}

/// The genres, themes and game modes the Discover tab can filter by: IGDB's own
/// fixed lists (`/genres`, `/themes`, `/game_modes`), most looked-for first. The
/// names are IGDB's, so a tag on a game's screen is found here by its text.
/// "Erotic" is the one theme left out.
abstract final class CatalogTags {
  static const genres = [
    CatalogTag(31, 'Adventure'),
    CatalogTag(12, 'Role-playing (RPG)', label: 'RPG'),
    CatalogTag(5, 'Shooter'),
    CatalogTag(8, 'Platform'),
    CatalogTag(9, 'Puzzle'),
    CatalogTag(15, 'Strategy'),
    CatalogTag(13, 'Simulator'),
    CatalogTag(32, 'Indie'),
    CatalogTag(4, 'Fighting'),
    CatalogTag(10, 'Racing'),
    CatalogTag(14, 'Sport'),
    CatalogTag(33, 'Arcade'),
    CatalogTag(25, "Hack and slash/Beat 'em up", label: 'Hack and slash'),
    CatalogTag(24, 'Tactical'),
    CatalogTag(11, 'Real Time Strategy (RTS)', label: 'Real-time strategy'),
    CatalogTag(16, 'Turn-based strategy (TBS)', label: 'Turn-based strategy'),
    CatalogTag(34, 'Visual Novel'),
    CatalogTag(2, 'Point-and-click'),
    CatalogTag(35, 'Card & Board Game'),
    CatalogTag(36, 'MOBA'),
    CatalogTag(7, 'Music'),
    CatalogTag(26, 'Quiz/Trivia'),
    CatalogTag(30, 'Pinball'),
  ];

  static const themes = [
    CatalogTag(1, 'Action'),
    CatalogTag(17, 'Fantasy'),
    CatalogTag(18, 'Science fiction', label: 'Sci-fi'),
    CatalogTag(19, 'Horror'),
    CatalogTag(21, 'Survival'),
    CatalogTag(38, 'Open world'),
    CatalogTag(33, 'Sandbox'),
    CatalogTag(23, 'Stealth'),
    CatalogTag(43, 'Mystery'),
    CatalogTag(20, 'Thriller'),
    CatalogTag(27, 'Comedy'),
    CatalogTag(31, 'Drama'),
    CatalogTag(22, 'Historical'),
    CatalogTag(39, 'Warfare'),
    CatalogTag(44, 'Romance'),
    CatalogTag(40, 'Party'),
    CatalogTag(35, 'Kids'),
    CatalogTag(34, 'Educational'),
    CatalogTag(28, 'Business'),
    CatalogTag(32, 'Non-fiction'),
    CatalogTag(
      41,
      '4X (explore, expand, exploit, and exterminate)',
      label: '4X',
    ),
  ];

  static const gameModes = [
    CatalogTag(1, 'Single player', label: 'Single-player'),
    CatalogTag(2, 'Multiplayer'),
    CatalogTag(3, 'Co-operative', label: 'Co-op'),
    CatalogTag(4, 'Split screen'),
    CatalogTag(5, 'Massively Multiplayer Online (MMO)', label: 'MMO'),
    CatalogTag(6, 'Battle Royale', label: 'Battle royale'),
  ];

  /// The attributes the Discover tab filters by, in the order its sheet lists them.
  static const discoverable = [
    GameAttribute.genre,
    GameAttribute.gameMode,
    GameAttribute.theme,
  ];

  /// IGDB's list for [attribute]; empty for one Discover can't filter by.
  static List<CatalogTag> of(GameAttribute attribute) => switch (attribute) {
    GameAttribute.genre => genres,
    GameAttribute.theme => themes,
    GameAttribute.gameMode => gameModes,
    _ => const [],
  };

  /// The tag of [attribute] named [name] (ignoring case and surrounding space),
  /// or null when IGDB's list has none by that name.
  static CatalogTag? find(GameAttribute attribute, String name) {
    final wanted = name.trim().toLowerCase();
    for (final tag in of(attribute)) {
      if (tag.name.toLowerCase() == wanted) return tag;
    }
    return null;
  }

  /// [value] as a filter chip names it: its tag's short label, or [value] in
  /// the app's language.
  static String labelOf(GameAttribute attribute, String value) =>
      find(attribute, value)?.label ?? tagName(value);
}

/// [name] (IGDB's name of a genre, theme, game mode or player perspective) in
/// the app's language: what a game's screen and the filters show. Any other
/// value (an engine, a company, a name IGDB added later) is shown as it is.
String tagName(String name) => _tagName(L10n.current, name) ?? name;

String? _tagName(AppLocalizations l10n, String name) => switch (name) {
  'Adventure' => l10n.tagAdventure,
  'Role-playing (RPG)' => l10n.tagRolePlayingRpg,
  'Shooter' => l10n.tagShooter,
  'Platform' => l10n.tagPlatform,
  'Puzzle' => l10n.tagPuzzle,
  'Strategy' => l10n.tagStrategy,
  'Simulator' => l10n.tagSimulator,
  'Indie' => l10n.tagIndie,
  'Fighting' => l10n.tagFighting,
  'Racing' => l10n.tagRacing,
  'Sport' => l10n.tagSport,
  'Arcade' => l10n.tagArcade,
  "Hack and slash/Beat 'em up" => l10n.tagHackAndSlashBeatEmUp,
  'Tactical' => l10n.tagTactical,
  'Real Time Strategy (RTS)' => l10n.tagRealTimeStrategyRts,
  'Turn-based strategy (TBS)' => l10n.tagTurnBasedStrategyTbs,
  'Visual Novel' => l10n.tagVisualNovel,
  'Point-and-click' => l10n.tagPointAndClick,
  'Card & Board Game' => l10n.tagCardBoardGame,
  'MOBA' => l10n.tagMoba,
  'Music' => l10n.tagMusic,
  'Quiz/Trivia' => l10n.tagQuizTrivia,
  'Pinball' => l10n.tagPinball,
  'Action' => l10n.tagAction,
  'Fantasy' => l10n.tagFantasy,
  'Science fiction' => l10n.tagScienceFiction,
  'Horror' => l10n.tagHorror,
  'Survival' => l10n.tagSurvival,
  'Open world' => l10n.tagOpenWorld,
  'Sandbox' => l10n.tagSandbox,
  'Stealth' => l10n.tagStealth,
  'Mystery' => l10n.tagMystery,
  'Thriller' => l10n.tagThriller,
  'Comedy' => l10n.tagComedy,
  'Drama' => l10n.tagDrama,
  'Historical' => l10n.tagHistorical,
  'Warfare' => l10n.tagWarfare,
  'Romance' => l10n.tagRomance,
  'Party' => l10n.tagParty,
  'Kids' => l10n.tagKids,
  'Educational' => l10n.tagEducational,
  'Business' => l10n.tagBusiness,
  'Non-fiction' => l10n.tagNonFiction,
  '4X (explore, expand, exploit, and exterminate)' => l10n.tag4xExploreExpandExploitAndExterminate,
  'Single player' => l10n.tagSinglePlayer,
  'Multiplayer' => l10n.tagMultiplayer,
  'Co-operative' => l10n.tagCoOperative,
  'Split screen' => l10n.tagSplitScreen,
  'Massively Multiplayer Online (MMO)' => l10n.tagMassivelyMultiplayerOnlineMmo,
  'Battle Royale' => l10n.tagBattleRoyale,
  'Erotic' => l10n.tagErotic,
  'First person' => l10n.tagFirstPerson,
  'Third person' => l10n.tagThirdPerson,
  'Bird view / Isometric' => l10n.tagBirdViewIsometric,
  'Side view' => l10n.tagSideView,
  'Text' => l10n.tagText,
  'Auditory' => l10n.tagAuditory,
  'Virtual Reality' => l10n.tagVirtualReality,
  _ => null,
};

/// The shorter name a filter chip gives the long ones ("RPG"), in the app's
/// language.
String? _shortTagName(AppLocalizations l10n, String name) => switch (name) {
  'Role-playing (RPG)' => l10n.tagRolePlayingRpgShort,
  "Hack and slash/Beat 'em up" => l10n.tagHackAndSlashBeatEmUpShort,
  'Real Time Strategy (RTS)' => l10n.tagRealTimeStrategyRtsShort,
  'Turn-based strategy (TBS)' => l10n.tagTurnBasedStrategyTbsShort,
  'Science fiction' => l10n.tagScienceFictionShort,
  '4X (explore, expand, exploit, and exterminate)' => l10n.tag4xExploreExpandExploitAndExterminateShort,
  'Single player' => l10n.tagSinglePlayerShort,
  'Co-operative' => l10n.tagCoOperativeShort,
  'Massively Multiplayer Online (MMO)' => l10n.tagMassivelyMultiplayerOnlineMmoShort,
  'Battle Royale' => l10n.tagBattleRoyaleShort,
  _ => null,
};
