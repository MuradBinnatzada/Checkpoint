import 'package:flutter/material.dart';

import 'package:checkpoint/theme/palette.dart';

class Panel extends StatelessWidget {
  const Panel({super.key, required this.child, this.title, this.trailing, this.padding = const EdgeInsets.all(16)});
  final Widget child;
  final String? title;
  final Widget? trailing;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: padding,
      decoration: BoxDecoration(
        color: context.palette.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: context.palette.hairline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (title != null) ...[
            Row(children: [
              Expanded(
                // A heading, so screen readers can jump from panel to panel.
                child: Semantics(
                  header: true,
                  child: Text(title!, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                ),
              ),
              ?trailing,
            ]),
            const SizedBox(height: 14),
          ],
          child,
        ],
      ),
    );
  }
}
