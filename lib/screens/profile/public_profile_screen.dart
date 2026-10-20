import 'dart:async';

import 'package:flutter/material.dart';

import 'package:checkpoint/models/game.dart';
import 'package:checkpoint/models/share_link.dart';
import 'package:checkpoint/models/social_user.dart';
import 'package:checkpoint/screens/lists/lists_screen.dart';
import 'package:checkpoint/screens/profile/milestones_section.dart';
import 'package:checkpoint/widgets/share_link_button.dart';
import 'package:checkpoint/screens/profile/profile_layout.dart';
import 'package:checkpoint/state/auth_store.dart';
import 'package:checkpoint/state/library_state.dart';
import 'package:checkpoint/state/milestones_store.dart';
import 'package:checkpoint/state/profile_store.dart';
import 'package:checkpoint/state/public_profile_store.dart';
import 'package:checkpoint/state/social_graph_store.dart';
import 'package:checkpoint/state/store_scope.dart';
import 'package:checkpoint/utils/navigation.dart';
import 'package:checkpoint/widgets/empty_state.dart';
import 'package:checkpoint/widgets/profile_link_rows.dart';

/// Another member's profile, laid out like your own ([ProfileLayout]): who they
/// are, icons of the accounts they connected, their bio, who follows them, then
/// their favorites, latest sessions, playtime, library numbers (each box opens
/// their library), hours per platform, ratings, their achievement count, and last
/// of all a short menu into their library and follow lists. The achievements are
/// left out when they have not connected Steam or keep them private (on your own
/// page, only when you have not connected Steam).
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
      appBar: AppBar(actions: [ShareLinkButton(target: MemberLink(widget.userId))]),
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
          ProfileHeader(
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
    final showAchievements = isSelf
        ? own.steamConnected
        : profile.steamConnected && profile.showSteamAchievements;

    void openFollowers(FollowListKind kind) => openFollows(
      context,
      userId: userId,
      kind: kind,
      ownerName: profile.name,
    );
    // Your own are the live ones; someone else's came with their profile.
    final milestones = isSelf
        ? context.watch<MilestonesStore>().earned
        : view.milestones;
    void openAllMilestones() =>
        openMilestones(context, userId: userId, ownerName: profile.name);
    void openLibrary({GameStatus? status, SortField? sortBy}) =>
        openPublicLibrary(
          context,
          userId: userId,
          ownerName: profile.name,
          status: status,
          sortBy: sortBy,
        );

    return ProfileLayout(
      userId: userId,
      header: ProfileHeader(
        name: profile.name,
        handle: profile.handle,
        avatarUrl: profile.avatarUrl,
        joined: profile.joined,
        isSelf: isSelf,
        flair: isSelf ? own.flair : profile.flair,
        milestones: milestones,
      ),
      notice: view.refreshFailed
          ? 'Could not refresh. Showing the last copy.'
          : null,
      bio: profile.bio,
      followers: followers,
      following: followingCount,
      onFollowers: () => openFollowers(FollowListKind.followers),
      onFollowing: () => openFollowers(FollowListKind.following),
      actions: isSelf
          ? null
          : SizedBox(
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
      favorites: view.favorites,
      activity: view.activity,
      library: library,
      onStatus: (status) => openLibrary(status: status),
      showAchievements: showAchievements,
      milestones: MilestonesSection(
        earned: milestones,
        own: isSelf,
        onSeeAll: openAllMilestones,
      ),
      services: profile.connectedServices,
      accountNames: profile.accountNames,
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
          icon: Icons.format_list_bulleted_rounded,
          label: 'Lists',
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => ListsScreen(userId: userId, ownerName: profile.name),
            ),
          ),
        ),
        ProfileLink(
          icon: Icons.emoji_events_rounded,
          label: 'Milestones',
          count: milestones.count,
          onTap: openAllMilestones,
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
