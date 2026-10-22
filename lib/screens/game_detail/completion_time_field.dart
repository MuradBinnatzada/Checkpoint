import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:checkpoint/l10n/l10n.dart';
import 'package:checkpoint/models/completion_time.dart';
import 'package:checkpoint/models/game.dart';
import 'package:checkpoint/models/limits.dart';
import 'package:checkpoint/state/auth_store.dart';
import 'package:checkpoint/state/library_store.dart';
import 'package:checkpoint/state/store_scope.dart';
import 'package:checkpoint/theme/palette.dart';
import 'package:checkpoint/utils/formatters.dart';
import 'package:checkpoint/widgets/app_choice_chip.dart';

/// "How long did it take?" under the status buttons of a completed game: what
/// the member finished (Main Story, Main + Extras or Completionist) and how
/// long it took, in hours (12.5 works) and minutes. It is optional. The form
/// opens by itself when the game is marked completed on this screen, and is
/// one line to tap otherwise. A saved time shows in its place; tapping it
/// edits or removes it. Nothing is drawn for a game that isn't completed (its
/// saved time is kept), or when signed out.
class CompletionTimeField extends StatefulWidget {
  const CompletionTimeField({super.key, required this.game});

  final Game game;

  @override
  State<CompletionTimeField> createState() => _CompletionTimeFieldState();
}

class _CompletionTimeFieldState extends State<CompletionTimeField> {
  final _hours = TextEditingController();
  final _minutes = TextEditingController();
  CompletionCategory? _category;
  bool _editing = false;

  @override
  void didUpdateWidget(CompletionTimeField oldWidget) {
    super.didUpdateWidget(oldWidget);
    final game = widget.game;
    if (oldWidget.game.id != game.id) {
      _editing = false;
      return;
    }
    // Just marked completed: ask now, unless there is a time already.
    if (oldWidget.game.status != GameStatus.completed &&
        game.status == GameStatus.completed &&
        game.completionTime == null) {
      _startEditing();
    }
  }

  @override
  void dispose() {
    _hours.dispose();
    _minutes.dispose();
    super.dispose();
  }

  /// Opens the form with the saved time in it, if there is one.
  void _startEditing() {
    final saved = widget.game.completionTime;
    _category = saved?.category;
    final hours = saved == null ? 0 : saved.minutes ~/ 60;
    final minutes = saved == null ? 0 : saved.minutes % 60;
    _hours.text = hours == 0 ? '' : '$hours';
    _minutes.text = minutes == 0 ? '' : '$minutes';
    _editing = true;
  }

  void _close() {
    FocusScope.of(context).unfocus();
    setState(() => _editing = false);
  }

  void _save(CompletionTime time) {
    context.read<LibraryStore>().setCompletionTime(widget.game.id, time);
    _close();
  }

  void _remove() {
    context.read<LibraryStore>().setCompletionTime(widget.game.id, null);
    _close();
  }

  /// The time typed in, in whole minutes, or why it isn't one. Both are null
  /// while nothing is typed.
  ({int? minutes, String? error}) _typed() {
    final hoursText = _hours.text.trim();
    final minutesText = _minutes.text.trim();
    if (hoursText.isEmpty && minutesText.isEmpty) {
      return (minutes: null, error: null);
    }
    final hours = hoursText.isEmpty ? 0.0 : parseNum(hoursText);
    final minutes = minutesText.isEmpty ? 0 : int.tryParse(minutesText);
    if (hours == null || !hours.isFinite) {
      return (minutes: null, error: L10n.current.completionHoursInvalid(fmtHours(12.5)));
    }
    if (minutes == null || minutes > 59) {
      return (minutes: null, error: L10n.current.completionMinutesInvalid);
    }
    final total = hours > maxTotalHours ? null : (hours * 60).round() + minutes;
    if (total == null || total > maxTotalHours * 60) {
      return (
        minutes: null,
        error: L10n.current.completionTooLong(fmtThousands(maxTotalHours.round())),
      );
    }
    if (total < 1) return (minutes: null, error: L10n.current.completionEnterTime);
    return (minutes: total, error: null);
  }

  @override
  Widget build(BuildContext context) {
    final game = widget.game;
    if (game.status != GameStatus.completed ||
        !context.watch<AuthStore>().isLoggedIn) {
      return const SizedBox.shrink();
    }
    final saved = game.completionTime;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Divider(height: 28, color: context.palette.hairline),
        if (_editing)
          _form(saved)
        else if (saved != null)
          _savedTime(saved)
        else
          TextButton.icon(
            onPressed: () => setState(_startEditing),
            style: TextButton.styleFrom(padding: EdgeInsets.zero),
            icon: const Icon(Icons.timer_outlined, size: 18),
            label: Text(context.l10n.completionAdd),
          ),
      ],
    );
  }

  Widget _savedTime(CompletionTime saved) {
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: () => setState(_startEditing),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          children: [
            Icon(Icons.timer_outlined, size: 18, color: context.palette.muted),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    context.l10n.completionYourTime,
                    style: TextStyle(color: context.palette.muted, fontSize: 12),
                  ),
                  Text(
                    '${fmtMinutes(saved.minutes)} · ${saved.category.label}',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ],
              ),
            ),
            Icon(Icons.edit_rounded, size: 16, color: context.palette.muted),
          ],
        ),
      ),
    );
  }

  Widget _form(CompletionTime? saved) {
    final typed = _typed();
    final category = _category;
    final minutes = typed.minutes;
    final time = category == null || minutes == null
        ? null
        : CompletionTime(category, minutes);
    void save() {
      if (time != null) _save(time);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          context.l10n.completionHowLong,
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 4),
        Text(
          context.l10n.completionOptional,
          style: TextStyle(color: context.palette.muted, fontSize: 12.5, height: 1.35),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final c in CompletionCategory.values)
              AppChoiceChip(
                label: c.label,
                selected: c == category,
                onSelected: () => setState(() => _category = c),
              ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _hours,
                keyboardType: decimalKeyboard,
                inputFormatters: [decimalFormatter],
                textInputAction: TextInputAction.next,
                onChanged: (_) => setState(() {}),
                decoration: fieldDecoration(context, context.l10n.hours, suffix: context.l10n.hoursUnit),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: TextField(
                controller: _minutes,
                keyboardType: TextInputType.number,
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                  LengthLimitingTextInputFormatter(2),
                ],
                textInputAction: TextInputAction.done,
                onChanged: (_) => setState(() {}),
                onSubmitted: (_) => save(),
                decoration: fieldDecoration(context, context.l10n.minutes, suffix: context.l10n.minutesUnit),
              ),
            ),
          ],
        ),
        if (typed.error != null) ...[
          const SizedBox(height: 6),
          Text(
            typed.error!,
            style: TextStyle(color: context.palette.danger, fontSize: 12.5),
          ),
        ] else if (minutes != null && category == null) ...[
          const SizedBox(height: 6),
          Text(
            context.l10n.completionPickCategory(
              CompletionCategory.mainStory.label,
              CompletionCategory.mainExtras.label,
              CompletionCategory.completionist.label,
            ),
            style: TextStyle(color: context.palette.muted, fontSize: 12.5),
          ),
        ],
        const SizedBox(height: 8),
        Row(
          children: [
            if (saved != null)
              TextButton(
                onPressed: _remove,
                style: TextButton.styleFrom(foregroundColor: context.palette.danger),
                child: Text(context.l10n.remove),
              ),
            const Spacer(),
            TextButton(
              onPressed: _close,
              child: Text(saved == null ? context.l10n.notNow : context.l10n.cancel),
            ),
            const SizedBox(width: 8),
            FilledButton(
              onPressed: time == null || time == saved ? null : save,
              child: Text(context.l10n.save),
            ),
          ],
        ),
      ],
    );
  }
}

/// "12 h 30 min", "12 h", or "45 min": a time as typed in, to the minute.
String fmtMinutes(int minutes) {
  final h = minutes ~/ 60;
  final m = minutes % 60;
  final l10n = L10n.current;
  if (h == 0) return l10n.minutesShort(m);
  return m == 0 ? l10n.hoursShort('$h') : l10n.hoursMinutesShort(h, m);
}
