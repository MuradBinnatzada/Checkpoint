import 'package:flutter/material.dart';

import 'package:checkpoint/data/db_schema.dart';
import 'package:checkpoint/state/library_store.dart';
import 'package:checkpoint/state/store_scope.dart';
import 'package:checkpoint/theme/palette.dart';
import 'package:checkpoint/utils/formatters.dart';
import 'package:checkpoint/widgets/sheet_frame.dart';

/// Opens the sheet that writes, changes or removes the member's short review of
/// [gameId].
Future<void> showReviewSheet(BuildContext context, String gameId) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  builder: (_) => ReviewSheet(gameId: gameId),
);

/// A short review next to the rating, at most [Db.reviewMaxLength] characters.
/// Members who follow you see it on the game's screen, like your rating.
class ReviewSheet extends StatefulWidget {
  const ReviewSheet({super.key, required this.gameId});
  final String gameId;

  @override
  State<ReviewSheet> createState() => _ReviewSheetState();
}

class _ReviewSheetState extends State<ReviewSheet> {
  late final String _saved = context.read<LibraryStore>().gameById(widget.gameId).review;
  late final _text = TextEditingController(text: _saved);

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  void _save(String review) {
    context.read<LibraryStore>().setReview(widget.gameId, review);
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final game = context.read<LibraryStore>().gameById(widget.gameId);
    return SheetFrame(
      title: _saved.isEmpty ? 'Write a review' : 'Your review',
      subtitle: game.title,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        TextField(
          controller: _text,
          autofocus: true,
          minLines: 4,
          maxLines: 8,
          maxLength: Db.reviewMaxLength,
          textCapitalization: TextCapitalization.sentences,
          onChanged: (_) => setState(() {}),
          decoration: fieldDecoration('What did you think?'),
        ),
        const Text(
          'Members who follow you see it on the game\'s page, with your rating.',
          style: TextStyle(color: Palette.muted, fontSize: 12.5, height: 1.35),
        ),
        const SizedBox(height: 18),
        SizedBox(
          width: double.infinity,
          child: FilledButton(
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
            onPressed: _text.text.trim() == _saved ? null : () => _save(_text.text),
            child: const Text('Save review'),
          ),
        ),
        if (_saved.isNotEmpty) ...[
          const SizedBox(height: 8),
          Center(
            child: TextButton(
              style: TextButton.styleFrom(foregroundColor: Palette.danger),
              onPressed: () => _save(''),
              child: const Text('Remove review'),
            ),
          ),
        ],
      ]),
    );
  }
}
