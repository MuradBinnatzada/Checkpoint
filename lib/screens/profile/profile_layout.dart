import 'package:flutter/material.dart';

import 'package:checkpoint/models/activity_entry.dart';
import 'package:checkpoint/models/connected_service.dart';
import 'package:checkpoint/models/game.dart';
import 'package:checkpoint/models/library_stats.dart';
import 'package:checkpoint/screens/profile/achievements_section.dart';
import 'package:checkpoint/theme/palette.dart';
import 'package:checkpoint/utils/formatters.dart';
import 'package:checkpoint/widgets/connected_account_icons.dart';
import 'package:checkpoint/widgets/count_stat.dart';
import 'package:checkpoint/widgets/favorite_games_row.dart';
import 'package:checkpoint/widgets/hours_by_platform_panel.dart';
import 'package:checkpoint/widgets/panel.dart';
import 'package:checkpoint/widgets/profile_avatar.dart';
import 'package:checkpoint/widgets/profile_link_rows.dart';
import 'package:checkpoint/widgets/ratings_panel.dart';
import 'package:checkpoint/widgets/recent_activity_panel.dart';
import 'package:checkpoint/widgets/stat_tile.dart';

/// Photo, name, @handle and, once known, when they joined. [trailing] sits at the
/// top right, level with the name.
class ProfileHeader extends StatelessWidget {
  const ProfileHeader({
    super.key,
    required this.name,
    required this.handle,
    this.avatarUrl,
    this.joined,
    this.isSelf = false,
    this.trailing,
  });

  final String name;
  final String handle;
  final String? avatarUrl;
  final DateTime? joined;

  /// Another member's page that is yours: says "This is you" instead of the date.
  final bool isSelf;

  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        ProfileAvatar(name: name, size: 76, imageUrl: avatarUrl),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  ?trailing,
                ],
              ),
              Text(
                handle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Palette.accent,
                  fontWeight: FontWeight.w600,
                ),
              ),
              if (isSelf || joined != null) ...[
                const SizedBox(height: 2),
                Text(
                  isSelf
                      ? 'This is you'
                      : 'Member since ${fmtMonthYear(joined!)}',
                  style: const TextStyle(color: Palette.muted, fontSize: 12.5),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

/// One profile page for everyone, yours included: who they are, icons of the
/// accounts they connected, their bio, who follows them, then their favorites,
/// latest sessions, playtime, library numbers (each box opens a library), hours per
/// platform, ratings, their achievements (when [showAchievements]), and last of
/// all a short menu into their library and follow lists.
///
/// It only lays things out. Where the numbers come from, and what a tap does,
/// differ between your own profile (your live library, the Library tab) and
/// someone else's (what the server returned, their library screen), so both are
/// handed in.
class ProfileLayout extends StatelessWidget {
  const ProfileLayout({
    super.key,
    required this.userId,
    required this.header,
    required this.followers,
    required this.following,
    required this.onFollowers,
    required this.onFollowing,
    required this.favorites,
    required this.activity,
    required this.library,
    required this.onStatus,
    required this.links,
    required this.showAchievements,
    this.notice,
    this.bio,
    this.actions,
    this.services = const {},
    this.accountNames = const {},
    this.emptyFavorites = 'No favorites picked yet.',
    this.emptyHours = 'No hours logged yet.',
  });

  /// Whose achievements the page offers.
  final String userId;
  final Widget header;

  /// Small line under the header, e.g. that a refresh failed.
  final String? notice;
  final String? bio;

  final int followers;
  final int following;
  final VoidCallback onFollowers;
  final VoidCallback onFollowing;

  /// The button(s) under the counts: Follow, or Edit profile and Settings.
  final Widget? actions;

  final List<Game> favorites;
  final List<ActivityEntry> activity;
  final LibraryStats library;
  final void Function(GameStatus status) onStatus;

  /// The connected services and the names behind them, shown as icons above the
  /// bio; none leaves the row out.
  final Set<ConnectedService> services;
  final Map<ConnectedService, String> accountNames;
  final List<ProfileLink> links;

  /// Whether the page has the Achievements card. Only with Steam connected, and
  /// on someone else's page only when they share them (Settings > Privacy); the
  /// callers decide.
  final bool showAchievements;

  final String emptyFavorites;
  final String emptyHours;

  @override
  Widget build(BuildContext context) {
    final text = bio?.trim();
    final hasBio = text != null && text.isNotEmpty;

    Widget statTile(IconData icon, GameStatus status, String label) => Expanded(
      child: StatTile(
        icon: icon,
        value: '${library.count(status)}',
        label: label,
        onTap: () => onStatus(status),
      ),
    );

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
      children: [
        header,
        if (notice != null) ...[
          const SizedBox(height: 10),
          Text(
            notice!,
            style: const TextStyle(color: Palette.muted, fontSize: 12.5),
          ),
        ],
        const SizedBox(height: 14),
        if (services.isNotEmpty) ...[
          ConnectedAccountIcons(services: services, names: accountNames),
          const SizedBox(height: 14),
        ],
        if (hasBio) ...[
          Text(
            text,
            style: const TextStyle(height: 1.4, color: Colors.white70),
          ),
          const SizedBox(height: 16),
        ],
        // Tapping a count opens the list behind it.
        Row(
          children: [
            CountStat(
              value: fmtCount(followers),
              label: 'Followers',
              onTap: onFollowers,
            ),
            const SizedBox(width: 14),
            CountStat(
              value: fmtCount(following),
              label: 'Following',
              onTap: onFollowing,
            ),
          ],
        ),
        if (actions != null) ...[const SizedBox(height: 14), actions!],
        const SizedBox(height: 28),
        const _SectionTitle('Favorite Games'),
        if (favorites.isEmpty)
          Panel(
            child: Text(
              emptyFavorites,
              style: const TextStyle(
                color: Palette.muted,
                fontSize: 13,
                height: 1.35,
              ),
            ),
          )
        else
          FavoriteGamesRow(games: favorites),
        const SizedBox(height: 28),
        RecentActivityPanel(entries: activity),
        const SizedBox(height: 24),
        Text(
          'Total Playtime: ${fmtHours(library.totalHours)} hours',
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            statTile(Icons.play_arrow_rounded, GameStatus.playing, 'Playing'),
            const SizedBox(width: 10),
            statTile(Icons.verified_rounded, GameStatus.completed, 'Completed'),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            statTile(Icons.inventory_2_rounded, GameStatus.toPlay, 'To Play'),
            const SizedBox(width: 10),
            statTile(Icons.block_rounded, GameStatus.dropped, 'Dropped'),
          ],
        ),
        const SizedBox(height: 14),
        HoursByPlatformPanel(
          hours: library.hoursByPlatform,
          emptyText: emptyHours,
        ),
        const SizedBox(height: 14),
        RatingsPanel(stats: library),
        // The count shows at once; the games and their achievements are fetched
        // only when asked for.
        if (showAchievements) ...[
          const SizedBox(height: 14),
          AchievementsSection(userId: userId),
        ],
        const SizedBox(height: 24),
        ProfileLinkRows(links: links),
      ],
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.title);
  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Text(
        title,
        style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w800),
      ),
    );
  }
}
