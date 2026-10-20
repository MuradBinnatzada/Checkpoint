import 'package:flutter/material.dart';

import 'package:checkpoint/models/filter_options.dart';
import 'package:checkpoint/models/game.dart';
import 'package:checkpoint/models/game_attributes.dart';
import 'package:checkpoint/services/game_api_service.dart';
import 'package:checkpoint/theme/palette.dart';
import 'package:checkpoint/widgets/app_choice_chip.dart';
import 'package:checkpoint/widgets/sheet_frame.dart';

// The filters of the Discover and Library tabs, Letterboxd style: a filter button
// badged with how many things are picked, a sheet of multi-select chips grouped by
// kind, and a row of what is picked. The pieces work on a [FilterOptions] value
// and hand every change back as a new one, so each tab composes its own sheet
// from them: the Discover sheet is here, the Library's is in library_filters.dart.

/// The filter icon next to a search field, lit and badged with [count] (how many
/// things are picked) when there is something picked.
class FilterButton extends StatelessWidget {
  const FilterButton({super.key, required this.count, required this.onPressed});

  final int count;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: 'Filter',
      onPressed: onPressed,
      icon: Badge(
        isLabelVisible: count > 0,
        label: Text('$count'),
        backgroundColor: context.palette.accent,
        textColor: context.palette.onAccent,
        child: Icon(
          Icons.filter_list_rounded,
          color: count > 0 ? context.palette.accent : null,
        ),
      ),
    );
  }
}

/// One kind of filter in a sheet: a title, how many values are picked (or a
/// [summary] of them), a way to clear them, and the chips.
class FilterSection extends StatelessWidget {
  const FilterSection({
    super.key,
    required this.title,
    required this.icon,
    required this.selected,
    required this.onClear,
    required this.children,
    this.summary,
    this.header,
  });

  final String title;
  final IconData icon;
  final int selected;
  final VoidCallback? onClear;
  final List<Widget> children;

  /// Shown instead of "N picked" when something is picked ("1990s").
  final String? summary;

  /// Shown between the title and the chips (the search field of a long list).
  final Widget? header;

  @override
  Widget build(BuildContext context) {
    final onClear = this.onClear;
    return Padding(
      padding: const EdgeInsets.only(top: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 16, color: context.palette.muted),
              const SizedBox(width: 8),
              // The title and the summary share what Clear leaves, and wrap
              // with large text.
              Expanded(
                child: Row(
                  children: [
                    Flexible(
                      child: Text(
                        title,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    if (selected > 0) ...[
                      const SizedBox(width: 8),
                      Flexible(
                        child: Text(
                          summary ?? '$selected picked',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: context.palette.accent,
                            fontSize: 12.5,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (selected > 0 && onClear != null)
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

/// A [FilterSection] of multi-select chips, one per option. A long list shows its
/// first [collapsedCount] options (and every one picked) and unfolds on request,
/// with a search box once it has [searchFrom] options or more. Nothing is shown
/// for an empty [options].
class ChipFilterSection<T> extends StatefulWidget {
  const ChipFilterSection({
    super.key,
    required this.title,
    required this.icon,
    required this.options,
    required this.labelOf,
    required this.isSelected,
    required this.selectedCount,
    required this.onToggle,
    required this.onClear,
    this.iconOf,
    this.iconColorOf,
    this.collapsedCount = 12,
    this.searchFrom = 20,
  });

  final String title;
  final IconData icon;
  final List<T> options;
  final String Function(T option) labelOf;
  final bool Function(T option) isSelected;
  final int selectedCount;
  final ValueChanged<T> onToggle;
  final VoidCallback onClear;

  /// A chip's own icon, and its tint while not picked (a platform's logo).
  final IconData? Function(T option)? iconOf;
  final Color? Function(T option)? iconColorOf;

  final int collapsedCount;
  final int searchFrom;

  @override
  State<ChipFilterSection<T>> createState() => _ChipFilterSectionState<T>();
}

class _ChipFilterSectionState<T> extends State<ChipFilterSection<T>> {
  bool _expanded = false;
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final options = widget.options;
    if (options.isEmpty) return const SizedBox.shrink();
    final folds = options.length > widget.collapsedCount;
    final searchable = _expanded && options.length >= widget.searchFrom;
    final query = searchable ? _query.trim().toLowerCase() : '';

    var listed = options;
    if (query.isNotEmpty) {
      listed = [
        for (final o in options)
          if (widget.labelOf(o).toLowerCase().contains(query)) o,
      ];
    } else if (folds && !_expanded) {
      listed = [
        for (var i = 0; i < options.length; i++)
          if (i < widget.collapsedCount || widget.isSelected(options[i]))
            options[i],
      ];
    }

    return FilterSection(
      title: widget.title,
      icon: widget.icon,
      selected: widget.selectedCount,
      onClear: widget.onClear,
      header: searchable
          ? TextField(
              onChanged: (v) => setState(() => _query = v),
              style: const TextStyle(fontSize: 14),
              decoration: InputDecoration(
                isDense: true,
                filled: true,
                fillColor: context.palette.surfaceHigh,
                hintText: 'Search ${widget.title.toLowerCase()}',
                hintStyle: TextStyle(color: context.palette.muted),
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
            label: widget.labelOf(o),
            icon: widget.iconOf?.call(o),
            iconColor: widget.iconColorOf?.call(o),
            selected: widget.isSelected(o),
            onSelected: () => widget.onToggle(o),
          ),
        if (query.isNotEmpty && listed.isEmpty)
          Padding(
            padding: EdgeInsets.symmetric(vertical: 6),
            child: Text('No match.', style: TextStyle(color: context.palette.muted)),
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

/// The release-year filter: a chip per decade from [min] to [max], and a slider
/// for any range in between. A slider end pulled all the way out leaves that end
/// open, so it also takes in the years past it.
class YearRangeSection extends StatelessWidget {
  const YearRangeSection({
    super.key,
    required this.value,
    required this.onChanged,
    required this.min,
    required this.max,
  });

  final YearRange value;
  final ValueChanged<YearRange> onChanged;
  final int min;
  final int max;

  @override
  Widget build(BuildContext context) {
    final decades = [
      for (var d = max ~/ 10 * 10; d >= min ~/ 10 * 10; d -= 10) d,
    ];
    final from = (value.from ?? min).clamp(min, max);
    final to = (value.to ?? max).clamp(min, max);
    return FilterSection(
      title: 'Release year',
      icon: Icons.event_rounded,
      selected: value.isAny ? 0 : 1,
      summary: value.label,
      onClear: () => onChanged(YearRange.any),
      children: [
        for (final d in decades)
          AppChoiceChip(
            label: '${d}s',
            selected: value == YearRange.decade(d),
            onSelected: () => onChanged(
              value == YearRange.decade(d)
                  ? YearRange.any
                  : YearRange.decade(d),
            ),
          ),
        if (max > min)
          SizedBox(
            width: double.infinity,
            child: RangeSlider(
              min: min.toDouble(),
              max: max.toDouble(),
              divisions: max - min,
              values: RangeValues(from.toDouble(), to.toDouble()),
              labels: RangeLabels('$from', '$to'),
              onChanged: (range) {
                final start = range.start.round();
                final end = range.end.round();
                onChanged(
                  YearRange(
                    from: start <= min ? null : start,
                    to: end >= max ? null : end,
                  ),
                );
              },
            ),
          ),
      ],
    );
  }
}

/// What is picked, as a row of removable chips, so it is clear why a list is
/// short; nothing when nothing is picked. [labelOf] names an attribute's value
/// (the value itself unless given).
class ActiveFilterChips extends StatelessWidget {
  const ActiveFilterChips({
    super.key,
    required this.filters,
    required this.onChanged,
    this.labelOf,
    this.padding = const EdgeInsets.symmetric(horizontal: 16),
  });

  final FilterOptions filters;
  final ValueChanged<FilterOptions> onChanged;
  final String Function(GameAttribute attribute, String value)? labelOf;

  /// Around the row, which scrolls sideways under it.
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    if (filters.isEmpty) return const SizedBox.shrink();

    Widget chip({
      required IconData icon,
      required Color color,
      required String label,
      required FilterOptions without,
    }) => Padding(
      padding: const EdgeInsets.only(right: 6),
      child: InputChip(
        avatar: Icon(icon, size: 16, color: color),
        label: Text(label, style: const TextStyle(fontSize: 12.5)),
        onDeleted: () => onChanged(without),
        deleteIcon: const Icon(Icons.close_rounded, size: 16),
        deleteButtonTooltipMessage: 'Remove $label',
        backgroundColor: context.palette.surfaceHigh,
        side: BorderSide(color: context.palette.accent.withValues(alpha: 0.5)),
        shape: const StadiumBorder(),
        visualDensity: VisualDensity.compact,
      ),
    );

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: padding,
      child: Row(
        children: [
          for (final p in GamePlatform.values)
            if (filters.platforms.contains(p))
              chip(
                icon: p.icon,
                color: context.palette.legible(p.color),
                label: p.label,
                without: filters.togglePlatform(p),
              ),
          if (!filters.years.isAny)
            chip(
              icon: Icons.event_rounded,
              color: context.palette.muted,
              label: filters.years.label,
              without: filters.withYears(YearRange.any),
            ),
          for (final a in GameAttribute.values)
            for (final value in filters.valuesOf(a))
              chip(
                icon: a.icon,
                color: context.palette.muted,
                label: labelOf?.call(a, value) ?? value,
                without: filters.toggle(a, value),
              ),
          if (filters.count > 1)
            TextButton(
              onPressed: () => onChanged(filters.cleared()),
              child: const Text('Clear all'),
            ),
        ],
      ),
    );
  }
}

// ---- The Discover tab's sheet ----

/// The oldest year the Discover sheet's slider starts at: pulled all the way
/// out it takes in anything older.
const _discoverFirstYear = 1970;

/// Opens the Discover filter sheet on [initial] and answers what was picked in it
/// when it closes, or null when nothing changed. Nothing is fetched while it is
/// open: every request counts against the IGDB quota, so the caller searches
/// once, with what it answers. [searching] says a search text is in the box,
/// which IGDB orders by relevance whatever the sort.
Future<FilterOptions?> showDiscoverFilterSheet(
  BuildContext context, {
  required FilterOptions initial,
  bool searching = false,
}) async {
  final draft = ValueNotifier(initial);
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => DiscoverFilterSheet(draft: draft, searching: searching),
  );
  final picked = draft.value;
  draft.dispose();
  return picked == initial ? null : picked;
}

/// What the Discover tab can be filtered by: the order, IGDB's genres, game
/// modes, platforms and themes, and the release years. Edits [draft]; closing the
/// sheet, or "Show results", is what applies it.
class DiscoverFilterSheet extends StatelessWidget {
  const DiscoverFilterSheet({
    super.key,
    required this.draft,
    this.searching = false,
  });

  final ValueNotifier<FilterOptions> draft;
  final bool searching;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<FilterOptions>(
      valueListenable: draft,
      builder: (context, filters, _) {
        // Every change is made to the draft as it is when the chip is tapped,
        // not as it was drawn: two taps in one frame both count.
        void edit(FilterOptions Function(FilterOptions f) change) =>
            draft.value = change(draft.value);
        final count = filters.count;
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: SheetFrame(
                title: 'Filter games',
                subtitle: count == 0
                    ? 'Browse IGDB by genre, mode, platform, theme and year.'
                    : '$count ${count == 1 ? 'filter' : 'filters'} picked',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    FilterSection(
                      title: 'Sort by',
                      icon: Icons.sort_rounded,
                      selected: 0,
                      onClear: null,
                      children: [
                        for (final s in DiscoverSort.values)
                          AppChoiceChip(
                            label: s.label,
                            selected: filters.sort == s,
                            onSelected: () => edit((f) => f.withSort(s)),
                          ),
                        if (searching)
                          Padding(
                            padding: EdgeInsets.only(top: 4),
                            child: Text(
                              'A search is ordered by relevance. The order '
                              'applies when you browse by filters alone.',
                              style: TextStyle(
                                color: context.palette.muted,
                                fontSize: 12.5,
                              ),
                            ),
                          ),
                      ],
                    ),
                    _tagSection(GameAttribute.genre, filters, edit),
                    _tagSection(GameAttribute.gameMode, filters, edit),
                    ChipFilterSection<GamePlatform>(
                      title: 'Platforms',
                      icon: Icons.sports_esports_rounded,
                      options: GameApiService.discoverPlatforms,
                      labelOf: (p) => p.label,
                      iconOf: (p) => p.icon,
                      iconColorOf: (p) => context.palette.legible(p.color),
                      isSelected: filters.platforms.contains,
                      selectedCount: filters.platforms.length,
                      onToggle: (p) => edit((f) => f.togglePlatform(p)),
                      onClear: () => edit((f) => f.withPlatforms(const [])),
                      collapsedCount: 9,
                    ),
                    _tagSection(GameAttribute.theme, filters, edit),
                    YearRangeSection(
                      value: filters.years,
                      onChanged: (years) => edit((f) => f.withYears(years)),
                      min: _discoverFirstYear,
                      // Next year too: announced games have a date.
                      max: DateTime.now().year + 1,
                    ),
                  ],
                ),
              ),
            ),
            _SheetFooter(
              canClear: !filters.isEmpty,
              onClear: () => edit((f) => f.cleared()),
            ),
          ],
        );
      },
    );
  }

  /// The chips of IGDB's list for [attribute] (see [CatalogTags]).
  Widget _tagSection(
    GameAttribute attribute,
    FilterOptions filters,
    void Function(FilterOptions Function(FilterOptions f) change) edit,
  ) {
    return ChipFilterSection<CatalogTag>(
      title: attribute.pluralLabel,
      icon: attribute.icon,
      options: CatalogTags.of(attribute),
      labelOf: (t) => t.label,
      isSelected: (t) => filters.has(attribute, t.name),
      selectedCount: filters.valuesOf(attribute).length,
      onToggle: (t) => edit((f) => f.toggle(attribute, t.name)),
      onClear: () => edit((f) => f.clear(attribute)),
    );
  }
}

/// "Clear all" and "Show results", kept in view under the scrolling sheet.
class _SheetFooter extends StatelessWidget {
  const _SheetFooter({required this.canClear, required this.onClear});

  final bool canClear;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(color: context.palette.hairline),
        ),
      ),
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          12,
          8,
          20,
          MediaQuery.paddingOf(context).bottom + 12,
        ),
        child: Row(
          children: [
            TextButton(
              onPressed: canClear ? onClear : null,
              child: const Text('Clear all'),
            ),
            const Spacer(),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Show results'),
            ),
          ],
        ),
      ),
    );
  }
}
