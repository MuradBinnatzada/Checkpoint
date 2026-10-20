import 'dart:async';

import 'package:flutter/material.dart';

import 'package:checkpoint/state/auth_store.dart';
import 'package:checkpoint/state/load_status.dart';
import 'package:checkpoint/state/profile_store.dart';
import 'package:checkpoint/state/public_profile_store.dart';
import 'package:checkpoint/state/social_graph_store.dart';
import 'package:checkpoint/state/store_scope.dart';
import 'package:checkpoint/theme/palette.dart';
import 'package:checkpoint/utils/formatters.dart';
import 'package:checkpoint/widgets/empty_state.dart';
import 'package:checkpoint/widgets/load_more_footer.dart';
import 'package:checkpoint/widgets/member_tile.dart';

/// Who follows a member and who they follow, as two tabs of one screen, each with
/// its count. [initialKind] is the tab that opens: the count that was tapped. Each
/// tab asks the server for a fresh first page when it is first shown, with the
/// copy the app already holds on screen meanwhile.
class FollowsScreen extends StatefulWidget {
  const FollowsScreen({
    super.key,
    required this.userId,
    this.initialKind = FollowListKind.followers,
    this.ownerName,
  });

  final String userId;
  final FollowListKind initialKind;

  /// Whose lists these are, shown as the title.
  final String? ownerName;

  @override
  State<FollowsScreen> createState() => _FollowsScreenState();
}

class _FollowsScreenState extends State<FollowsScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(
    length: FollowListKind.values.length,
    vsync: this,
    initialIndex: FollowListKind.values.indexOf(widget.initialKind),
  );

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  /// How many people are in a tab's list, as far as is known: your own counts are
  /// the live ones; someone else's come from their profile, if it was opened.
  int? _count(BuildContext context, FollowListKind kind) {
    final isSelf = context.watch<AuthStore>().user?.id == widget.userId;
    if (isSelf) {
      final own = context.watch<ProfileStore>();
      return kind == FollowListKind.followers
          ? own.followersCount
          : own.followingCount;
    }
    final stats = context
        .watch<PublicProfileStore>()
        .viewOf(widget.userId)
        .stats;
    if (stats == null) return null;
    return kind == FollowListKind.followers ? stats.followers : stats.following;
  }

  @override
  Widget build(BuildContext context) {
    String label(FollowListKind kind) {
      final count = _count(context, kind);
      final name = kind.label.toLowerCase();
      return count == null ? kind.label : '${fmtThousands(count)} $name';
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.ownerName ?? 'People',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
        ),
        bottom: TabBar(
          controller: _tabs,
          indicatorColor: context.palette.accent,
          indicatorSize: TabBarIndicatorSize.tab,
          labelColor: context.palette.text,
          unselectedLabelColor: context.palette.muted,
          dividerColor: context.palette.text.withValues(alpha: 0.08),
          labelStyle: const TextStyle(
            fontWeight: FontWeight.w700,
            fontSize: 14,
          ),
          unselectedLabelStyle: const TextStyle(
            fontWeight: FontWeight.w600,
            fontSize: 14,
          ),
          tabs: [
            for (final kind in FollowListKind.values) Tab(text: label(kind)),
          ],
        ),
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: TabBarView(
              controller: _tabs,
              children: [
                for (final kind in FollowListKind.values)
                  _FollowList(
                    key: ValueKey(kind),
                    userId: widget.userId,
                    kind: kind,
                    ownerName: widget.ownerName,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// One tab: the members of one list.
class _FollowList extends StatefulWidget {
  const _FollowList({
    super.key,
    required this.userId,
    required this.kind,
    this.ownerName,
  });

  final String userId;
  final FollowListKind kind;
  final String? ownerName;

  @override
  State<_FollowList> createState() => _FollowListState();
}

class _FollowListState extends State<_FollowList>
    with AutomaticKeepAliveClientMixin {
  // Keeps the list (and its scroll position) when the other tab is shown.
  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    // After the first frame: loading notifies, which isn't allowed during build.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(_load());
    });
  }

  Future<void> _load() =>
      context.read<SocialGraphStore>().load(widget.userId, widget.kind);

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final store = context.watch<SocialGraphStore>();
    final view = store.listOf(widget.userId, widget.kind);
    final followers = widget.kind == FollowListKind.followers;

    if (view.status == LoadStatus.failed) {
      return EmptyState(
        icon: Icons.cloud_off_rounded,
        title: 'Could not load ${widget.kind.label.toLowerCase()}',
        message: 'Check your connection and try again.',
        actionLabel: 'Try again',
        onAction: _load,
      );
    }
    if (view.status != LoadStatus.ready) {
      return const Center(child: CircularProgressIndicator());
    }
    if (view.users.isEmpty) {
      final who = widget.ownerName ?? 'this member';
      return EmptyState(
        icon: followers
            ? Icons.people_outline_rounded
            : Icons.person_add_alt_rounded,
        title: followers ? 'No followers yet' : 'Not following anyone yet',
        message: followers
            ? 'When people follow $who, they show up here.'
            : 'People $who follows show up here.',
      );
    }

    final showFooter = view.hasMore || view.loadingMore || view.loadMoreFailed;
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.builder(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 32),
        itemCount: view.users.length + (showFooter ? 1 : 0),
        itemBuilder: (context, i) {
          if (i < view.users.length) return MemberTile(user: view.users[i]);
          return LoadMoreFooter(
            loading: view.loadingMore,
            failed: view.loadMoreFailed,
            onLoadMore: () => unawaited(
              context.read<SocialGraphStore>().loadMore(
                widget.userId,
                widget.kind,
              ),
            ),
          );
        },
      ),
    );
  }
}
