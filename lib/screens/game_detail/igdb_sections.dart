import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart' show LaunchMode, launchUrl;

import 'package:checkpoint/models/filter_options.dart';
import 'package:checkpoint/models/game.dart';
import 'package:checkpoint/models/game_attributes.dart';
import 'package:checkpoint/models/game_details.dart';
import 'package:checkpoint/state/game_details_store.dart';
import 'package:checkpoint/state/store_scope.dart';
import 'package:checkpoint/theme/palette.dart';
import 'package:checkpoint/utils/formatters.dart';
import 'package:checkpoint/utils/navigation.dart';
import 'package:checkpoint/widgets/expandable_text.dart';
import 'package:checkpoint/widgets/game_poster_card.dart';
import 'package:checkpoint/widgets/panel.dart';

/// Everything there is to read about a game, in one panel: its description,
/// IGDB's story and the game info (genres, main developers, publishers, themes,
/// game modes, player perspectives, engine). The description, genres and
/// developer come with the library, so they show at once; the rest joins them
/// when IGDB answers (see [GameInfoSections], which asks). A genre, theme or game
/// mode the Discover tab can filter by is a button: it opens Discover on it. So
/// is a developer or publisher IGDB gave an id for: it opens its page.
class AboutPanel extends StatelessWidget {
  const AboutPanel({super.key, required this.game});

  final Game game;

  @override
  Widget build(BuildContext context) {
    final details = context
        .watch<GameDetailsStore>()
        .viewOf(game.id)
        .details;
    final hasInfo = details?.hasInfo ?? false;
    final companyIds = details?.companyIds ?? const <String, int>{};
    // (label, values, as chips, what a chip filters Discover by, chips are companies)
    final rows = <(String, List<String>, bool, GameAttribute?, bool)>[
      ('Genres', game.genres, true, GameAttribute.genre, false),
      if (hasInfo) ...[
        ('Main developers', details!.developers, true, null, true),
        ('Publishers', details.publishers, true, null, true),
        ('Themes', details.themes, true, GameAttribute.theme, false),
        ('Game modes', details.gameModes, true, GameAttribute.gameMode, false),
        ('Player perspectives', details.perspectives, true, null, false),
        ('Game engine', details.engines, true, null, false),
      ] else
        ('Developer', [game.developer], false, null, false),
    ].where((row) => row.$2.any((v) => v.trim().isNotEmpty)).toList();
    final synopsis = game.synopsis.trim();
    final storyline = details?.storyline?.trim() ?? '';

    final text = <Widget>[
      if (synopsis.isNotEmpty) ExpandableText(synopsis, collapsedLines: 6),
      if (storyline.isNotEmpty) ...[
        if (synopsis.isNotEmpty) const SizedBox(height: 14),
        const _Label('Story'),
        const SizedBox(height: 6),
        ExpandableText(storyline, collapsedLines: 4),
      ],
    ];

    return Panel(
      title: 'About',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ...text,
          if (text.isNotEmpty && rows.isNotEmpty)
            Divider(height: 28, color: Colors.white.withValues(alpha: 0.06)),
          for (var i = 0; i < rows.length; i++) ...[
            if (i > 0) const SizedBox(height: 14),
            _Label(rows[i].$1),
            const SizedBox(height: 6),
            if (rows[i].$3)
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final v in rows[i].$2)
                    if (rows[i].$5)
                      _CompanyChip(name: v, companyId: companyIds[v])
                    else
                      _TagChip(value: v, attribute: rows[i].$4),
                ],
              )
            else
              Text(rows[i].$2.join(', '), style: const TextStyle(height: 1.4)),
          ],
        ],
      ),
    );
  }
}

/// One genre, theme or game mode of a game. When the Discover tab can filter by
/// it (it is in [CatalogTags]), tapping it opens Discover on the games that have
/// it; anything else is only a label.
class _TagChip extends StatelessWidget {
  const _TagChip({required this.value, this.attribute});

  final String value;
  final GameAttribute? attribute;

  @override
  Widget build(BuildContext context) {
    final a = attribute;
    final tag = a == null ? null : CatalogTags.find(a, value);
    if (a == null || tag == null) return Chip(label: Text(value));
    return ActionChip(
      label: Text(value),
      tooltip: 'Browse ${tag.label} games',
      onPressed: () => openDiscover(context, FilterOptions.only(a, tag.name)),
    );
  }
}

/// A developer or publisher of a game. With an IGDB id, tapping it opens the
/// company's page; without, it is only a label.
class _CompanyChip extends StatelessWidget {
  const _CompanyChip({required this.name, this.companyId});

  final String name;
  final int? companyId;

  @override
  Widget build(BuildContext context) {
    final id = companyId;
    if (id == null) return Chip(label: Text(name));
    return ActionChip(
      avatar: const Icon(Icons.business_rounded, size: 16),
      label: Text(name),
      tooltip: 'See $name',
      onPressed: () => openCompany(context, id, name: name),
    );
  }
}

/// The time to beat and similar games, under About on a game's screen. Asks
/// IGDB for the game's details when the screen opens (see [GameDetailsStore]);
/// until they are here, or when they can't be loaded, nothing is drawn, as
/// everything else on the screen works without them.
class GameInfoSections extends StatefulWidget {
  const GameInfoSections({super.key, required this.game});

  final Game game;

  @override
  State<GameInfoSections> createState() => _GameInfoSectionsState();
}

class _GameInfoSectionsState extends State<GameInfoSections> {
  @override
  void initState() {
    super.initState();
    _loadAfterFrame();
  }

  @override
  void didUpdateWidget(GameInfoSections oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.game.id != widget.game.id) _loadAfterFrame();
  }

  /// After the frame: loading notifies, which isn't allowed during build.
  void _loadAfterFrame() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) context.read<GameDetailsStore>().load(widget.game);
    });
  }

  @override
  Widget build(BuildContext context) {
    final details = context
        .watch<GameDetailsStore>()
        .viewOf(widget.game.id)
        .details;
    if (details == null) return const SizedBox.shrink();

    final sections = <Widget>[
      _TimeToBeatPanel(title: widget.game.title, timeToBeat: details.timeToBeat),
      if (details.similarGames.isNotEmpty)
        _SimilarGames(games: details.similarGames),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final section in sections) ...[
          const SizedBox(height: 14),
          section,
        ],
      ],
    );
  }
}

/// A small grey heading inside a panel.
class _Label extends StatelessWidget {
  const _Label(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(
        color: Palette.muted,
        fontSize: 12.5,
        fontWeight: FontWeight.w600,
      ),
    );
  }
}

/// "42 h", "12.5 h", or "45 min" for under an hour.
String fmtDuration(Duration d) =>
    d.inMinutes < 60 ? '${d.inMinutes} min' : '${fmtHours(d.inMinutes / 60)} h';

/// Fewer reports than this and IGDB's times are flagged as rough.
const _fewTimeToBeatReports = 10;

/// Where HowLongToBeat lists [title]: its search page, opened in the browser.
/// Only a link: HowLongToBeat does not allow its data to be fetched by apps.
Uri howLongToBeatSearch(String title) =>
    Uri.parse('https://howlongtobeat.com/?q=${Uri.encodeComponent(title)}');

class _TimeToBeatPanel extends StatelessWidget {
  const _TimeToBeatPanel({required this.title, required this.timeToBeat});

  final String title;

  /// IGDB's times; null when IGDB has none for the game.
  final TimeToBeat? timeToBeat;

  @override
  Widget build(BuildContext context) {
    Widget figure(String label, Duration? value) => Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              value == null ? '–' : fmtDuration(value),
              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
            ),
          ),
          Text(
            label,
            style: const TextStyle(fontSize: 12, color: Palette.muted),
          ),
        ],
      ),
    );

    const caption = TextStyle(color: Palette.muted, fontSize: 12, height: 1.35);
    final times = timeToBeat;
    final count = times?.count ?? 0;
    return Panel(
      title: 'Time to beat',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (times == null)
            const Text('IGDB has no times for this game yet.', style: caption)
          else ...[
            Row(
              children: [
                figure('Hastily', times.hastily),
                figure('Normally', times.normally),
                figure('Completely', times.completely),
              ],
            ),
            if (count > 0) ...[
              const SizedBox(height: 10),
              Text(
                'From ${fmtThousands(count)} '
                '${count == 1 ? 'player' : 'players'} on IGDB'
                '${count < _fewTimeToBeatReports ? ', so it may be off' : ''}',
                style: caption,
              ),
            ],
          ],
          const SizedBox(height: 4),
          TextButton.icon(
            onPressed: () => launchUrl(
              howLongToBeatSearch(title),
              mode: LaunchMode.externalApplication,
            ),
            style: TextButton.styleFrom(
              padding: EdgeInsets.zero,
              minimumSize: const Size(0, 36),
              alignment: Alignment.centerLeft,
            ),
            icon: const Icon(Icons.open_in_new_rounded, size: 16),
            label: const Text('Compare on HowLongToBeat'),
          ),
        ],
      ),
    );
  }
}

class _SimilarGames extends StatelessWidget {
  const _SimilarGames({required this.games});

  final List<Game> games;

  @override
  Widget build(BuildContext context) {
    const width = 112.0;
    // Cards run to the screen edges, past the 20 px the rest of the page is inset by.
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(2, 10, 0, 12),
          child: Text(
            'Similar games',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
          ),
        ),
        SizedBox(
          height: posterCardHeight(context, width, subtitle: false),
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            clipBehavior: Clip.none,
            itemCount: games.length,
            separatorBuilder: (context, index) => const SizedBox(width: 12),
            itemBuilder: (_, i) => GamePosterCard(
              game: games[i],
              width: width,
              showUnrated: false,
            ),
          ),
        ),
      ],
    );
  }
}
