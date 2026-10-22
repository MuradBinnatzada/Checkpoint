import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:checkpoint/l10n/l10n.dart';
import 'package:checkpoint/theme/palette.dart';

/// Opens [BackupCodesScreen] with new [codes] (Settings > Security > New
/// backup codes).
Future<void> showBackupCodes(BuildContext context, List<String> codes) =>
    Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        fullscreenDialog: true,
        builder: (_) => BackupCodesScreen(codes: codes),
      ),
    );

/// New backup codes, on a screen of their own.
class BackupCodesScreen extends StatelessWidget {
  const BackupCodesScreen({super.key, required this.codes});

  final List<String> codes;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(context.l10n.backupCodes)),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: BackupCodesList(
                codes: codes,
                onDone: () => Navigator.of(context).pop(),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Backup codes as they are shown once, right after they are made: what they
/// are for, the codes, Copy, and "I saved them" ([onDone]). Also the last step
/// of turning two-factor authentication on.
class BackupCodesList extends StatelessWidget {
  const BackupCodesList({super.key, required this.codes, required this.onDone});

  final List<String> codes;
  final VoidCallback onDone;

  Future<void> _copy(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    final copied = context.l10n.backupCodesCopied;
    await Clipboard.setData(ClipboardData(text: codes.join('\n')));
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(copied)));
  }

  @override
  Widget build(BuildContext context) {
    final muted = TextStyle(color: context.palette.muted, height: 1.4);
    const codeStyle = TextStyle(
      fontFamily: 'monospace',
      fontSize: 16,
      fontWeight: FontWeight.w600,
      letterSpacing: 1,
    );
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          context.l10n.backupCodesIntro,
          style: muted,
        ),
        const SizedBox(height: 8),
        Text(
          context.l10n.backupCodesNote,
          style: muted,
        ),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            color: context.palette.surfaceHigh,
            borderRadius: BorderRadius.circular(12),
          ),
          child: SelectionArea(
            child: Column(
              children: [
                for (var i = 0; i < codes.length; i += 2)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            codes[i],
                            textAlign: TextAlign.center,
                            style: codeStyle,
                          ),
                        ),
                        Expanded(
                          child: i + 1 < codes.length
                              ? Text(
                                  codes[i + 1],
                                  textAlign: TextAlign.center,
                                  style: codeStyle,
                                )
                              : const SizedBox.shrink(),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          onPressed: () => _copy(context),
          icon: const Icon(Icons.copy_rounded, size: 18),
          label: Text(context.l10n.copy),
        ),
        const SizedBox(height: 8),
        FilledButton(onPressed: onDone, child: Text(context.l10n.iSavedThem)),
      ],
    );
  }
}
