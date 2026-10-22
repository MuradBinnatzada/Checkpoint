import 'dart:async';

import 'package:flutter/material.dart';

import 'package:checkpoint/l10n/l10n.dart';
import 'package:checkpoint/models/discussion.dart';
import 'package:checkpoint/screens/discussions/new_thread_screen.dart';
import 'package:checkpoint/state/discussions_store.dart';
import 'package:checkpoint/state/load_status.dart';
import 'package:checkpoint/state/store_scope.dart';
import 'package:checkpoint/theme/palette.dart';
import 'package:checkpoint/widgets/empty_state.dart';
import 'package:checkpoint/widgets/load_more_footer.dart';
import 'package:checkpoint/widgets/thread_tile.dart';

/// Opens the threads of [scope]: a board's, or those about a game ([gameTitle] is
/// its name, for the title).
void openBoard(
  BuildContext context,
  DiscussionScope scope, {
  String? gameTitle,
}) => unawaited(
  Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => BoardScreen(scope: scope, gameTitle: gameTitle),
    ),
  ),
);

/// The threads of a board, or about one game, the ones written in last first
/// (pinned ones on top of a board), paged as the list is scrolled, with a button
/// to start a new one.
class BoardScreen extends StatefulWidget {
  const BoardScreen({super.key, required this.scope, this.gameTitle});

  final DiscussionScope scope;

  /// The name of the game of a game's scope.
  final String? gameTitle;

  @override
  State<BoardScreen> createState() => _BoardScreenState();
}

class _BoardScreenState extends State<BoardScreen> {
  @override
  void initState() {
    super.initState();
    // After the frame: loading notifies, which isn't allowed during build.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final store = context.read<DiscussionsStore>();
      unawaited(store.loadBoards());
      unawaited(store.loadThreads(widget.scope));
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final palette = context.palette;
    final store = context.watch<DiscussionsStore>();
    final list = store.listOf(widget.scope);
    final board = widget.scope.boardId == null
        ? null
        : store.boardById(widget.scope.boardId!);
    final forGame = widget.scope.gameId != null;
    final title = forGame
        ? l10n.gameDiscussions
        : (board?.title ?? l10n.discussions);
    final subtitle = forGame ? widget.gameTitle : board?.description;

    Widget body;
    if (list.status == LoadStatus.failed) {
      body = EmptyState(
        icon: Icons.cloud_off_rounded,
        title: l10n.discussionsLoadFailed,
        message: l10n.checkConnection,
        actionLabel: l10n.tryAgain,
        onAction: () => unawaited(store.loadThreads(widget.scope, force: true)),
      );
    } else if (list.status != LoadStatus.ready) {
      body = const Center(child: CircularProgressIndicator());
    } else if (list.threads.isEmpty) {
      body = EmptyState(
        icon: Icons.forum_outlined,
        title: l10n.noDiscussionsYet,
        message: l10n.noDiscussionsYetMessage,
        actionLabel: l10n.newDiscussion,
        onAction: () => _newThread(context),
      );
    } else {
      final footer = list.hasMore || list.loadingMore || list.loadMoreFailed;
      body = RefreshIndicator(
        onRefresh: () => store.loadThreads(widget.scope, force: true),
        child: ListView.separated(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: EdgeInsets.fromLTRB(
            16,
            0,
            16,
            MediaQuery.paddingOf(context).bottom + 96,
          ),
          itemCount: list.threads.length + (footer ? 1 : 0),
          separatorBuilder: (_, _) =>
              Divider(height: 1, color: palette.hairline),
          itemBuilder: (_, i) {
            if (i < list.threads.length) {
              return ThreadTile(
                key: ValueKey(list.threads[i].id),
                thread: list.threads[i],
              );
            }
            return LoadMoreFooter(
              loading: list.loadingMore,
              failed: list.loadMoreFailed,
              onLoadMore: () => unawaited(store.loadMoreThreads(widget.scope)),
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
            Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
            if (subtitle != null && subtitle.isNotEmpty)
              Text(
                subtitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 13, color: palette.muted),
              ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _newThread(context),
        icon: const Icon(Icons.edit_rounded),
        label: Text(l10n.newDiscussion),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: body,
        ),
      ),
    );
  }

  void _newThread(BuildContext context) => openNewThread(
    context,
    boardId: widget.scope.boardId,
    game: widget.scope.gameId == null
        ? null
        : DiscussionGame(
            id: widget.scope.gameId!,
            title: widget.gameTitle ?? '',
          ),
  );
}
