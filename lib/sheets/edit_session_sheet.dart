import 'package:flutter/material.dart';

import 'package:checkpoint/models/game.dart';
import 'package:checkpoint/models/limits.dart';
import 'package:checkpoint/models/log_entry.dart';
import 'package:checkpoint/state/library_store.dart';
import 'package:checkpoint/state/store_scope.dart';
import 'package:checkpoint/theme/palette.dart';
import 'package:checkpoint/utils/formatters.dart';
import 'package:checkpoint/widgets/platform_widgets.dart';
import 'package:checkpoint/widgets/session_time_field.dart';
import 'package:checkpoint/widgets/sheet_frame.dart';

/// How long a snack bar with an Undo stays (see game_detail_screen.dart).
const _undoDuration = Duration(seconds: 5);

/// Opens the sheet that edits or deletes the play session [sessionId].
Future<void> showEditSessionSheet(BuildContext context, String sessionId) async {
  final session = context.read<LibraryStore>().sessionById(sessionId);
  if (session == null) return;
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => EditSessionSheet(session: session),
  );
}

/// Deletes [session], with an Undo that logs it again as it was.
Future<void> deleteSessionWithUndo(BuildContext context, LogEntry session) async {
  final store = context.read<LibraryStore>();
  final messenger = ScaffoldMessenger.of(context);
  final removed = await store.deleteSession(session.id);
  if (removed == null) return;
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(
      content: Text('Deleted the ${fmtHours(removed.hours)} h session'),
      duration: _undoDuration,
      persist: false,
      action: SnackBarAction(label: 'Undo', onPressed: () => store.restoreSession(removed)),
    ));
}

/// A play session's hours, platform, day and note, for fixing one logged wrong;
/// or deleting it. The game's total follows the change in hours.
class EditSessionSheet extends StatefulWidget {
  const EditSessionSheet({super.key, required this.session});
  final LogEntry session;

  @override
  State<EditSessionSheet> createState() => _EditSessionSheetState();
}

class _EditSessionSheetState extends State<EditSessionSheet> {
  late final _hours = TextEditingController(text: fmtHours(widget.session.hours));
  late final _note = TextEditingController(text: widget.session.note);
  late GamePlatform _platform = widget.session.platform;
  late DateTime _at = widget.session.timestamp;

  @override
  void dispose() {
    _hours.dispose();
    _note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final store = context.read<LibraryStore>();
    final game = store.maybeGame(widget.session.gameId);
    final platforms = <GamePlatform>{
      ...?game?.playedOnOptions,
      widget.session.platform,
    }.toList();
    final hours = parseNum(_hours.text);
    final valid = hours != null && hours > 0 && hours <= maxTotalHours;

    return SheetFrame(
      title: 'Edit session',
      subtitle: game?.title ?? '',
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        TextField(
          controller: _hours,
          keyboardType: decimalKeyboard,
          inputFormatters: [decimalFormatter],
          onChanged: (_) => setState(() {}),
          decoration: fieldDecoration('Hours played', suffix: 'hrs').copyWith(
            errorText: hours != null && !valid ? 'Enter more than 0 hours.' : null,
          ),
        ),
        const SizedBox(height: 18),
        const Text('Played on', style: TextStyle(fontWeight: FontWeight.w700)),
        const SizedBox(height: 10),
        PlatformChips(
          platforms: platforms,
          selected: _platform,
          onSelected: (p) => setState(() => _platform = p),
        ),
        const SizedBox(height: 18),
        SessionTimeField(
          value: _at,
          allowNow: false,
          onChanged: (at) => setState(() => _at = at ?? DateTime.now()),
        ),
        const SizedBox(height: 14),
        TextField(
          controller: _note,
          maxLength: maxNoteLength,
          textCapitalization: TextCapitalization.sentences,
          decoration: fieldDecoration('Note (optional)').copyWith(counterText: ''),
        ),
        const SizedBox(height: 20),
        SizedBox(
          width: double.infinity,
          child: FilledButton(
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
            onPressed: !valid
                ? null
                : () {
                    store.editSession(
                      widget.session.id,
                      hours: hours,
                      platform: _platform,
                      at: _at,
                      note: _note.text,
                    );
                    Navigator.pop(context);
                  },
            child: const Text('Save changes'),
          ),
        ),
        const SizedBox(height: 8),
        Center(
          child: TextButton.icon(
            style: TextButton.styleFrom(foregroundColor: Palette.danger),
            onPressed: () {
              // Reads what it needs from the sheet before it closes.
              deleteSessionWithUndo(context, widget.session);
              Navigator.pop(context);
            },
            icon: const Icon(Icons.delete_outline_rounded, size: 18),
            label: const Text('Delete session'),
          ),
        ),
      ]),
    );
  }
}
