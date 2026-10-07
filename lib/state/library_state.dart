enum LibraryView { grid, list }

enum SortField {
  dateAdded('Date Added'),
  rating('Rating'),
  hoursPlayed('Hours Played'),
  releaseYear('Release Year');

  const SortField(this.label);
  final String label;
}
