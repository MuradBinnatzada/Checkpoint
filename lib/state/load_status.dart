/// Where a request for a screen's data stands.
enum LoadStatus {
  /// Nothing was asked for yet.
  idle,

  /// The first answer is on its way.
  loading,

  /// There is data to show (possibly empty).
  ready,

  /// The request failed and there is nothing to show.
  failed,
}
