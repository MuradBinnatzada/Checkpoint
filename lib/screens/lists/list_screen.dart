import 'package:flutter/material.dart';

import 'package:checkpoint/models/game.dart';
import 'package:checkpoint/models/game_list.dart';
import 'package:checkpoint/models/share_link.dart';
import 'package:checkpoint/sheets/list_sheets.dart';
import 'package:checkpoint/state/lists_store.dart';
import 'package:checkpoint/state/store_scope.dart';
import 'package:checkpoint/theme/palette.dart';
import 'package:checkpoint/utils/navigation.dart';
import 'package:checkpoint/widgets/cover_art.dart';
import 'package:checkpoint/widgets/empty_state.dart';
import 'package:checkpoint/widgets/share_link_button.dart';

/// One list: its games in order, each opening its screen. The owner can drag
/// them into another order, take one off, edit the list or delete it; anyone
/// else (a public list) only looks.
class ListScreen extends StatefulWidget {
  const ListScreen({super.key, required this.listId});
  final String listId;

  @override
  State<ListScreen> createState() => _ListScreenState();
}

class _ListScreenState extends State<ListScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final store = context.read<ListsStore>();
      // A list not held yet: one opened from a link.
      if (store.listById(widget.listId) == null) store.open(widget.listId);
    });
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<ListsStore>();
    final list = store.listById(widget.listId);
    if (list == null) {
      return Scaffold(
        appBar: AppBar(),
        body: store.wasOpened(widget.listId)
            ? const EmptyState(
                icon: Icons.lock_outline_rounded,
                title: 'List not found',
                message: 'It may have been deleted, or it is private.',
              )
            : const Center(child: CircularProgressIndicator()),
      );
    }
    final own = list.ownerId == store.accountId;
    return Scaffold(
      appBar: AppBar(
        title: Text(list.title, maxLines: 1, overflow: TextOverflow.ellipsis),
        actions: [
          // A private list's link would open for its owner only.
          if (list.isPublic) ShareLinkButton(target: ListLink(list.id)),
          if (own) ...[
            IconButton(
              tooltip: 'Edit list',
              onPressed: () => showEditListSheet(context, list: list),
              icon: const Icon(Icons.edit_rounded),
            ),
            IconButton(
              tooltip: 'Delete list',
              onPressed: () => _confirmDelete(context, list),
              icon: const Icon(Icons.delete_outline_rounded),
            ),
          ],
        ],
      ),
      body: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Icon(list.isPublic ? Icons.public_rounded : Icons.lock_outline_rounded, size: 14, color: context.palette.muted),
              const SizedBox(width: 6),
              Text(
                '${list.isPublic ? 'Public' : 'Private'} · ${list.games.length} game${list.games.length == 1 ? '' : 's'}',
                style: TextStyle(color: context.palette.muted, fontSize: 12.5),
              ),
            ]),
            if (list.description.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(list.description, style: const TextStyle(height: 1.4)),
            ],
          ]),
        ),
        Expanded(
          child: list.games.isEmpty
              ? EmptyState(
                  icon: Icons.playlist_add_rounded,
                  title: 'No games yet',
                  message: own
                      ? 'Open a game and tap the list button at the top to put it here.'
                      : 'Nothing on this list yet.',
                )
              : own
              ? ReorderableListView.builder(
                  buildDefaultDragHandles: false,
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 32),
                  itemCount: list.games.length,
                  onReorderItem: (from, to) => store.move(list.id, from, to),
                  itemBuilder: (context, i) => _GameRow(
                    key: ValueKey(list.games[i].id),
                    index: i,
                    game: list.games[i],
                    onRemove: () => store.toggleGame(list.id, list.games[i]),
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 32),
                  itemCount: list.games.length,
                  itemBuilder: (context, i) => _GameRow(index: i, game: list.games[i]),
                ),
        ),
      ]),
    );
  }

  Future<void> _confirmDelete(BuildContext context, GameList list) async {
    final store = context.read<ListsStore>();
    final navigator = Navigator.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Delete "${list.title}"?'),
        content: const Text('The list goes; its games stay in your library and the catalog.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: context.palette.danger),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    navigator.pop();
    await store.delete(list.id);
  }
}

class _GameRow extends StatelessWidget {
  const _GameRow({super.key, required this.index, required this.game, this.onRemove});
  final int index;
  final Game game;

  /// Takes the game off the list (the owner's lists only).
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () => openGame(context, game.id),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 8),
        child: Row(children: [
          SizedBox(
            width: 28,
            child: Text('${index + 1}', style: TextStyle(color: context.palette.muted, fontWeight: FontWeight.w700)),
          ),
          SizedBox(width: 44, child: CoverArt(game: game, radius: 6, showTitle: false)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(game.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600)),
              if (game.hasReleaseYear)
                Text('${game.releaseYear}', style: TextStyle(color: context.palette.muted, fontSize: 12.5)),
            ]),
          ),
          if (onRemove != null) ...[
            IconButton(
              tooltip: 'Take off the list',
              onPressed: onRemove,
              icon: Icon(Icons.remove_circle_outline_rounded, color: context.palette.muted),
            ),
            ReorderableDragStartListener(
              index: index,
              child: Padding(
                padding: EdgeInsets.all(8),
                child: Icon(Icons.drag_handle_rounded, color: context.palette.muted),
              ),
            ),
          ],
        ]),
      ),
    );
  }
}
