import 'package:flutter/material.dart';

import 'package:checkpoint/l10n/l10n.dart';
import 'package:checkpoint/theme/palette.dart';

/// Under a text the server machine-translated into the app's language (DeepL):
/// says so, with a button for the English original, or back to the
/// translation while the original shows.
class TranslationNote extends StatelessWidget {
  const TranslationNote({
    super.key,
    required this.showingOriginal,
    required this.onToggle,
  });

  final bool showingOriginal;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final muted = context.palette.muted;
    return Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 6,
      children: [
        Icon(Icons.translate_rounded, size: 14, color: muted),
        Text(
          showingOriginal ? l10n.originalText : l10n.translatedByDeepL,
          style: TextStyle(color: muted, fontSize: 12),
        ),
        TextButton(
          onPressed: onToggle,
          style: TextButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 6),
            minimumSize: const Size(0, 36),
            textStyle: const TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
            ),
          ),
          child: Text(
            showingOriginal ? l10n.showTranslation : l10n.showOriginal,
          ),
        ),
      ],
    );
  }
}
