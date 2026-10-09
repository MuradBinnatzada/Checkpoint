import 'dart:async';
import 'package:flutter/material.dart';

import 'package:checkpoint/models/game.dart';
import 'package:checkpoint/models/social_user.dart';
import 'package:checkpoint/state/store_scope.dart';
import 'package:checkpoint/theme/palette.dart';
import 'package:checkpoint/utils/formatters.dart';
import 'package:checkpoint/utils/navigation.dart';
import 'package:checkpoint/widgets/app_choice_chip.dart';
import 'package:checkpoint/widgets/cover_art.dart';
import 'package:checkpoint/widgets/empty_state.dart';
import 'package:checkpoint/widgets/profile_avatar.dart';
import 'package:checkpoint/widgets/status_pill.dart';

class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _GenreChipRow extends StatelessWidget {
  const _GenreChipRow({required this.genres, required this.selected, required this.onChanged});
  final List<String> genres;
  final String? selected;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 40,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        children: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: AppChoiceChip(label: 'All', selected: selected == null, onSelected: () => onChanged(null)),
          ),
          for (final g in genres)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: AppChoiceChip(
                label: g,
                selected: selected == g,
                onSelected: () => onChanged(selected == g ? null : g),
              ),
            ),
        ],
      ),
    );
  }
}

enum SearchKind { games, users }

class _SearchScreenState extends State<SearchScreen> {
  final _controller = TextEditingController();
  String _query = '';
  String? _genre;
  SearchKind _kind = SearchKind.games;
  Timer? _debounce; 

  @override
  void dispose() {
    _controller.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  List<Game> _filterGames(List<Game> all, String q) => all.where((g) {
        if (_genre != null && !g.genres.contains(_genre)) return false;
        if (q.isEmpty) return true;
        final hay = [g.title, g.publisher, g.developer, ...g.genres, ...g.platforms.map((p) => p.label)].join(' ').toLowerCase();
        return hay.contains(q);
      }).toList()
        ..sort((a, b) {
          final ai = a.inLibrary ? 1 : 0;
          final bi = b.inLibrary ? 1 : 0;
          if (ai != bi) return ai - bi; 
          return a.title.compareTo(b.title);
        });

  @override
  Widget build(BuildContext context) {
    final store = context.store;
    final isUsers = _kind == SearchKind.users;
    final all = store.games;
    final genres = ({for (final g in all) ...g.genres}.toList())..sort();
    final q = _query.trim().toLowerCase();

    // If searching, pull from IGDB and merge local status. If empty, show local catalog.
    final games = isUsers
        ? const <Game>[]
        : (q.isEmpty
            ? _filterGames(all, q)
            : store.searchResults.map((g) => store.maybeGame(g.id) ?? g).toList());

    final users = isUsers ? store.searchUsers(_query) : const <SocialUser>[];
    final count = isUsers ? users.length : games.length;
    final browsing = q.isEmpty && (isUsers || _genre == null);
    final label = browsing
        ? (isUsers ? 'Suggested people' : 'Popular on Checkpoint')
        : '$count result${count == 1 ? '' : 's'}';

    return SafeArea(
      bottom: false,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(20, 16, 20, 12),
          child: Text('Discover', style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800)),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: TextField(
            controller: _controller,
            textInputAction: TextInputAction.search,
            onChanged: (v) {
              setState(() => _query = v);
              if (_kind == SearchKind.games) {
                if (_debounce?.isActive ?? false) _debounce!.cancel();
                _debounce = Timer(const Duration(milliseconds: 600), () {
                  if (v.trim().isNotEmpty) {
                    context.store.searchExternalGames(v);
                  }
                });
              }
            },
            decoration: fieldDecoration(
              'Search',
              hint: isUsers ? 'Names or @handles…' : 'Games, studios, platforms…',
              prefixIcon: const Icon(Icons.search_rounded),
              suffixIcon: _query.isEmpty
                  ? null
                  : IconButton(
                      icon: const Icon(Icons.close_rounded),
                      onPressed: () {
                        _controller.clear();
                        setState(() => _query = '');
                        _debounce?.cancel();
                      },
                    ),
            ).copyWith(labelText: null),
          ),
        ),
        const SizedBox(height: 12),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: SizedBox(
            width: double.infinity,
            child: SegmentedButton<SearchKind>(
              showSelectedIcon: false,
              segments: const [
                ButtonSegment(value: SearchKind.games, icon: Icon(Icons.sports_esports_rounded), label: Text('Games')),
                ButtonSegment(value: SearchKind.users, icon: Icon(Icons.people_alt_rounded), label: Text('Users')),
              ],
              selected: {_kind},
              onSelectionChanged: (s) => setState(() => _kind = s.first),
              style: SegmentedButton.styleFrom(
                backgroundColor: Palette.surfaceHigh,
                foregroundColor: Colors.white70,
                selectedBackgroundColor: Palette.accent,
                selectedForegroundColor: Palette.onAccent,
                side: BorderSide(color: Colors.white.withValues(alpha: 0.18)),
              ),
            ),
          ),
        ),
        if (!isUsers) ...[
          const SizedBox(height: 12),
          _GenreChipRow(genres: genres, selected: _genre, onChanged: (g) => setState(() => _genre = g)),
        ],
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 4),
          child: Text(label, style: const TextStyle(color: Palette.muted, fontWeight: FontWeight.w600)),
        ),
        Expanded(
          child: count == 0
              ? EmptyState(
                  icon: isUsers ? Icons.person_search_rounded : Icons.search_off_rounded,
                  title: isUsers ? 'No users found' : 'No games found',
                  message: isUsers ? 'Try a different name or @handle.' : 'Try a different title, studio or genre.',
                )
              : ListView.builder(
                  keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                  padding: const EdgeInsets.fromLTRB(12, 4, 12, 32),
                  itemCount: count,
                  itemBuilder: (_, i) => isUsers ? _UserTile(user: users[i]) : _SearchTile(game: games[i]),
                ),
        ),
      ]),
    );
  }
}

class _UserTile extends StatelessWidget {
  const _UserTile({required this.user});
  final SocialUser user;

  @override
  Widget build(BuildContext context) {
    final store = context.store;
    final following = store.isFollowing(user.id);

    void toggle() {
      if (!store.isLoggedIn) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(const SnackBar(content: Text('Log in to follow people')));
        return;
      }
      context.actions.toggleFollow(user.id);
    }

    return Padding(
      padding: const EdgeInsets.all(8),
      child: Row(children: [
        ProfileAvatar(name: user.name, size: 52),
        const SizedBox(width: 14),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(user.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
            Text(user.handle, style: const TextStyle(color: Palette.accent, fontSize: 12.5, fontWeight: FontWeight.w600)),
            const SizedBox(height: 2),
            Text('${user.gamesLogged} games · ${fmtCount(user.followers)} followers', style: const TextStyle(color: Palette.muted, fontSize: 12)),
          ]),
        ),
        const SizedBox(width: 8),
        following
            ? OutlinedButton(
                style: OutlinedButton.styleFrom(visualDensity: VisualDensity.compact),
                onPressed: toggle,
                child: const Text('Following'),
              )
            : FilledButton(
                style: FilledButton.styleFrom(visualDensity: VisualDensity.compact),
                onPressed: toggle,
                child: const Text('Follow'),
              ),
      ]),
    );
  }
}

class _SearchTile extends StatelessWidget {
  const _SearchTile({required this.game});
  final Game game;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: () => openGame(context, game.id),
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Row(children: [
          SizedBox(width: 60, child: CoverArt(game: game, radius: 10)),
          const SizedBox(width: 14),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(game.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
              const SizedBox(height: 2),
              Text('${game.publisher} · ${game.releaseYear}', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Palette.muted, fontSize: 12.5)),
              const SizedBox(height: 8),
              Wrap(spacing: 6, runSpacing: 4, children: [
                for (final p in game.platforms.take(4)) Icon(p.icon, size: 16, color: p.color),
                if (game.platforms.length > 4)
                  Text('+${game.platforms.length - 4}', style: const TextStyle(fontSize: 11, color: Palette.muted)),
              ]),
            ]),
          ),
          const SizedBox(width: 8),
          if (!context.store.isLoggedIn)
            const SizedBox.shrink()
          else if (game.status != null)
            StatusPill(game.status!)
          else
            PopupMenuButton<GameStatus>(
              tooltip: 'Add to library',
              icon: const Icon(Icons.add_circle_outline_rounded, color: Palette.accent, size: 28),
              onSelected: (s) {
                context.actions.addToLibrary(game.id, s);
                ScaffoldMessenger.of(context)
                  ..hideCurrentSnackBar()
                  ..showSnackBar(SnackBar(content: Text('${game.title} added to ${s.label}')));
              },
              itemBuilder: (_) => [
                for (final s in const [GameStatus.playing, GameStatus.toPlay, GameStatus.wishlist, GameStatus.completed])
                  PopupMenuItem(
                    value: s,
                    child: Row(children: [Icon(s.icon, color: s.color, size: 20), const SizedBox(width: 10), Text(s.label)]),
                  ),
              ],
            ),
        ]),
      ),
    );
  }
}