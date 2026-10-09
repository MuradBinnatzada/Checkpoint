import 'package:flutter/material.dart';

import 'package:checkpoint/app/nav_tab.dart';
import 'package:checkpoint/models/game.dart';
import 'package:checkpoint/state/checkpoint_store.dart';
import 'package:checkpoint/state/library_state.dart';
import 'package:checkpoint/state/store_scope.dart';
import 'package:checkpoint/theme/palette.dart';
import 'package:checkpoint/utils/formatters.dart';
import 'package:checkpoint/utils/navigation.dart';
import 'package:checkpoint/widgets/cover_art.dart';
import 'package:checkpoint/widgets/empty_state.dart';
import 'package:checkpoint/widgets/star_rating.dart';

class LibraryScreen extends StatefulWidget {
  const LibraryScreen({super.key});

  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

/// Owns the status-tab `TabController` and keeps it in lock-step with
/// `store.currentLibraryTabIndex` in both directions:
///   user taps/swipes a tab  → controller listener → store.setLibraryTabIndex
///   store.openLibraryTab()  → store listener      → controller.index = …
/// Both sides compare before writing, so the two listeners can never loop.
class _LibraryScreenState extends State<LibraryScreen>
    with SingleTickerProviderStateMixin {
  late final CheckpointStore _store;
  late final TabController _tabs;

  @override
  void initState() {
    super.initState();
    _store = context.actions; // non-subscribing lookup is allowed in initState
    _tabs = TabController(
      length: GameStatus.values.length,
      vsync: this,
      initialIndex: _store.currentLibraryTabIndex,
    )..addListener(_onTabsChanged);
    _store.addListener(_onStoreChanged);
  }

  @override
  void dispose() {
    _store.removeListener(_onStoreChanged);
    _tabs
      ..removeListener(_onTabsChanged)
      ..dispose();
    super.dispose();
  }

  void _onTabsChanged() {
    final i = _tabs.index;
    if (i != _store.currentLibraryTabIndex) _store.setLibraryTabIndex(i);
  }

  void _onStoreChanged() {
    final i = _store.currentLibraryTabIndex;
    if (i != _tabs.index) _tabs.index = i;
  }

  @override
  Widget build(BuildContext context) {
    final store = context.store;
    return SafeArea(
      bottom: false,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 8, 0),
            child: Row(
              children: [
                const Expanded(
                  child: Text(
                    'My Library',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800),
                  ),
                ),
                _PlatformFilterButton(selected: store.platformFilter),
                _SortButton(
                  field: store.sortField,
                  descending: store.sortDescending,
                ),
                const SizedBox(width: 4),
                _ViewToggle(view: store.libraryView),
                const SizedBox(width: 8),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 2, 20, 10),
            child: Text(
              'Sorted by ${store.sortField.label} · ${store.sortDescending ? 'high to low' : 'low to high'}'
              '${store.platformFilter != null ? ' · ${store.platformFilter!.label}' : ''}',
              style: const TextStyle(color: Palette.muted, fontSize: 12.5),
            ),
          ),
          TabBar(
            controller: _tabs,
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
            labelStyle: const TextStyle(
              fontWeight: FontWeight.w700,
              fontSize: 13.5,
            ),
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
              for (final s in GameStatus.values)
                Tab(
                  height: 38,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(s.label),
                        const SizedBox(width: 6),
                        Text(
                          '${store.libraryFor(s).length}',
                          style: const TextStyle(
                            fontWeight: FontWeight.w500,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Expanded(
            child: TabBarView(
              controller: _tabs,
              children: [
                for (final s in GameStatus.values) LibraryCollection(status: s),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ViewToggle extends StatelessWidget {
  const _ViewToggle({required this.view});
  final LibraryView view;

  @override
  Widget build(BuildContext context) {
    Widget cell(LibraryView v, IconData icon, String tooltip) {
      final active = v == view;
      return Tooltip(
        message: tooltip,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => context.actions.setLibraryView(v),
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

class _SortButton extends StatelessWidget {
  const _SortButton({required this.field, required this.descending});
  final SortField field;
  final bool descending;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<SortField>(
      tooltip: 'Sort',
      icon: const Icon(Icons.sort_rounded),
      onSelected: context.actions.setSort,
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

class _PlatformFilterButton extends StatelessWidget {
  const _PlatformFilterButton({required this.selected});
  final GamePlatform? selected;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<Object>(
      tooltip: 'Filter by platform',
      icon: Icon(
        Icons.filter_list_rounded,
        color: selected != null ? Palette.accent : null,
      ),
      onSelected: (v) =>
          context.actions.setPlatformFilter(v is GamePlatform ? v : null),
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
        for (final p in GamePlatform.values)
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

class LibraryCollection extends StatelessWidget {
  const LibraryCollection({super.key, required this.status});
  final GameStatus status;

  @override
  Widget build(BuildContext context) {
    final store = context.store;
    if (store.isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    final error = store.lastError;
    if (error != null) {
      return EmptyState(
        icon: Icons.cloud_off_rounded,
        title: 'Could not load library',
        message: error,
        actionLabel: 'Retry',
        onAction: () => context.actions.refresh(),
      );
    }

    final games = store.libraryFor(status);
    if (games.isEmpty) {
      final p = store.platformFilter;
      return EmptyState(
        icon: status.icon,
        title: p != null
            ? 'No ${status.label.toLowerCase()} games on ${p.label}'
            : 'Nothing in ${status.label} yet',
        message: p != null
            ? 'Clear the platform filter to see everything.'
            : 'Find something new in Discover and add it here.',
        actionLabel: p != null ? 'Clear filter' : 'Discover games',
        onAction: () => p != null
            ? context.actions.setPlatformFilter(null)
            : context.actions.setBottomNavIndex(NavTab.search),
      );
    }
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 220),
      child: store.libraryView == LibraryView.grid
          ? _PosterGrid(key: ValueKey('grid-${status.name}'), games: games)
          : _GameList(key: ValueKey('list-${status.name}'), games: games),
    );
  }
}

class _PosterGrid extends StatelessWidget {
  const _PosterGrid({super.key, required this.games});
  final List<Game> games;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) {
        final cols = c.maxWidth >= 900 ? 6 : (c.maxWidth >= 600 ? 5 : 3);
        return GridView.builder(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
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

class _GameList extends StatelessWidget {
  const _GameList({super.key, required this.games});
  final List<Game> games;

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 32),
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
                        const Text(
                          '  ·  ',
                          style: TextStyle(color: Palette.muted),
                        ),
                      ],
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
