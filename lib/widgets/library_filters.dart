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
import 'package:checkpoint/widgets/app_choice_chip.dart';
import 'package:checkpoint/widgets/sheet_frame.dart';

// The filters of the signed-in member's Library tab: the button that opens the
// filter sheet, the sheet itself (platform, genre and what IGDB says about the
// games: themes, game modes, perspectives, engines, developers, publishers) and
// the row of what is picked. They read and write the nearest [LibraryViewStore].

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

/// The filter icon of the Library header, lit and badged with how many things are
/// picked; opens [showLibraryFilterSheet].
class LibraryFilterButton extends StatelessWidget {
  const LibraryFilterButton({super.key, required this.count});

  /// How many things are picked ([LibraryViewStore.filterCount]).
  final int count;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: 'Filter',
      onPressed: () => showLibraryFilterSheet(context),
      icon: Badge(
        isLabelVisible: count > 0,
        label: Text('$count'),
        backgroundColor: Palette.accent,
        textColor: Palette.onAccent,
        child: Icon(
          Icons.filter_list_rounded,
          color: count > 0 ? Palette.accent : null,
        ),
      ),
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
          if (platforms.isNotEmpty)
            _Section(
              title: 'Platform',
              icon: Icons.sports_esports_rounded,
              selected: view.platformFilter == null ? 0 : 1,
              onClear: () => view.setPlatformFilter(null),
              children: [
                for (final p in platforms)
                  AppChoiceChip(
                    label: p.label,
                    icon: p.icon,
                    iconColor: p.color,
                    selected: view.platformFilter == p,
                    onSelected: () => view.setPlatformFilter(
                      view.platformFilter == p ? null : p,
                    ),
                  ),
              ],
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

/// One kind of filter: a title, how many values are picked, a way to clear them,
/// and the chips.
class _Section extends StatelessWidget {
  const _Section({
    required this.title,
    required this.icon,
    required this.selected,
    required this.onClear,
    required this.children,
    this.header,
  });

  final String title;
  final IconData icon;
  final int selected;
  final VoidCallback onClear;
  final List<Widget> children;

  /// Shown between the title and the chips (the search field of a long list).
  final Widget? header;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 16, color: Palette.muted),
              const SizedBox(width: 8),
              Text(
                title,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                ),
              ),
              if (selected > 0) ...[
                const SizedBox(width: 8),
                Text(
                  '$selected picked',
                  style: const TextStyle(color: Palette.accent, fontSize: 12.5),
                ),
              ],
              const Spacer(),
              if (selected > 0)
                TextButton(
                  onPressed: onClear,
                  style: TextButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    minimumSize: const Size(0, 28),
                  ),
                  child: const Text('Clear'),
                ),
            ],
          ),
          if (header != null) ...[const SizedBox(height: 6), header!],
          const SizedBox(height: 8),
          Wrap(spacing: 8, runSpacing: 4, children: children),
        ],
      ),
    );
  }
}

/// The filter for one [GameAttribute]: its values as chips, most common first, with
/// how many games have each. A long list shows its first values (and every one
/// picked) and unfolds on request, with a search box once it is long. Nothing is
/// shown for an attribute no game has a value of.
class _AttributeSection extends StatefulWidget {
  const _AttributeSection({required this.attribute, required this.options});

  final GameAttribute attribute;
  final List<FilterOption> options;

  @override
  State<_AttributeSection> createState() => _AttributeSectionState();
}

class _AttributeSectionState extends State<_AttributeSection> {
  /// A list this long gets a search box when unfolded.
  static const _searchFrom = 20;

  bool _expanded = false;
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final attribute = widget.attribute;
    final options = widget.options;
    if (options.isEmpty) return const SizedBox.shrink();
    final view = context.watch<LibraryViewStore>();
    final picked = view.filterValues(attribute);
    final folds = options.length > attribute.collapsedCount;
    final searchable = _expanded && options.length >= _searchFrom;
    final query = searchable ? _query.trim().toLowerCase() : '';

    var listed = options;
    if (query.isNotEmpty) {
      listed = [
        for (final o in options)
          if (o.value.toLowerCase().contains(query)) o,
      ];
    } else if (folds && !_expanded) {
      listed = [
        for (var i = 0; i < options.length; i++)
          if (i < attribute.collapsedCount || picked.contains(options[i].value))
            options[i],
      ];
    }

    return _Section(
      title: attribute.pluralLabel,
      icon: attribute.icon,
      selected: picked.length,
      onClear: () => view.clearFilter(attribute),
      header: searchable
          ? TextField(
              onChanged: (v) => setState(() => _query = v),
              style: const TextStyle(fontSize: 14),
              decoration: InputDecoration(
                isDense: true,
                filled: true,
                fillColor: Palette.surfaceHigh,
                hintText: 'Search ${attribute.pluralLabel.toLowerCase()}',
                hintStyle: const TextStyle(color: Palette.muted),
                prefixIcon: const Icon(Icons.search_rounded, size: 18),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
              ),
            )
          : null,
      children: [
        for (final o in listed)
          AppChoiceChip(
            label: '${o.value} (${o.count})',
            selected: picked.contains(o.value),
            onSelected: () => view.toggleFilter(attribute, o.value),
          ),
        if (query.isNotEmpty && listed.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 6),
            child: Text('No match.', style: TextStyle(color: Palette.muted)),
          ),
        if (folds && query.isEmpty)
          TextButton(
            onPressed: () => setState(() {
              _expanded = !_expanded;
              _query = '';
            }),
            child: Text(
              _expanded ? 'Show fewer' : 'Show all ${options.length}',
            ),
          ),
      ],
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
    final platform = view.platformFilter;
    final missing = view.hasDetailFilters
        ? view.gamesWithoutDetails(library) ?? 0
        : 0;

    InputChip chip({
      required IconData icon,
      required Color color,
      required String label,
      required VoidCallback onDeleted,
    }) => InputChip(
      avatar: Icon(icon, size: 16, color: color),
      label: Text(label, style: const TextStyle(fontSize: 12.5)),
      onDeleted: onDeleted,
      deleteIcon: const Icon(Icons.close_rounded, size: 16),
      deleteButtonTooltipMessage: 'Remove $label',
      backgroundColor: Palette.surfaceHigh,
      side: BorderSide(color: Palette.accent.withValues(alpha: 0.5)),
      shape: const StadiumBorder(),
      visualDensity: VisualDensity.compact,
    );

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                if (platform != null)
                  Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: chip(
                      icon: platform.icon,
                      color: platform.color,
                      label: platform.label,
                      onDeleted: () => view.setPlatformFilter(null),
                    ),
                  ),
                for (final a in GameAttribute.values)
                  for (final value in view.filterValues(a))
                    Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: chip(
                        icon: a.icon,
                        color: Palette.muted,
                        label: value,
                        onDeleted: () => view.toggleFilter(a, value),
                      ),
                    ),
                if (view.filterCount > 1)
                  TextButton(
                    onPressed: view.clearFilters,
                    child: const Text('Clear all'),
                  ),
              ],
            ),
          ),
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
