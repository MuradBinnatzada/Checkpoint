import 'package:flutter/foundation.dart';

import 'package:checkpoint/l10n/l10n.dart';
import 'package:checkpoint/models/company.dart';
import 'package:checkpoint/models/filter_options.dart';

/// The order of a list of studios. [wireName] is the `sort` the `igdb-handler`
/// Edge Function takes for its `companies` mode.
enum StudioSort {
  popular('popular'),
  name('name'),
  oldest('oldest'),
  newest('newest');

  const StudioSort(this.wireName);
  final String wireName;

  String get label => switch (this) {
    popular => L10n.current.studioSortMostGames,
    name => L10n.current.studioSortName,
    oldest => L10n.current.studioSortOldest,
    newest => L10n.current.studioSortNewest,
  };
}

/// What the Studios tab narrows its list down by: the [role] (developer or
/// publisher, any when not narrowed), the [countries] (ISO 3166-1 numbers, as
/// IGDB gives them; a studio needs to be in any of them) and the years it was
/// [founded] in, plus the [sort] of the list. An immutable value: every change
/// makes a new one.
@immutable
class StudioFilters {
  const StudioFilters._(this.role, this.countries, this.founded, this.sort);

  factory StudioFilters({
    CompanyRole role = CompanyRole.any,
    Iterable<int> countries = const [],
    YearRange founded = YearRange.any,
    StudioSort sort = StudioSort.popular,
  }) => StudioFilters._(role, Set.unmodifiable(countries), founded, sort);

  /// Nothing picked, in the default order.
  static const none = StudioFilters._(
    CompanyRole.any,
    {},
    YearRange.any,
    StudioSort.popular,
  );

  final CompanyRole role;
  final Set<int> countries;
  final YearRange founded;
  final StudioSort sort;

  /// Whether nothing narrows the list ([sort] is an order, not a filter).
  bool get isEmpty =>
      role == CompanyRole.any && countries.isEmpty && founded.isAny;

  /// How many things are picked: the role, every country, and the years.
  int get count =>
      (role == CompanyRole.any ? 0 : 1) +
      countries.length +
      (founded.isAny ? 0 : 1);

  StudioFilters withRole(CompanyRole role) => _with(role: role);

  /// Picks [country], or lets go of it when it is picked.
  StudioFilters toggleCountry(int country) {
    final picked = {...countries};
    if (!picked.remove(country)) picked.add(country);
    return _with(countries: picked);
  }

  StudioFilters withCountries(Iterable<int> countries) =>
      _with(countries: countries);

  StudioFilters withFounded(YearRange founded) => _with(founded: founded);

  StudioFilters withSort(StudioSort sort) => _with(sort: sort);

  /// Nothing picked, in the same order.
  StudioFilters cleared() => StudioFilters(sort: sort);

  StudioFilters _with({
    CompanyRole? role,
    Iterable<int>? countries,
    YearRange? founded,
    StudioSort? sort,
  }) => StudioFilters(
    role: role ?? this.role,
    countries: countries ?? this.countries,
    founded: founded ?? this.founded,
    sort: sort ?? this.sort,
  );

  /// The `filters` object of `igdb-handler`'s `companies` mode, with only what
  /// is picked; empty when nothing is.
  Map<String, Object> toWire() => {
    if (role != CompanyRole.any) 'role': role.wireName,
    if (countries.isNotEmpty) 'countries': countries.toList(),
    if (!founded.isAny)
      'founded': {
        if (founded.from != null) 'from': founded.from!,
        if (founded.to != null) 'to': founded.to!,
      },
  };

  @override
  bool operator ==(Object other) =>
      other is StudioFilters &&
      other.role == role &&
      other.sort == sort &&
      other.founded == founded &&
      setEquals(other.countries, countries);

  @override
  int get hashCode =>
      Object.hash(role, sort, founded, Object.hashAllUnordered(countries));

  @override
  String toString() =>
      'StudioFilters($role, $countries, $founded, ${sort.name})';
}
