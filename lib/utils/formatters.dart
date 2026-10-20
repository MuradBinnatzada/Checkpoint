import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:checkpoint/theme/palette.dart';

String fmtCount(int n) => n < 1000 ? '$n' : '${(n / 1000).toStringAsFixed(n < 10000 ? 1 : 0)}k';

/// 1280 -> "1,280": the exact number, for places that have room for it.
String fmtThousands(int n) => n.toString().replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (_) => ',');

String fmtHours(double h) => (h - h.roundToDouble()).abs() < 0.05 ? h.round().toString() : h.toStringAsFixed(1);
String fmtMoney(double v) => '\$${v.toStringAsFixed(2)}';

/// 40.9 -> "40.9%", 100 -> "100%", 0.04 -> "<0.1%": a share out of 100, one decimal.
String fmtPercent(double p) {
  if (p > 0 && p < 0.05) return '<0.1%';
  final rounded = (p * 10).round() / 10;
  return rounded == rounded.roundToDouble() ? '${rounded.round()}%' : '${rounded.toStringAsFixed(1)}%';
}

double? parseNum(String s) => double.tryParse(s.trim().replaceAll(',', '.'));

String timeAgo(DateTime t) {
  final d = DateTime.now().difference(t);
  if (d.inMinutes < 60) return '${math.max(1, d.inMinutes)}m ago';
  if (d.inHours < 24) return '${d.inHours}h ago';
  if (d.inDays < 7) return '${d.inDays}d ago';
  if (d.inDays < 60) return '${d.inDays ~/ 7}w ago';
  return '${d.inDays ~/ 30}mo ago';
}

const _monthNames = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

/// "Oct 14": the calendar day of [d] as stored, without shifting it to local time.
String fmtMonthDay(DateTime d) => '${_monthNames[d.month - 1]} ${d.day}';

String initials(String name) => name
    .trim()
    .split(RegExp(r'\s+'))
    .where((p) => p.isNotEmpty)
    .take(2)
    .map((p) => p[0].toUpperCase())
    .join();

String greeting() {
  final h = DateTime.now().hour;
  if (h < 5) return 'Late night';
  if (h < 12) return 'Good morning';
  if (h < 18) return 'Good afternoon';
  return 'Good evening';
}

/// The largest text size the app follows from the device's setting: twice the
/// normal size, what low-vision settings reach on most phones.
const maxTextScale = 2.0;

double textScale(BuildContext context) =>
    MediaQuery.textScalerOf(context).scale(1).clamp(1.0, maxTextScale).toDouble();

double posterCardHeight(BuildContext context, double width, {required bool subtitle}) =>
    width * 1.5 + 14 + (18 + 6 + 16 + (subtitle ? 18 : 0)) * textScale(context);

InputDecoration fieldDecoration(
  BuildContext context,
  String label, {
  String? prefix,
  String? suffix,
  String? hint,
  Widget? prefixIcon,
  Widget? suffixIcon,
}) =>
    InputDecoration(
      labelText: label,
      hintText: hint,
      prefixText: prefix,
      suffixText: suffix,
      prefixIcon: prefixIcon,
      suffixIcon: suffixIcon,
      filled: true,
      fillColor: context.palette.surfaceHigh,
      labelStyle: TextStyle(color: context.palette.muted),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: context.palette.accent, width: 1.5),
      ),
    );

final decimalFormatter = FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'));
const decimalKeyboard = TextInputType.numberWithOptions(decimal: true);

/// "Oct 2026": the month and year of [d], as stored, without shifting it to local time.
String fmtMonthYear(DateTime d) => '${_monthNames[d.month - 1]} ${d.year}';

/// "Today", "Yesterday", "Oct 14", or "Oct 14, 2025" in another year: the day of
/// [d] as the device sees it, relative to [now].
String fmtDay(DateTime d, {DateTime? now}) {
  final today = now ?? DateTime.now();
  // Calendar days in UTC, so a daylight saving change can't make a day 23 hours.
  final daysAgo = DateTime.utc(today.year, today.month, today.day)
      .difference(DateTime.utc(d.year, d.month, d.day))
      .inDays;
  if (daysAgo == 0) return 'Today';
  if (daysAgo == 1) return 'Yesterday';
  final monthDay = '${_monthNames[d.month - 1]} ${d.day}';
  return d.year == today.year ? monthDay : '$monthDay, ${d.year}';
}

/// 0:04:09, 1:02:33: a running timer, hours first.
String fmtElapsed(Duration d) {
  final seconds = d.isNegative ? 0 : d.inSeconds;
  String two(int n) => n.toString().padLeft(2, '0');
  return '${seconds ~/ 3600}:${two(seconds ~/ 60 % 60)}:${two(seconds % 60)}';
}
