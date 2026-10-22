import 'package:flutter/material.dart';

import 'package:checkpoint/l10n/l10n.dart';
import 'package:checkpoint/models/game_reviews.dart';
import 'package:checkpoint/state/game_reviews_store.dart';
import 'package:checkpoint/state/store_scope.dart';
import 'package:checkpoint/theme/palette.dart';
import 'package:checkpoint/widgets/sheet_frame.dart';

/// Asks why something is reported, in a sheet with a row for each [ReportReason];
/// the one tapped is answered, or null when the sheet is closed without one.
Future<ReportReason?> pickReportReason(
  BuildContext context, {
  required String title,
  required String subtitle,
}) => showModalBottomSheet<ReportReason>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  builder: (_) => _ReportReasonSheet(title: title, subtitle: subtitle),
);

/// Asks why [review] of [gameId] is reported, sends the report, and says how it
/// went. The server leaves a reported review out for the member who reported it,
/// so it also disappears from the lists on screen.
Future<void> reportReview(BuildContext context, String gameId, GameReview review) async {
  final reason = await pickReportReason(
    context,
    title: context.l10n.reportReview,
    subtitle: context.l10n.reportReviewSubtitle(review.member.name),
  );
  if (reason == null || !context.mounted) return;
  final store = context.read<GameReviewsStore>();
  final messenger = ScaffoldMessenger.of(context);
  final l10n = context.l10n;
  String message;
  try {
    await store.report(gameId, review, reason);
    message = l10n.reviewReported;
  } catch (_) {
    message = l10n.reviewReportFailed;
  }
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message)));
}

class _ReportReasonSheet extends StatelessWidget {
  const _ReportReasonSheet({required this.title, required this.subtitle});

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return SheetFrame(
      title: title,
      subtitle: subtitle,
      child: Column(
        children: [
          for (final reason in ReportReason.values)
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(reason.label, style: const TextStyle(fontWeight: FontWeight.w600)),
              trailing: Icon(Icons.chevron_right_rounded, color: context.palette.muted),
              onTap: () => Navigator.of(context).pop(reason),
            ),
        ],
      ),
    );
  }
}
