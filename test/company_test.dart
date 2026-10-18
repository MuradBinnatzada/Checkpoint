import 'package:flutter_test/flutter_test.dart';

import 'package:checkpoint/models/company.dart';
import 'package:checkpoint/utils/countries.dart';

void main() {
  group('Company.fromResponse', () {
    // What igdb-handler answers for Valve (trimmed).
    Map<String, dynamic> valve([Map<String, dynamic> overrides = const {}]) => {
      'company': {
        'id': 56,
        'name': 'Valve',
        'description': 'Makers of Half-Life.',
        'country': 840,
        'start_date': 830304000, // 1996-04-24
        'logo_image_id': 'cl1',
        'parent': null,
        'websites': [
          {'url': 'https://www.valvesoftware.com', 'type': 1},
          {'url': 'https://en.wikipedia.org/wiki/Valve_Corporation', 'type': 3},
          {'url': 'not a url', 'type': 1},
        ],
        'published_count': 42,
        'developed_count': 18,
        ...overrides,
      },
    };

    test('reads the whole page', () {
      final company = Company.fromResponse(valve())!;

      expect(company.id, 56);
      expect(company.name, 'Valve');
      expect(company.description, 'Makers of Half-Life.');
      expect(company.countryName, 'United States');
      expect(company.foundedYear, 1996);
      expect(
        company.logoUrl,
        'https://images.igdb.com/igdb/image/upload/t_logo_med/cl1.png',
      );
      expect(company.parent, isNull);
      expect(company.publishedCount, 42);
      expect(company.developedCount, 18);
      expect(
        [for (final w in company.websites) w.label],
        ['Official website', 'Wikipedia'],
      );
    });

    test('reads the parent company', () {
      final company = Company.fromResponse(
        valve({
          'parent': {'id': 9, 'name': 'Parent Co'},
        }),
      )!;

      expect(company.parent?.id, 9);
      expect(company.parent?.name, 'Parent Co');
    });

    test('a sparse company gives a sparse page, not a failure', () {
      final company = Company.fromResponse({
        'company': {
          'id': 7,
          'name': 'Tiny',
          'country': 999,
          'websites': 'nope',
        },
      })!;

      expect(company.logoUrl, isNull);
      expect(company.countryName, isNull);
      expect(company.foundedYear, isNull);
      expect(company.description, isNull);
      expect(company.websites, isEmpty);
      expect(company.publishedCount, 0);
    });

    test('an answer without a company with an id and a name is no company', () {
      expect(Company.fromResponse(null), isNull);
      expect(
        Company.fromResponse({'error': 'No such company', 'code': 'NOT_FOUND'}),
        isNull,
      );
      expect(
        Company.fromResponse({
          'company': {'id': 7},
        }),
        isNull,
      );
      expect(
        Company.fromResponse({
          'company': {'name': 'No id'},
        }),
        isNull,
      );
    });
  });

  test('CompanySummary.fromJson reads a studio search row', () {
    final summary = CompanySummary.fromJson({
      'id': 70,
      'name': 'Nintendo',
      'logo_image_id': null,
      'country': 392,
      'published_count': 900,
      'developed_count': 300,
    })!;

    expect(summary.name, 'Nintendo');
    expect(summary.logoUrl, isNull);
    expect(summary.countryName, 'Japan');
    expect(summary.publishedCount, 900);
    expect(CompanySummary.fromJson('nope'), isNull);
  });

  group('CompanyWebsite', () {
    CompanyWebsiteKind kind(String url, [int? type]) =>
        CompanyWebsite(Uri.parse(url), type: type).kind;

    test('is known by where it points', () {
      expect(
        kind('https://store.steampowered.com/developer/valve'),
        CompanyWebsiteKind.steam,
      );
      expect(kind('https://x.com/valve'), CompanyWebsiteKind.x);
      expect(kind('https://twitter.com/valve'), CompanyWebsiteKind.x);
      expect(
        kind('https://www.youtube.com/@valve'),
        CompanyWebsiteKind.youtube,
      );
      expect(
        kind('https://bsky.app/profile/valve'),
        CompanyWebsiteKind.bluesky,
      );
    });

    test('a site of no known kind is official when IGDB says so, its host otherwise', () {
      expect(
        kind('https://www.valvesoftware.com', 1),
        CompanyWebsiteKind.official,
      );
      final other = CompanyWebsite(Uri.parse('https://www.example.org/about'));
      expect(other.kind, CompanyWebsiteKind.other);
      expect(other.label, 'example.org');
    });

    test('a look-alike domain is not the site', () {
      expect(kind('https://notx.com/valve'), CompanyWebsiteKind.other);
    });
  });

  test('countryName knows the main game-industry countries only', () {
    expect(countryName(392), 'Japan');
    expect(countryName(826), 'United Kingdom');
    expect(countryName(null), isNull);
    expect(countryName(1), isNull);
  });
}
