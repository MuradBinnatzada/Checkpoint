import 'package:flutter/material.dart';

import 'package:checkpoint/models/game.dart';
import 'package:checkpoint/state/auth_store.dart';
import 'package:checkpoint/state/library_store.dart';
import 'package:checkpoint/state/store_scope.dart';
import 'package:checkpoint/utils/formatters.dart';
import 'package:checkpoint/widgets/platform_widgets.dart';
import 'package:checkpoint/widgets/sheet_frame.dart';

/// Read-only guard: returns true (and shows a hint) when logged out.
bool _blockedByReadOnly(BuildContext context) {
  if (context.read<AuthStore>().isLoggedIn) return false;
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(const SnackBar(content: Text('Log in to track games')));
  return true;
}

Future<void> showQuickLogSheet(BuildContext context, {String? gameId}) async {
  if (_blockedByReadOnly(context)) return;
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => QuickLogSheet(initialGameId: gameId),
  );
}

/// FAB sheet: pick a game, pick the platform you played on, add a session.
class QuickLogSheet extends StatefulWidget {
  const QuickLogSheet({super.key, this.initialGameId});
  final String? initialGameId;

  @override
  State<QuickLogSheet> createState() => _QuickLogSheetState();
}

class _QuickLogSheetState extends State<QuickLogSheet> {
  final _hours = TextEditingController(text: '1');
  final _note = TextEditingController();
  String? _gameId;
  GamePlatform? _platform;

  @override
  void initState() {
    super.initState();
    _gameId = widget.initialGameId;
    if (_gameId != null) _platform = _defaultPlatform(context.read<LibraryStore>().gameById(_gameId!));
  }

  @override
  void dispose() {
    _hours.dispose();
    _note.dispose();
    super.dispose();
  }

  // Official release platforms + the saved selection (so it never disappears) + the manual-only Steam Deck and Emulator options.
  // Always non-empty (Emulator is always present), so `.first` is safe.
  List<GamePlatform> _availablePlatforms(Game g) => {...g.platforms, if (g.playedOn != null) g.playedOn!, GamePlatform.steamDeck, GamePlatform.emulator}.toList();

  GamePlatform _defaultPlatform(Game g) => g.playedOn ?? _availablePlatforms(g).first;

  void _save(Game game, double hours) {
    final messenger = ScaffoldMessenger.of(context);
    context.read<LibraryStore>().logSession(gameId: game.id, hours: hours, platform: _platform, note: _note.text);
    Navigator.pop(context);
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text('Logged ${fmtHours(hours)}h of ${game.title} on ${_platform?.label ?? 'your platform'}')));
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<LibraryStore>();
    final game = _gameId == null ? null : store.maybeGame(_gameId!);
    final hours = parseNum(_hours.text);
    final canSave = game != null && hours != null && hours > 0;

    final sorted = [...store.games]..sort((a, b) {
        int rank(Game g) => g.status == GameStatus.playing ? 0 : (g.inLibrary ? 1 : 2);
        final c = rank(a).compareTo(rank(b));
        return c != 0 ? c : a.title.compareTo(b.title);
      });

    return SheetFrame(
      title: 'Log a session',
      subtitle: 'Track your time and where you played.',
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        DropdownMenu<String>(
          initialSelection: _gameId,
          expandedInsets: EdgeInsets.zero,
          enableFilter: true,
          requestFocusOnTap: true,
          menuHeight: 280,
          label: const Text('Game'),
          leadingIcon: const Icon(Icons.sports_esports_rounded),
          dropdownMenuEntries: [
            for (final g in sorted)
              DropdownMenuEntry<String>(value: g.id, label: g.title, leadingIcon: Icon(g.coverIcon, color: g.coverColors.first, size: 20)),
          ],
          onSelected: (id) => setState(() {
            _gameId = id;
            _platform = id == null ? null : _defaultPlatform(store.gameById(id));
          }),
        ),
        if (game != null) ...[
          const SizedBox(height: 18),
          const Text('Played on', style: TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 10),
          PlatformChips(platforms: _availablePlatforms(game), selected: _platform, onSelected: (p) => setState(() => _platform = p)),
        ],
        const SizedBox(height: 18),
        TextField(
          controller: _hours,
          keyboardType: decimalKeyboard,
          inputFormatters: [decimalFormatter],
          onChanged: (_) => setState(() {}),
          decoration: fieldDecoration('Hours played this session', suffix: 'hrs'),
        ),
        const SizedBox(height: 10),
        Wrap(spacing: 8, children: [
          for (final h in const <double>[0.5, 1, 2, 4])
            ActionChip(
              label: Text('+${fmtHours(h)}h'),
              onPressed: () => setState(() => _hours.text = fmtHours((parseNum(_hours.text) ?? 0) + h)),
            ),
        ]),
        const SizedBox(height: 14),
        TextField(controller: _note, textCapitalization: TextCapitalization.sentences, decoration: fieldDecoration('Note (optional)')),
        const SizedBox(height: 20),
        SizedBox(
          width: double.infinity,
          child: FilledButton(
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
            onPressed: canSave ? () => _save(game, hours) : null,
            child: const Text('Save session'),
          ),
        ),
      ]),
    );
  }
}