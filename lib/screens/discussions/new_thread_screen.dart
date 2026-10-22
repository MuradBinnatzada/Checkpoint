import 'dart:async';

import 'package:flutter/material.dart';

import 'package:checkpoint/l10n/l10n.dart';
import 'package:checkpoint/models/discussion.dart';
import 'package:checkpoint/screens/discussions/thread_screen.dart';
import 'package:checkpoint/services/discussion_failure.dart';
import 'package:checkpoint/sheets/chat_rules_sheet.dart';
import 'package:checkpoint/state/discussions_store.dart';
import 'package:checkpoint/state/store_scope.dart';
import 'package:checkpoint/theme/palette.dart';
import 'package:checkpoint/utils/formatters.dart';

/// The board a thread about a game goes on.
const gameBoardId = 'games';

/// Opens the form to start a thread, on [boardId] (the member picks one when it
/// is null) or, with a [game], about that game on the Game talk board. When the
/// thread is posted this screen is replaced by it.
void openNewThread(
  BuildContext context, {
  String? boardId,
  DiscussionGame? game,
}) => unawaited(
  Navigator.of(context).push(
    MaterialPageRoute<void>(
      fullscreenDialog: true,
      builder: (_) => NewThreadScreen(boardId: boardId, game: game),
    ),
  ),
);

/// Starting a thread: a board, a title and the opening text. The chat rules are
/// agreed to before the first post. A post the server refuses (a word the chat
/// rules refuse, posting too fast...) stays in the form, with what to do said.
class NewThreadScreen extends StatefulWidget {
  const NewThreadScreen({super.key, this.boardId, this.game});

  final String? boardId;

  /// The game it is about, if any: it goes on the Game talk board.
  final DiscussionGame? game;

  @override
  State<NewThreadScreen> createState() => _NewThreadScreenState();
}

class _NewThreadScreenState extends State<NewThreadScreen> {
  final _title = TextEditingController();
  final _text = TextEditingController();
  late String? _board = widget.game != null ? gameBoardId : widget.boardId;
  bool _sending = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(context.read<DiscussionsStore>().loadBoards());
    });
  }

  @override
  void dispose() {
    _title.dispose();
    _text.dispose();
    super.dispose();
  }

  bool get _ready =>
      _board != null &&
      _title.text.trim().length >= DiscussionLimits.titleMin &&
      _text.text.trim().isNotEmpty;

  Future<void> _post() async {
    final board = _board;
    if (!_ready || board == null || _sending) return;
    if (!await ensureChatRules(context) || !mounted) return;
    final store = context.read<DiscussionsStore>();
    final navigator = Navigator.of(context);
    setState(() {
      _sending = true;
      _error = null;
    });
    try {
      final id = await store.createThread(
        boardId: board,
        title: _title.text.trim(),
        text: _text.text.trim(),
        gameId: widget.game?.id,
      );
      if (!mounted) return;
      unawaited(
        navigator.pushReplacement(
          MaterialPageRoute<void>(builder: (_) => ThreadScreen(threadId: id)),
        ),
      );
    } on DiscussionFailure catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final palette = context.palette;
    final store = context.watch<DiscussionsStore>();
    final game = widget.game;
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.newDiscussion),
        actions: [
          IconButton(
            tooltip: l10n.chatRules,
            icon: const Icon(Icons.rule_rounded),
            onPressed: () => unawaited(showChatRules(context)),
          ),
        ],
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
              children: [
                if (game != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 14),
                    child: Row(
                      children: [
                        Icon(
                          Icons.sports_esports_rounded,
                          size: 18,
                          color: palette.muted,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            l10n.aboutGame(game.title),
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                        ),
                      ],
                    ),
                  )
                else
                  Padding(
                    padding: const EdgeInsets.only(bottom: 14),
                    child: DropdownButtonFormField<String>(
                      initialValue: store.boardById(_board ?? '') == null
                          ? null
                          : _board,
                      isExpanded: true,
                      decoration: fieldDecoration(context, l10n.board),
                      items: [
                        for (final b in store.boards)
                          DropdownMenuItem(
                            value: b.id,
                            child: Text(
                              b.title,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                      ],
                      onChanged: _sending
                          ? null
                          : (id) => setState(() => _board = id),
                    ),
                  ),
                TextField(
                  controller: _title,
                  enabled: !_sending,
                  maxLength: DiscussionLimits.titleMax,
                  textCapitalization: TextCapitalization.sentences,
                  textInputAction: TextInputAction.next,
                  onChanged: (_) => setState(() => _error = null),
                  decoration: fieldDecoration(context, l10n.discussionTitle),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _text,
                  enabled: !_sending,
                  minLines: 6,
                  maxLines: 14,
                  maxLength: DiscussionLimits.threadTextMax,
                  textCapitalization: TextCapitalization.sentences,
                  onChanged: (_) => setState(() => _error = null),
                  decoration: fieldDecoration(context, l10n.discussionText),
                ),
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 4, bottom: 8),
                    child: Text(
                      _error!,
                      style: TextStyle(color: palette.danger),
                    ),
                  ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(52),
                    ),
                    onPressed: _ready && !_sending ? _post : null,
                    child: _sending
                        ? const SizedBox.square(
                            dimension: 20,
                            child: CircularProgressIndicator(strokeWidth: 2.5),
                          )
                        : Text(l10n.postDiscussion),
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  l10n.postingAgreesToRules,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: palette.muted,
                    fontSize: 12.5,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
