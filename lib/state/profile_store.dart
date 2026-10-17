import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:checkpoint/models/connected_service.dart';
import 'package:checkpoint/models/user_profile.dart';
import 'package:checkpoint/services/checkpoint_repository.dart';
import 'package:checkpoint/services/connection_failure.dart';
import 'package:checkpoint/services/connectivity_service.dart';
import 'package:checkpoint/services/delete_account_failure.dart';
import 'package:checkpoint/services/local_cache.dart';
import 'package:checkpoint/services/pending_edits.dart';
import 'package:checkpoint/state/auth_store.dart';

/// The signed-in user as a person: their profile, who they follow, and the
/// gaming accounts they have connected. Reloads when the account changes, shows
/// the copy saved on the device first, and keeps it when the network is down.
///
/// Follows and unfollows made while the server can't be reached are kept on the
/// device ([PendingEdits.follows]), shown as if saved, and sent when the
/// connection is back ([flushPending]). One the server refuses is reverted
/// instead.
///
/// Which services are connected, and the account names behind PSN, Xbox, Discord,
/// Instagram and Twitch, are saved on the device first and mirrored to the profile
/// row (`connected_services`, `psn_id`, `xbox_id`, `discord_id`, `instagram_id`,
/// `twitch_id`), which is what other members' profile pages show and open. A change
/// the server hasn't received is remembered and sent when the connection is back;
/// see [_pushServices].
class ProfileStore extends ChangeNotifier {
  ProfileStore({
    required this._repository,
    required this._auth,
    this._connectivity,
    LocalCache? cache,
    PendingEditsStorage? pendingStorage,
  }) : _cache = cache ?? LocalCache(),
       _pendingStorage =
           pendingStorage ?? PendingEditsStorage(PendingScope.follows),
       _profile = _guestProfile();

  final CheckpointRepository _repository;
  final AuthStore _auth;
  final LocalCache _cache;
  final PendingEditsStorage _pendingStorage;
  final ConnectivityService? _connectivity;

  User? _user;

  /// The account whose local service data is loaded, and whether its saved copy
  /// has been read. Tracked as state rather than inferred from "a different user
  /// signed in": a load that was overtaken by a second auth event never got to
  /// read them, and the load that overtook it sees the same user.
  String? _localDataFor;
  bool _hydrated = false;

  UserProfile _profile;

  /// Who the user follows as shown: what the server (or the saved copy) says,
  /// with the follows that haven't reached the server applied on top.
  Set<String> _followingIds = {};
  int _followersCount = 0;

  /// Follows the server hasn't accepted yet, for the account in [_pendingFor].
  PendingEdits _pending = PendingEdits();
  String? _pendingFor;

  /// The replay of [_pending] that is running, if any. A new follow waits for it,
  /// so the two can't cross on their way to the server.
  Future<void>? _replay;

  String? _notice;

  StreamSubscription<User?>? _authSubscription;
  StreamSubscription<bool>? _connectivitySubscription;

  /// The last load did not finish (the server could not be reached), so what is
  /// shown may be the saved copy.
  bool _incomplete = false;
  final List<StreamSubscription<dynamic>> _dataSubscriptions = [];

  /// Bumped by every account event, so a load that was overtaken (another
  /// account signed in, or a retry started) can tell and stop.
  int _loadSeq = 0;

  static UserProfile _guestProfile() => UserProfile(
    name: 'Player',
    handle: '@guest',
    bio: '',
    joined: DateTime.now(),
    followers: 0,
    following: 0,
  );

  UserProfile get profile => _profile;

  /// How many follows and unfollows are waiting for the server (see
  /// [flushPending]).
  int get pendingCount => _pending.count;

  /// A message about something that just went wrong with a follow or with the
  /// connected services. The app shell shows it once and calls [clearNotice].
  String? get notice => _notice;

  void clearNotice() => _notice = null;

  void _setNotice(String message) {
    _notice = message;
    notifyListeners();
  }

  Future<void> initialize() async {
    final prefs = await SharedPreferences.getInstance();
    // The Steam ID now lives on the `profiles` row. Delete any copy that an
    // older build left on this device; it is deliberately not read or migrated.
    await prefs.remove('steam_id');
    // These used to be saved for the whole device, so they showed up on whichever
    // account signed in next. They are saved per account now (see
    // _loadAccountLocalData); delete the old shared copies, which can't be
    // attributed to anyone.
    for (final key in const ['psn_id', 'xbox_id', 'discord_id', 'connected_services']) {
      await prefs.remove(key);
    }
    _authSubscription = _auth.userChanges.listen((user) {
      unawaited(_onUser(user));
    });
    _connectivitySubscription = _connectivity?.onlineChanges.listen((online) {
      if (!online || _user == null) return;
      // A reload ends with the replay; without one there is only the replay to do.
      if (_incomplete) {
        unawaited(refresh());
      } else {
        unawaited(flushPending());
        unawaited(_pushServices());
      }
    });
    await _onUser(_auth.user);
  }

  @override
  void dispose() {
    unawaited(_authSubscription?.cancel());
    unawaited(_connectivitySubscription?.cancel());
    unawaited(_cancelDataSubscriptions());
    super.dispose();
  }

  /// Loads everything again for the signed-in user (a retry after a failed load).
  Future<void> refresh() => _onUser(_user);

  Future<void> _onUser(User? user) async {
    final seq = ++_loadSeq;
    // Token refreshes and retries re-enter here for the same user; their loaded
    // data stays valid, a different user's does not.
    final previous = _user;
    final sameUser = user != null && user.id == previous?.id;
    _user = user;
    if (!sameUser) {
      // A different account (or signing out) must not inherit the previous
      // account's profile, follows or local service data.
      _clearAccountLocalData();
      _localDataFor = null;
      _hydrated = false;
      _profile = _guestProfile();
      _followingIds = {};
      _followersCount = 0;
      _pending = PendingEdits();
      _pendingFor = null;
      // The previous account's saved copy goes too (it stays valid only while
      // that account stays signed in).
      if (previous != null) unawaited(_cache.clearAccount(previous.id));
      notifyListeners();
    }

    await _cancelDataSubscriptions();
    if (user == null || seq != _loadSeq) return;

    if (_localDataFor != user.id) {
      await _loadAccountLocalData(user.id);
      if (seq != _loadSeq) return;
      _localDataFor = user.id;
    }
    // Their own copy, not the saved server copy: these follows exist nowhere else
    // (and stay on the device when the account signs out).
    if (_pendingFor != user.id) {
      final saved = await _pendingStorage.read(user.id);
      if (seq != _loadSeq) return;
      _pending = saved;
      _pendingFor = user.id;
    }
    if (!_hydrated) {
      await _hydrateFromCache(user.id, seq);
      if (seq != _loadSeq) return;
      _hydrated = true;
    }

    // No live session (the app started offline): the saved copy is all there is
    // until the session is restored, which announces itself as an auth event.
    if (_auth.isSessionPending) {
      _incomplete = true;
      return;
    }

    // Independent reads, started together. Each falls back to the saved copy on
    // its own, so a failed one doesn't throw away the other.
    final (profileLoaded, socialLoaded) =
        await (_loadProfile(user, seq), _loadSocial(user.id, seq)).wait;
    if (seq != _loadSeq) return;
    _incomplete = !(profileLoaded && socialLoaded);
    if (!_incomplete) _startSubscriptions(user);
    // The follows table answered, so whatever was queued while it couldn't be
    // reached goes now.
    if (socialLoaded) unawaited(flushPending());
  }

  /// Puts the copy saved on this device on screen while the network answers.
  Future<void> _hydrateFromCache(String userId, int seq) async {
    final profile = await _cache.readProfile(userId);
    final social = await _cache.readSocial(userId);
    if (seq != _loadSeq) return;
    if (profile == null && social == null && _pending.follows.isEmpty) return;
    if (profile != null) _profile = profile.value;
    if (social != null) _followersCount = social.value.followersCount;
    _followingIds = _withPendingFollows(
      social?.value.followingIds ?? _followingIds,
    );
    notifyListeners();
  }

  /// Creates the profiles row on first login. This lives only in
  /// CheckpointRepository.ensureProfile; AuthService has no copy of it, so two
  /// code paths can't race to create the same row during sign-in.
  Future<bool> _loadProfile(User user, int seq) async {
    final versionBefore = _serviceVersion;
    try {
      final fetched = await _repository.ensureProfile(user);
      if (seq != _loadSeq) return true;
      _profile = fetched;
      _applyServerAccounts(user.id, fetched, versionBefore);
      notifyListeners();
      unawaited(_cache.writeProfile(user.id, fetched));
      return true;
    } catch (e, st) {
      // Keeps whatever is showing: the saved copy, or the guest placeholder.
      debugPrint('Profile load failed: $e\n$st');
      return false;
    }
  }

  Future<bool> _loadSocial(String userId, int seq) async {
    try {
      final (following, followers) = await (
        _repository.fetchFollowingIds(userId),
        _repository.fetchFollowersCount(userId),
      ).wait;
      if (seq != _loadSeq) return true;
      _followingIds = _withPendingFollows(following);
      _followersCount = followers;
      notifyListeners();
      unawaited(_writeSocialCache(userId, following, followers));
      return true;
    } catch (e, st) {
      debugPrint('Social load failed: $e\n$st');
      return false;
    }
  }

  /// Saves what the server returned, not what is on screen: a follow that hasn't
  /// reached the server is in [_pending], and goes on top again when this is read.
  Future<void> _writeSocialCache(
    String userId,
    Set<String> following,
    int followers,
  ) => _cache.writeSocial(
    userId,
    SocialSnapshot(followingIds: following, followersCount: followers),
  );

  void _startSubscriptions(User user) {
    void onError(Object e, StackTrace st) =>
        debugPrint('Profile realtime stream failed: $e\n$st');
    _dataSubscriptions
      ..add(
        _repository
            .watchProfile(user.id)
            .listen((_) => unawaited(_refreshProfile(user)), onError: onError),
      )
      ..add(
        _repository
            .watchFollows(user.id)
            .listen((_) => unawaited(_refreshSocial(user.id)), onError: onError),
      );
  }

  Future<void> _cancelDataSubscriptions() async {
    for (final subscription in _dataSubscriptions) {
      await subscription.cancel();
    }
    _dataSubscriptions.clear();
  }

  Future<void> _refreshProfile(User user) async {
    final versionBefore = _serviceVersion;
    try {
      final fetched = await _repository.fetchProfile(user);
      if (_user?.id != user.id) return;
      _profile = fetched;
      _applyServerAccounts(user.id, fetched, versionBefore);
      notifyListeners();
      unawaited(_cache.writeProfile(user.id, fetched));
    } catch (e, st) {
      debugPrint('Profile refresh failed: $e\n$st');
    }
  }

  Future<void> _refreshSocial(String userId) async {
    try {
      final (following, followers) = await (
        _repository.fetchFollowingIds(userId),
        _repository.fetchFollowersCount(userId),
      ).wait;
      if (_user?.id != userId) return;
      _followingIds = _withPendingFollows(following);
      _followersCount = followers;
      notifyListeners();
      unawaited(_writeSocialCache(userId, following, followers));
    } catch (e, st) {
      debugPrint('Social refresh failed: $e\n$st');
    }
  }

  // ---- Per-account local data: account names + connected flags ----
  // Steam is not stored here. It is connected exactly when the signed-in user's
  // profile has a Steam ID (see [steamConnected]).
  //
  // Every key ends in `.<user id>`, which is what lets account deletion find and
  // erase them (LocalCache.eraseAccount).

  static String _scoped(String key, String userId) => '$key.$userId';

  /// Forgets the previous account's service data (memory only; the saved copy
  /// stays on disk for when that account signs in again).
  void _clearAccountLocalData() {
    _psnId = null;
    _xboxId = null;
    _discordId = null;
    _instagramId = null;
    _twitchId = null;
    _connected.clear();
    _servicesPending = false;
    _serviceVersion++;
  }

  /// Loads the service names and connected flags saved for [userId].
  Future<void> _loadAccountLocalData(String userId) async {
    final prefs = await SharedPreferences.getInstance();
    if (_user?.id != userId) return; // signed out or switched while we waited
    _psnId = prefs.getString(_scoped('psn_id', userId));
    _xboxId = prefs.getString(_scoped('xbox_id', userId));
    _discordId = prefs.getString(_scoped('discord_id', userId));
    _instagramId = prefs.getString(_scoped('instagram_id', userId));
    _twitchId = prefs.getString(_scoped('twitch_id', userId));
    final saved = prefs.getStringList(_scoped('connected_services', userId));
    _connected.addAll(connectedServicesFromDb(saved));
    // No record means the accounts were saved before the server kept them (the
    // list, and the names too, which came later): what this device has is then
    // newer than what the server has, and goes up.
    _servicesPending =
        prefs.getBool(_scoped(_servicesPendingKey, userId)) ?? _connected.isNotEmpty;
  }

  /// Whether the server has the device's connected accounts yet. (An earlier
  /// build kept `services_pending` for the list alone; it is not read any more, so
  /// that every device sends the account names once.)
  static const _servicesPendingKey = 'accounts_pending';

  /// Saves the connected services and whether the server has them yet.
  Future<void> _saveConnectedServices(String userId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(
      _scoped('connected_services', userId),
      _connected.map((e) => e.name).toList(),
    );
    await prefs.setBool(_scoped(_servicesPendingKey, userId), _servicesPending);
  }

  // ---- Following ----

  bool isFollowing(String userId) => _followingIds.contains(userId);
  int get followersCount => _followersCount;
  int get followingCount => _followingIds.length;

  /// [fetched] with the follows and unfollows that haven't reached the server
  /// applied, so a refresh never undoes them.
  Set<String> _withPendingFollows(Set<String> fetched) {
    if (_pending.follows.isEmpty) return fetched;
    final ids = {...fetched};
    _pending.follows.forEach((id, following) {
      if (following) {
        ids.add(id);
      } else {
        ids.remove(id);
      }
    });
    return ids;
  }

  void _showFollowing(String userId, bool following) {
    _followingIds = following
        ? {..._followingIds, userId}
        : ({..._followingIds}..remove(userId));
    notifyListeners();
  }

  /// Follows [userId], or unfollows them if they are followed. Shown at once. If
  /// the server can't be reached it is kept and sent later; if it refuses, the
  /// change is undone and a [notice] says so.
  Future<void> toggleFollow(String userId) async {
    final current = _user;
    if (current == null) return;
    final following = !_followingIds.contains(userId);
    _showFollowing(userId, following);

    await _replay;
    if (_user?.id != current.id) return;

    // Already queued, so this undoes it: nothing has reached the server, and
    // sending now would jump ahead of the queue.
    if (_pending.follows.containsKey(userId)) {
      _pending.putFollow(userId, following: following);
      _savePending();
      notifyListeners();
      return;
    }

    try {
      _auth.requireSession();
      await _send(current.id, userId, following: following);
    } catch (e, st) {
      debugPrint('Follow update failed: $e\n$st');
      if (_user?.id != current.id) return;
      if (isConnectionFailure(e)) {
        _pending.putFollow(userId, following: following);
        _savePending();
        _setNotice(queuedNotice);
      } else {
        _showFollowing(userId, !following);
        _setNotice(
          following ? 'Could not follow that user.' : 'Could not unfollow that user.',
        );
        await _refreshSocial(current.id);
      }
      return;
    }
    await _refreshSocial(current.id);
  }

  Future<void> _send(
    String followerId,
    String userId, {
    required bool following,
  }) async {
    if (!following) {
      await _repository.unfollow(followerId: followerId, followeeId: userId);
      return;
    }
    try {
      await _repository.follow(followerId: followerId, followeeId: userId);
    } on PostgrestException catch (e) {
      // Already following (the table's key): what was asked for is true.
      if (e.code != '23505') rethrow;
    }
  }

  void _savePending() {
    final userId = _pendingFor;
    if (userId != null) unawaited(_pendingStorage.write(userId, _pending));
  }

  /// Sends the queued follows and unfollows. Stops at the first one the server
  /// can't be reached for (the rest stay queued); one it refuses is dropped, with
  /// a notice. Safe to call any time: it does nothing without a live session,
  /// with nothing queued, or while already running.
  Future<void> flushPending() {
    final running = _replay;
    if (running != null) return running;
    final user = _user;
    if (user == null || _pending.follows.isEmpty || _auth.isSessionPending) {
      return Future.value();
    }
    return _replay = _sendPending(user).whenComplete(() {
      _replay = null;
    });
  }

  Future<void> _sendPending(User user) async {
    var sent = 0;
    var refused = 0;
    try {
      for (final MapEntry(key: id, value: following) in [..._pending.follows.entries]) {
        if (_user?.id != user.id) return;
        try {
          await _send(user.id, id, following: following);
          sent++;
        } catch (e, st) {
          debugPrint('Sending a queued follow failed: $e\n$st');
          if (isConnectionFailure(e)) return;
          refused++;
        }
        if (_user?.id != user.id) return;
        _pending.follows.remove(id);
      }
    } finally {
      if (_user?.id == user.id) {
        _savePending();
        if (refused > 0) {
          _setNotice('Some offline follow changes could not be saved.');
        } else {
          notifyListeners();
        }
        // Pull in what the server has now, anything still queued applied on top.
        if (sent + refused > 0) unawaited(_refreshSocial(user.id));
      }
    }
  }

  // ---- Connected services ----

  final Set<ConnectedService> _connected = {};

  /// Steam is connected exactly when the signed-in user's profile has a Steam ID.
  /// Every other service is a flag saved per account on this device.
  bool get steamConnected =>
      _user != null && (_profile.steamId?.trim().isNotEmpty ?? false);

  int get connectedCount => connectedServices.length;
  Set<ConnectedService> get connectedServices => Set.unmodifiable({
    ..._connected,
    if (steamConnected) ConnectedService.steam,
  });
  bool isConnected(ConnectedService s) =>
      s == ConnectedService.steam ? steamConnected : _connected.contains(s);

  /// The signed-in user's Steam ID64, read from `profiles.steam_id` along with
  /// the rest of their profile. `null` when signed out or not set yet.
  String? get steamId => _profile.steamId;

  /// Clears the Steam ID on the profile, which is what disconnects Steam.
  /// Returns null on success, or a message that is safe to show.
  Future<String?> disconnectSteam() async {
    if (!steamConnected) return null;
    try {
      await _repository.clearSteamId();
      _profile = _profile.copyWith(clearSteamId: true);
      notifyListeners();
      unawaited(_writeProfileCache());
      return null;
    } catch (e, st) {
      debugPrint('Disconnecting Steam failed: $e\n$st');
      return 'Could not disconnect Steam. Please try again.';
    }
  }

  void toggleService(ConnectedService s) async {
    if (s == ConnectedService.steam) {
      // Toggling Steam off clears its ID. Connecting goes through [setSteamId].
      unawaited(disconnectSteam());
      return;
    }
    if (!_connected.remove(s)) _connected.add(s);
    _servicesPending = true;
    _serviceVersion++;
    notifyListeners();

    final userId = _user?.id;
    if (userId == null) return;
    await _saveConnectedServices(userId);
    unawaited(_pushServices(userAction: true));
  }

  // ---- Connected accounts on the server ----
  //
  // `profiles.connected_services` names the connected services other than Steam,
  // and `psn_id` / `xbox_id` / `discord_id` / `instagram_id` / `twitch_id` hold the
  // account names behind them:
  // what another member's profile shows, and what its icons open. They are a
  // mirror of what the device has, written as a whole, so sending them twice is
  // harmless and there is no queue of edits: only whether the latest arrived.

  /// What the device has connected, as the server stores it: a service that is
  /// not connected has no name.
  ConnectedAccounts get _accounts => ConnectedAccounts(
    services: {..._connected},
    psnId: _connected.contains(ConnectedService.psn) ? _psnId : null,
    xboxId: _connected.contains(ConnectedService.xbox) ? _xboxId : null,
    discordId: _connected.contains(ConnectedService.discord) ? _discordId : null,
    instagramId: _connected.contains(ConnectedService.instagram) ? _instagramId : null,
    twitchId: _connected.contains(ConnectedService.twitch) ? _twitchId : null,
  );

  /// The device has a change the server doesn't have yet. Saved with the list.
  bool _servicesPending = false;

  /// Bumped by every change made on the device and every send that reached the
  /// server, so a read of the server's accounts that was under way meanwhile can
  /// tell its answer is out of date.
  int _serviceVersion = 0;

  /// The send that is running, if any.
  Future<void>? _servicesPush;

  /// The server's accounts were just read (as part of [server], the profile). A
  /// change the device hasn't sent goes up now; otherwise the server's accounts are
  /// the truth (another device may have changed them) and replace the device's,
  /// except a name this device has and the server lacks, which goes up.
  /// [versionBefore] is [_serviceVersion] from before the read started.
  void _applyServerAccounts(
    String userId,
    UserProfile server,
    int versionBefore,
  ) {
    if (versionBefore != _serviceVersion) return;
    if (_servicesPending) {
      unawaited(_pushServices());
      return;
    }
    final onServer = ConnectedAccounts(
      services: server.connectedServices,
      psnId: server.psnId,
      xboxId: server.xboxId,
      discordId: server.discordId,
      instagramId: server.instagramId,
      twitchId: server.twitchId,
    );
    if (onServer == _accounts) return;

    _connected
      ..clear()
      ..addAll(server.connectedServices);
    // The server's name wins; where it has none, this device's is kept. A name
    // for a service the server doesn't list as connected is stale, and ignored.
    bool listed(ConnectedService s) => server.connectedServices.contains(s);
    if (listed(ConnectedService.psn)) _psnId = server.psnId ?? _psnId;
    if (listed(ConnectedService.xbox)) _xboxId = server.xboxId ?? _xboxId;
    if (listed(ConnectedService.discord)) {
      _discordId = server.discordId ?? _discordId;
    }
    if (listed(ConnectedService.instagram)) {
      _instagramId = server.instagramId ?? _instagramId;
    }
    if (listed(ConnectedService.twitch)) {
      _twitchId = server.twitchId ?? _twitchId;
    }
    unawaited(_saveAccountNames(userId));
    if (onServer != _accounts) {
      // This device knows a name the server doesn't.
      _servicesPending = true;
      _serviceVersion++;
      unawaited(_saveConnectedServices(userId));
      unawaited(_pushServices());
      return;
    }
    unawaited(_saveConnectedServices(userId));
  }

  Future<void> _saveAccountNames(String userId) async {
    final prefs = await SharedPreferences.getInstance();
    for (final (key, name) in [
      ('psn_id', _psnId),
      ('xbox_id', _xboxId),
      ('discord_id', _discordId),
      ('instagram_id', _instagramId),
      ('twitch_id', _twitchId),
    ]) {
      if (name != null) await prefs.setString(_scoped(key, userId), name);
    }
  }

  /// Sends the connected accounts to the server while the device has a change it
  /// hasn't received. Does nothing without a live session or with nothing to send,
  /// and a second call joins the one running. A failed send leaves the change
  /// pending: it is tried again when the profile next loads or the connection
  /// comes back. [userAction] says the user just made the change, so they are told
  /// when it did not get through.
  Future<void> _pushServices({bool userAction = false}) {
    final running = _servicesPush;
    if (running != null) return running;
    final user = _user;
    if (user == null || !_servicesPending) return Future.value();
    if (_auth.isSessionPending) {
      if (userAction) _setNotice(queuedNotice);
      return Future.value();
    }
    return _servicesPush = _sendServices(user, userAction).whenComplete(() {
      _servicesPush = null;
    });
  }

  Future<void> _sendServices(User user, bool userAction) async {
    // Again while a change was made during the send.
    while (_servicesPending && _user?.id == user.id) {
      final sent = _accounts;
      try {
        await _repository.setConnectedAccounts(sent);
      } catch (e, st) {
        debugPrint('Saving the connected accounts failed: $e\n$st');
        if (userAction && _user?.id == user.id) {
          _setNotice(
            isConnectionFailure(e)
                ? queuedNotice
                : 'Could not update the accounts shown on your profile.',
          );
        }
        return;
      }
      if (_user?.id != user.id) return;
      _serviceVersion++;
      if (sent == _accounts) {
        _servicesPending = false;
        await _saveConnectedServices(user.id);
      }
    }
  }

  /// Saves [id] to the signed-in user's `profiles` row (not to the device).
  /// The local copy is updated only after the save succeeds. Returns null on
  /// success, or a user-facing error message.
  Future<String?> setSteamId(String id) async {
    final current = _user;
    if (current == null) return 'Sign in to connect your Steam account.';

    final trimmed = id.trim();
    if (trimmed.isEmpty) return 'Enter your Steam ID.';

    try {
      await _repository.setSteamId(trimmed);
      _profile = _profile.copyWith(steamId: trimmed);
      notifyListeners();
      unawaited(_writeProfileCache());
      return null;
    } catch (e, st) {
      debugPrint('Saving Steam ID failed: $e\n$st');
      return 'Could not save your Steam ID. Please try again.';
    }
  }

  String? _psnId;
  String? _xboxId;
  String? _discordId;
  String? _instagramId;
  String? _twitchId;
  String? get psnId => _psnId;
  String? get xboxId => _xboxId;
  String? get discordId => _discordId;
  String? get instagramId => _instagramId;
  String? get twitchId => _twitchId;

  /// The name saved for each connected service that has one, for the Connected
  /// accounts box on the Profile tab: the Steam ID and the PSN, Xbox, Discord,
  /// Instagram and Twitch names. A service that is not connected is left out.
  Map<ConnectedService, String> get accountNames => {
    for (final s in connectedServices)
      if (_nameOf(s)?.trim() case final name? when name.isNotEmpty) s: name,
  };

  String? _nameOf(ConnectedService s) => switch (s) {
    ConnectedService.steam => steamId,
    ConnectedService.psn => _psnId,
    ConnectedService.xbox => _xboxId,
    ConnectedService.discord => _discordId,
    ConnectedService.instagram => _instagramId,
    ConnectedService.twitch => _twitchId,
    ConnectedService.nintendo => null,
  };

  /// Saves the username for PSN, Xbox, Discord, Instagram or Twitch, marks that
  /// service as connected, and persists both the ID and the connected-services
  /// list. Steam uses [setSteamId] (stored on the profile); Nintendo has no stored
  /// ID.
  void setServiceId(ConnectedService service, String id) async {
    final String prefKey;
    switch (service) {
      case ConnectedService.psn:
        _psnId = id;
        prefKey = 'psn_id';
      case ConnectedService.xbox:
        _xboxId = id;
        prefKey = 'xbox_id';
      case ConnectedService.discord:
        _discordId = id;
        prefKey = 'discord_id';
      case ConnectedService.instagram:
        _instagramId = id;
        prefKey = 'instagram_id';
      case ConnectedService.twitch:
        _twitchId = id;
        prefKey = 'twitch_id';
      case ConnectedService.steam || ConnectedService.nintendo:
        debugPrint('setServiceId: ${service.name} has no stored ID.');
        return;
    }
    // The name may have changed even if the service was already connected.
    _connected.add(service);
    _servicesPending = true;
    _serviceVersion++;
    notifyListeners();

    // Saved per account, so another account on this device doesn't see it; the
    // server gets a copy for other members' profile pages.
    final userId = _user?.id;
    if (userId == null) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_scoped(prefKey, userId), id);
    await _saveConnectedServices(userId);
    unawaited(_pushServices(userAction: true));
  }

  // ---- Editing the profile ----

  static String _normalizeHandle(String handle) =>
      handle.trim().replaceFirst(RegExp(r'^@+'), '').toLowerCase();

  /// Whether [handle] (with or without the leading "@") is free for the
  /// signed-in user. Case-insensitive; the user's own current handle counts as
  /// available. Throws if signed out or if the lookup fails, so callers can
  /// decide how to degrade (the unique constraint still guards the save).
  Future<bool> isHandleAvailable(String handle) {
    final current = _user;
    if (current == null) {
      throw StateError('Sign in to check username availability.');
    }
    return _repository.isHandleAvailable(_normalizeHandle(handle), current.id);
  }

  /// Uploads [image] to the avatars bucket and returns its public URL. This
  /// doesn't touch the profile; pass the URL to [updateProfile] to save it.
  Future<String> uploadAvatar(XFile image) => _repository.uploadAvatar(image);

  /// Updates the signed-in user's display name, handle (without the leading
  /// "@"), bio and avatar. A null [bio] or [avatarUrl] leaves that field as is.
  /// Returns null on success, or a user-facing error message.
  Future<String?> updateProfile({
    required String name,
    required String handle,
    String? bio,
    String? avatarUrl,
  }) async {
    final current = _user;
    if (current == null) return 'Sign in to edit your profile.';

    final nextName = name.trim();
    final nextHandle = _normalizeHandle(handle);
    final nextBio = bio?.trim();
    if (nextName.isEmpty || nextHandle.isEmpty) {
      return 'Display name and username can\'t be empty.';
    }

    final currentHandle = _profile.handle.replaceFirst(RegExp(r'^@+'), '');
    final unchanged =
        nextName == _profile.name &&
        nextHandle == currentHandle &&
        (nextBio == null || nextBio == _profile.bio) &&
        (avatarUrl == null || avatarUrl == _profile.avatarUrl);
    if (unchanged) return null;

    try {
      await _repository.updateProfile(
        name: nextName,
        handle: nextHandle,
        bio: nextBio,
        avatarUrl: avatarUrl,
      );

      // Optimistically update local profile state and trigger instant UI re-render
      _profile = _profile.copyWith(
        name: nextName,
        handle: '@$nextHandle',
        bio: nextBio,
        avatarUrl: avatarUrl ?? _profile.avatarUrl,
      );
      notifyListeners();

      await _refreshProfile(current);
      return null;
    } on PostgrestException catch (e, st) {
      debugPrint('Profile update failed: $e\n$st');
      if (e.code == '23505') return 'That username is already taken.';
      return 'Could not save your profile. Please try again.';
    } catch (e, st) {
      debugPrint('Profile update failed: $e\n$st');
      return 'Could not save your profile. Please try again.';
    }
  }

  // ---- Deleting the account ----

  /// Permanently deletes the signed-in account: its profile, library, play logs,
  /// follows and photo on the server, then the sign-in, and then everything this
  /// device holds for it. Signs out. Returns null on success, or a message that is
  /// safe to show; the account is untouched then, and this can be tried again.
  Future<String?> deleteAccount() async {
    final current = _user;
    if (current == null) return deleteAccountMessage(StateError('Not signed in.'));
    try {
      await _auth.deleteAccount();
    } catch (e, st) {
      debugPrint('Deleting the account failed: $e\n$st');
      return deleteAccountMessage(e);
    }
    // The account is gone and the session ended; the stores have dropped what they
    // held in memory. What is left is on disk, and must not outlive the account.
    await _cache.eraseAccount(current.id);
    return null;
  }

  /// Saves the profile as it is now, after an edit the server accepted.
  Future<void> _writeProfileCache() async {
    final userId = _user?.id;
    if (userId != null) await _cache.writeProfile(userId, _profile);
  }
}
