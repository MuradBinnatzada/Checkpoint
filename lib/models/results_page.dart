/// One page of a paged search (IGDB games, members...).
///
/// [fetched] is how many rows the source returned for this page, counted before
/// the caller dropped any it couldn't use. The next page starts at the sum of
/// the [fetched] values so far, so a dropped row doesn't shift every later page.
class ResultsPage<T> {
  ResultsPage(this.items, {required this.hasMore, int? fetched})
    : fetched = fetched ?? items.length;

  final List<T> items;

  /// Whether the source may have more rows after this page.
  final bool hasMore;

  final int fetched;
}
