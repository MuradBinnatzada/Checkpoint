import 'dart:async';

import 'package:flutter/material.dart';

import 'package:checkpoint/state/load_status.dart';
import 'package:checkpoint/state/social_graph_store.dart';
import 'package:checkpoint/state/store_scope.dart';
import 'package:checkpoint/theme/palette.dart';
import 'package:checkpoint/widgets/empty_state.dart';
import 'package:checkpoint/widgets/load_more_footer.dart';
import 'package:checkpoint/widgets/member_tile.dart';

/// The members who follow [userId], or the members they follow. Opens on the copy
/// the app already holds, if any, and asks the server for a fresh first page.
class FollowListScreen extends StatefulWidget {
  const FollowListScreen({
    super.key,
    required this.userId,
    required this.kind,
    this.ownerName,
  });

  final String userId;
  final FollowListKind kind;

  /// Whose list this is, shown under the title.
  final String? ownerName;

  @override
  State<FollowListScreen> createState() => _FollowListScreenState();
}

class _FollowListScreenState extends State<FollowListScreen> {
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
    final store = context.watch<SocialGraphStore>();
    final view = store.listOf(widget.userId, widget.kind);
    final followers = widget.kind == FollowListKind.followers;

    final Widget body;
    if (view.status == LoadStatus.failed) {
      body = EmptyState(
        icon: Icons.cloud_off_rounded,
        title: 'Could not load ${widget.kind.label.toLowerCase()}',
        message: 'Check your connection and try again.',
        actionLabel: 'Try again',
        onAction: _load,
      );
    } else if (view.status != LoadStatus.ready) {
      body = const Center(child: CircularProgressIndicator());
    } else if (view.users.isEmpty) {
      body = EmptyState(
        icon: followers
            ? Icons.people_outline_rounded
            : Icons.person_add_alt_rounded,
        title: followers ? 'No followers yet' : 'Not following anyone yet',
        message: followers
            ? 'When people follow ${widget.ownerName ?? 'this member'}, they show up here.'
            : 'People ${widget.ownerName ?? 'this member'} follows show up here.',
      );
    } else {
      final showFooter =
          view.hasMore || view.loadingMore || view.loadMoreFailed;
      body = RefreshIndicator(
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

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.kind.label,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
            ),
            if (widget.ownerName != null)
              Text(
                widget.ownerName!,
                style: const TextStyle(fontSize: 12.5, color: Palette.muted),
              ),
          ],
        ),
      ),
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
