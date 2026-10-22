import 'package:flutter/material.dart';

import 'package:checkpoint/l10n/l10n.dart';
import 'package:checkpoint/models/discussion.dart';
import 'package:checkpoint/screens/discussions/thread_screen.dart';
import 'package:checkpoint/state/discussions_store.dart';
import 'package:checkpoint/state/store_scope.dart';
import 'package:checkpoint/theme/palette.dart';
import 'package:checkpoint/utils/formatters.dart';

/// One thread in a list: its title and the start of its text, who started it, how
/// many replies it has and how long ago it was last written in. [showBoard] adds
/// the board it is on (for lists that mix boards). Tapping opens it.
class ThreadTile extends StatelessWidget {
  const ThreadTile({super.key, required this.thread, this.showBoard = false});

  final DiscussionThread thread;
  final bool showBoard;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final l10n = context.l10n;
    final board = showBoard
        ? context.watch<DiscussionsStore>().boardById(thread.boardId)
        : null;
    final details = [
      thread.author.name,
      if (board != null) board.title,
      if (thread.game != null) thread.game!.title,
      timeAgo(thread.lastPostAt.toLocal()),
    ];
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: () => openDiscussionThread(context, thread.id),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (thread.pinned)
                  Padding(
                    padding: const EdgeInsetsDirectional.only(end: 6, top: 2),
                    child: Icon(
                      Icons.push_pin_rounded,
                      size: 16,
                      color: palette.accent,
                    ),
                  ),
                if (thread.locked)
                  Padding(
                    padding: const EdgeInsetsDirectional.only(end: 6, top: 2),
                    child: Icon(
                      Icons.lock_outline_rounded,
                      size: 16,
                      color: palette.muted,
                    ),
                  ),
                Expanded(
                  child: Text(
                    thread.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 15.5,
                      fontWeight: FontWeight.w700,
                      height: 1.25,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              thread.text,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: palette.textSoft,
                fontSize: 13,
                height: 1.35,
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: Text(
                    details.join(' · '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: palette.muted, fontSize: 12.5),
                  ),
                ),
                const SizedBox(width: 10),
                Semantics(
                  label: l10n.repliesCount(thread.replyCount),
                  excludeSemantics: true,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.chat_bubble_outline_rounded,
                        size: 14,
                        color: palette.muted,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        fmtCount(thread.replyCount),
                        style: TextStyle(
                          color: palette.muted,
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
