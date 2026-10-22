import 'dart:async';

import 'package:flutter/material.dart';

import 'package:checkpoint/l10n/l10n.dart';
import 'package:checkpoint/models/game.dart';
import 'package:checkpoint/sheets/quick_log_sheet.dart';
import 'package:checkpoint/state/library_store.dart';
import 'package:checkpoint/state/play_timer_store.dart';
import 'package:checkpoint/state/store_scope.dart';
import 'package:checkpoint/theme/palette.dart';
import 'package:checkpoint/utils/formatters.dart';
import 'package:checkpoint/utils/navigation.dart';

/// How long the play timer has run, counting up every second while shown.
class ElapsedText extends StatefulWidget {
  const ElapsedText({super.key, this.style});
  final TextStyle? style;

  @override
  State<ElapsedText> createState() => _ElapsedTextState();
}

class _ElapsedTextState extends State<ElapsedText> {
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final elapsed = context.watch<PlayTimerStore>().elapsed;
    return Text(
      fmtElapsed(elapsed),
      style: (widget.style ?? const TextStyle()).copyWith(
        fontFeatures: const [FontFeature.tabularFigures()],
      ),
    );
  }
}

/// Starts the play timer on [game], after asking when it would replace one that
/// runs for another game (that time is not logged).
Future<void> startPlayTimer(BuildContext context, Game game) async {
  final timers = context.read<PlayTimerStore>();
  final running = timers.running;
  if (running != null && running.gameId != game.id) {
    final other = context.read<LibraryStore>().maybeGame(running.gameId)?.title ?? context.l10n.anotherGame;
    final replace = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(context.l10n.replaceTimerTitle),
        content: Text(context.l10n.replaceTimerBody(other, game.title)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: Text(context.l10n.cancel)),
          TextButton(onPressed: () => Navigator.pop(context, true), child: Text(context.l10n.replace)),
        ],
      ),
    );
    if (replace != true) return;
  }
  timers.start(game.id);
}

/// While the play timer runs: a bar above the tabs with the game and the time,
/// from any tab. Tapping it opens the game; Stop opens the session to log.
class PlayTimerBar extends StatelessWidget {
  const PlayTimerBar({super.key});

  @override
  Widget build(BuildContext context) {
    final running = context.watch<PlayTimerStore>().running;
    if (running == null) return const SizedBox.shrink();
    final game = context.watch<LibraryStore>().maybeGame(running.gameId);
    return Material(
      color: context.palette.surfaceHigh,
      child: InkWell(
        onTap: game == null ? null : () => openGame(context, game.id),
        child: Padding(
          padding: const EdgeInsetsDirectional.fromSTEB(16, 8, 8, 8),
          child: Row(children: [
            Icon(Icons.timer_rounded, color: context.palette.accent, size: 20),
            const SizedBox(width: 10),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(
                  game?.title ?? GameStatus.playing.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                ElapsedText(style: TextStyle(color: context.palette.muted, fontSize: 12.5)),
              ]),
            ),
            FilledButton.tonalIcon(
              onPressed: () => showTimerLogSheet(context),
              icon: const Icon(Icons.stop_rounded, size: 18),
              label: Text(context.l10n.stop),
            ),
          ]),
        ),
      ),
    );
  }
}
