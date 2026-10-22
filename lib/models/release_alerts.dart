import 'package:checkpoint/l10n/l10n.dart';
import 'package:checkpoint/models/game.dart';

/// A wishlist game around its release: [daysAway] is 0 on the day, negative
/// once it is out.
typedef ReleaseAlert = ({Game game, int daysAway});

/// The wishlist games that come out within [ahead] days, or came out within
/// [since] days: the ones just out first (newest first), then the upcoming
/// ones (soonest first). [today] is the device's date.
List<ReleaseAlert> releaseAlerts(
  List<Game> library, {
  required DateTime today,
  int ahead = 60,
  int since = 14,
}) {
  final day = _day(today);
  final alerts = <ReleaseAlert>[
    for (final g in library)
      if (g.status == GameStatus.wishlist && g.releaseDate != null)
        (game: g, daysAway: _day(g.releaseDate!).difference(day).inDays),
  ].where((a) => a.daysAway <= ahead && a.daysAway >= -since).toList();
  alerts.sort((a, b) {
    final outA = a.daysAway <= 0;
    final outB = b.daysAway <= 0;
    if (outA != outB) return outA ? -1 : 1;
    return outA ? b.daysAway.compareTo(a.daysAway) : a.daysAway.compareTo(b.daysAway);
  });
  return alerts;
}

/// "Out today", "Out now", "Out tomorrow", "Out in 5 days".
String releaseLabel(int daysAway) => switch (daysAway) {
  0 => L10n.current.releaseOutToday,
  < 0 => L10n.current.releaseOutNow,
  1 => L10n.current.releaseOutTomorrow,
  _ => L10n.current.releaseOutInDays(daysAway),
};

/// Calendar days in UTC, so a daylight saving change can't make a day 23 hours.
DateTime _day(DateTime d) => DateTime.utc(d.year, d.month, d.day);
