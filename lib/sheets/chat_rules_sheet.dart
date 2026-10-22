import 'package:flutter/material.dart';

import 'package:checkpoint/l10n/l10n.dart';
import 'package:checkpoint/state/discussions_store.dart';
import 'package:checkpoint/state/store_scope.dart';
import 'package:checkpoint/theme/palette.dart';
import 'package:checkpoint/widgets/sheet_frame.dart';

/// Shows the chat rules, to read.
Future<void> showChatRules(BuildContext context) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  builder: (_) => const ChatRulesSheet(),
);

/// Whether the member may post: they agreed to the chat rules before on this
/// device, or agree to them now, in a sheet that asks. False when they close it
/// without agreeing.
Future<bool> ensureChatRules(BuildContext context) async {
  final store = context.read<DiscussionsStore>();
  if (await store.hasAcceptedRules()) return true;
  if (!context.mounted) return false;
  final agreed = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => const ChatRulesSheet(asksToAgree: true),
  );
  if (agreed != true) return false;
  await store.acceptRules();
  return true;
}

/// The chat rules, short: what the discussions are asked to be, and what is
/// never allowed. With [asksToAgree] the button is "I agree", which is what lets
/// a member post for the first time.
class ChatRulesSheet extends StatelessWidget {
  const ChatRulesSheet({super.key, this.asksToAgree = false});

  final bool asksToAgree;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final rules = [
      (Icons.favorite_border_rounded, l10n.rulesBeKind, l10n.rulesBeKindText),
      (Icons.block_rounded, l10n.rulesNoHate, l10n.rulesNoHateText),
      (Icons.campaign_outlined, l10n.rulesNoSpam, l10n.rulesNoSpamText),
      (
        Icons.visibility_off_outlined,
        l10n.rulesSpoilers,
        l10n.rulesSpoilersText,
      ),
      (Icons.flag_outlined, l10n.rulesReport, l10n.rulesReportText),
    ];
    return SheetFrame(
      title: l10n.chatRules,
      subtitle: l10n.chatRulesSubtitle,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final (icon, title, text) in rules)
            Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(icon, size: 22, color: context.palette.accent),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          text,
                          style: TextStyle(
                            color: context.palette.textSoft,
                            height: 1.35,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 4),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(52),
              ),
              onPressed: () => Navigator.of(context).pop(true),
              child: Text(asksToAgree ? l10n.iAgree : l10n.gotIt),
            ),
          ),
        ],
      ),
    );
  }
}
