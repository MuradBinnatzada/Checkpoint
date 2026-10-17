import 'dart:async';

import 'package:flutter/material.dart';

import 'package:checkpoint/models/game.dart';
import 'package:checkpoint/models/social_user.dart';
import 'package:checkpoint/screens/profile/achievements_section.dart';
import 'package:checkpoint/state/auth_store.dart';
import 'package:checkpoint/state/library_state.dart';
import 'package:checkpoint/state/profile_store.dart';
import 'package:checkpoint/state/public_profile_store.dart';
import 'package:checkpoint/state/social_graph_store.dart';
import 'package:checkpoint/state/store_scope.dart';
import 'package:checkpoint/theme/palette.dart';
import 'package:checkpoint/utils/formatters.dart';
import 'package:checkpoint/utils/navigation.dart';
import 'package:checkpoint/widgets/connected_service_badges.dart';
import 'package:checkpoint/widgets/count_stat.dart';
import 'package:checkpoint/widgets/empty_state.dart';
import 'package:checkpoint/widgets/favorite_games_row.dart';
import 'package:checkpoint/widgets/hours_by_platform_panel.dart';
import 'package:checkpoint/widgets/panel.dart';
import 'package:checkpoint/widgets/profile_avatar.dart';
import 'package:checkpoint/widgets/profile_link_rows.dart';
import 'package:checkpoint/widgets/ratings_panel.dart';
import 'package:checkpoint/widgets/recent_activity_panel.dart';
import 'package:checkpoint/widgets/stat_tile.dart';

/// Another member's profile, laid out like your own: who they are, their bio and
/// linked accounts, who follows them, then their favorites, latest sessions,
/// playtime, library numbers (each box opens their library), hours per platform,
/// ratings, and a short menu into their library and follow lists. Their
/// achievements stay behind a button.
///
/// [preview] is the row the member was tapped from; it fills in the name and
/// photo while the profile loads.
class PublicProfileScreen extends StatefulWidget {
  const PublicProfileScreen({super.key, required this.userId, this.preview});

  final String userId;
  final SocialUser? preview;

  @override
  State<PublicProfileScreen> createState() => _PublicProfileScreenState();
}

class _PublicProfileScreenState extends State<PublicProfileScreen> {
  @override
  void initState() {
    super.initState();
    // After the first frame: loading notifies, which isn't allowed during build.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(_load());
    });
  }

  Future<void> _load({bool force = false}) =>
      context.read<PublicProfileStore>().load(widget.userId, force: force);

  @override
  Widget build(BuildContext context) {
    final store = context.watch<PublicProfileStore>();
    final view = store.viewOf(widget.userId);
    final isSelf = context.watch<AuthStore>().user?.id == widget.userId;

    final Widget body;
    switch (view.status) {
      case PublicProfileStatus.notFound:
        body = const EmptyState(
          icon: Icons.person_off_rounded,
          title: 'Profile not found',
          message: 'This member may have deleted their account.',
        );
      case PublicProfileStatus.failed:
        body = EmptyState(
          icon: Icons.cloud_off_rounded,
          title: 'Could not load this profile',
          message: 'Check your connection and try again.',
          actionLabel: 'Try again',
          onAction: () => unawaited(_load(force: true)),
        );
      case PublicProfileStatus.loading:
        body = _Loading(preview: widget.preview);
      case PublicProfileStatus.ready:
        body = RefreshIndicator(
          onRefresh: () => _load(force: true),
          child: _Loaded(userId: widget.userId, view: view, isSelf: isSelf),
        );
    }

    return Scaffold(
      appBar: AppBar(),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: body,
          ),
        ),
      ),
    );
  }
}

/// Photo, name, @handle and, once known, when they joined.
class _Header extends StatelessWidget {
  const _Header({
    required this.name,
    required this.handle,
    this.avatarUrl,
    this.joined,
    this.isSelf = false,
  });

  final String name;
  final String handle;
  final String? avatarUrl;
  final DateTime? joined;
  final bool isSelf;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        ProfileAvatar(name: name, size: 76, imageUrl: avatarUrl),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w800,
                ),
              ),
              Text(
                handle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Palette.accent,
                  fontWeight: FontWeight.w600,
                ),
              ),
              if (isSelf || joined != null) ...[
                const SizedBox(height: 2),
                Text(
                  isSelf
                      ? 'This is you'
                      : 'Member since ${fmtMonthYear(joined!)}',
                  style: const TextStyle(color: Palette.muted, fontSize: 12.5),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _Loading extends StatelessWidget {
  const _Loading({this.preview});
  final SocialUser? preview;

  @override
  Widget build(BuildContext context) {
    final user = preview;
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
      children: [
        if (user != null)
          _Header(
            name: user.name,
            handle: user.handle,
            avatarUrl: user.avatarUrl,
          ),
        const SizedBox(height: 48),
        const Center(child: CircularProgressIndicator()),
      ],
    );
  }
}

class _Loaded extends StatelessWidget {
  const _Loaded({
    required this.userId,
    required this.view,
    required this.isSelf,
  });

  final String userId;
  final PublicProfileView view;
  final bool isSelf;

  @override
  Widget build(BuildContext context) {
    final profile = view.profile!;
    final stats = view.stats!;
    final library = view.library;
    final own = context.watch<ProfileStore>();
    final following = own.isFollowing(userId);

    // On your own profile the counts are the live ones from ProfileStore; on
    // someone else's, a follow you made after the page loaded is already in.
    final followers = isSelf
        ? own.followersCount
        : view.followersFor(viewerFollows: following);
    final followingCount = isSelf ? own.followingCount : stats.following;

    void openFollowers(FollowListKind kind) => openFollows(
      context,
      userId: userId,
      kind: kind,
      ownerName: profile.name,
    );
    void openLibrary({GameStatus? status, SortField? sortBy}) =>
        openPublicLibrary(
          context,
          userId: userId,
          ownerName: profile.name,
          status: status,
          sortBy: sortBy,
        );

    Widget statTile(IconData icon, GameStatus status, String label) => Expanded(
      child: StatTile(
        icon: icon,
        value: '${library.count(status)}',
        label: label,
        onTap: () => openLibrary(status: status),
      ),
    );

    final bio = profile.bio?.trim();
    final hasBio = bio != null && bio.isNotEmpty;
    final services = profile.connectedServices;

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
      children: [
        _Header(
          name: profile.name,
          handle: profile.handle,
          avatarUrl: profile.avatarUrl,
          joined: profile.joined,
          isSelf: isSelf,
        ),
        if (view.refreshFailed) ...[
          const SizedBox(height: 10),
          const Text(
            'Could not refresh. Showing the last copy.',
            style: TextStyle(color: Palette.muted, fontSize: 12.5),
          ),
        ],
        const SizedBox(height: 14),
        if (hasBio || services.isNotEmpty) ...[
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (hasBio)
                Text(
                  bio,
                  style: const TextStyle(height: 1.4, color: Colors.white70),
                ),
              if (hasBio && services.isNotEmpty) const SizedBox(height: 12),
              if (services.isNotEmpty)
                ConnectedServiceBadges(
                  services: services,
                  steamId: profile.steamId,
                  psnId: profile.psnId,
                  xboxId: profile.xboxId,
                  discordId: profile.discordId,
                ),
            ],
          ),
          const SizedBox(height: 16),
        ],
        // Tapping a count opens the list behind it.
        Row(
          children: [
            CountStat(
              value: fmtCount(followers),
              label: 'Followers',
              onTap: () => openFollowers(FollowListKind.followers),
            ),
            const SizedBox(width: 14),
            CountStat(
              value: fmtCount(followingCount),
              label: 'Following',
              onTap: () => openFollowers(FollowListKind.following),
            ),
          ],
        ),
        if (!isSelf) ...[
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: following
                ? OutlinedButton(
                    onPressed: () => _toggleFollow(context),
                    child: const Text('Following'),
                  )
                : FilledButton(
                    onPressed: () => _toggleFollow(context),
                    child: const Text('Follow'),
                  ),
          ),
        ],
        const SizedBox(height: 28),
        const _SectionTitle('Favorite Games'),
        if (view.favorites.isEmpty)
          const Panel(
            child: Text(
              'No favorites picked yet.',
              style: TextStyle(
                color: Palette.muted,
                fontSize: 13,
                height: 1.35,
              ),
            ),
          )
        else
          FavoriteGamesRow(games: view.favorites),
        const SizedBox(height: 28),
        RecentActivityPanel(entries: view.activity),
        const SizedBox(height: 24),
        Text(
          'Total Playtime: ${fmtHours(library.totalHours)} hours',
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            statTile(Icons.play_arrow_rounded, GameStatus.playing, 'Playing'),
            const SizedBox(width: 10),
            statTile(Icons.verified_rounded, GameStatus.completed, 'Completed'),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            statTile(Icons.inventory_2_rounded, GameStatus.toPlay, 'To Play'),
            const SizedBox(width: 10),
            statTile(Icons.block_rounded, GameStatus.dropped, 'Dropped'),
          ],
        ),
        const SizedBox(height: 14),
        HoursByPlatformPanel(
          hours: library.hoursByPlatform,
          emptyText: 'No hours logged yet.',
        ),
        const SizedBox(height: 14),
        RatingsPanel(stats: library),
        const SizedBox(height: 24),
        ProfileLinkRows(
          links: [
            ProfileLink(
              icon: Icons.collections_bookmark_rounded,
              label: 'Library',
              count: library.games,
              onTap: () => openLibrary(),
            ),
            ProfileLink(
              icon: Icons.bookmark_rounded,
              label: 'Wishlist',
              count: library.count(GameStatus.wishlist),
              onTap: () => openLibrary(status: GameStatus.wishlist),
            ),
            ProfileLink(
              icon: Icons.star_rounded,
              label: 'Top rated',
              count: library.ratedCount,
              onTap: () => openLibrary(sortBy: SortField.rating),
            ),
            ProfileLink(
              icon: Icons.people_alt_rounded,
              label: 'Followers',
              count: followers,
              onTap: () => openFollowers(FollowListKind.followers),
            ),
            ProfileLink(
              icon: Icons.person_add_alt_1_rounded,
              label: 'Following',
              count: followingCount,
              onTap: () => openFollowers(FollowListKind.following),
            ),
          ],
        ),
        const SizedBox(height: 14),
        // Fetched only when "View Achievements" is pressed.
        AchievementsSection(userId: userId),
      ],
    );
  }

  void _toggleFollow(BuildContext context) {
    if (!context.read<AuthStore>().isLoggedIn) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(content: Text('Log in to follow people')),
        );
      return;
    }
    unawaited(context.read<ProfileStore>().toggleFollow(userId));
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.title);
  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Text(
        title,
        style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w800),
      ),
    );
  }
}
