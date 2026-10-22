import 'dart:async';

import 'package:flutter/material.dart';

import 'package:checkpoint/l10n/l10n.dart';
import 'package:checkpoint/models/discussion.dart';
import 'package:checkpoint/models/game.dart';
import 'package:checkpoint/screens/discussions/board_screen.dart';
import 'package:checkpoint/screens/discussions/new_thread_screen.dart';
import 'package:checkpoint/state/auth_store.dart';
import 'package:checkpoint/state/discussions_store.dart';
import 'package:checkpoint/state/library_store.dart';
import 'package:checkpoint/state/load_status.dart';
import 'package:checkpoint/state/store_scope.dart';
import 'package:checkpoint/theme/palette.dart';
import 'package:checkpoint/widgets/panel.dart';
import 'package:checkpoint/widgets/thread_tile.dart';

/// What the members are discussing about the game: the latest few threads about it,
/// and a way to start one or see them all. Asks when the screen opens (see
/// [DiscussionsStore]); signed out, until the answer is here, or when it fails,
/// nothing is drawn.
class DiscussionsPanel extends StatefulWidget {
  const DiscussionsPanel({super.key, required this.game});

  final Game game;

  @override
  State<DiscussionsPanel> createState() => _DiscussionsPanelState();
}

class _DiscussionsPanelState extends State<DiscussionsPanel> {
  /// Threads the panel lists.
  static const _shown = 3;

  DiscussionScope get _scope => DiscussionScope(gameId: widget.game.id);

  @override
  void initState() {
    super.initState();
    _loadAfterFrame();
  }

  @override
  void didUpdateWidget(DiscussionsPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.game.id != widget.game.id) _loadAfterFrame();
  }

  /// After the frame: loading notifies, which isn't allowed during build. A game
  /// that is not in the catalog yet has no threads, and none is asked for.
  void _loadAfterFrame() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && context.read<AuthStore>().isLoggedIn) {
        unawaited(
          context.read<DiscussionsStore>().loadThreads(_scope, force: true),
        );
      }
    });
  }

  /// A thread names its game by its catalog row, which a game found by search may
  /// not have yet: it is put there first.
  Future<void> _start() async {
    final library = context.read<LibraryStore>();
    final messenger = ScaffoldMessenger.of(context);
    final failed = context.l10n.postNotFound;
    final navigator = context;
    try {
      await library.ensureInCatalog(widget.game);
    } catch (_) {
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(failed)));
      return;
    }
    if (!navigator.mounted) return;
    openNewThread(
      navigator,
      game: DiscussionGame(id: widget.game.id, title: widget.game.title),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final palette = context.palette;
    if (!context.watch<AuthStore>().isLoggedIn) return const SizedBox.shrink();
    final list = context.watch<DiscussionsStore>().listOf(_scope);
    if (list.status != LoadStatus.ready) return const SizedBox.shrink();
    final threads = list.threads;

    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Panel(
        title: l10n.gameDiscussions,
        trailing: threads.length > _shown || list.hasMore
            ? TextButton(
                onPressed: () =>
                    openBoard(context, _scope, gameTitle: widget.game.title),
                child: Text(l10n.seeAllShort),
              )
            : null,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (threads.isEmpty)
              Text(
                l10n.noGameDiscussionsYet,
                style: TextStyle(color: palette.muted, height: 1.4),
              )
            else
              for (var i = 0; i < threads.take(_shown).length; i++) ...[
                if (i > 0) Divider(height: 1, color: palette.hairline),
                ThreadTile(thread: threads[i]),
              ],
            const SizedBox(height: 8),
            FilledButton.tonalIcon(
              onPressed: _start,
              icon: const Icon(Icons.edit_rounded, size: 18),
              label: Text(l10n.startDiscussion),
            ),
          ],
        ),
      ),
    );
  }
}
