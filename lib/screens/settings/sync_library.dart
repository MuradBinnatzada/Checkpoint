import 'package:flutter/material.dart';

import 'package:checkpoint/state/library_store.dart';
import 'package:checkpoint/state/store_scope.dart';
import 'package:checkpoint/theme/palette.dart';

/// The Sync Library button under the game profiles, with the notice that appears
/// while the last sync was cut short.
class SyncLibraryButton extends StatelessWidget {
  const SyncLibraryButton({super.key});

  @override
  Widget build(BuildContext context) {
    final library = context.watch<LibraryStore>();
    return Column(
      children: [
        if (library.syncStatus == SyncStatus.delayed) ...[
          _SyncDelayedNotice(message: library.syncFailure?.message ?? ''),
          const SizedBox(height: 10),
        ],
        SizedBox(
          width: double.infinity,
          child: FilledButton.tonalIcon(
            onPressed: library.isSyncing
                ? null
                : () async {
                    final messenger = ScaffoldMessenger.of(context);
                    // null = everything synced; otherwise why not, or what is still waiting.
                    final message = await context
                        .read<LibraryStore>()
                        .syncLibrary();
                    messenger
                      ..hideCurrentSnackBar()
                      ..showSnackBar(
                        SnackBar(
                          content: Text(
                            message ?? 'Library synced successfully',
                          ),
                        ),
                      );
                  },
            icon: library.isSyncing
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.sync_rounded),
            label: Text(
              library.isSyncing
                  ? 'Syncing…'
                  : library.syncStatus == SyncStatus.delayed
                  ? 'Retry Sync'
                  : 'Sync Library',
            ),
          ),
        ),
      ],
    );
  }
}

/// Shown over the Sync button while the last sync was cut short by Steam or the
/// game database (rate limited or down). Nothing is wrong with the account; the
/// button turns into "Retry Sync".
class _SyncDelayedNotice extends StatelessWidget {
  const _SyncDelayedNotice({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      label: 'Sync delayed. $message',
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Palette.star.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Palette.star.withValues(alpha: 0.35)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.schedule_rounded, size: 18, color: Palette.star),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Sync Delayed',
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 13.5,
                    ),
                  ),
                  if (message.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      message,
                      style: const TextStyle(
                        color: Palette.muted,
                        fontSize: 12.5,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
