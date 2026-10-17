import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:checkpoint/models/connected_service.dart';
import 'package:checkpoint/models/user_profile.dart';
import 'package:checkpoint/services/checkpoint_repository.dart';
import 'package:checkpoint/services/local_cache.dart';
import 'package:checkpoint/state/auth_store.dart';

/// The signed-in user as a person: their profile, who they follow, and the
/// gaming accounts they have connected. Reloads when the account changes, shows
/// the copy saved on the device first, and keeps it when the network is down.
class ProfileStore extends ChangeNotifier {
  ProfileStore({
    required this._repository,
    required this._auth,
    LocalCache? cache,
  }) : _cache = cache ?? LocalCache(),
       _profile = _guestProfile();

  final CheckpointRepository _repository;
  final AuthStore _auth;
  final LocalCache _cache;

  User? _user;

  /// The account whose local service data is loaded, and whether its saved copy
  /// has been read. Tracked as state rather than inferred from "a different user
  /// signed in": a load that was overtaken by a second auth event never got to
  /// read them, and the load that overtook it sees the same user.
  String? _localDataFor;
  bool _hydrated = false;

  UserProfile _profile;
  Set<String> _followingIds = {};
  int _followersCount = 0;

  StreamSubscription<User?>? _authSubscription;
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
    await _onUser(_auth.user);
  }

  @override
  void dispose() {
    unawaited(_authSubscription?.cancel());
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
    if (!_hydrated) {
      await _hydrateFromCache(user.id, seq);
      if (seq != _loadSeq) return;
      _hydrated = true;
    }

    // Independent reads, started together. Each falls back to the saved copy on
    // its own, so a failed one doesn't throw away the other.
    final (profileLoaded, socialLoaded) =
        await (_loadProfile(user, seq), _loadSocial(user.id, seq)).wait;
    if (seq != _loadSeq) return;
    if (profileLoaded && socialLoaded) _startSubscriptions(user);
  }

  /// Puts the copy saved on this device on screen while the network answers.
  Future<void> _hydrateFromCache(String userId, int seq) async {
    final profile = await _cache.readProfile(userId);
    final social = await _cache.readSocial(userId);
    if (seq != _loadSeq) return;
    if (profile == null && social == null) return;
    if (profile != null) _profile = profile.value;
    if (social != null) {
      _followingIds = social.value.followingIds;
      _followersCount = social.value.followersCount;
    }
    notifyListeners();
  }

  /// Creates the profiles row on first login. This lives only in
  /// CheckpointRepository.ensureProfile; AuthService has no copy of it, so two
  /// code paths can't race to create the same row during sign-in.
  Future<bool> _loadProfile(User user, int seq) async {
    try {
      final fetched = await _repository.ensureProfile(user);
      if (seq != _loadSeq) return true;
      _profile = fetched;
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
      _followingIds = following;
      _followersCount = followers;
      notifyListeners();
      unawaited(_writeSocialCache(userId));
      return true;
    } catch (e, st) {
      debugPrint('Social load failed: $e\n$st');
      return false;
    }
  }

  Future<void> _writeSocialCache(String userId) => _cache.writeSocial(
    userId,
    SocialSnapshot(
      followingIds: _followingIds,
      followersCount: _followersCount,
    ),
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
    try {
      final fetched = await _repository.fetchProfile(user);
      if (_user?.id != user.id) return;
      _profile = fetched;
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
      _followingIds = following;
      _followersCount = followers;
      notifyListeners();
      unawaited(_writeSocialCache(userId));
    } catch (e, st) {
      debugPrint('Social refresh failed: $e\n$st');
    }
  }

  // ---- Per-account local data: PSN / Xbox / Discord names + connected flags ----
  // Steam is not stored here. It is connected exactly when the signed-in user's
  // profile has a Steam ID (see [steamConnected]).

  static String _scoped(String key, String userId) => '$key.$userId';

  /// Forgets the previous account's service data (memory only; the saved copy
  /// stays on disk for when that account signs in again).
  void _clearAccountLocalData() {
    _psnId = null;
    _xboxId = null;
    _discordId = null;
    _connected.clear();
  }

  /// Loads the service names and connected flags saved for [userId].
  Future<void> _loadAccountLocalData(String userId) async {
    final prefs = await SharedPreferences.getInstance();
    if (_user?.id != userId) return; // signed out or switched while we waited
    _psnId = prefs.getString(_scoped('psn_id', userId));
    _xboxId = prefs.getString(_scoped('xbox_id', userId));
    _discordId = prefs.getString(_scoped('discord_id', userId));
    final saved = prefs.getStringList(_scoped('connected_services', userId)) ?? const <String>[];
    for (final service in ConnectedService.values) {
      if (service != ConnectedService.steam && saved.contains(service.name)) {
        _connected.add(service);
      }
    }
  }

  Future<void> _saveConnectedServices(String userId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(
      _scoped('connected_services', userId),
      _connected.map((e) => e.name).toList(),
    );
  }

  // ---- Following ----

  bool isFollowing(String userId) => _followingIds.contains(userId);
  int get followersCount => _followersCount;
  int get followingCount => _followingIds.length;

  Future<void> toggleFollow(String userId) async {
    final current = _user;
    if (current == null) return;
    final wasFollowing = _followingIds.contains(userId);
    if (wasFollowing) {
      _followingIds = {..._followingIds}..remove(userId);
    } else {
      _followingIds = {..._followingIds, userId};
    }
    notifyListeners();

    try {
      if (wasFollowing) {
        await _repository.unfollow(followerId: current.id, followeeId: userId);
      } else {
        await _repository.follow(followerId: current.id, followeeId: userId);
      }
      await _refreshSocial(current.id);
    } catch (e, st) {
      debugPrint('Follow update failed: $e\n$st');
      await _refreshSocial(current.id);
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
    notifyListeners();

    final userId = _user?.id;
    if (userId != null) await _saveConnectedServices(userId);
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
  String? get psnId => _psnId;
  String? get xboxId => _xboxId;
  String? get discordId => _discordId;

  /// Saves the username for PSN, Xbox or Discord, marks that service as
  /// connected, and persists both the ID and the connected-services list.
  /// Steam uses [setSteamId] (stored on the profile); Nintendo has no stored ID.
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
      case ConnectedService.steam || ConnectedService.nintendo:
        debugPrint('setServiceId: ${service.name} has no stored ID.');
        return;
    }
    _connected.add(service);
    notifyListeners();

    // Saved per account, so another account on this device doesn't see it.
    final userId = _user?.id;
    if (userId == null) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_scoped(prefKey, userId), id);
    await _saveConnectedServices(userId);
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

  /// Saves the profile as it is now, after an edit the server accepted.
  Future<void> _writeProfileCache() async {
    final userId = _user?.id;
    if (userId != null) await _cache.writeProfile(userId, _profile);
  }
}
