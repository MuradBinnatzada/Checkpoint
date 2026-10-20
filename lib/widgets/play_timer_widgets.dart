import 'dart:async';

import 'package:flutter/material.dart';

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
    final other = context.read<LibraryStore>().maybeGame(running.gameId)?.title ?? 'another game';
    final replace = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Replace the running timer?'),
        content: Text(
          'A timer is running for $other. Starting one for ${game.title} '
          'throws its time away. To keep it, stop it and log it first.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Replace')),
        ],
      ),
    );
    if (replace != true) return;
  }
  timers.start(game.id);
}

/// The timer on a game's screen: "Start timer", or how long it has run with
/// Stop, which opens the session to log.
class PlayTimerButton extends StatelessWidget {
  const PlayTimerButton({super.key, required this.game});
  final Game game;

  @override
  Widget build(BuildContext context) {
    final timers = context.watch<PlayTimerStore>();
    if (!timers.isRunningFor(game.id)) {
      return OutlinedButton.icon(
        onPressed: () => startPlayTimer(context, game),
        icon: const Icon(Icons.play_arrow_rounded, size: 18),
        label: const Text('Start timer'),
      );
    }
    return FilledButton.icon(
      onPressed: () => showTimerLogSheet(context),
      icon: const Icon(Icons.stop_rounded, size: 18),
      label: Row(mainAxisSize: MainAxisSize.min, children: [
        const Text('Stop · '),
        const ElapsedText(),
      ]),
    );
  }
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
          padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
          child: Row(children: [
            Icon(Icons.timer_rounded, color: context.palette.accent, size: 20),
            const SizedBox(width: 10),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(
                  game?.title ?? 'Playing',
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
              label: const Text('Stop'),
            ),
          ]),
        ),
      ),
    );
  }
}
