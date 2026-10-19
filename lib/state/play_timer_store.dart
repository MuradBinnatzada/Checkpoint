import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:checkpoint/state/auth_store.dart';

/// A timer started on a game: which one, and since when.
@immutable
class RunningTimer {
  const RunningTimer({required this.gameId, required this.startedAt});

  final String gameId;
  final DateTime startedAt;
}

/// The live play timer: start it when you sit down to play, stop it when you're
/// done, and the time becomes a play session (the Quick Log sheet, filled in).
///
/// There is one timer per account, kept on the device, so it keeps running
/// while the app is closed and is still there when it opens again. It follows
/// [AuthStore] only: another account signing in sees its own timer, and a
/// sign-out hides it (it is still there after signing back in).
class PlayTimerStore extends ChangeNotifier {
  PlayTimerStore({required this._auth, DateTime Function()? clock})
    : _clock = clock ?? DateTime.now;

  final AuthStore _auth;
  final DateTime Function() _clock;

  String? _userId;
  RunningTimer? _running;

  /// Bumped on every account change, so a read that was overtaken stops.
  int _loadSeq = 0;

  /// The timer that is running, or null.
  RunningTimer? get running => _running;

  /// Whether the timer runs for [gameId].
  bool isRunningFor(String gameId) => _running?.gameId == gameId;

  /// How long the timer has run.
  Duration get elapsed {
    final timer = _running;
    return timer == null ? Duration.zero : _clock().difference(timer.startedAt);
  }

  DateTime now() => _clock();

  static String _key(String userId) => 'play_timer.v1.$userId';

  Future<void> initialize() async {
    _auth.addListener(_onAuth);
    await _load(_auth.user?.id);
  }

  @override
  void dispose() {
    _auth.removeListener(_onAuth);
    super.dispose();
  }

  void _onAuth() {
    final id = _auth.user?.id;
    if (id != _userId) unawaited(_load(id));
  }

  Future<void> _load(String? userId) async {
    final seq = ++_loadSeq;
    _userId = userId;
    _running = null;
    notifyListeners();
    if (userId == null) return;
    final saved = await _read(userId);
    if (seq != _loadSeq) return;
    _running = saved;
    notifyListeners();
  }

  /// Starts the timer on [gameId], replacing one that was running (its time is
  /// not logged). Does nothing when signed out.
  void start(String gameId) {
    final userId = _userId;
    if (userId == null) return;
    _running = RunningTimer(gameId: gameId, startedAt: _clock());
    notifyListeners();
    unawaited(_write(userId, _running));
  }

  /// Stops the timer without logging anything: after its session was logged,
  /// or to throw it away.
  void clear() {
    final userId = _userId;
    if (_running == null || userId == null) return;
    _running = null;
    notifyListeners();
    unawaited(_write(userId, null));
  }

  /// Never throws: a timer that can't be read is no timer.
  static Future<RunningTimer?> _read(String userId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_key(userId));
      if (raw == null) return null;
      final json = Map<String, dynamic>.from(jsonDecode(raw) as Map);
      return RunningTimer(
        gameId: json['gameId'] as String,
        startedAt: DateTime.parse(json['startedAt'] as String).toLocal(),
      );
    } catch (e) {
      debugPrint('Reading the play timer failed: $e');
      return null;
    }
  }

  static Future<void> _write(String userId, RunningTimer? timer) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (timer == null) {
        await prefs.remove(_key(userId));
      } else {
        await prefs.setString(
          _key(userId),
          jsonEncode({
            'gameId': timer.gameId,
            'startedAt': timer.startedAt.toUtc().toIso8601String(),
          }),
        );
      }
    } catch (e) {
      debugPrint('Saving the play timer failed: $e');
    }
  }
}

/// The hours a session of [elapsed] logs: to the tenth of an hour (as the
/// sheets show hours), at least a tenth and at most one sitting ([maxHours]).
double timerHours(Duration elapsed, {required double maxHours}) {
  final hours = (elapsed.inSeconds / 3600 * 10).round() / 10;
  return hours.clamp(0.1, maxHours).toDouble();
}
