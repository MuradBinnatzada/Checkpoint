import 'package:flutter/material.dart';

import 'package:checkpoint/app/nav_tab.dart';
import 'package:checkpoint/models/browse.dart';
import 'package:checkpoint/models/friend_activity.dart';
import 'package:checkpoint/models/game.dart';
import 'package:checkpoint/models/release_alerts.dart';
import 'package:checkpoint/sheets/pick_next_sheet.dart';
import 'package:checkpoint/sheets/quick_log_sheet.dart';
import 'package:checkpoint/state/auth_store.dart';
import 'package:checkpoint/state/browse_store.dart';
import 'package:checkpoint/state/friends_feed_store.dart';
import 'package:checkpoint/state/library_state.dart';
import 'package:checkpoint/state/library_store.dart';
import 'package:checkpoint/state/library_view_store.dart';
import 'package:checkpoint/state/nav_store.dart';
import 'package:checkpoint/state/profile_store.dart';
import 'package:checkpoint/state/release_alerts_store.dart';
import 'package:checkpoint/state/store_scope.dart';
import 'package:checkpoint/theme/app_theme.dart';
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
                        style: TextStyle(
                          color: context.palette.muted,
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
                // A photo says nothing to a screen reader; 48 px to tap.
                Semantics(
                  button: true,
                  label: 'Your profile',
                  excludeSemantics: true,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () =>
                        context.read<NavStore>().select(NavTab.profile),
                    child: SizedBox.square(
                      dimension: 48,
                      child: Center(
                        child: ProfileAvatar(name: profile.name, size: 44, imageUrl: profile.avatarUrl),
                      ),
                    ),
                  ),
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
          if (context.watch<AuthStore>().isLoggedIn &&
              library.count(GameStatus.toPlay) + library.count(GameStatus.playing) >= 2)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
              child: OutlinedButton.icon(
                onPressed: () => showPickNextSheet(context),
                style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
                icon: const Icon(Icons.casino_rounded, size: 18),
                label: const Text('Can\'t decide? Pick my next game'),
              ),
            ),
          const _ReleasesRow(),
          const SectionHeader('Recent Activity'),
          const _RecentActivityRow(),
          const _FriendsFeedRow(),
          const _PopularRow(),
        ],
      ),
    );
  }
}

/// What is popular on IGDB right now: Discover's "Most popular" list, with each
/// game's IGDB score. IGDB answers signed-in members only, so for a visitor, and
/// while the list loads (or when IGDB can't be reached), the games most recently
/// added to the catalog stand in, under a title that says so.
class _PopularRow extends StatefulWidget {
  const _PopularRow();

  @override
  State<_PopularRow> createState() => _PopularRowState();
}

class _PopularRowState extends State<_PopularRow> {
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Runs again whenever a store watched in build changes. [BrowseStore.load]
    // does nothing while the list is loading or fresh, and a list that failed is
    // left alone (the catalog stands in), so this can't loop.
    final browse = context.read<BrowseStore>();
    if (context.read<AuthStore>().isLoggedIn &&
        !browse.hasFailed(BrowseMode.popular)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) browse.load(BrowseMode.popular);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final loggedIn = context.watch<AuthStore>().isLoggedIn;
    final popular = context.watch<BrowseStore>().entries(BrowseMode.popular);
    if (loggedIn && popular.isNotEmpty) {
      final scores = {for (final e in popular) e.game.id: e.score};
      return _CarouselSection(
        title: 'Popular Right Now',
        games: [for (final e in popular.take(10)) e.game],
        icon: Icons.star_rounded,
        caption: (g) {
          final score = scores[g.id];
          return score == null ? null : '${score.round()} / 100';
        },
      );
    }
    final recent = context.watch<LibraryStore>().recentlyAdded;
    if (recent.isEmpty) return const SizedBox.shrink();
    return _CarouselSection(
      title: 'Recently Added',
      games: recent,
      icon: Icons.event_rounded,
      caption: (g) => g.hasReleaseYear ? '${g.releaseYear}' : null,
    );
  }
}

/// A [SectionHeader] over a [_GameCarousel].
class _CarouselSection extends StatelessWidget {
  const _CarouselSection({
    required this.title,
    required this.games,
    required this.caption,
    required this.icon,
  });
  final String title;
  final List<Game> games;
  final String? Function(Game) caption;
  final IconData icon;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      SectionHeader(title),
      _GameCarousel(games: games, caption: caption, icon: icon),
    ],
  );
}

/// Wishlist release alerts: the wishlist games just out or coming out soon, each
/// captioned "Out now · Oct 10" or "Out in 5 days · Oct 24". Hidden when there
/// are none.
class _ReleasesRow extends StatelessWidget {
  const _ReleasesRow();

  @override
  Widget build(BuildContext context) {
    final alerts = context.watch<ReleaseAlertsStore>().alerts;
    if (alerts.isEmpty) return const SizedBox.shrink();
    final byId = {for (final a in alerts) a.game.id: a};
    return _CarouselSection(
      title: 'Wishlist Releases',
      games: [for (final a in alerts) a.game],
      icon: Icons.notifications_active_rounded,
      caption: (g) {
        final alert = byId[g.id]!;
        return '${releaseLabel(alert.daysAway)} · ${fmtMonthDay(g.releaseDate!)}';
      },
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
  final String? Function(Game) caption;
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
              Icon(Icons.hourglass_empty_rounded, color: context.palette.muted),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Nothing in progress. Pick something from your To Play list.',
                  style: TextStyle(color: context.palette.muted),
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
          // Text on the cover art, under a dark scrim: dark in either theme.
          child: DarkArtTheme(child: _HeroCard(game: games[i])),
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
              child: Semantics(
                button: true,
                label: 'Open ${game.title}',
                child: InkWell(onTap: () => openGame(context, game.id)),
              ),
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
    // A session whose game can't be found is left out, rather than failing the
    // whole tab.
    final entries = [
      for (final e in library.recentActivity(limit: 10))
        if (library.maybeGame(e.gameId) != null) e,
    ];
    if (entries.isEmpty) {
      return Padding(
        padding: EdgeInsets.symmetric(horizontal: 20),
        child: Panel(
          child: Text(
            'Log your first session with the Log Game button.',
            style: TextStyle(color: context.palette.muted),
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

/// "From people you follow": what the members you follow logged, completed or
/// rated lately, newest first (see [FriendsFeedStore]). Hidden when signed out,
/// until the answer is here, when it failed, and when none of them did anything.
class _FriendsFeedRow extends StatefulWidget {
  const _FriendsFeedRow();

  @override
  State<_FriendsFeedRow> createState() => _FriendsFeedRowState();
}

class _FriendsFeedRowState extends State<_FriendsFeedRow> {
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Runs again whenever the store changes, a sign-in included.
    // [FriendsFeedStore.load] does nothing when signed out, while a request runs
    // or for a while after one (answered or failed), so this can't loop.
    final feed = context.read<FriendsFeedStore>();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) feed.load();
    });
  }

  @override
  Widget build(BuildContext context) {
    final items = context.watch<FriendsFeedStore>().items;
    if (items.isEmpty) return const SizedBox.shrink();
    const w = 124.0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SectionHeader('From people you follow'),
        SizedBox(
          height: posterCardHeight(context, w, subtitle: true),
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 20),
            itemCount: items.length,
            separatorBuilder: (context, index) => const SizedBox(width: 14),
            itemBuilder: (context, i) =>
                _FriendActivityCard(item: items[i], width: w),
          ),
        ),
      ],
    );
  }
}

/// "+2h · 3h ago", "Completed", "Rated 4.5". A completion or a rating gets no
/// time: the only date other members can see is when the game was added.
String friendActivityCaption(FriendActivity item) => switch (item.kind) {
  FriendActivityKind.session =>
    '+${fmtHours(item.hours)}h · ${timeAgo(item.at)}',
  FriendActivityKind.completed => 'Completed',
  FriendActivityKind.rated => 'Rated ${fmtHours(item.rating)}',
};

/// One item of the friends feed: the game's cover (opens the game) with the
/// member's photo on its corner (opens their profile), then the game's title,
/// the member's name and what they did.
class _FriendActivityCard extends StatelessWidget {
  const _FriendActivityCard({required this.item, required this.width});

  final FriendActivity item;
  final double width;

  static const double _avatar = 34;

  @override
  Widget build(BuildContext context) {
    final member = item.member;
    final game = item.game;
    final icon = switch (item.kind) {
      FriendActivityKind.session => Icons.schedule_rounded,
      FriendActivityKind.completed => GameStatus.completed.icon,
      FriendActivityKind.rated => Icons.star_rounded,
    };
    void openMember() =>
        openProfile(context, userId: member.id, preview: member);
    return SizedBox(
      width: width,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Stack(
            children: [
              Semantics(
                button: true,
                label: 'Open ${game.title}',
                excludeSemantics: true,
                child: InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: () => openGame(context, game.id),
                  child: CoverArt(game: game),
                ),
              ),
              Positioned(
                left: 6,
                bottom: 6,
                child: Tooltip(
                  message: member.name,
                  child: Semantics(
                    button: true,
                    label: "Open ${member.name}'s profile",
                    excludeSemantics: true,
                    child: InkWell(
                      customBorder: const CircleBorder(),
                      onTap: openMember,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: context.palette.background,
                            width: 2,
                          ),
                        ),
                        child: ProfileAvatar(
                          name: member.name,
                          size: _avatar,
                          imageUrl: member.avatarUrl,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            game.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
          ),
          const SizedBox(height: 4),
          GestureDetector(
            onTap: openMember,
            child: Text(
              member.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 12, color: context.palette.textSoft),
            ),
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              Icon(icon, size: 12, color: context.palette.muted),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  friendActivityCaption(item),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 11, color: context.palette.muted),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
