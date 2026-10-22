import 'package:flutter/foundation.dart';

import 'package:checkpoint/l10n/l10n.dart';
import 'package:checkpoint/models/browse.dart';
import 'package:checkpoint/models/game.dart';
import 'package:checkpoint/models/game_details.dart';
import 'package:checkpoint/utils/countries.dart' as countries;

/// Which of a company's games a list holds. [wireName] is the `role` the
/// `igdb-handler` Edge Function takes.
enum CompanyRole {
  any('any'),
  publisher('publisher'),
  developer('developer');

  const CompanyRole(this.wireName);
  final String wireName;

  String get label => switch (this) {
    any => L10n.current.companyRoleAll,
    publisher => L10n.current.companyRolePublished,
    developer => L10n.current.companyRoleDeveloped,
  };
}

/// A company as the studio search lists it. IGDB keeps publishers and
/// developers as one thing, a company: Valve both develops and publishes.
@immutable
class CompanySummary {
  const CompanySummary({
    required this.id,
    required this.name,
    this.logoUrl,
    this.country,
    this.publishedCount = 0,
    this.developedCount = 0,
  });

  /// IGDB's id of the company.
  final int id;
  final String name;
  final String? logoUrl;

  /// ISO 3166-1 numeric code of where it is based.
  final int? country;

  /// How many games IGDB lists it as publisher / developer of.
  final int publishedCount;
  final int developedCount;

  /// Where it is based, when that is a country [countries.countryName] knows.
  String? get countryName => countries.countryName(country);

  /// What the `companies` request answered, or null when it is not a company
  /// with an id and a name. The other fields are optional.
  static CompanySummary? fromJson(Object? json) {
    if (json is! Map) return null;
    final id = _positive(json['id']);
    final name = _text(json['name']);
    if (id == null || name == null) return null;
    return CompanySummary(
      id: id,
      name: name,
      logoUrl: logoUrlFor(_text(json['logo_image_id'])),
      country: _positive(json['country']),
      publishedCount: _positive(json['published_count']) ?? 0,
      developedCount: _positive(json['developed_count']) ?? 0,
    );
  }

  /// IGDB's medium-size logo of [imageId] (a PNG, so it keeps its transparency).
  static String? logoUrlFor(String? imageId) => imageId == null
      ? null
      : 'https://images.igdb.com/igdb/image/upload/t_logo_med/$imageId.png';
}

/// Another company a company page links to (its parent).
@immutable
class CompanyRef {
  const CompanyRef(this.id, this.name);
  final int id;
  final String name;
}

/// What a website of a company is, by where it points.
enum CompanyWebsiteKind {
  official(null),
  wikipedia('Wikipedia'),
  steam('Steam'),
  x('X'),
  youtube('YouTube'),
  facebook('Facebook'),
  instagram('Instagram'),
  twitch('Twitch'),
  discord('Discord'),
  reddit('Reddit'),
  linkedin('LinkedIn'),
  bluesky('Bluesky'),
  itch('itch.io'),
  other(null);

  const CompanyWebsiteKind(this._name);

  /// The site's own name; null for the ones named in the app's language.
  final String? _name;

  String get label =>
      _name ??
      switch (this) {
        official => L10n.current.websiteOfficial,
        _ => L10n.current.websiteOther,
      };
}

/// One website of a company.
@immutable
class CompanyWebsite {
  const CompanyWebsite(this.url, {this.type});

  final Uri url;

  /// IGDB's website type: 1 is the official site.
  final int? type;

  static const _officialType = 1;

  CompanyWebsiteKind get kind {
    final host = url.host.toLowerCase();
    bool on(String domain) => host == domain || host.endsWith('.$domain');
    if (on('wikipedia.org')) return CompanyWebsiteKind.wikipedia;
    if (on('steampowered.com') || on('steamcommunity.com')) {
      return CompanyWebsiteKind.steam;
    }
    if (on('twitter.com') || on('x.com')) return CompanyWebsiteKind.x;
    if (on('youtube.com') || on('youtu.be')) return CompanyWebsiteKind.youtube;
    if (on('facebook.com')) return CompanyWebsiteKind.facebook;
    if (on('instagram.com')) return CompanyWebsiteKind.instagram;
    if (on('twitch.tv')) return CompanyWebsiteKind.twitch;
    if (on('discord.gg') || on('discord.com')) {
      return CompanyWebsiteKind.discord;
    }
    if (on('reddit.com')) return CompanyWebsiteKind.reddit;
    if (on('linkedin.com')) return CompanyWebsiteKind.linkedin;
    if (on('bsky.app')) return CompanyWebsiteKind.bluesky;
    if (on('itch.io')) return CompanyWebsiteKind.itch;
    if (type == _officialType) return CompanyWebsiteKind.official;
    return CompanyWebsiteKind.other;
  }

  /// What a link to it says: the kind of site, or its host for any other.
  String get label {
    final k = kind;
    if (k != CompanyWebsiteKind.other) return k.label;
    final host = url.host.toLowerCase();
    return host.startsWith('www.') ? host.substring(4) : host;
  }
}

/// Everything a company's page shows about it, apart from its games.
@immutable
class Company extends CompanySummary {
  const Company({
    required super.id,
    required super.name,
    super.logoUrl,
    super.country,
    super.publishedCount,
    super.developedCount,
    this.description,
    this.translatedDescription,
    this.foundedYear,
    this.parent,
    this.websites = const [],
  });

  final String? description;

  /// [description] in the app's language, when it is not English and the
  /// server translated it (DeepL); null otherwise.
  final IgdbTranslation? translatedDescription;
  final int? foundedYear;

  /// The company with a controlling interest in this one.
  final CompanyRef? parent;
  final List<CompanyWebsite> websites;

  /// What the `company` request answered (`{ "company": {...} }`), or null when
  /// it is not an answer with a company in it.
  static Company? fromResponse(Object? response) {
    if (response is! Map) return null;
    final json = response['company'];
    final summary = CompanySummary.fromJson(json);
    if (summary == null || json is! Map) return null;

    final parent = json['parent'];
    final parentId = parent is Map ? _positive(parent['id']) : null;
    final parentName = parent is Map ? _text(parent['name']) : null;
    final sites = json['websites'];
    return Company(
      id: summary.id,
      name: summary.name,
      logoUrl: summary.logoUrl,
      country: summary.country,
      publishedCount: summary.publishedCount,
      developedCount: summary.developedCount,
      description: _text(json['description']),
      translatedDescription: IgdbTranslation.fromJson(response['translations']),
      foundedYear: releaseYearFromUnixSeconds(json['start_date']),
      parent: parentId != null && parentName != null
          ? CompanyRef(parentId, parentName)
          : null,
      websites: [
        if (sites is List)
          for (final site in sites)
            if (site is Map)
              if (_text(site['url']) case final String raw)
                if (Uri.tryParse(raw) case final Uri url
                    when url.hasScheme && url.host.isNotEmpty)
                  CompanyWebsite(url, type: _positive(site['type'])),
      ],
    );
  }
}

/// A game on a company's page: the list entry, and what the company did on it.
@immutable
class CompanyGame {
  const CompanyGame(
    this.entry, {
    required this.developed,
    required this.published,
  });

  final BrowseEntry entry;
  final bool developed;
  final bool published;

  Game get game => entry.game;
}

int? _positive(Object? value) =>
    value is num && value.isFinite && value > 0 ? value.toInt() : null;

String? _text(Object? value) {
  if (value is! String) return null;
  final text = value.trim();
  return text.isEmpty ? null : text;
}
