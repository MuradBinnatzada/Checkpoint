import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:checkpoint/models/game.dart';
import 'package:checkpoint/models/log_entry.dart';

/// What the user is told when an edit was kept on the device instead of sent.
const queuedNotice = 'Saved on this device. It will sync when you\'re back online.';

/// A play session logged while the server could not be reached.
@immutable
class PendingLog {
  const PendingLog({
    required this.localId,
    required this.gameId,
    required this.hours,
    required this.platform,
    required this.note,
    required this.timestamp,
  });

  factory PendingLog.fromJson(Map<String, dynamic> json) => PendingLog(
    localId: json['localId'] as String,
    gameId: json['gameId'] as String,
    hours: (json['hours'] as num).toDouble(),
    platform: gamePlatformFromDb(json['platform']) ?? GamePlatform.pc,
    note: json['note'] as String? ?? '',
    timestamp: DateTime.parse(json['timestamp'] as String).toLocal(),
  );

  /// The id the session has on screen until the server gives it a real one.
  final String localId;
  final String gameId;
  final double hours;
  final GamePlatform platform;
  final String note;
  final DateTime timestamp;

  LogEntry toEntry() => LogEntry(
    id: localId,
    gameId: gameId,
    timestamp: timestamp,
    hours: hours,
    platform: platform,
    note: note,
  );

  Map<String, dynamic> toJson() => {
    'localId': localId,
    'gameId': gameId,
    'hours': hours,
    'platform': gamePlatformToDb(platform),
    'note': note,
    'timestamp': timestamp.toUtc().toIso8601String(),
  };
}

/// Which store owns a part of an account's [PendingEdits]. Each store keeps and
/// saves only its own part (see [PendingEditsStorage]), so one can never
/// overwrite what the other has queued.
enum PendingScope {
  /// Games, deletes and play sessions: [PendingEdits.games], [PendingEdits.removed]
  /// and [PendingEdits.logs]. Owned by `LibraryStore`.
  library,

  /// Follows and unfollows: [PendingEdits.follows]. Owned by `ProfileStore`.
  follows,
}

/// Changes the user made that the server has not accepted yet. Unlike
/// [LocalCache] this is not a copy of server data: it is the only place these
/// edits exist, so it is kept per account and survives sign-out.
///
/// Edits are kept as the end result, not as a history: [games] holds the latest
/// state of each edited game (a base game is inserted first if needed, like any
/// save), [removed] the games to delete, [logs] the sessions to insert, and
/// [follows] whether each person is to be followed or unfollowed.
class PendingEdits {
  PendingEdits();

  /// Every part is optional, so what one store saved reads back without the
  /// parts the other one owns.
  factory PendingEdits.fromJson(Map<String, dynamic> json) {
    final edits = PendingEdits();
    for (final g in json['games'] as List? ?? const []) {
      final game = Game.fromJson(Map<String, dynamic>.from(g as Map));
      edits.games[game.id] = game;
    }
    edits.removed.addAll([for (final id in json['removed'] as List? ?? const []) '$id']);
    edits.logs.addAll([
      for (final l in json['logs'] as List? ?? const [])
        PendingLog.fromJson(Map<String, dynamic>.from(l as Map)),
    ]);
    final follows = json['follows'] as Map? ?? const {};
    for (final entry in follows.entries) {
      edits.follows['${entry.key}'] = entry.value == true;
    }
    return edits;
  }

  final Map<String, Game> games = {};
  final Set<String> removed = {};
  final List<PendingLog> logs = [];

  /// By user id: `true` to follow them, `false` to unfollow them.
  final Map<String, bool> follows = {};

  bool get isEmpty =>
      games.isEmpty && removed.isEmpty && logs.isEmpty && follows.isEmpty;
  bool get isNotEmpty => !isEmpty;
  int get count => games.length + removed.length + logs.length + follows.length;

  /// Whether [scope]'s part is empty.
  bool isEmptyIn(PendingScope scope) => switch (scope) {
    PendingScope.library => games.isEmpty && removed.isEmpty && logs.isEmpty,
    PendingScope.follows => follows.isEmpty,
  };

  /// Remembers [game]'s latest state. Saving a removed game again cancels the removal.
  void putGame(Game game) {
    removed.remove(game.id);
    games[game.id] = game;
  }

  /// Remembers that [gameId] is to be deleted. Its unsent edits and sessions are
  /// moot: deleting a game deletes its sessions too.
  void markRemoved(String gameId) {
    games.remove(gameId);
    logs.removeWhere((l) => l.gameId == gameId);
    removed.add(gameId);
  }

  /// Remembers that [userId] is to be followed ([following]) or unfollowed. Only
  /// the last choice is kept: undoing a queued follow or unfollow leaves nothing
  /// to send, so the pair cancels out.
  void putFollow(String userId, {required bool following}) {
    if (follows[userId] == !following) {
      follows.remove(userId);
    } else {
      follows[userId] = following;
    }
  }

  /// Everything, or only [scope]'s part (what is saved: see [PendingEditsStorage]).
  Map<String, dynamic> toJson([PendingScope? scope]) => {
    if (scope != PendingScope.follows) ...{
      'games': [for (final g in games.values) g.toJson()],
      'removed': removed.toList(),
      'logs': [for (final l in logs) l.toJson()],
    },
    if (scope != PendingScope.library) 'follows': {...follows},
  };
}

/// Saves one [PendingScope] of [PendingEdits] on the device, one entry per
/// account.
///
/// The library's and the follows' edits live under different keys, and each
/// storage reads and writes only its own part. The two stores each hold their own
/// [PendingEdits], so a shared key would have each save wipe out the other's
/// queue (the last writer wins, and an empty one deletes the key).
class PendingEditsStorage {
  PendingEditsStorage([this.scope = PendingScope.library]);

  final PendingScope scope;

  /// The library keeps the key it had before follows were queued, so edits that
  /// are already waiting on a device are still found.
  String _key(String userId) => switch (scope) {
    PendingScope.library => 'pending.v1.$userId',
    PendingScope.follows => 'pending.v1.follows.$userId',
  };

  /// Never throws: unreadable data reads as empty (and is dropped).
  Future<PendingEdits> read(String userId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_key(userId));
      if (raw == null) return PendingEdits();
      try {
        return PendingEdits.fromJson(
          Map<String, dynamic>.from(jsonDecode(raw) as Map),
        );
      } catch (e) {
        debugPrint('Dropping unreadable pending edits: $e');
        await prefs.remove(_key(userId));
        return PendingEdits();
      }
    } catch (e, st) {
      debugPrint('Reading pending edits failed: $e\n$st');
      return PendingEdits();
    }
  }

  /// Saves this storage's part of [edits]; the rest is ignored.
  Future<void> write(String userId, PendingEdits edits) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (edits.isEmptyIn(scope)) {
        await prefs.remove(_key(userId));
      } else {
        await prefs.setString(_key(userId), jsonEncode(edits.toJson(scope)));
      }
    } catch (e, st) {
      debugPrint('Saving pending edits failed: $e\n$st');
    }
  }
}
