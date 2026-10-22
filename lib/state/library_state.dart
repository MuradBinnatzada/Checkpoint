import 'package:checkpoint/l10n/l10n.dart';

enum LibraryView { grid, list }

enum SortField {
  dateAdded,
  rating,
  hoursPlayed,
  releaseYear;

  String get label => switch (this) {
    dateAdded => L10n.current.sortDateAdded,
    rating => L10n.current.sortRating,
    hoursPlayed => L10n.current.sortHoursPlayed,
    releaseYear => L10n.current.sortReleaseYear,
  };
}
