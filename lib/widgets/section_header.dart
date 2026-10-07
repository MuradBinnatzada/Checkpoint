import 'package:flutter/material.dart';

class SectionHeader extends StatelessWidget {
  const SectionHeader(this.title, {super.key, this.actionLabel, this.onAction});
  final String title;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 24, 12, 12),
      child: Row(children: [
        Expanded(child: Text(title, style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w800))),
        if (actionLabel != null) TextButton(onPressed: onAction, child: Text(actionLabel!)),
      ]),
    );
  }
}
