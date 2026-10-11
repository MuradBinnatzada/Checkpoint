import 'package:flutter/material.dart';

import 'package:checkpoint/models/connected_service.dart';
import 'package:checkpoint/models/game.dart';
import 'package:checkpoint/state/library_state.dart';
import 'package:checkpoint/state/store_scope.dart';
import 'package:checkpoint/theme/palette.dart';
import 'package:checkpoint/utils/formatters.dart';
import 'package:checkpoint/widgets/game_poster_card.dart';
import 'package:checkpoint/widgets/panel.dart';
import 'package:checkpoint/widgets/profile_avatar.dart';
import 'package:checkpoint/widgets/stat_tile.dart';

class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  static const _months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

  @override
  Widget build(BuildContext context) {
    final store = context.store;
    final p = store.profile;
    final byPlatform = store.hoursByPlatform.entries.toList();
    final maxH = byPlatform.isEmpty ? 1.0 : byPlatform.first.value;
    final week = store.hoursThisWeek;
    final weekProgress = (week / p.weeklyGoalHours).clamp(0.0, 1.0).toDouble();
    final top = store.topRated;

    return SafeArea(
      bottom: false,
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
            children: [
              Row(children: [
                ProfileAvatar(name: p.name, size: 76),
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
                  onPressed: context.actions.logOut,
                  icon: const Icon(Icons.logout_rounded, color: Palette.muted),
                ),
              ]),
              const SizedBox(height: 14),
              Text(p.bio, style: const TextStyle(height: 1.4, color: Colors.white70)),
              const SizedBox(height: 16),
              Row(children: [
                _CountStat(value: fmtCount(store.followersCount), label: 'Followers'),
                const SizedBox(width: 28),
                _CountStat(value: fmtCount(store.followingCount), label: 'Following'),
              ]),
              const SizedBox(height: 14),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () {
                    // TODO: open an edit-profile sheet
                    ScaffoldMessenger.of(context)
                      ..hideCurrentSnackBar()
                      ..showSnackBar(const SnackBar(content: Text('Edit Profile coming soon')));
                  },
                  icon: const Icon(Icons.edit_rounded, size: 18),
                  label: const Text('Edit Profile'),
                ),
              ),
              const SizedBox(height: 20),
              // Plain, non-interactive total playtime above the stat cards.
              Text(
                'Total Playtime: ${fmtHours(store.totalHours)} hours',
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 12),
              Row(children: [
                Expanded(
                  child: StatTile(
                    icon: Icons.play_arrow_rounded,
                    value: '${store.count(GameStatus.playing)}',
                    label: 'Playing',
                    onTap: () => context.actions.openLibraryTab(GameStatus.playing),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: StatTile(
                    icon: Icons.verified_rounded,
                    value: '${store.count(GameStatus.completed)}',
                    label: 'Completed',
                    onTap: () => context.actions.openLibraryTab(GameStatus.completed),
                  ),
                ),
              ]),
              const SizedBox(height: 10),
              Row(children: [
                Expanded(
                  child: StatTile(
                    icon: Icons.star_rounded,
                    value: store.averageRating == 0 ? '—' : store.averageRating.toStringAsFixed(1),
                    label: 'Avg. rating',
                    onTap: () => context.actions.openLibraryTab(GameStatus.completed, sortBy: SortField.rating),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: StatTile(
                    icon: Icons.inventory_2_rounded,
                    value: '${store.count(GameStatus.toPlay)}',
                    label: 'To Play',
                    onTap: () => context.actions.openLibraryTab(GameStatus.toPlay),
                  ),
                ),
              ]),
              const SizedBox(height: 16),
              Panel(
                title: 'Connected accounts',
                child: Column(children: [
                  Row(children: [
                    for (final s in ConnectedService.values) ...[
                      if (s != ConnectedService.values.first) const SizedBox(width: 10),
                      Expanded(
                        child: _ServiceTile(
                          service: s,
                          connected: store.isConnected(s),
                          onTap: () {
                            // 1. Steam requires an ID dialog before enabling sync
                            if (s == ConnectedService.steam) {
                              String enteredSteamId = '';
                              showDialog(
                                context: context,
                                builder: (c) => AlertDialog(
                                  title: const Text('Connect Steam Account'),
                                  content: TextField(
                                    autofocus: true,
                                    keyboardType: TextInputType.number,
                                    decoration: const InputDecoration(
                                      hintText: 'Enter 17-digit Steam ID64',
                                      helperText: 'e.g., 76561198000000000',
                                    ),
                                    onChanged: (val) => enteredSteamId = val.trim(),
                                  ),
                                  actions: [
                                    TextButton(
                                      onPressed: () => Navigator.pop(c),
                                      child: const Text('Cancel'),
                                    ),
                                    FilledButton(
                                      onPressed: () {
                                        if (enteredSteamId.isNotEmpty) {
                                          store.setSteamId(enteredSteamId);
                                          if (!store.isConnected(s)) {
                                            context.actions.toggleService(s);
                                          }
                                        }
                                        Navigator.pop(c);
                                      },
                                      child: const Text('Save Steam ID'),
                                    ),
                                  ],
                                ),
                              );
                            } else if (s.supportsSync) {
                              // 2. Direct toggle for other sync-capable services (e.g. Discord)
                              context.actions.toggleService(s);
                            } else {
                              // 3. Profile-link dialog for PSN/Xbox
                              String enteredId = '';
                              showDialog(
                                context: context,
                                builder: (c) => AlertDialog(
                                  title: Text('Connect ${s.label}'),
                                  content: TextField(
                                    autofocus: true,
                                    decoration: InputDecoration(
                                      hintText: 'Enter your ${s.label} Gamertag/ID',
                                    ),
                                    onChanged: (val) => enteredId = val.trim(),
                                  ),
                                  actions: [
                                    TextButton(
                                      onPressed: () => Navigator.pop(c),
                                      child: const Text('Cancel'),
                                    ),
                                    FilledButton(
                                      onPressed: () {
                                        if (enteredId.isNotEmpty && !store.isConnected(s)) {
                                          context.actions.toggleService(s);
                                        }
                                        Navigator.pop(c);
                                      },
                                      child: const Text('Save Profile Link'),
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
                  SizedBox(
                    width: double.infinity,
                    child: Builder(
                      builder: (context) {
                        // 3. Only enable Sync if at least one connected service supports syncing
                        final hasSyncableService = ConnectedService.values
                            .any((s) => s.supportsSync && store.isConnected(s));

                        return FilledButton.tonalIcon(
                          onPressed: !hasSyncableService || store.isSyncing
                              ? null
                              : () async {
                                  final messenger = ScaffoldMessenger.of(context);
                                  await context.actions.syncLibrary();
                                  messenger
                                    ..hideCurrentSnackBar()
                                    ..showSnackBar(const SnackBar(content: Text('Library synced successfully')));
                                },
                          icon: store.isSyncing
                              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                              : const Icon(Icons.sync_rounded),
                          label: Text(store.isSyncing ? 'Syncing…' : 'Sync Library'),
                        );
                      }
                    ),
                  ),
                ]),
              ),
              const SizedBox(height: 14),
              Panel(
                title: 'Weekly goal',
                trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    tooltip: 'Decrease goal',
                    onPressed: () => context.actions.setWeeklyGoal(p.weeklyGoalHours - 5),
                    icon: const Icon(Icons.remove_circle_outline_rounded),
                  ),
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    tooltip: 'Increase goal',
                    onPressed: () => context.actions.setWeeklyGoal(p.weeklyGoalHours + 5),
                    icon: const Icon(Icons.add_circle_outline_rounded),
                  ),
                ]),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text.rich(TextSpan(children: [
                    TextSpan(text: fmtHours(week), style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w800)),
                    TextSpan(text: ' / ${fmtHours(p.weeklyGoalHours)} hrs this week', style: const TextStyle(color: Palette.muted)),
                  ])),
                  const SizedBox(height: 10),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: LinearProgressIndicator(value: weekProgress, minHeight: 8, color: weekProgress >= 1 ? Palette.success : Palette.accent, backgroundColor: Colors.white12),
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
                    separatorBuilder: (_, __) => const SizedBox(width: 12),
                    itemBuilder: (_, i) => GamePosterCard(game: top[i], width: 104),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _CountStat extends StatelessWidget {
  const _CountStat({required this.value, required this.label});
  final String value;
  final String label;

  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(value, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
        Text(label, style: const TextStyle(color: Palette.muted, fontSize: 12.5)),
      ]);
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
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Column(children: [
            Icon(service.icon, size: 28, color: connected ? service.color : Palette.muted),
            const SizedBox(height: 6),
            Text(service.label, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
            const SizedBox(height: 2),
            Text(connected ? 'Connected' : 'Connect', style: TextStyle(fontSize: 11, color: connected ? Palette.success : Palette.muted)),
          ]),
        ),
      ),
    );
  }
}