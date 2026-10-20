import 'dart:convert';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import 'package:checkpoint/models/library_csv.dart';
import 'package:checkpoint/services/game_api_service.dart';
import 'package:checkpoint/state/library_import.dart';
import 'package:checkpoint/state/library_store.dart';
import 'package:checkpoint/state/store_scope.dart';
import 'package:checkpoint/theme/palette.dart';
import 'package:checkpoint/widgets/panel.dart';
import 'package:checkpoint/widgets/profile_link_rows.dart';

/// Your library and play sessions as CSV files (spreadsheets open them), and a
/// library file read back in: Checkpoint's own export, or another tracker's.
class DataSection extends StatelessWidget {
  const DataSection({super.key, this.saveFile = _saveCsv, this.pickFile = _pickCsv});

  /// Saves [bytes] as [name] ([origin]: what was tapped, for the share sheet's
  /// arrow on an iPad); false when the member cancelled. Replaced in tests.
  final Future<bool> Function(String name, List<int> bytes, Rect? origin) saveFile;

  /// The text of a file the member picks; null when they cancelled.
  final Future<String?> Function() pickFile;

  static const _csvFiles = XTypeGroup(
    label: 'CSV',
    extensions: ['csv'],
    mimeTypes: ['text/csv', 'text/comma-separated-values'],
    uniformTypeIdentifiers: ['public.comma-separated-values-text'],
  );

  static bool get _isDesktop =>
      !kIsWeb &&
      {TargetPlatform.linux, TargetPlatform.macOS, TargetPlatform.windows}.contains(defaultTargetPlatform);

  /// A save dialog on desktop; elsewhere the share sheet (Files, Drive, mail...),
  /// which on the web downloads the file when the browser can't share it.
  static Future<bool> _saveCsv(String name, List<int> bytes, Rect? origin) async {
    final file = XFile.fromData(Uint8List.fromList(bytes), mimeType: 'text/csv', name: name);
    if (_isDesktop) {
      final location = await getSaveLocation(suggestedName: name, acceptedTypeGroups: const [_csvFiles]);
      if (location == null) return false;
      await file.saveTo(location.path);
      return true;
    }
    final result = await SharePlus.instance.share(
      ShareParams(files: [file], fileNameOverrides: [name], subject: name, sharePositionOrigin: origin),
    );
    return result.status != ShareResultStatus.dismissed;
  }

  static Future<String?> _pickCsv() async {
    final file = await openFile(acceptedTypeGroups: const [_csvFiles]);
    if (file == null) return null;
    return utf8.decode(await file.readAsBytes(), allowMalformed: true);
  }

  String _stamp() => DateTime.now().toIso8601String().substring(0, 10);

  Future<void> _export(BuildContext context, String name, String csv) async {
    final messenger = ScaffoldMessenger.of(context);
    final box = context.findRenderObject() as RenderBox?;
    final origin = box == null || !box.hasSize ? null : box.localToGlobal(Offset.zero) & box.size;
    String? message;
    try {
      // The byte order mark tells spreadsheets the file is UTF-8.
      final saved = await saveFile(name, utf8.encode('\uFEFF$csv'), origin);
      if (saved) message = 'Exported $name';
    } catch (e) {
      debugPrint('Export failed: $e');
      message = 'Could not save the file.';
    }
    if (message == null) return;
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _import(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    String? text;
    try {
      text = await pickFile();
    } catch (e) {
      debugPrint('Reading the import failed: $e');
      messenger.showSnackBar(const SnackBar(content: Text('Could not read that file.')));
      return;
    }
    if (text == null || !context.mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => ImportScreen(file: ImportRow.parse(text!))),
    );
  }

  @override
  Widget build(BuildContext context) {
    final library = context.watch<LibraryStore>();
    final games = library.libraryGames.length;
    final sessions = library.sessions.length;
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
      children: [
        Panel(
          title: 'Export',
          child: Text(
            'Your library and play sessions as CSV files, which any spreadsheet opens.',
            style: TextStyle(color: context.palette.muted, height: 1.4),
          ),
        ),
        const SizedBox(height: 10),
        ProfileLinkRows(
          links: [
            ProfileLink(
              icon: Icons.collections_bookmark_rounded,
              label: 'Export library',
              count: games,
              onTap: () => _export(context, 'checkpoint-library-${_stamp()}.csv', libraryCsv(library.libraryGames)),
            ),
            ProfileLink(
              icon: Icons.timer_rounded,
              label: 'Export play sessions',
              count: sessions,
              onTap: () => _export(context, 'checkpoint-sessions-${_stamp()}.csv', sessionsCsv(library.sessions, library.maybeGame)),
            ),
          ],
        ),
        const SizedBox(height: 20),
        Panel(
          title: 'Import',
          child: Text(
            'Add games from a CSV file: a Checkpoint export, or a spreadsheet from another '
            'tracker with a "title" column, and optionally status, rating, hours, platform '
            'and review. Games already in your library are updated; hours never go down.',
            style: TextStyle(color: context.palette.muted, height: 1.4),
          ),
        ),
        const SizedBox(height: 10),
        ProfileLinkRows(
          links: [
            ProfileLink(
              icon: Icons.upload_file_rounded,
              label: 'Import from CSV',
              onTap: () => _import(context),
            ),
          ],
        ),
      ],
    );
  }
}

/// What a picked file holds, "Import N games", then the import as it goes and
/// what it couldn't match.
class ImportScreen extends StatefulWidget {
  const ImportScreen({super.key, required this.file, this.api});
  final ImportFile file;

  /// Where games are looked up; the real IGDB search by default.
  final GameApiService? api;

  @override
  State<ImportScreen> createState() => _ImportScreenState();
}

class _ImportScreenState extends State<ImportScreen> {
  LibraryImport? _import;

  @override
  void dispose() {
    _import?.cancel();
    _import?.dispose();
    super.dispose();
  }

  void _start() {
    final run = LibraryImport(
      rows: widget.file.rows,
      api: widget.api ?? GameApiService(),
      library: context.read<LibraryStore>(),
    )..addListener(() {
        if (mounted) setState(() {});
      });
    setState(() => _import = run);
    run.run();
  }

  @override
  Widget build(BuildContext context) {
    final file = widget.file;
    final run = _import;
    return PopScope(
      canPop: run == null || !run.isRunning,
      child: Scaffold(
        appBar: AppBar(title: const Text('Import')),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
          children: [
            if (run == null) ...[
              Text(
                file.rows.isEmpty
                    ? 'Nothing to import in this file.'
                    : '${file.rows.length} game${file.rows.length == 1 ? '' : 's'} to import',
                style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 6),
              Text(
                'Each game is looked up on IGDB by its title, a few a second.',
                style: TextStyle(color: context.palette.muted),
              ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: file.rows.isEmpty ? null : _start,
                style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
                child: Text('Import ${file.rows.length} game${file.rows.length == 1 ? '' : 's'}'),
              ),
            ] else ...[
              Text(
                run.isRunning
                    ? 'Importing ${run.done} of ${file.rows.length}…'
                    : run.wasCancelled
                    ? 'Stopped after ${run.done} of ${file.rows.length}'
                    : 'Imported ${run.imported} of ${file.rows.length}',
                style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 12),
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: LinearProgressIndicator(
                  value: file.rows.isEmpty ? 1 : run.done / file.rows.length,
                  minHeight: 8,
                ),
              ),
              const SizedBox(height: 12),
              if (run.isRunning)
                OutlinedButton(onPressed: run.cancel, child: const Text('Stop'))
              else
                FilledButton(onPressed: () => Navigator.pop(context), child: const Text('Done')),
              if (run.searchFailed) ...[
                const SizedBox(height: 12),
                Text(
                  'IGDB couldn\'t be reached for some games. Import the file again later to add them.',
                  style: TextStyle(color: context.palette.danger, height: 1.35),
                ),
              ],
              if (run.unmatched.isNotEmpty) ...[
                const SizedBox(height: 20),
                Text('Not found (${run.unmatched.length})', style: const TextStyle(fontWeight: FontWeight.w700)),
                const SizedBox(height: 4),
                Text(
                  'No game on IGDB has exactly this title. Add them from Search.',
                  style: TextStyle(color: context.palette.muted, fontSize: 12.5),
                ),
                for (final row in run.unmatched)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text('Line ${row.line}: ${row.title}'),
                  ),
              ],
            ],
            if (file.skipped.isNotEmpty) ...[
              const SizedBox(height: 20),
              Text('Left out (${file.skipped.length})', style: const TextStyle(fontWeight: FontWeight.w700)),
              for (final reason in file.skipped)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(reason, style: TextStyle(color: context.palette.muted)),
                ),
            ],
          ],
        ),
      ),
    );
  }
}
