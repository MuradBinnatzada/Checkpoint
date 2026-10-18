import 'package:flutter/material.dart';

import 'package:checkpoint/models/game.dart';
import 'package:checkpoint/state/library_state.dart';
import 'package:checkpoint/state/library_view_store.dart';
import 'package:checkpoint/state/store_scope.dart';
import 'package:checkpoint/theme/palette.dart';
import 'package:checkpoint/utils/formatters.dart';
import 'package:checkpoint/utils/navigation.dart';
import 'package:checkpoint/widgets/cover_art.dart';
import 'package:checkpoint/widgets/star_rating.dart';

// The controls and game views of a Library screen: search box, grid / list toggle,
// sort and platform-filter menus, and the poster grid and list themselves. They
// read and write the nearest [LibraryViewStore], so the signed-in member's Library
// tab and another member's Library screen (which provides its own store) share
// them.

/// Dark rounded search field shown between the tab bar and the game grid/list.
class LibrarySearchField extends StatelessWidget {
  const LibrarySearchField({
    super.key,
    required this.controller,
    required this.tabLabel,
    required this.hasText,
    required this.onChanged,
    required this.onClear,
    this.trailing,
  });
  final TextEditingController controller;
  final String tabLabel;
  final bool hasText;
  final ValueChanged<String> onChanged;
  final VoidCallback onClear;

  /// Beside the field, on its right (the filter button).
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final border = OutlineInputBorder(
      borderRadius: BorderRadius.circular(14),
      borderSide: BorderSide.none,
    );
    final field = TextField(
      controller: controller,
      onChanged: onChanged,
      textInputAction: TextInputAction.search,
      cursorColor: Palette.accent,
      style: const TextStyle(fontSize: 15),
      decoration: InputDecoration(
        isDense: true,
        filled: true,
        fillColor: Palette.surfaceHigh,
        contentPadding: const EdgeInsets.symmetric(vertical: 12),
        hintText: 'Search in $tabLabel',
        hintStyle: const TextStyle(color: Palette.muted),
        prefixIcon: const Icon(Icons.search_rounded, color: Palette.muted),
        suffixIcon: hasText
            ? IconButton(
                tooltip: 'Clear search',
                icon: const Icon(Icons.close_rounded, color: Palette.muted),
                onPressed: onClear,
              )
            : null,
        border: border,
        enabledBorder: border,
        focusedBorder: border.copyWith(
          borderSide: BorderSide(
            color: Palette.accent.withValues(alpha: 0.6),
          ),
        ),
      ),
    );
    final trailing = this.trailing;
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 0, trailing == null ? 16 : 6, 4),
      child: trailing == null
          ? field
          : Row(
              children: [
                Expanded(child: field),
                const SizedBox(width: 2),
                trailing,
              ],
            ),
    );
  }
}

class LibraryViewToggle extends StatelessWidget {
  const LibraryViewToggle({super.key, required this.view});
  final LibraryView view;

  @override
  Widget build(BuildContext context) {
    Widget cell(LibraryView v, IconData icon, String tooltip) {
      final active = v == view;
      return Tooltip(
        message: tooltip,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => context.read<LibraryViewStore>().setView(v),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            width: 38,
            height: 34,
            decoration: BoxDecoration(
              color: active
                  ? Palette.accent.withValues(alpha: 0.20)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              icon,
              size: 20,
              color: active ? Palette.accent : Palette.muted,
            ),
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: Palette.surfaceHigh,
        borderRadius: BorderRadius.circular(13),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          cell(LibraryView.grid, Icons.grid_view_rounded, 'Poster grid'),
          cell(LibraryView.list, Icons.view_list_rounded, 'List'),
        ],
      ),
    );
  }
}

class LibrarySortButton extends StatelessWidget {
  const LibrarySortButton({
    super.key,
    required this.field,
    required this.descending,
  });
  final SortField field;
  final bool descending;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<SortField>(
      tooltip: 'Sort',
      icon: const Icon(Icons.sort_rounded),
      onSelected: context.read<LibraryViewStore>().setSort,
      itemBuilder: (_) => [
        for (final f in SortField.values)
          PopupMenuItem(
            value: f,
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    f.label,
                    style: TextStyle(
                      fontWeight: f == field
                          ? FontWeight.w800
                          : FontWeight.w500,
                      color: f == field ? Palette.accent : null,
                    ),
                  ),
                ),
                if (f == field)
                  Icon(
                    descending
                        ? Icons.arrow_downward_rounded
                        : Icons.arrow_upward_rounded,
                    size: 16,
                    color: Palette.accent,
                  ),
              ],
            ),
          ),
      ],
    );
  }
}

class LibraryPlatformFilterButton extends StatelessWidget {
  const LibraryPlatformFilterButton({
    super.key,
    required this.selected,
    required this.options,
  });
  final GamePlatform? selected;
  final List<GamePlatform> options;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<Object>(
      tooltip: 'Filter by platform',
      icon: Icon(
        Icons.filter_list_rounded,
        color: selected != null ? Palette.accent : null,
      ),
      onSelected: (v) => context.read<LibraryViewStore>().setPlatformFilter(
        v is GamePlatform ? v : null,
      ),
      itemBuilder: (_) => [
        PopupMenuItem<Object>(
          value: 'all',
          child: Text(
            'All platforms',
            style: TextStyle(
              fontWeight: selected == null ? FontWeight.w800 : FontWeight.w500,
              color: selected == null ? Palette.accent : null,
            ),
          ),
        ),
        for (final p in options)
          PopupMenuItem<Object>(
            value: p,
            child: Row(
              children: [
                Icon(p.icon, size: 18, color: p.color),
                const SizedBox(width: 10),
                Text(
                  p.label,
                  style: TextStyle(
                    fontWeight: selected == p
                        ? FontWeight.w800
                        : FontWeight.w500,
                    color: selected == p ? Palette.accent : null,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class LibraryPosterGrid extends StatelessWidget {
  const LibraryPosterGrid({super.key, required this.games});
  final List<Game> games;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) {
        final cols = c.maxWidth >= 900 ? 6 : (c.maxWidth >= 600 ? 5 : 3);
        return GridView.builder(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: cols,
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
            childAspectRatio: 2 / 3,
          ),
          itemCount: games.length,
          itemBuilder: (_, i) => _PosterTile(game: games[i]),
        );
      },
    );
  }
}

class _PosterTile extends StatelessWidget {
  const _PosterTile({required this.game});
  final Game game;

  Widget _badge(Widget child) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
    decoration: BoxDecoration(
      color: Colors.black.withValues(alpha: 0.62),
      borderRadius: BorderRadius.circular(8),
    ),
    child: child,
  );

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Positioned.fill(child: CoverArt(game: game)),
        if (game.rating > 0)
          Positioned(
            left: 6,
            top: 6,
            child: _badge(
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.star_rounded, size: 12, color: Palette.star),
                  const SizedBox(width: 2),
                  Text(
                    fmtHours(game.rating),
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
          ),
        if (game.hoursPlayed > 0)
          Positioned(
            right: 6,
            top: 6,
            child: _badge(
              Text(
                '${fmtHours(game.hoursPlayed)}h',
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
        Positioned.fill(
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: () => openGame(context, game.id),
            ),
          ),
        ),
      ],
    );
  }
}

class LibraryGameList extends StatelessWidget {
  const LibraryGameList({super.key, required this.games});
  final List<Game> games;

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 32),
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      itemCount: games.length,
      separatorBuilder: (context, index) => Divider(
        height: 1,
        indent: 82,
        color: Colors.white.withValues(alpha: 0.06),
      ),
      itemBuilder: (_, i) => _LibraryListTile(game: games[i]),
    );
  }
}

class _LibraryListTile extends StatelessWidget {
  const _LibraryListTile({required this.game});
  final Game game;

  @override
  Widget build(BuildContext context) {
    final platform =
        game.playedOn ??
        (game.platforms.isNotEmpty ? game.platforms.first : null);
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: () => openGame(context, game.id),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
        child: Row(
          children: [
            SizedBox(width: 60, child: CoverArt(game: game, radius: 10)),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    game.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      if (platform != null) ...[
                        Icon(platform.icon, size: 14, color: platform.color),
                        const SizedBox(width: 5),
                        Flexible(
                          child: Text(
                            platform.label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 12.5,
                              color: platform.color,
                            ),
                          ),
                        ),
                      ],
                      if (platform != null && game.hasReleaseYear)
                        const Text(
                          '  ·  ',
                          style: TextStyle(color: Palette.muted),
                        ),
                      if (game.hasReleaseYear)
                        Text(
                          '${game.releaseYear}',
                          style: const TextStyle(
                            fontSize: 12.5,
                            color: Palette.muted,
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      game.rating > 0
                          ? StarRating(rating: game.rating, size: 15)
                          : const Text(
                              'Not rated',
                              style: TextStyle(
                                fontSize: 12,
                                color: Palette.muted,
                              ),
                            ),
                      const Spacer(),
                      const Icon(
                        Icons.schedule_rounded,
                        size: 14,
                        color: Palette.muted,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        game.hoursPlayed > 0
                            ? '${fmtHours(game.hoursPlayed)} h'
                            : '—',
                        style: const TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 4),
            const Icon(Icons.chevron_right_rounded, color: Palette.muted),
          ],
        ),
      ),
    );
  }
}

/// The row of status tabs of a Library: "All", then one per [GameStatus], each
/// with how many games it holds. [counts] has [GameStatus.values].length + 1
/// entries, "All" first.
class LibraryStatusTabBar extends StatelessWidget {
  const LibraryStatusTabBar({
    super.key,
    required this.controller,
    required this.counts,
  });

  final TabController controller;
  final List<int> counts;

  @override
  Widget build(BuildContext context) {
    Tab statusTab(String label, int count) => Tab(
      height: 38,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(label),
            const SizedBox(width: 6),
            Text(
              '$count',
              style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 12),
            ),
          ],
        ),
      ),
    );
    return TabBar(
      controller: controller,
      isScrollable: true,
      tabAlignment: TabAlignment.start,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      dividerColor: Colors.transparent,
      indicatorSize: TabBarIndicatorSize.tab,
      indicatorPadding: const EdgeInsets.symmetric(vertical: 2),
      splashBorderRadius: BorderRadius.circular(20),
      labelPadding: const EdgeInsets.symmetric(horizontal: 3),
      labelColor: Palette.accent,
      unselectedLabelColor: Palette.muted,
      labelStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5),
      unselectedLabelStyle: const TextStyle(
        fontWeight: FontWeight.w600,
        fontSize: 13.5,
      ),
      indicator: BoxDecoration(
        color: Palette.accent.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Palette.accent.withValues(alpha: 0.5)),
      ),
      tabs: [
        statusTab('All', counts[0]),
        for (var i = 0; i < GameStatus.values.length; i++)
          statusTab(GameStatus.values[i].label, counts[i + 1]),
      ],
    );
  }
}
