import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:url_launcher/url_launcher.dart' show LaunchMode, launchUrl;

import 'package:checkpoint/app/auth_gate.dart';
import 'package:checkpoint/models/company.dart';
import 'package:checkpoint/models/filter_options.dart';
import 'package:checkpoint/state/auth_store.dart';
import 'package:checkpoint/state/company_store.dart';
import 'package:checkpoint/state/library_store.dart';
import 'package:checkpoint/state/load_status.dart';
import 'package:checkpoint/state/store_scope.dart';
import 'package:checkpoint/theme/palette.dart';
import 'package:checkpoint/utils/formatters.dart';
import 'package:checkpoint/utils/navigation.dart';
import 'package:checkpoint/widgets/company_logo.dart';
import 'package:checkpoint/widgets/count_stat.dart';
import 'package:checkpoint/widgets/empty_state.dart';
import 'package:checkpoint/widgets/expandable_text.dart';
import 'package:checkpoint/widgets/game_poster_card.dart';
import 'package:checkpoint/widgets/load_more_footer.dart';
import 'package:checkpoint/widgets/panel.dart';

/// A publisher's or developer's page (IGDB keeps both as one company): its
/// logo, where and since when it is, what it is part of, its description and
/// websites, and a grid of its games, all of them or only those it published
/// or developed, in an order to pick. Pull down to fetch everything again.
class CompanyScreen extends StatefulWidget {
  const CompanyScreen({super.key, required this.companyId, this.name});

  final int companyId;

  /// The name the company was opened by, shown until its page has loaded.
  final String? name;

  @override
  State<CompanyScreen> createState() => _CompanyScreenState();
}

class _CompanyScreenState extends State<CompanyScreen> {
  static const _gutter = 20.0;
  static const _spacing = 12.0;

  /// Posters are laid out at about this width, at least 3 to a row.
  static const _targetCellWidth = 140.0;

  CompanyRole _role = CompanyRole.any;
  DiscoverSort _sort = DiscoverSort.popular;

  /// The roles the company has games in (until it is known, every role).
  static List<CompanyRole> _rolesOf(Company? company) => [
    CompanyRole.any,
    if (company == null || company.publishedCount > 0) CompanyRole.publisher,
    if (company == null || company.developedCount > 0) CompanyRole.developer,
  ];

  /// The list on screen: the role picked, unless the company turned out to
  /// have no games in it.
  CompanyGamesKey get _key {
    final company = context
        .read<CompanyStore>()
        .viewOf(widget.companyId)
        .company;
    final role = _rolesOf(company).contains(_role) ? _role : CompanyRole.any;
    return (widget.companyId, role, _sort);
  }

  @override
  void initState() {
    super.initState();
    // Starting a load notifies listeners, which can't happen while the route is
    // still being built.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final store = context.read<CompanyStore>();
      unawaited(store.load(widget.companyId));
      unawaited(store.loadGames(_key));
    });
  }

  void _show({CompanyRole? role, DiscoverSort? sort}) {
    setState(() {
      _role = role ?? _role;
      _sort = sort ?? _sort;
    });
    unawaited(context.read<CompanyStore>().loadGames(_key));
  }

  Future<void> _refresh() {
    final store = context.read<CompanyStore>();
    return Future.wait([
      store.load(widget.companyId, force: true),
      store.refreshGames(_key),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<CompanyStore>();
    final view = store.viewOf(widget.companyId);
    final company = view.company;
    final name = company?.name ?? widget.name ?? 'Studio';

    if (!context.watch<AuthStore>().isLoggedIn) {
      return Scaffold(
        appBar: AppBar(title: Text(name)),
        // The Edge Function answers signed-in users only.
        body: EmptyState(
          icon: Icons.lock_outline_rounded,
          title: 'Log in to see studios',
          message: 'Studios and their games come from IGDB, which Checkpoint only reaches for signed-in users.',
          actionLabel: 'Log in',
          onAction: () => logIn(context),
        ),
      );
    }

    final bottomInset = MediaQuery.paddingOf(context).bottom;
    return Scaffold(
      appBar: AppBar(
        title: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis),
      ),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final columns = math.max(
              3,
              (constraints.maxWidth / _targetCellWidth).floor(),
            );
            final cellWidth =
                (constraints.maxWidth -
                    2 * _gutter -
                    (columns - 1) * _spacing) /
                columns;
            return CustomScrollView(
              // Pull-to-refresh also has to work for a page too short to scroll.
              physics: const AlwaysScrollableScrollPhysics(),
              slivers: [
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(_gutter, 8, _gutter, 0),
                  sliver: SliverToBoxAdapter(
                    child: _CompanyInfo(
                      name: name,
                      view: view,
                      onRetry: () =>
                          unawaited(store.load(widget.companyId, force: true)),
                      onRole: (role) => _show(role: role),
                    ),
                  ),
                ),
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(_gutter, 22, _gutter, 12),
                  sliver: SliverToBoxAdapter(child: _buildGamesHeader(company)),
                ),
                ..._buildGames(store, _key, cellWidth, columns),
                SliverToBoxAdapter(child: SizedBox(height: bottomInset + 24)),
              ],
            );
          },
        ),
      ),
    );
  }

  /// "Games", the order, and which of the company's games.
  Widget _buildGamesHeader(Company? company) {
    // A role the company has no games in is not offered.
    final roles = _rolesOf(company);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Expanded(
              child: Text(
                'Games',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
              ),
            ),
            PopupMenuButton<DiscoverSort>(
              tooltip: 'Sort games',
              initialValue: _sort,
              onSelected: (sort) => _show(sort: sort),
              itemBuilder: (_) => [
                for (final sort in DiscoverSort.values)
                  PopupMenuItem(value: sort, child: Text(sort.label)),
              ],
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.sort_rounded,
                      size: 18,
                      color: Palette.muted,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      _sort.label,
                      style: const TextStyle(
                        color: Palette.muted,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
        if (roles.length > 1) ...[
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: SegmentedButton<CompanyRole>(
              showSelectedIcon: false,
              segments: [
                for (final role in roles)
                  ButtonSegment(value: role, label: Text(role.label)),
              ],
              selected: {_key.$2},
              onSelectionChanged: (s) => _show(role: s.first),
              style: SegmentedButton.styleFrom(
                backgroundColor: Palette.surfaceHigh,
                foregroundColor: Colors.white70,
                selectedBackgroundColor: Palette.accent,
                selectedForegroundColor: Palette.onAccent,
                side: BorderSide(color: Colors.white.withValues(alpha: 0.18)),
              ),
            ),
          ),
        ],
      ],
    );
  }

  /// The games grid, or what stands in for it while there is nothing to show.
  List<Widget> _buildGames(
    CompanyStore store,
    CompanyGamesKey key,
    double cellWidth,
    int columns,
  ) {
    if (!store.isGamesLoaded(key) &&
        !store.isLoadingGames(key) &&
        !store.gamesFailed(key)) {
      // Not asked for yet: the role picked fell back to All once the company
      // turned out to have no games in it.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) unawaited(context.read<CompanyStore>().loadGames(key));
      });
    }
    final entries = store.games(key);
    if (entries.isEmpty) {
      final Widget state;
      if (store.gamesFailed(key)) {
        state = EmptyState(
          icon: Icons.cloud_off_rounded,
          title: 'Couldn’t load games',
          message: 'Check your connection and try again.',
          actionLabel: 'Try again',
          onAction: () => unawaited(store.refreshGames(key)),
        );
      } else if (store.isGamesLoaded(key) && !store.isLoadingGames(key)) {
        // "Most popular" and "Highest rated" only list rated games.
        final ratedOnly =
            _sort == DiscoverSort.popular || _sort == DiscoverSort.topRated;
        state = ratedOnly
            ? EmptyState(
                icon: Icons.star_outline_rounded,
                title: 'No rated games here',
                message: 'This list only has games with ratings on IGDB. The newest ones list them all.',
                actionLabel: 'Show newest',
                onAction: () => _show(sort: DiscoverSort.newest),
              )
            : const EmptyState(
                icon: Icons.search_off_rounded,
                title: 'No games to show',
                message: 'IGDB lists no games with a cover here.',
              );
      } else {
        state = const Padding(
          padding: EdgeInsets.all(32),
          child: Center(child: CircularProgressIndicator()),
        );
      }
      return [SliverToBoxAdapter(child: state)];
    }

    // The user's own copy (status, stars) wins over the catalog's for games in
    // their library.
    final library = context.watch<LibraryStore>();
    final showFooter =
        store.hasMoreGames(key) ||
        store.isLoadingMoreGames(key) ||
        store.loadMoreGamesFailed(key);
    return [
      SliverPadding(
        padding: const EdgeInsets.symmetric(horizontal: _gutter),
        sliver: SliverGrid.builder(
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columns,
            crossAxisSpacing: _spacing,
            mainAxisSpacing: 16,
            mainAxisExtent: posterCardHeight(
              context,
              cellWidth,
              subtitle: true,
            ),
          ),
          itemCount: entries.length,
          itemBuilder: (_, i) {
            final game = entries[i].game;
            return GamePosterCard(
              game: library.maybeGame(game.id) ?? game,
              width: cellWidth,
              subtitle: game.hasReleaseYear ? '${game.releaseYear}' : null,
              subtitleIcon: Icons.event_rounded,
              showUnrated: false,
            );
          },
        ),
      ),
      if (showFooter)
        SliverToBoxAdapter(
          child: LoadMoreFooter(
            loading: store.isLoadingMoreGames(key),
            failed: store.loadMoreGamesFailed(key),
            onLoadMore: () => unawaited(store.loadMoreGames(key)),
          ),
        ),
    ];
  }
}

/// Who the company is: logo, name, founding year and country, parent, how many
/// games it published and developed, its description and websites.
class _CompanyInfo extends StatelessWidget {
  const _CompanyInfo({
    required this.name,
    required this.view,
    required this.onRetry,
    required this.onRole,
  });

  final String name;
  final CompanyView view;
  final VoidCallback onRetry;

  /// Shows only the games of a role (a count was tapped).
  final ValueChanged<CompanyRole> onRole;

  @override
  Widget build(BuildContext context) {
    final company = view.company;
    final facts = [
      if (company?.foundedYear case final year?) 'Founded $year',
      ?company?.countryName,
    ];
    final parent = company?.parent;
    final description = company?.description;
    final websites = _distinctWebsites(company?.websites ?? const []);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            CompanyLogo(name: name, size: 76, logoUrl: company?.logoUrl),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                      height: 1.15,
                    ),
                  ),
                  if (facts.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      facts.join(' · '),
                      style: const TextStyle(
                        color: Palette.muted,
                        fontSize: 13,
                      ),
                    ),
                  ],
                  if (parent != null)
                    InkWell(
                      borderRadius: BorderRadius.circular(8),
                      onTap: () =>
                          openCompany(context, parent.id, name: parent.name),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Flexible(
                              child: Text(
                                'Part of ${parent.name}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: Palette.accent,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                            const Icon(
                              Icons.chevron_right_rounded,
                              size: 18,
                              color: Palette.accent,
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
        if (view.status == LoadStatus.loading)
          const Padding(
            padding: EdgeInsets.only(top: 16),
            child: LinearProgressIndicator(minHeight: 2),
          )
        else if (view.status == LoadStatus.failed)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Row(
              children: [
                const Expanded(
                  child: Text(
                    'Couldn’t load this studio’s details.',
                    style: TextStyle(color: Palette.muted, fontSize: 13),
                  ),
                ),
                TextButton(onPressed: onRetry, child: const Text('Try again')),
              ],
            ),
          ),
        if (company != null) ...[
          const SizedBox(height: 16),
          Row(
            children: [
              CountStat(
                value: fmtCount(company.publishedCount),
                label: 'Published',
                onTap: company.publishedCount > 0
                    ? () => onRole(CompanyRole.publisher)
                    : null,
              ),
              const SizedBox(width: 20),
              CountStat(
                value: fmtCount(company.developedCount),
                label: 'Developed',
                onTap: company.developedCount > 0
                    ? () => onRole(CompanyRole.developer)
                    : null,
              ),
            ],
          ),
        ],
        if (description != null) ...[
          const SizedBox(height: 16),
          Panel(
            title: 'About',
            child: ExpandableText(description, collapsedLines: 5),
          ),
        ],
        if (websites.isNotEmpty) ...[
          const SizedBox(height: 14),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final site in websites)
                ActionChip(
                  avatar: _WebsiteIcon(site.kind),
                  label: Text(site.label),
                  tooltip: site.url.toString(),
                  onPressed: () =>
                      launchUrl(site.url, mode: LaunchMode.externalApplication),
                ),
            ],
          ),
        ],
      ],
    );
  }

  /// [websites] without repeats of a kind (IGDB often lists a site twice),
  /// official site first. Any other site is kept once per address.
  static List<CompanyWebsite> _distinctWebsites(List<CompanyWebsite> websites) {
    final seen = <Object>{};
    final kept = [
      for (final site in websites)
        if (seen.add(
          site.kind == CompanyWebsiteKind.other
              ? site.url.toString()
              : site.kind,
        ))
          site,
    ];
    kept.sort((a, b) => a.kind.index.compareTo(b.kind.index));
    return kept;
  }
}

class _WebsiteIcon extends StatelessWidget {
  const _WebsiteIcon(this.kind);

  final CompanyWebsiteKind kind;

  @override
  Widget build(BuildContext context) {
    const size = 14.0;
    const color = Colors.white70;
    final brand = switch (kind) {
      CompanyWebsiteKind.wikipedia => FontAwesomeIcons.wikipediaW,
      CompanyWebsiteKind.steam => FontAwesomeIcons.steam,
      CompanyWebsiteKind.x => FontAwesomeIcons.xTwitter,
      CompanyWebsiteKind.youtube => FontAwesomeIcons.youtube,
      CompanyWebsiteKind.facebook => FontAwesomeIcons.facebook,
      CompanyWebsiteKind.instagram => FontAwesomeIcons.instagram,
      CompanyWebsiteKind.twitch => FontAwesomeIcons.twitch,
      CompanyWebsiteKind.discord => FontAwesomeIcons.discord,
      CompanyWebsiteKind.reddit => FontAwesomeIcons.reddit,
      CompanyWebsiteKind.linkedin => FontAwesomeIcons.linkedin,
      CompanyWebsiteKind.bluesky => FontAwesomeIcons.bluesky,
      CompanyWebsiteKind.itch => FontAwesomeIcons.itchIo,
      CompanyWebsiteKind.official || CompanyWebsiteKind.other => null,
    };
    if (brand == null) {
      return const Icon(Icons.language_rounded, size: size + 2, color: color);
    }
    return FaIcon(brand, size: size, color: color);
  }
}
