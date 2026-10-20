import 'package:flutter/material.dart';

import 'package:checkpoint/models/game_list.dart';
import 'package:checkpoint/screens/lists/list_screen.dart';
import 'package:checkpoint/sheets/list_sheets.dart';
import 'package:checkpoint/state/lists_store.dart';
import 'package:checkpoint/state/load_status.dart';
import 'package:checkpoint/state/store_scope.dart';
import 'package:checkpoint/theme/palette.dart';
import 'package:checkpoint/widgets/cover_art.dart';
import 'package:checkpoint/widgets/empty_state.dart';

/// The member's own lists ([userId] null), with "New list"; or another member's
/// public ones, to look at.
class ListsScreen extends StatefulWidget {
  const ListsScreen({super.key, this.userId, this.ownerName});

  /// Whose public lists to show; null: the signed-in member's own.
  final String? userId;
  final String? ownerName;

  @override
  State<ListsScreen> createState() => _ListsScreenState();
}

class _ListsScreenState extends State<ListsScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load({bool force = false}) {
    final store = context.read<ListsStore>();
    final userId = widget.userId;
    return userId == null ? store.load(force: force) : store.loadPublic(userId);
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<ListsStore>();
    final userId = widget.userId;
    final own = userId == null;
    final lists = own ? store.lists : store.publicListsOf(userId);
    final status = own ? store.status : store.publicStatusOf(userId);
    final Widget body;
    if (lists.isEmpty && (status == LoadStatus.loading || status == LoadStatus.idle)) {
      body = const Center(child: CircularProgressIndicator());
    } else if (lists.isEmpty && status == LoadStatus.failed) {
      body = EmptyState(
        icon: Icons.cloud_off_rounded,
        title: 'Could not load the lists',
        message: 'Lists need a connection. Check it and try again.',
        actionLabel: 'Retry',
        onAction: () => _load(force: true),
      );
    } else if (lists.isEmpty) {
      body = EmptyState(
        icon: Icons.format_list_bulleted_rounded,
        title: own ? 'No lists yet' : 'No public lists',
        message: own
            ? 'Make lists of games in any order: favorites of a genre, a backlog for the holidays, a ranking.'
            : '${widget.ownerName ?? 'This member'} has no public lists.',
        actionLabel: own ? 'New list' : null,
        onAction: own ? () => _newList(context) : null,
      );
    } else {
      body = RefreshIndicator(
        onRefresh: () => _load(force: true),
        child: ListView.separated(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
          itemCount: lists.length,
          separatorBuilder: (_, _) => const SizedBox(height: 10),
          itemBuilder: (context, i) => ListCard(list: lists[i]),
        ),
      );
    }
    return Scaffold(
      appBar: AppBar(title: Text(own ? 'Your lists' : '${widget.ownerName ?? 'Their'} lists')),
      floatingActionButton: own && lists.isNotEmpty
          ? FloatingActionButton.extended(
              onPressed: () => _newList(context),
              icon: const Icon(Icons.add_rounded),
              label: const Text('New list'),
            )
          : null,
      body: body,
    );
  }

  Future<void> _newList(BuildContext context) async {
    final made = await showEditListSheet(context);
    if (made != null && context.mounted) openList(context, made.id);
  }
}

void openList(BuildContext context, String listId) => Navigator.of(context).push(
  MaterialPageRoute<void>(builder: (_) => ListScreen(listId: listId)),
);

/// A list's title, how many games, whether it is public, and its first covers.
class ListCard extends StatelessWidget {
  const ListCard({super.key, required this.list});
  final GameList list;

  @override
  Widget build(BuildContext context) {
    final count = list.games.length;
    return Material(
      color: context.palette.surface,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: () => openList(context, list.id),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(
                child: Text(
                  list.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                ),
              ),
              Icon(
                list.isPublic ? Icons.public_rounded : Icons.lock_outline_rounded,
                size: 16,
                color: context.palette.muted,
                semanticLabel: list.isPublic ? 'Public' : 'Private',
              ),
            ]),
            const SizedBox(height: 2),
            Text('$count game${count == 1 ? '' : 's'}', style: TextStyle(color: context.palette.muted, fontSize: 12.5)),
            if (count > 0) ...[
              const SizedBox(height: 10),
              SizedBox(
                height: 72,
                child: Row(children: [
                  for (final game in list.games.take(6))
                    Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: SizedBox(width: 48, child: CoverArt(game: game, radius: 6, showTitle: false)),
                    ),
                ]),
              ),
            ],
          ]),
        ),
      ),
    );
  }
}
