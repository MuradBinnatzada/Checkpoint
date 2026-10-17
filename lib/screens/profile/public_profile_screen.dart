import 'dart:async';

import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

import 'package:checkpoint/models/connected_service.dart';
import 'package:checkpoint/models/game.dart';
import 'package:checkpoint/models/social_user.dart';
import 'package:checkpoint/screens/profile/achievements_section.dart';
import 'package:checkpoint/state/auth_store.dart';
import 'package:checkpoint/state/profile_store.dart';
import 'package:checkpoint/state/public_profile_store.dart';
import 'package:checkpoint/state/social_graph_store.dart';
import 'package:checkpoint/state/store_scope.dart';
import 'package:checkpoint/theme/palette.dart';
import 'package:checkpoint/utils/formatters.dart';
import 'package:checkpoint/utils/navigation.dart';
import 'package:checkpoint/widgets/count_stat.dart';
import 'package:checkpoint/widgets/empty_state.dart';
import 'package:checkpoint/widgets/favorite_games_row.dart';
import 'package:checkpoint/widgets/game_poster_card.dart';
import 'package:checkpoint/widgets/panel.dart';
import 'package:checkpoint/widgets/profile_avatar.dart';

/// Another member's profile: who they are, who follows them, what they play and
/// which services they linked. Their achievements stay behind a button.
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

/// Name, @handle and photo.
class _Header extends StatelessWidget {
  const _Header({
    required this.name,
    required this.handle,
    this.avatarUrl,
    this.isSelf = false,
  });

  final String name;
  final String handle;
  final String? avatarUrl;
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
              if (isSelf) ...[
                const SizedBox(height: 2),
                const Text(
                  'This is you',
                  style: TextStyle(color: Palette.muted, fontSize: 12.5),
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
    final own = context.watch<ProfileStore>();
    final following = own.isFollowing(userId);

    // On your own profile the counts are the live ones from ProfileStore; on
    // someone else's, a follow you made after the page loaded is already in.
    final followers = isSelf
        ? own.followersCount
        : view.followersFor(viewerFollows: following);
    final followingCount = isSelf ? own.followingCount : stats.following;

    void open(FollowListKind kind) => openFollowList(
      context,
      userId: userId,
      kind: kind,
      ownerName: profile.name,
    );

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
      children: [
        _Header(
          name: profile.name,
          handle: profile.handle,
          avatarUrl: profile.avatarUrl,
          isSelf: isSelf,
        ),
        if (view.refreshFailed) ...[
          const SizedBox(height: 10),
          const Text(
            'Could not refresh. Showing the last copy.',
            style: TextStyle(color: Palette.muted, fontSize: 12.5),
          ),
        ],
        const SizedBox(height: 16),
        Row(
          children: [
            CountStat(
              value: fmtCount(followers),
              label: 'Followers',
              onTap: () => open(FollowListKind.followers),
            ),
            CountStat(
              value: fmtCount(followingCount),
              label: 'Following',
              onTap: () => open(FollowListKind.following),
            ),
            CountStat(value: fmtCount(stats.games), label: 'Games'),
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
        const SizedBox(height: 20),
        Panel(
          title: 'Connected accounts',
          child: profile.connectedServices.isEmpty
              ? const Text(
                  'No connected accounts.',
                  style: TextStyle(color: Palette.muted, fontSize: 13),
                )
              : Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    // ConnectedService.values keeps the order stable.
                    for (final s in ConnectedService.values)
                      if (profile.connectedServices.contains(s))
                        _ServiceChip(service: s),
                  ],
                ),
        ),
        const SizedBox(height: 28),
        const _SectionTitle('Favorite Games'),
        if (view.favorites.isEmpty)
          const _EmptyNote('No favorites picked yet.')
        else
          FavoriteGamesRow(games: view.favorites),
        const SizedBox(height: 28),
        const _SectionTitle('Rated Games'),
        if (view.rated.isEmpty)
          const _EmptyNote('No rated games yet.')
        else
          SizedBox(
            height: posterCardHeight(context, 104, subtitle: false),
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: view.rated.length,
              separatorBuilder: (_, _) => const SizedBox(width: 12),
              itemBuilder: (_, i) =>
                  GamePosterCard(game: view.rated[i], width: 104),
            ),
          ),
        const SizedBox(height: 28),
        _SectionTitle('Library', count: view.libraryTotal),
        if (view.library.isEmpty)
          const _EmptyNote('Nothing in their library yet.')
        else ...[
          _LibraryGrid(games: view.library),
          if (view.libraryHasMore || view.loadingMoreLibrary)
            _ShowMore(userId: userId, view: view),
        ],
        const SizedBox(height: 28),
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
  const _SectionTitle(this.title, {this.count});
  final String title;
  final int? count;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: [
          Text(
            title,
            style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w800),
          ),
          if (count != null) ...[
            const SizedBox(width: 8),
            Text(
              fmtCount(count!),
              style: const TextStyle(
                color: Palette.muted,
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _EmptyNote extends StatelessWidget {
  const _EmptyNote(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Panel(
    child: Text(
      text,
      style: const TextStyle(color: Palette.muted, fontSize: 13, height: 1.35),
    ),
  );
}

/// Three posters across. A wrap rather than a lazy grid, because it sits inside
/// the page's own scroll view and holds one page of 30 at a time.
class _LibraryGrid extends StatelessWidget {
  const _LibraryGrid({required this.games});
  final List<Game> games;

  static const double _gap = 12;
  static const int _columns = 3;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = (constraints.maxWidth - _gap * (_columns - 1)) / _columns;
        return Wrap(
          spacing: _gap,
          runSpacing: 16,
          children: [
            for (final game in games)
              GamePosterCard(
                game: game,
                width: width,
                showUnrated: false,
                subtitle: game.status?.label,
                subtitleIcon: game.status?.icon,
              ),
          ],
        );
      },
    );
  }
}

/// Loads the next page of the library when pressed. A button rather than "load
/// when scrolled to": the page is one scroll view, so everything would be built,
/// and so loaded, at once.
class _ShowMore extends StatelessWidget {
  const _ShowMore({required this.userId, required this.view});
  final String userId;
  final PublicProfileView view;

  @override
  Widget build(BuildContext context) {
    final remaining = view.libraryTotal - view.library.length;
    final String label;
    if (view.loadMoreLibraryFailed) {
      label = 'Couldn’t load. Tap to retry';
    } else if (view.loadingMoreLibrary) {
      label = 'Loading…';
    } else {
      label = 'Show more ($remaining left)';
    }
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: SizedBox(
        width: double.infinity,
        child: OutlinedButton(
          onPressed: view.loadingMoreLibrary
              ? null
              : () => unawaited(
                  context.read<PublicProfileStore>().loadMoreLibrary(userId),
                ),
          child: Text(label),
        ),
      ),
    );
  }
}

/// A connected service, in its brand color. Not tappable: the member's account
/// names and Steam ID are private; only the fact that it is linked is shown.
class _ServiceChip extends StatelessWidget {
  const _ServiceChip({required this.service});
  final ConnectedService service;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: '${service.label} connected',
      excludeSemantics: true,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: service.color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: service.color.withValues(alpha: 0.6)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            FaIcon(service.icon, size: 16, color: service.color),
            const SizedBox(width: 8),
            Text(
              service.label,
              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
            ),
          ],
        ),
      ),
    );
  }
}
