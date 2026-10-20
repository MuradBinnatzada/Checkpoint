import 'package:flutter/material.dart';

import 'package:checkpoint/models/year_review.dart';
import 'package:checkpoint/state/library_store.dart';
import 'package:checkpoint/state/store_scope.dart';
import 'package:checkpoint/theme/palette.dart';
import 'package:checkpoint/utils/formatters.dart';
import 'package:checkpoint/utils/navigation.dart';
import 'package:checkpoint/widgets/app_choice_chip.dart';
import 'package:checkpoint/widgets/cover_art.dart';
import 'package:checkpoint/widgets/empty_state.dart';
import 'package:checkpoint/widgets/hours_by_platform_panel.dart';
import 'package:checkpoint/widgets/panel.dart';
import 'package:checkpoint/widgets/stat_tile.dart';

const _monthLetters = ['J', 'F', 'M', 'A', 'M', 'J', 'J', 'A', 'S', 'O', 'N', 'D'];
const _monthNames = [
  'January', 'February', 'March', 'April', 'May', 'June',
  'July', 'August', 'September', 'October', 'November', 'December',
];

/// The member's year of play, worked out on the device from their sessions and
/// library ([YearReview]): totals, hours by month, the most played games,
/// platforms and genres, and what they completed. One year at a time.
class YearReviewScreen extends StatefulWidget {
  const YearReviewScreen({super.key, this.year});

  /// The year to open on; the current one by default.
  final int? year;

  @override
  State<YearReviewScreen> createState() => _YearReviewScreenState();
}

class _YearReviewScreenState extends State<YearReviewScreen> {
  late int _year = widget.year ?? DateTime.now().year;

  @override
  Widget build(BuildContext context) {
    final library = context.watch<LibraryStore>();
    final years = YearReview.yearsOf(
      sessions: library.sessions,
      games: library.libraryGames,
      currentYear: DateTime.now().year,
    );
    if (!years.contains(_year)) years.add(_year);
    final review = YearReview.of(
      year: _year,
      sessions: library.sessions,
      games: library.libraryGames,
    );

    return Scaffold(
      appBar: AppBar(title: const Text('Year in Review')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 32),
            children: [
              // The one filter, above everything it changes.
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(children: [
                  for (final y in years)
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: AppChoiceChip(
                        label: '$y',
                        selected: y == _year,
                        onSelected: () => setState(() => _year = y),
                      ),
                    ),
                ]),
              ),
              const SizedBox(height: 18),
              if (review.isEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 40),
                  child: EmptyState(
                    icon: Icons.insights_rounded,
                    title: 'Nothing logged in $_year',
                    message: 'Log your sessions (or start the timer on a game) and your year adds up here.',
                  ),
                )
              else
                ..._sections(context, review),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _sections(BuildContext context, YearReview r) => [
    _Headline(review: r),
    const SizedBox(height: 14),
    // Rows rather than a fixed-ratio grid: the tiles take the height their
    // content needs, at any screen width and text size.
    Row(children: [
      Expanded(child: StatTile(icon: Icons.calendar_month_rounded, value: '${r.daysPlayed}', label: r.daysPlayed == 1 ? 'Day played' : 'Days played')),
      const SizedBox(width: 10),
      Expanded(child: StatTile(icon: Icons.local_fire_department_rounded, value: '${r.longestStreak}', label: 'Longest streak (days)')),
    ]),
    const SizedBox(height: 10),
    Row(children: [
      Expanded(child: StatTile(icon: Icons.verified_rounded, value: '${r.completed.length}', label: 'Games completed')),
      const SizedBox(width: 10),
      Expanded(child: StatTile(icon: Icons.library_add_rounded, value: '${r.addedCount}', label: 'Games added')),
    ]),
    const SizedBox(height: 14),
    if (r.sessionCount > 0) ...[
      _MonthsPanel(review: r),
      const SizedBox(height: 14),
    ],
    if (r.topGames.isNotEmpty) ...[
      Panel(
        title: 'Most played',
        child: _HoursList(
          rows: [
            for (final g in r.topGames)
              _HoursRow(
                label: g.game.title,
                hours: g.hours,
                leading: SizedBox(width: 30, child: CoverArt(game: g.game, radius: 6, showTitle: false)),
                onTap: () => openGame(context, g.game.id),
              ),
          ],
        ),
      ),
      const SizedBox(height: 14),
    ],
    if (r.hoursByPlatform.isNotEmpty) ...[
      HoursByPlatformPanel(hours: r.hoursByPlatform),
      const SizedBox(height: 14),
    ],
    if (r.topGenres.isNotEmpty) ...[
      Panel(
        title: 'Top genres',
        child: _HoursList(
          rows: [for (final g in r.topGenres) _HoursRow(label: g.genre, hours: g.hours)],
        ),
      ),
      const SizedBox(height: 14),
    ],
    if (r.completed.isNotEmpty) _CompletedPanel(review: r),
    Padding(
      padding: EdgeInsets.fromLTRB(4, 14, 4, 0),
      child: Text(
        'Hours come from the sessions you logged, the timer and your Steam playtime. '
        'Hours a Steam import added without a session count in no year.',
        style: TextStyle(color: context.palette.muted, fontSize: 12, height: 1.4),
      ),
    ),
  ];
}

class _Headline extends StatelessWidget {
  const _Headline({required this.review});
  final YearReview review;

  @override
  Widget build(BuildContext context) {
    final r = review;
    final busiest = r.busiestDay;
    return Panel(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('${fmtHours(r.hours)} h', style: const TextStyle(fontSize: 40, height: 1.05, fontWeight: FontWeight.w800)),
        const SizedBox(height: 4),
        Text(
          'played in ${r.year}, over ${r.sessionCount} session${r.sessionCount == 1 ? '' : 's'} '
          'of ${r.gamesPlayed} game${r.gamesPlayed == 1 ? '' : 's'}',
          style: TextStyle(color: context.palette.muted),
        ),
        if (busiest != null) ...[
          const SizedBox(height: 10),
          Text(
            'Biggest day: ${fmtMonthDay(busiest)}, ${fmtHours(r.busiestDayHours)} h',
            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
          ),
        ],
      ]),
    );
  }
}

/// Hours by month, a bar each. A tap (or a hover) on a bar says its month and
/// hours; the busiest month is labelled. "Table" lists the numbers instead.
class _MonthsPanel extends StatefulWidget {
  const _MonthsPanel({required this.review});
  final YearReview review;

  @override
  State<_MonthsPanel> createState() => _MonthsPanelState();
}

class _MonthsPanelState extends State<_MonthsPanel> {
  bool _table = false;

  static const double _chartHeight = 120;

  @override
  Widget build(BuildContext context) {
    final months = widget.review.hoursByMonth;
    final tallest = months.reduce((a, b) => a > b ? a : b);
    final busiest = months.indexOf(tallest);
    return Panel(
      title: 'Hours by month',
      trailing: TextButton(
        onPressed: () => setState(() => _table = !_table),
        child: Text(_table ? 'Chart' : 'Table'),
      ),
      child: _table
          ? Column(children: [
              for (var m = 0; m < 12; m++)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 3),
                  child: Row(children: [
                    Expanded(child: Text(_monthNames[m])),
                    Text('${fmtHours(months[m])} h', style: const TextStyle(fontWeight: FontWeight.w600)),
                  ]),
                ),
            ])
          : Column(children: [
              SizedBox(
                height: _chartHeight,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    for (var m = 0; m < 12; m++)
                      Expanded(
                        child: Tooltip(
                          message: '${_monthNames[m]}: ${fmtHours(months[m])} h',
                          triggerMode: TooltipTriggerMode.tap,
                          child: Semantics(
                            label: '${_monthNames[m]}, ${fmtHours(months[m])} hours',
                            child: _MonthBar(
                              hours: months[m],
                              tallest: tallest,
                              label: m == busiest && tallest > 0 ? fmtHours(tallest) : null,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 6),
              Row(children: [
                for (final letter in _monthLetters)
                  Expanded(
                    child: Text(letter, textAlign: TextAlign.center, style: TextStyle(color: context.palette.muted, fontSize: 11)),
                  ),
              ]),
            ]),
    );
  }
}

class _MonthBar extends StatelessWidget {
  const _MonthBar({required this.hours, required this.tallest, this.label});
  final double hours;
  final double tallest;

  /// The value written over the bar (the busiest month only).
  final String? label;

  /// Room over the bars for [label]: the busiest bar reaches up to it.
  static const double _labelRoom = 18;

  @override
  Widget build(BuildContext context) {
    final share = tallest <= 0 ? 0.0 : (hours / tallest).clamp(0.0, 1.0);
    return Padding(
      // The gap between bars.
      padding: const EdgeInsets.symmetric(horizontal: 3),
      child: Column(children: [
        SizedBox(
          height: _labelRoom,
          width: double.infinity,
          child: label == null
              ? null
              : FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.bottomCenter,
                  child: Text(label!, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700)),
                ),
        ),
        Expanded(
          child: Align(
            alignment: Alignment.bottomCenter,
            child: hours <= 0
                ? const SizedBox.shrink()
                : FractionallySizedBox(
                    heightFactor: share,
                    widthFactor: 1,
                    child: ConstrainedBox(
                      // A month with a little play still shows.
                      constraints: const BoxConstraints(minHeight: 3),
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: context.palette.accent,
                          // Rounded at the data end, square on the baseline.
                          borderRadius: BorderRadius.vertical(top: Radius.circular(4)),
                        ),
                      ),
                    ),
                  ),
          ),
        ),
        // The baseline.
        Container(height: 1, color: context.palette.text.withValues(alpha: 0.12)),
      ]),
    );
  }
}

class _HoursRow {
  const _HoursRow({required this.label, required this.hours, this.leading, this.onTap});
  final String label;
  final double hours;
  final Widget? leading;
  final VoidCallback? onTap;
}

/// Rows of a label, a bar as long as its share of the first row's hours, and the
/// hours, most first.
class _HoursList extends StatelessWidget {
  const _HoursList({required this.rows});
  final List<_HoursRow> rows;

  @override
  Widget build(BuildContext context) {
    final most = rows.isEmpty ? 1.0 : rows.first.hours;
    return Column(children: [
      for (final row in rows)
        InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: row.onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(children: [
              if (row.leading != null) ...[row.leading!, const SizedBox(width: 10)],
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(row.label, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 5),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: most <= 0 ? 0 : row.hours / most,
                      minHeight: 6,
                      color: context.palette.accent,
                      backgroundColor: context.palette.track,
                    ),
                  ),
                ]),
              ),
              const SizedBox(width: 12),
              Text('${fmtHours(row.hours)} h', style: const TextStyle(fontWeight: FontWeight.w700)),
            ]),
          ),
        ),
    ]);
  }
}

class _CompletedPanel extends StatelessWidget {
  const _CompletedPanel({required this.review});
  final YearReview review;

  @override
  Widget build(BuildContext context) {
    return Panel(
      title: 'Completed in ${review.year}',
      child: SizedBox(
        height: 132,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          itemCount: review.completed.length,
          separatorBuilder: (_, _) => const SizedBox(width: 10),
          itemBuilder: (context, i) {
            final game = review.completed[i];
            return SizedBox(
              width: 84,
              child: InkWell(
                borderRadius: BorderRadius.circular(10),
                onTap: () => openGame(context, game.id),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  // What the title leaves: a taller title (larger text) can't push it out.
                  Expanded(child: CoverArt(game: game, radius: 10, showTitle: false)),
                  const SizedBox(height: 4),
                  Text(game.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12)),
                ]),
              ),
            );
          },
        ),
      ),
    );
  }
}
