import 'package:flutter/material.dart';

import 'package:checkpoint/l10n/l10n.dart';
import 'package:checkpoint/models/company.dart';
import 'package:checkpoint/models/filter_options.dart';
import 'package:checkpoint/models/studio_filters.dart';
import 'package:checkpoint/theme/palette.dart';
import 'package:checkpoint/utils/countries.dart' as countries;
import 'package:checkpoint/widgets/app_choice_chip.dart';
import 'package:checkpoint/widgets/filter_sheet.dart';
import 'package:checkpoint/widgets/sheet_frame.dart';

// The filters of the Studios tab on Discover, made of the same pieces as the
// games' (see filter_sheet.dart): a sheet of chips, and a row of what is picked.
// They work on a [StudioFilters] value and hand every change back as a new one.

/// The oldest founding year the sheet's slider starts at: pulled all the way out
/// it takes in anything older (what `igdb-handler` accepts goes no further back).
const _firstFoundedYear = 1970;

/// The role a chip or the sheet names: "Developers", "Publishers", "All".
String studioRoleLabel(CompanyRole role) => switch (role) {
  CompanyRole.any => L10n.current.companyRoleAll,
  CompanyRole.developer => L10n.current.studioRoleDevelopers,
  CompanyRole.publisher => L10n.current.studioRolePublishers,
};

/// Opens the studio filter sheet on [initial] and answers what was picked in it
/// when it closes, or null when nothing changed. Like the games' sheet nothing is
/// fetched while it is open: the caller searches once, with what it answers.
Future<StudioFilters?> showStudioFilterSheet(
  BuildContext context, {
  required StudioFilters initial,
}) async {
  final draft = ValueNotifier(initial);
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => StudioFilterSheet(draft: draft),
  );
  final picked = draft.value;
  draft.dispose();
  return picked == initial ? null : picked;
}

/// What the Studios tab can be filtered by: the order, the role, the country and
/// the years a studio was founded in. Edits [draft]; closing the sheet, or "Show
/// results", is what applies it.
class StudioFilterSheet extends StatelessWidget {
  const StudioFilterSheet({super.key, required this.draft});

  final ValueNotifier<StudioFilters> draft;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<StudioFilters>(
      valueListenable: draft,
      builder: (context, filters, _) {
        // Every change is made to the draft as it is when the chip is tapped,
        // not as it was drawn: two taps in one frame both count.
        void edit(StudioFilters Function(StudioFilters f) change) =>
            draft.value = change(draft.value);
        final count = filters.count;
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: SheetFrame(
                title: context.l10n.filterStudios,
                subtitle: count == 0
                    ? context.l10n.filterStudiosSubtitle
                    : context.l10n.filtersPicked(count),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    FilterSection(
                      title: context.l10n.sortBy,
                      icon: Icons.sort_rounded,
                      selected: 0,
                      onClear: null,
                      children: [
                        for (final s in StudioSort.values)
                          AppChoiceChip(
                            label: s.label,
                            selected: filters.sort == s,
                            onSelected: () => edit((f) => f.withSort(s)),
                          ),
                      ],
                    ),
                    FilterSection(
                      title: context.l10n.studioRole,
                      icon: Icons.work_outline_rounded,
                      selected: filters.role == CompanyRole.any ? 0 : 1,
                      summary: studioRoleLabel(filters.role),
                      onClear: () => edit((f) => f.withRole(CompanyRole.any)),
                      children: [
                        for (final r in CompanyRole.values)
                          AppChoiceChip(
                            label: studioRoleLabel(r),
                            selected: filters.role == r,
                            onSelected: () => edit((f) => f.withRole(r)),
                          ),
                      ],
                    ),
                    ChipFilterSection<int>(
                      title: context.l10n.country,
                      icon: Icons.public_rounded,
                      options: countries.countryCodes(),
                      labelOf: (c) => countries.countryName(c) ?? '$c',
                      isSelected: filters.countries.contains,
                      selectedCount: filters.countries.length,
                      onToggle: (c) => edit((f) => f.toggleCountry(c)),
                      onClear: () => edit((f) => f.withCountries(const [])),
                    ),
                    YearRangeSection(
                      title: context.l10n.foundedFilter,
                      value: filters.founded,
                      onChanged: (years) => edit((f) => f.withFounded(years)),
                      min: _firstFoundedYear,
                      max: DateTime.now().year,
                    ),
                  ],
                ),
              ),
            ),
            FilterSheetFooter(
              canClear: !filters.isEmpty,
              onClear: () => edit((f) => f.cleared()),
            ),
          ],
        );
      },
    );
  }
}

/// What is picked, as a row of removable chips, so it is clear why a list is
/// short; nothing when nothing is picked.
class StudioFilterChips extends StatelessWidget {
  const StudioFilterChips({
    super.key,
    required this.filters,
    required this.onChanged,
    this.padding = const EdgeInsets.symmetric(horizontal: 16),
  });

  final StudioFilters filters;
  final ValueChanged<StudioFilters> onChanged;

  /// Around the row, which scrolls sideways under it.
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    if (filters.isEmpty) return const SizedBox.shrink();
    final muted = context.palette.muted;
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: padding,
      child: Row(
        children: [
          if (filters.role != CompanyRole.any)
            FilterValueChip(
              icon: Icons.work_outline_rounded,
              color: muted,
              label: studioRoleLabel(filters.role),
              onRemoved: () => onChanged(filters.withRole(CompanyRole.any)),
            ),
          for (final c in filters.countries)
            FilterValueChip(
              icon: Icons.public_rounded,
              color: muted,
              label: countries.countryName(c) ?? '$c',
              onRemoved: () => onChanged(filters.toggleCountry(c)),
            ),
          if (!filters.founded.isAny)
            FilterValueChip(
              icon: Icons.event_rounded,
              color: muted,
              label: context.l10n.foundedRange(filters.founded.label),
              onRemoved: () => onChanged(filters.withFounded(YearRange.any)),
            ),
          if (filters.count > 1)
            TextButton(
              onPressed: () => onChanged(filters.cleared()),
              child: Text(context.l10n.clearAll),
            ),
        ],
      ),
    );
  }
}
