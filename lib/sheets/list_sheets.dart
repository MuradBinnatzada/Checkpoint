import 'package:flutter/material.dart';

import 'package:checkpoint/models/game.dart';
import 'package:checkpoint/models/game_list.dart';
import 'package:checkpoint/state/lists_store.dart';
import 'package:checkpoint/state/load_status.dart';
import 'package:checkpoint/state/store_scope.dart';
import 'package:checkpoint/theme/palette.dart';
import 'package:checkpoint/utils/formatters.dart';
import 'package:checkpoint/widgets/sheet_frame.dart';

/// Makes a list ([list] null) or changes one: title, description, public or
/// not. Returns the list that was made, or null.
Future<GameList?> showEditListSheet(BuildContext context, {GameList? list}) =>
    showModalBottomSheet<GameList>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => EditListSheet(list: list),
    );

class EditListSheet extends StatefulWidget {
  const EditListSheet({super.key, this.list});
  final GameList? list;

  @override
  State<EditListSheet> createState() => _EditListSheetState();
}

class _EditListSheetState extends State<EditListSheet> {
  late final _title = TextEditingController(text: widget.list?.title ?? '');
  late final _description = TextEditingController(text: widget.list?.description ?? '');
  late bool _public = widget.list?.isPublic ?? false;
  bool _saving = false;

  @override
  void dispose() {
    _title.dispose();
    _description.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final store = context.read<ListsStore>();
    final list = widget.list;
    if (list != null) {
      store.update(list.id, title: _title.text, description: _description.text, isPublic: _public);
      Navigator.pop(context);
      return;
    }
    setState(() => _saving = true);
    final made = await store.create(title: _title.text, description: _description.text, isPublic: _public);
    if (!mounted) return;
    if (made == null) {
      setState(() => _saving = false);
      return;
    }
    Navigator.pop(context, made);
  }

  @override
  Widget build(BuildContext context) {
    final valid = _title.text.trim().isNotEmpty;
    return SheetFrame(
      title: widget.list == null ? 'New list' : 'Edit list',
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        TextField(
          controller: _title,
          autofocus: widget.list == null,
          maxLength: GameList.titleMax,
          textCapitalization: TextCapitalization.sentences,
          onChanged: (_) => setState(() {}),
          decoration: fieldDecoration(context, 'Title').copyWith(counterText: ''),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _description,
          minLines: 2,
          maxLines: 5,
          maxLength: GameList.descriptionMax,
          textCapitalization: TextCapitalization.sentences,
          decoration: fieldDecoration(context, 'Description (optional)'),
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          value: _public,
          onChanged: (v) => setState(() => _public = v),
          title: const Text('Public'),
          subtitle: Text(
            _public
                ? 'Shown on your profile, and anyone signed in can open its link.'
                : 'Only you can see it.',
            style: TextStyle(color: context.palette.muted, fontSize: 12.5),
          ),
        ),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          child: FilledButton(
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
            onPressed: !valid || _saving ? null : _save,
            child: Text(widget.list == null ? 'Create list' : 'Save'),
          ),
        ),
      ]),
    );
  }
}

/// Puts [game] on the member's lists, or takes it off: a tick per list, and
/// "New list" to make one with the game on it.
Future<void> showAddToListSheet(BuildContext context, Game game) {
  final store = context.read<ListsStore>();
  store.load();
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => _AddToListSheet(game: game),
  );
}

class _AddToListSheet extends StatelessWidget {
  const _AddToListSheet({required this.game});
  final Game game;

  @override
  Widget build(BuildContext context) {
    final store = context.watch<ListsStore>();
    final lists = store.lists;
    return SheetFrame(
      title: 'Add to list',
      subtitle: game.title,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if (lists.isEmpty && store.status == LoadStatus.loading)
          const Padding(
            padding: EdgeInsets.all(16),
            child: Center(child: CircularProgressIndicator()),
          ),
        for (final list in lists)
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            value: list.contains(game.id),
            onChanged: (_) => store.toggleGame(list.id, game),
            title: Text(list.title, maxLines: 1, overflow: TextOverflow.ellipsis),
            subtitle: Text(
              '${list.games.length} game${list.games.length == 1 ? '' : 's'}${list.isPublic ? ' · Public' : ''}',
              style: TextStyle(color: context.palette.muted, fontSize: 12.5),
            ),
          ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: () async {
            final made = await showEditListSheet(context);
            if (made != null) await store.toggleGame(made.id, game);
          },
          icon: const Icon(Icons.add_rounded),
          label: const Text('New list'),
        ),
      ]),
    );
  }
}
