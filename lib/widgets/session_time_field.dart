import 'package:flutter/material.dart';

import 'package:checkpoint/theme/palette.dart';
import 'package:checkpoint/utils/formatters.dart';

/// When a play session was played: now, or a day and time picked from the
/// calendar (never in the future), for a session logged afterwards.
class SessionTimeField extends StatelessWidget {
  const SessionTimeField({
    super.key,
    required this.value,
    required this.onChanged,
    this.allowNow = true,
  });

  /// The time picked; null is now.
  final DateTime? value;
  final ValueChanged<DateTime?> onChanged;

  /// Whether the field can go back to "Now" (a new session can, an edited one
  /// keeps a time).
  final bool allowNow;

  Future<void> _pick(BuildContext context) async {
    final now = DateTime.now();
    final initial = value ?? now;
    final day = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2000),
      lastDate: now,
      helpText: 'Day played',
    );
    if (day == null || !context.mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(initial),
      helpText: 'Time played',
    );
    if (time == null) return;
    final picked = DateTime(day.year, day.month, day.day, time.hour, time.minute);
    onChanged(picked.isAfter(now) ? now : picked);
  }

  @override
  Widget build(BuildContext context) {
    final at = value;
    final label = at == null
        ? 'Now'
        : '${fmtDay(at)}, ${MaterialLocalizations.of(context).formatTimeOfDay(TimeOfDay.fromDateTime(at))}';
    return Material(
      color: Palette.surfaceHigh,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => _pick(context),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 6, 6, 6),
          child: Row(children: [
            const Icon(Icons.event_rounded, size: 20, color: Palette.muted),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('When', style: TextStyle(color: Palette.muted, fontSize: 12)),
                Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
              ]),
            ),
            if (at != null && allowNow)
              IconButton(
                tooltip: 'Played just now',
                onPressed: () => onChanged(null),
                icon: const Icon(Icons.close_rounded, size: 20),
              )
            else
              const Padding(
                padding: EdgeInsets.all(12),
                child: Icon(Icons.edit_calendar_rounded, size: 20, color: Palette.muted),
              ),
          ]),
        ),
      ),
    );
  }
}
