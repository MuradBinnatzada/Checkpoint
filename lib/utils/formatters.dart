import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:checkpoint/theme/palette.dart';

String fmtCount(int n) => n < 1000 ? '$n' : '${(n / 1000).toStringAsFixed(n < 10000 ? 1 : 0)}k';

/// 1280 -> "1,280": the exact number, for places that have room for it.
String fmtThousands(int n) => n.toString().replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (_) => ',');

String fmtHours(double h) => (h - h.roundToDouble()).abs() < 0.05 ? h.round().toString() : h.toStringAsFixed(1);
String fmtMoney(double v) => '\$${v.toStringAsFixed(2)}';
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

double textScale(BuildContext context) =>
    MediaQuery.textScalerOf(context).scale(1).clamp(1.0, 1.3).toDouble();

double posterCardHeight(BuildContext context, double width, {required bool subtitle}) =>
    width * 1.5 + 14 + (18 + 6 + 16 + (subtitle ? 18 : 0)) * textScale(context);

InputDecoration fieldDecoration(
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
      fillColor: Palette.surfaceHigh,
      labelStyle: const TextStyle(color: Palette.muted),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: Palette.accent, width: 1.5),
      ),
    );

final decimalFormatter = FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'));
const decimalKeyboard = TextInputType.numberWithOptions(decimal: true);

/// "Oct 2026": the month and year of [d], as stored, without shifting it to local time.
String fmtMonthYear(DateTime d) => '${_monthNames[d.month - 1]} ${d.year}';
