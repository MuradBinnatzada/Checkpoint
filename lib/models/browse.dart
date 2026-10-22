import 'package:flutter/foundation.dart';

import 'package:checkpoint/l10n/l10n.dart';
import 'package:checkpoint/models/game.dart';

/// The lists under "Browse by" on the Discover tab. [wireName] is the `mode` the
/// `igdb-handler` Edge Function takes.
enum BrowseMode {
  popular('popular'),
  topRated('top_rated'),
  newReleases('new_releases');

  const BrowseMode(this.wireName);
  final String wireName;

  String get label => switch (this) {
    popular => L10n.current.sortMostPopular,
    topRated => L10n.current.sortHighestRated,
    newReleases => L10n.current.browseNewReleases,
  };
}

/// A game in a browse list, with the figures the list is about. [Game] has no
/// place for them: its `rating` is the user's own, not the catalog's.
@immutable
class BrowseEntry {
  const BrowseEntry(this.game, {this.score, this.releaseDate});

  final Game game;

  /// IGDB's average of user and critic scores, 0-100.
  final double? score;

  /// The first release date (UTC), when IGDB has one. [Game.releaseYear] only
  /// keeps the year.
  final DateTime? releaseDate;
}
