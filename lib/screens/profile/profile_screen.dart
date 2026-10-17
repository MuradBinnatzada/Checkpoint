import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:url_launcher/url_launcher.dart' show LaunchMode, launchUrl;

import 'package:checkpoint/models/connected_service.dart';
import 'package:checkpoint/models/game.dart';
import 'package:checkpoint/screens/profile/achievements_section.dart';
import 'package:checkpoint/screens/profile/edit_profile_screen.dart';
import 'package:checkpoint/state/auth_store.dart';
import 'package:checkpoint/state/library_store.dart';
import 'package:checkpoint/state/library_view_store.dart';
import 'package:checkpoint/state/profile_store.dart';
import 'package:checkpoint/state/social_graph_store.dart';
import 'package:checkpoint/state/store_scope.dart';
import 'package:checkpoint/theme/palette.dart';
import 'package:checkpoint/utils/formatters.dart';
import 'package:checkpoint/utils/navigation.dart';
import 'package:checkpoint/widgets/count_stat.dart';
import 'package:checkpoint/widgets/favorite_games_row.dart';
import 'package:checkpoint/widgets/game_poster_card.dart';
import 'package:checkpoint/widgets/panel.dart';
import 'package:checkpoint/widgets/profile_avatar.dart';
import 'package:checkpoint/widgets/stat_tile.dart';

class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  static const _months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

  /// Services that ask for a username when connected (Steam has its own ID dialog).
  static const _usernameServices = {ConnectedService.psn, ConnectedService.xbox, ConnectedService.discord};

  @override
  Widget build(BuildContext context) {
    final profileStore = context.watch<ProfileStore>();
    final library = context.watch<LibraryStore>();
    final p = profileStore.profile;
    final userId = context.watch<AuthStore>().user?.id;
    final byPlatform = library.hoursByPlatform.entries.toList();
    final maxH = byPlatform.isEmpty ? 1.0 : byPlatform.first.value;
    final top = library.topRated;
    final favorites = library.libraryGames.where((g) => g.isFavorite).toList();
    final hasBio = p.bio != null && p.bio!.trim().isNotEmpty;
    final connectedServices = profileStore.connectedServices;
    final steamId = profileStore.steamId;
    final steamUrl = steamId != null && steamId.isNotEmpty ? Uri.https('steamcommunity.com', '/profiles/$steamId') : null;

    Future<bool> openLink(Uri url) => launchUrl(url, mode: LaunchMode.externalApplication);

    // Where tapping a connected service's badge leads, once its ID is saved.
    // Steam, Xbox and PSN open the profile page; Discord has no public profile
    // URL, so it copies the username to the clipboard instead.
    ({String tooltip, VoidCallback onTap})? badgeLink(ConnectedService s) {
      switch (s) {
        case ConnectedService.steam:
          if (steamUrl == null) return null;
          return (tooltip: 'Open Steam profile', onTap: () => openLink(steamUrl));
        case ConnectedService.xbox:
          final id = profileStore.xboxId;
          if (id == null || id.isEmpty) return null;
          return (tooltip: 'Open Xbox profile', onTap: () => openLink(Uri.https('xboxgamertag.com', '/search/$id')));
        case ConnectedService.psn:
          final id = profileStore.psnId;
          if (id == null || id.isEmpty) return null;
          return (tooltip: 'Open PSN profile', onTap: () => openLink(Uri.https('psnprofiles.com', '/$id')));
        case ConnectedService.discord:
          final id = profileStore.discordId;
          if (id == null || id.isEmpty) return null;
          return (
            tooltip: 'Copy Discord username',
            onTap: () async {
              final messenger = ScaffoldMessenger.of(context);
              await Clipboard.setData(ClipboardData(text: id));
              messenger
                ..hideCurrentSnackBar()
                ..showSnackBar(const SnackBar(content: Text('Discord username copied to clipboard')));
            },
          );
        case ConnectedService.nintendo:
          return null;
      }
    }

    final badgeLinks = {for (final s in connectedServices) s: badgeLink(s)};

    return SafeArea(
      bottom: false,
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
            children: [
              Row(children: [
                ProfileAvatar(name: p.name, size: 76, imageUrl: p.avatarUrl),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(p.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800)),
                    Text(p.handle, style: const TextStyle(color: Palette.accent, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 2),
                    Text('Member since ${_months[p.joined.month - 1]} ${p.joined.year}', style: const TextStyle(color: Palette.muted, fontSize: 12.5)),
                  ]),
                ),
                IconButton(
                  tooltip: 'Log out (mock)',
                  onPressed: context.read<AuthStore>().logOut,
                  icon: const Icon(Icons.logout_rounded, color: Palette.muted),
                ),
              ]),
              const SizedBox(height: 14),
              if (hasBio || connectedServices.isNotEmpty) ...[
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (hasBio) Text(p.bio!, style: const TextStyle(height: 1.4, color: Colors.white70)),
                    if (hasBio && connectedServices.isNotEmpty) const SizedBox(height: 12),
                    if (connectedServices.isNotEmpty)
                      Wrap(spacing: 6, runSpacing: 8, children: [
                        // ConnectedService.values keeps the order stable, matching the
                        // Connected accounts panel below.
                        for (final s in ConnectedService.values)
                          if (connectedServices.contains(s))
                            _ServiceBadge(
                              service: s,
                              // Tappable only once an ID has been saved (see badgeLink above).
                              tooltip: badgeLinks[s]?.tooltip,
                              onTap: badgeLinks[s]?.onTap,
                            ),
                      ]),
                  ],
                ),
                const SizedBox(height: 16),
              ],
              // Tapping a count opens the list behind it.
              Row(children: [
                CountStat(
                  value: fmtCount(profileStore.followersCount),
                  label: 'Followers',
                  onTap: userId == null
                      ? null
                      : () => openFollowList(context, userId: userId, kind: FollowListKind.followers, ownerName: p.name),
                ),
                const SizedBox(width: 14),
                CountStat(
                  value: fmtCount(profileStore.followingCount),
                  label: 'Following',
                  onTap: userId == null
                      ? null
                      : () => openFollowList(context, userId: userId, kind: FollowListKind.following, ownerName: p.name),
                ),
              ]),
              const SizedBox(height: 14),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(builder: (_) => const EditProfileScreen()),
                  ),
                  icon: const Icon(Icons.edit_rounded, size: 18),
                  label: const Text('Edit Profile'),
                ),
              ),
              const SizedBox(height: 20),
              // Plain, non-interactive total playtime above the stat cards.
              Text(
                'Total Playtime: ${fmtHours(library.totalHours)} hours',
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 12),
              Row(children: [
                Expanded(
                  child: StatTile(
                    icon: Icons.play_arrow_rounded,
                    value: '${library.count(GameStatus.playing)}',
                    label: 'Playing',
                    onTap: () => context.read<LibraryViewStore>().openTab(GameStatus.playing),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: StatTile(
                    icon: Icons.verified_rounded,
                    value: '${library.count(GameStatus.completed)}',
                    label: 'Completed',
                    onTap: () => context.read<LibraryViewStore>().openTab(GameStatus.completed),
                  ),
                ),
              ]),
              const SizedBox(height: 10),
              Row(children: [
                Expanded(
                  child: StatTile(
                    icon: Icons.inventory_2_rounded,
                    value: '${library.count(GameStatus.toPlay)}',
                    label: 'To Play',
                    onTap: () => context.read<LibraryViewStore>().openTab(GameStatus.toPlay),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: StatTile(
                    icon: Icons.block_rounded,
                    value: '${library.count(GameStatus.dropped)}',
                    label: 'Dropped',
                    onTap: () => context.read<LibraryViewStore>().openTab(GameStatus.dropped),
                  ),
                ),
              ]),
              const SizedBox(height: 32),
              const Text('Favorite Games', style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800)),
              const SizedBox(height: 12),
              if (favorites.isEmpty)
                const Panel(
                  child: Text(
                    'No favorites selected yet. Tap the heart icon on a game to showcase it here.',
                    style: TextStyle(color: Palette.muted, fontSize: 13, height: 1.35),
                  ),
                )
              else
                FavoriteGamesRow(games: favorites),
              const SizedBox(height: 32),
              Panel(
                title: 'Connected accounts',
                child: Column(children: [
                  Row(children: [
                    for (final s in ConnectedService.values) ...[
                      if (s != ConnectedService.values.first) const SizedBox(width: 10),
                      Expanded(
                        child: _ServiceTile(
                          service: s,
                          connected: profileStore.isConnected(s),
                          onTap: () {
                            // 1. If already connected, tapping it disconnects immediately
                            if (profileStore.isConnected(s)) {
                              context.read<ProfileStore>().toggleService(s);
                              return;
                            }

                            // 2. Steam requires an ID dialog before enabling sync
                            if (s == ConnectedService.steam) {
                              // Use TextEditingController to capture (and optionally pre-fill) the ID
                              final controller = TextEditingController();
                              showDialog(
                                context: context,
                                builder: (c) => AlertDialog(
                                  title: const Text('Connect Steam Account'),
                                  content: TextField(
                                    controller: controller,
                                    autofocus: true,
                                    keyboardType: TextInputType.number,
                                    decoration: const InputDecoration(
                                      hintText: 'Enter 17-digit Steam ID64',
                                      helperText: 'e.g., 76561198000000000',
                                    ),
                                  ),
                                  actions: [
                                    TextButton(
                                      onPressed: () => Navigator.pop(c),
                                      child: const Text('Cancel'),
                                    ),
                                    FilledButton(
                                      onPressed: () async {
                                        final val = controller.text.trim();
                                        final navigator = Navigator.of(c);
                                        final messenger = ScaffoldMessenger.of(context);
                                        if (val.isEmpty) {
                                          navigator.pop();
                                          return;
                                        }
                                        // The ID is saved on the user's profile in Supabase; only
                                        // mark Steam as connected once that save has succeeded.
                                        final error = await profileStore.setSteamId(val);
                                        if (error != null) {
                                          messenger
                                            ..hideCurrentSnackBar()
                                            ..showSnackBar(SnackBar(content: Text(error)));
                                        }
                                        // On success Steam shows as connected by itself: it is
                                        // connected exactly when the profile has a Steam ID.
                                        navigator.pop();
                                      },
                                      child: const Text('Connect'),
                                    ),
                                  ],
                                ),
                              );
                            } else if (_usernameServices.contains(s)) {
                              // 3. PSN/Xbox/Discord: ask for a username, then save it and connect
                              showDialog<String>(
                                context: context,
                                builder: (_) => _UsernameDialog(service: s),
                              ).then((id) {
                                if (id != null) profileStore.setServiceId(s, id);
                              });
                            } else if (s.supportsSync) {
                              // 4. Direct toggle for any other sync-capable service
                              context.read<ProfileStore>().toggleService(s);
                            } else {
                              // 5. Profile-link dialog for Nintendo
                              final controller = TextEditingController();
                              showDialog(
                                context: context,
                                builder: (c) => AlertDialog(
                                  title: Text('Connect ${s.label}'),
                                  content: TextField(
                                    controller: controller,
                                    autofocus: true,
                                    decoration: InputDecoration(
                                      hintText: 'Enter your ${s.label} Gamertag/ID',
                                    ),
                                  ),
                                  actions: [
                                    TextButton(
                                      onPressed: () => Navigator.pop(c),
                                      child: const Text('Cancel'),
                                    ),
                                    FilledButton(
                                      onPressed: () {
                                        if (controller.text.trim().isNotEmpty && !profileStore.isConnected(s)) {
                                          context.read<ProfileStore>().toggleService(s);
                                        }
                                        Navigator.pop(c);
                                      },
                                      child: const Text('Connect'),
                                    ),
                                  ],
                                ),
                              );
                            }
                          },
                        ),
                      ),
                    ],
                  ]),
                  const SizedBox(height: 14),
                  if (library.syncStatus == SyncStatus.delayed) ...[
                    _SyncDelayedNotice(message: library.syncFailure?.message ?? ''),
                    const SizedBox(height: 10),
                  ],
                  SizedBox(
                    width: double.infinity,
                    child: Builder(
                      builder: (context) {
                        // 3. Only enable Sync if at least one connected service supports syncing
                        final hasSyncableService = ConnectedService.values
                            .any((s) => s.supportsSync && profileStore.isConnected(s));

                        return FilledButton.tonalIcon(
                          onPressed: !hasSyncableService || library.isSyncing
                              ? null
                              : () async {
                                  final messenger = ScaffoldMessenger.of(context);
                                  // null = everything synced; otherwise why not, or what is still waiting.
                                  final message = await context.read<LibraryStore>().syncLibrary();
                                  messenger
                                    ..hideCurrentSnackBar()
                                    ..showSnackBar(SnackBar(content: Text(message ?? 'Library synced successfully')));
                                },
                          icon: library.isSyncing
                              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                              : const Icon(Icons.sync_rounded),
                          label: Text(
                            library.isSyncing
                                ? 'Syncing…'
                                : library.syncStatus == SyncStatus.delayed
                                    ? 'Retry Sync'
                                    : 'Sync Library',
                          ),
                        );
                      }
                    ),
                  ),
                ]),
              ),
              const SizedBox(height: 14),
              Panel(
                title: 'Hours by platform',
                child: byPlatform.isEmpty
                    ? const Text('Log a session to see your breakdown.', style: TextStyle(color: Palette.muted))
                    : Column(children: [
                        for (final e in byPlatform)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 6),
                            child: Row(children: [
                              Icon(e.key.icon, size: 18, color: e.key.color),
                              const SizedBox(width: 10),
                              SizedBox(width: 82, child: Text(e.key.label, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600))),
                              Expanded(
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(5),
                                  child: LinearProgressIndicator(value: e.value / maxH, minHeight: 9, color: e.key.color, backgroundColor: Colors.white10),
                                ),
                              ),
                              const SizedBox(width: 10),
                              SizedBox(width: 52, child: Text('${fmtHours(e.value)} h', textAlign: TextAlign.end, style: const TextStyle(fontSize: 12.5, color: Palette.muted))),
                            ]),
                          ),
                      ]),
              ),
              if (top.isNotEmpty) ...[
                const SizedBox(height: 6),
                const Padding(
                  padding: EdgeInsets.only(top: 18, bottom: 12),
                  child: Text('Top rated', style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800)),
                ),
                SizedBox(
                  height: posterCardHeight(context, 104, subtitle: false),
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: top.length,
                    separatorBuilder: (_, _) => const SizedBox(width: 12),
                    itemBuilder: (_, i) => GamePosterCard(game: top[i], width: 104),
                  ),
                ),
              ],
              if (userId != null) ...[
                const SizedBox(height: 24),
                // Fetched only when "View Achievements" is pressed.
                AchievementsSection(userId: userId),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _ServiceTile extends StatelessWidget {
  const _ServiceTile({required this.service, required this.connected, required this.onTap});
  final ConnectedService service;
  final bool connected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Palette.surfaceHigh,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: connected ? service.color.withValues(alpha: 0.7) : Colors.white.withValues(alpha: 0.08)),
      ),
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 4),
          child: Column(children: [
            FaIcon(service.icon, size: 28, color: connected ? service.color : Palette.muted),
            const SizedBox(height: 6),
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(service.label, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
            ),
            const SizedBox(height: 2),
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(connected ? 'Connected' : 'Connect', style: TextStyle(fontSize: 11, color: connected ? Palette.success : Palette.muted)),
            ),
          ]),
        ),
      ),
    );
  }
}

/// Asks for the username to show on (and link from) a service badge. Pops with
/// the trimmed text, or null if cancelled or left empty.
class _UsernameDialog extends StatefulWidget {
  const _UsernameDialog({required this.service});
  final ConnectedService service;

  @override
  State<_UsernameDialog> createState() => _UsernameDialogState();
}

class _UsernameDialogState extends State<_UsernameDialog> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final value = _controller.text.trim();
    Navigator.pop(context, value.isEmpty ? null : value);
  }

  @override
  Widget build(BuildContext context) {
    final label = widget.service.label;
    return AlertDialog(
      title: Text('Connect $label'),
      content: TextField(
        controller: _controller,
        autofocus: true,
        autocorrect: false,
        enableSuggestions: false,
        textInputAction: TextInputAction.done,
        onSubmitted: (_) => _submit(),
        decoration: InputDecoration(hintText: 'Enter your $label username'),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(onPressed: _submit, child: const Text('Connect')),
      ],
    );
  }
}

/// Small, subtle icon badge for a connected service. Tappable only when [onTap]
/// is provided (Steam, Xbox, PSN and Discord, once an ID has been saved).
class _ServiceBadge extends StatelessWidget {
  const _ServiceBadge({required this.service, this.onTap, this.tooltip});
  final ConnectedService service;
  final VoidCallback? onTap;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip ?? service.label,
      // Transparent Material so the InkWell ripple still has somewhere to paint,
      // without drawing a background or border behind the icon.
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.only(right: 6, top: 4, bottom: 4),
            child: FaIcon(service.icon, size: 20, color: service.color),
          ),
        ),
      ),
    );
  }
}

/// Shown under the Sync button while the last sync was cut short by Steam or the
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
                  const Text('Sync Delayed', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5)),
                  if (message.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(message, style: const TextStyle(color: Palette.muted, fontSize: 12.5)),
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
