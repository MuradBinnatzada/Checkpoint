import 'package:flutter/material.dart';

import 'package:checkpoint/app/nav_tab.dart';
import 'package:checkpoint/models/game.dart';
import 'package:checkpoint/sheets/quick_log_sheet.dart';
import 'package:checkpoint/state/library_state.dart';
import 'package:checkpoint/state/library_store.dart';
import 'package:checkpoint/state/library_view_store.dart';
import 'package:checkpoint/state/nav_store.dart';
import 'package:checkpoint/state/profile_store.dart';
import 'package:checkpoint/state/store_scope.dart';
import 'package:checkpoint/theme/palette.dart';
import 'package:checkpoint/utils/formatters.dart';
import 'package:checkpoint/utils/navigation.dart';
import 'package:checkpoint/widgets/cover_art.dart';
import 'package:checkpoint/widgets/cover_backdrop.dart';
import 'package:checkpoint/widgets/game_poster_card.dart';
import 'package:checkpoint/widgets/panel.dart';
import 'package:checkpoint/widgets/profile_avatar.dart';
import 'package:checkpoint/widgets/section_header.dart';
import 'package:checkpoint/widgets/stat_tile.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final library = context.watch<LibraryStore>();
    final profile = context.watch<ProfileStore>().profile;
    return SafeArea(
      bottom: false,
      child: ListView(
        padding: const EdgeInsets.only(bottom: 112),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 4),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${greeting()},',
                        style: const TextStyle(
                          color: Palette.muted,
                          fontSize: 15,
                        ),
                      ),
                      Text(
                        profile.name.split(' ').first,
                        style: const TextStyle(
                          fontSize: 28,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                ),
                GestureDetector(
                  onTap: () =>
                      context.read<NavStore>().select(NavTab.profile),
                  child: ProfileAvatar(name: profile.name, size: 44, imageUrl: profile.avatarUrl),
                ),
              ],
            ),
          ),
          SectionHeader(
            'Currently Playing',
            actionLabel: 'See all',
            onAction: () => context.read<LibraryViewStore>().openTab(GameStatus.playing),
          ),
          _HeroBanner(games: library.playingNow()),
          const SizedBox(height: 20),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              children: [
                Expanded(
                  child: StatTile(
                    icon: Icons.schedule_rounded,
                    value: fmtHours(library.totalHours),
                    label: 'Hours logged',
                    onTap: () => context.read<LibraryViewStore>().openTab(
                      GameStatus.playing,
                      sortBy: SortField.hoursPlayed,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: StatTile(
                    icon: Icons.verified_rounded,
                    value: '${library.count(GameStatus.completed)}',
                    label: 'Completed',
                    onTap: () =>
                        context.read<LibraryViewStore>().openTab(GameStatus.completed),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: StatTile(
                    icon: Icons.inventory_2_rounded,
                    value: '${library.count(GameStatus.toPlay)}',
                    label: 'To Play',
                    onTap: () =>
                        context.read<LibraryViewStore>().openTab(GameStatus.toPlay),
                  ),
                ),
              ],
            ),
          ),
          const SectionHeader('Recent Activity'),
          const _RecentActivityRow(),
          const SectionHeader('Popular This Month'),
          _GameCarousel(
            games: library.popularThisMonth,
            icon: Icons.local_fire_department_rounded,
            caption: library.playersLabel,
          ),
          const SectionHeader('Trending Among Friends'),
          _GameCarousel(
            games: library.trendingAmongFriends,
            icon: Icons.group_rounded,
            caption: (g) {
              final n = library.friendsPlaying(g);
              return '$n friend${n == 1 ? '' : 's'} playing';
            },
          ),
        ],
      ),
    );
  }
}

class _GameCarousel extends StatelessWidget {
  const _GameCarousel({
    required this.games,
    required this.caption,
    required this.icon,
  });
  final List<Game> games;
  final String Function(Game) caption;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    const w = 124.0;
    return SizedBox(
      height: posterCardHeight(context, w, subtitle: true),
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        itemCount: games.length,
        separatorBuilder: (context, index) => const SizedBox(width: 14),
        itemBuilder: (_, i) => GamePosterCard(
          game: games[i],
          width: w,
          subtitle: caption(games[i]),
          subtitleIcon: icon,
        ),
      ),
    );
  }
}

class _HeroBanner extends StatefulWidget {
  const _HeroBanner({required this.games});
  final List<Game> games;

  @override
  State<_HeroBanner> createState() => _HeroBannerState();
}

class _HeroBannerState extends State<_HeroBanner> {
  final _controller = PageController(viewportFraction: 0.9);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final games = widget.games;
    if (games.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: Panel(
          child: Row(
            children: [
              const Icon(Icons.hourglass_empty_rounded, color: Palette.muted),
              const SizedBox(width: 12),
              const Expanded(
                child: Text(
                  'Nothing in progress. Pick something from your To Play list.',
                  style: TextStyle(color: Palette.muted),
                ),
              ),
              TextButton(
                onPressed: () =>
                    context.read<LibraryViewStore>().openTab(GameStatus.toPlay),
                child: const Text('To Play'),
              ),
            ],
          ),
        ),
      );
    }
    final scale = textScale(context);
    return SizedBox(
      height: 196 + (scale - 1) * 120,
      child: PageView.builder(
        controller: _controller,
        itemCount: games.length,
        itemBuilder: (_, i) => Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6),
          child: _HeroCard(game: games[i]),
        ),
      ),
    );
  }
}

class _HeroCard extends StatelessWidget {
  const _HeroCard({required this.game});
  final Game game;

  @override
  Widget build(BuildContext context) {
    final platform = game.playedOn ?? game.platforms.firstOrNull;
    return ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: Stack(
        fit: StackFit.expand,
        children: [
          // The chosen backdrop, or the blurred cover art (baked in, not a
          // BackdropFilter: see CoverBackdrop).
          CoverBackdrop(game: game),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                SizedBox(width: 92, child: CoverArt(game: game, showTitle: false)),
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
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                          height: 1.15,
                        ),
                      ),
                      if (platform != null) ...[
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            Icon(
                              platform.icon,
                              size: 14,
                              color: Colors.white70,
                            ),
                            const SizedBox(width: 5),
                            Expanded(
                              child: Text(
                                platform.label,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: Colors.white70,
                                  fontSize: 13,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                      const Spacer(),
                      Row(
                        children: [
                          Expanded(
                            child: Text.rich(
                              TextSpan(
                                children: [
                                  TextSpan(
                                    text: '${fmtHours(game.hoursPlayed)} hrs',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w800,
                                      fontSize: 17,
                                    ),
                                  ),
                                  const TextSpan(
                                    text: ' logged',
                                    style: TextStyle(
                                      color: Colors.white70,
                                      fontSize: 13,
                                    ),
                                  ),
                                ],
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          IconButton.filled(
                            tooltip: 'Log a session',
                            visualDensity: VisualDensity.compact,
                            onPressed: () =>
                                showQuickLogSheet(context, gameId: game.id),
                            icon: const Icon(Icons.add_rounded),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Positioned.fill(
            child: Material(
              color: Colors.transparent,
              child: InkWell(onTap: () => openGame(context, game.id)),
            ),
          ),
        ],
      ),
    );
  }
}

class _RecentActivityRow extends StatelessWidget {
  const _RecentActivityRow();

  @override
  Widget build(BuildContext context) {
    final library = context.watch<LibraryStore>();
    final entries = library.recentActivity(limit: 10);
    if (entries.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(horizontal: 20),
        child: Panel(
          child: Text(
            'Log your first session with the Log Game button.',
            style: TextStyle(color: Palette.muted),
          ),
        ),
      );
    }
    const w = 124.0;
    return SizedBox(
      height: posterCardHeight(context, w, subtitle: true),
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        itemCount: entries.length,
        separatorBuilder: (context, index) => const SizedBox(width: 14),
        itemBuilder: (context, i) {
          final e = entries[i];
          return GamePosterCard(
            game: library.gameById(e.gameId),
            width: w,
            subtitle: '+${fmtHours(e.hours)}h · ${timeAgo(e.timestamp)}',
            subtitleIcon: e.platform.icon,
          );
        },
      ),
    );
  }
}