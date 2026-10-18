import 'dart:async';

import 'package:flutter/material.dart';

import 'package:checkpoint/models/game.dart';
import 'package:checkpoint/models/game_attributes.dart';
import 'package:checkpoint/state/library_attributes_store.dart';
import 'package:checkpoint/state/library_store.dart';
import 'package:checkpoint/state/library_view_store.dart';
import 'package:checkpoint/state/load_status.dart';
import 'package:checkpoint/state/store_scope.dart';
import 'package:checkpoint/theme/palette.dart';
import 'package:checkpoint/widgets/filter_sheet.dart';
import 'package:checkpoint/widgets/sheet_frame.dart';

// The filters of the signed-in member's Library tab: the button that opens the
// filter sheet, the sheet itself (platforms, release years, genre and what IGDB
// says about the games: themes, game modes, perspectives, engines, developers,
// publishers) and the row of what is picked. They read and write the nearest
// [LibraryViewStore], and are built from the pieces in filter_sheet.dart.

/// The attributes that come from IGDB's details, which the library does not hold:
/// everything but the genre.
final _igdbAttributes = [
  for (final a in GameAttribute.values)
    if (a.isFromIgdb) a,
];

/// Opens the filter sheet, and starts reading the details it lists from the
/// server (see [LibraryAttributesStore]).
Future<void> showLibraryFilterSheet(BuildContext context) async {
  unawaited(context.read<LibraryAttributesStore>().ensureLoaded());
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => const LibraryFilterSheet(),
  );
}

/// The filter icon next to the Library's search field, lit and badged with how
/// many things are picked; opens [showLibraryFilterSheet].
class LibraryFilterButton extends StatelessWidget {
  const LibraryFilterButton({super.key, required this.count});

  /// How many things are picked ([LibraryViewStore.filterCount]).
  final int count;

  @override
  Widget build(BuildContext context) {
    return FilterButton(
      count: count,
      onPressed: () => showLibraryFilterSheet(context),
    );
  }
}

/// The sheet to pick filters in. Lists, per kind, only the values at least one
/// game of the library has, so it never offers a filter that would show an empty
/// library. What IGDB says about the games is read when the sheet opens and may
/// not exist for every game yet: the sheet says how many are missing.
class LibraryFilterSheet extends StatelessWidget {
  const LibraryFilterSheet({super.key});

  @override
  Widget build(BuildContext context) {
    final library = context.watch<LibraryStore>().libraryGames;
    final view = context.watch<LibraryViewStore>();
    final attributes = context.watch<LibraryAttributesStore>();
    final platforms = view.filterOptions(library);
    final years = view.yearSpan(library);
    final shown = view.count(library, null);

    return SheetFrame(
      title: 'Filter',
      subtitle: view.hasFilters
          ? 'Showing $shown of ${library.length} '
                '${library.length == 1 ? 'game' : 'games'}'
          : 'Narrow your library down.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (view.hasFilters)
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: view.clearFilters,
                child: const Text('Clear all'),
              ),
            ),
          ChipFilterSection<GamePlatform>(
            title: 'Platform',
            icon: Icons.sports_esports_rounded,
            options: platforms,
            labelOf: (p) => p.label,
            iconOf: (p) => p.icon,
            iconColorOf: (p) => p.color,
            isSelected: view.platformFilters.contains,
            selectedCount: view.platformFilters.length,
            onToggle: view.togglePlatform,
            onClear: () => view.setPlatformFilter(null),
          ),
          if (years != null)
            YearRangeSection(
              value: view.yearFilter,
              onChanged: view.setYearFilter,
              min: years.min,
              max: years.max,
            ),
          _AttributeSection(
            attribute: GameAttribute.genre,
            options: view.attributeOptions(GameAttribute.genre, library),
          ),
          _DetailsStatus(
            status: attributes.status,
            withoutDetails: view.gamesWithoutDetails(library),
            total: library.length,
            onRetry: () => attributes.ensureLoaded(),
          ),
          if (attributes.status == LoadStatus.ready)
            for (final a in _igdbAttributes)
              _AttributeSection(
                attribute: a,
                options: view.attributeOptions(a, library),
              ),
        ],
      ),
    );
  }
}

/// Where the details from IGDB stand: loading, failed (with a retry), or loaded
/// but missing for some games.
class _DetailsStatus extends StatelessWidget {
  const _DetailsStatus({
    required this.status,
    required this.withoutDetails,
    required this.total,
    required this.onRetry,
  });

  final LoadStatus status;
  final int? withoutDetails;
  final int total;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    const style = TextStyle(color: Palette.muted, fontSize: 12.5);
    final missing = withoutDetails ?? 0;
    final child = switch (status) {
      LoadStatus.idle => null,
      LoadStatus.loading => const Row(
        children: [
          SizedBox(
            width: 14,
            height: 14,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          SizedBox(width: 10),
          Text('Loading game details…', style: style),
        ],
      ),
      LoadStatus.failed => Row(
        children: [
          const Expanded(
            child: Text(
              'Could not load themes, modes, engines and companies.',
              style: style,
            ),
          ),
          TextButton(onPressed: onRetry, child: const Text('Retry')),
        ],
      ),
      LoadStatus.ready when missing > 0 => Text(
        missing == total
            ? 'IGDB details are not saved for any of your games yet. They '
                  'fill in over time, and when you open a game.'
            : 'IGDB details are not saved for $missing of $total games yet, so '
                  'the filters below leave them out. They fill in over time, '
                  'and when you open a game.',
        style: style,
      ),
      LoadStatus.ready => null,
    };
    if (child == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 6, bottom: 4),
      child: child,
    );
  }
}

/// The filter for one [GameAttribute]: its values as chips, most common first, with
/// how many games have each (see [ChipFilterSection] for how a long list folds).
/// Nothing is shown for an attribute no game has a value of.
class _AttributeSection extends StatelessWidget {
  const _AttributeSection({required this.attribute, required this.options});

  final GameAttribute attribute;
  final List<FilterOption> options;

  @override
  Widget build(BuildContext context) {
    final view = context.watch<LibraryViewStore>();
    final picked = view.filterValues(attribute);
    return ChipFilterSection<FilterOption>(
      title: attribute.pluralLabel,
      icon: attribute.icon,
      options: options,
      labelOf: (o) => '${o.value} (${o.count})',
      isSelected: (o) => picked.contains(o.value),
      selectedCount: picked.length,
      onToggle: (o) => view.toggleFilter(attribute, o.value),
      onClear: () => view.clearFilter(attribute),
      collapsedCount: attribute.collapsedCount,
    );
  }
}

/// What is picked, as removable chips under the Library title, so it is clear why
/// the library is short; empty when nothing is picked. With a filter on IGDB's
/// details picked, it also says how many games that leaves out for lack of them.
class LibraryActiveFilters extends StatelessWidget {
  const LibraryActiveFilters({super.key, required this.library});

  /// The member's whole library, to count the games without details.
  final List<Game> library;

  @override
  Widget build(BuildContext context) {
    final view = context.watch<LibraryViewStore>();
    if (!view.hasFilters) return const SizedBox.shrink();
    final missing = view.hasDetailFilters
        ? view.gamesWithoutDetails(library) ?? 0
        : 0;

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ActiveFilterChips(filters: view.filters, onChanged: view.setFilters),
          if (missing > 0)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 2, 20, 0),
              child: Text(
                '$missing ${missing == 1 ? 'game has' : 'games have'} no IGDB '
                'details yet, so these filters leave '
                '${missing == 1 ? 'it' : 'them'} out.',
                style: const TextStyle(color: Palette.muted, fontSize: 12),
              ),
            ),
        ],
      ),
    );
  }
}
