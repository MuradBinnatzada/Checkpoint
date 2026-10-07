// ═════════════════════════════════════════════════════════════════════════════
//  CHECKPOINT — video game tracker
//  Single-file Flutter architecture: models · state · theme · screens · sheets
//
//  • Zero third-party packages. Paste into lib/main.dart of a fresh
//    `flutter create checkpoint` project and run (Flutter 3.27+ / Dart 3.6+).
//  • State: `CheckpointStore` is a plain ChangeNotifier exposed through an
//    InheritedNotifier (`StoreScope`). It is a drop-in for Provider/Riverpod:
//    wrap the app in `ChangeNotifierProvider(create: (_) => CheckpointStore.seeded())`
//    and replace `context.store` with `context.watch<CheckpointStore>()`.
//  • Navigation: `CheckpointStore` owns BOTH `currentBottomNavIndex` and
//    `currentLibraryTabIndex`. Any widget (e.g. a stat card) can call
//    `context.actions.openLibraryTab(GameStatus.toPlay)` to jump to My Library
//    on a specific status tab in one `notifyListeners()` pass.
//  • Cover art is generated procedurally (gradient + glyph) so every screen
//    renders offline. Swap `CoverArt` for an Image.network/CachedNetworkImage
//    when a real backend (IGDB, RAWG, …) is wired in.
// ═════════════════════════════════════════════════════════════════════════════

import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart'; // 1. Added this import

// (Keep your other imports for CheckpointApp and Palette here)

// 2. Changed to Future<void> and async
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 3. Initialize Supabase
  await Supabase.initialize(
    url: 'https://nmbarqhvcjgyuwreebda.supabase.co/rest/v1/',
    anonKey: 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Im5tYmFycWh2Y2pneXV3cmVlYmRhIiwicm9sZSI6ImFub24iLCJpYXQiOjE3OTEzODE5OTcsImV4cCI6MjEwNjk1Nzk5N30.tXIvaeJPK1ZEI75U6f-SkD-4iRZBVVE3Cy5OxBCscGQ'
  );

  // 4. Keep your existing UI overlay styling
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
    statusBarBrightness: Brightness.dark,
    systemNavigationBarColor: Palette.navBar,
    systemNavigationBarIconBrightness: Brightness.light,
  ));
  
  runApp(const CheckpointApp());
}

// ═════════════════════════════════════════════════════════════════════════════
//  1 · DESIGN TOKENS & THEME
// ═════════════════════════════════════════════════════════════════════════════

abstract final class Palette {
  static const background = Color(0xFF121212);
  static const surface = Color(0xFF1C1C1E);
  static const surfaceHigh = Color(0xFF2A2A2E);
  static const navBar = Color(0xFF171719);
  static const accent = Color(0xFFBB86FC); // neon purple
  static const onAccent = Color(0xFF22103A);
  static const electric = Color(0xFF4FC3F7); // electric blue
  static const star = Color(0xFFFFC857);
  static const muted = Color(0xFF9B9BA5);
  static const danger = Color(0xFFCF6679);
  static const success = Color(0xFF7DDC9C);
}

ThemeData buildTheme() {
  const scheme = ColorScheme.dark(
    primary: Palette.accent,
    onPrimary: Palette.onAccent,
    secondary: Palette.electric,
    onSecondary: Color(0xFF00212E),
    surface: Palette.surface,
    onSurface: Colors.white,
    error: Palette.danger,
    onError: Colors.black,
    surfaceContainerHighest: Palette.surfaceHigh,
    outline: Color(0xFF3A3A3F),
    outlineVariant: Color(0xFF2C2C30),
  );

  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: Palette.background,
    canvasColor: Palette.background,
    appBarTheme: const AppBarTheme(
      backgroundColor: Palette.background,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: Palette.navBar,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      height: 68,
      indicatorColor: Palette.accent.withValues(alpha: 0.20),
      iconTheme: WidgetStateProperty.resolveWith((s) => IconThemeData(
            size: 26,
            color: s.contains(WidgetState.selected) ? Palette.accent : Palette.muted,
          )),
      labelTextStyle: WidgetStateProperty.resolveWith((s) => TextStyle(
            fontSize: 12,
            fontWeight: s.contains(WidgetState.selected) ? FontWeight.w700 : FontWeight.w500,
            color: s.contains(WidgetState.selected) ? Palette.accent : Palette.muted,
          )),
    ),
    floatingActionButtonTheme: const FloatingActionButtonThemeData(
      backgroundColor: Palette.accent,
      foregroundColor: Palette.onAccent,
      extendedTextStyle: TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
    ),
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: Palette.surface,
      surfaceTintColor: Colors.transparent,
      showDragHandle: true,
      dragHandleColor: Colors.white24,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
    ),
    chipTheme: ChipThemeData(
      backgroundColor: Palette.surfaceHigh,
      selectedColor: Palette.accent.withValues(alpha: 0.22),
      side: BorderSide(color: Colors.white.withValues(alpha: 0.08)),
      shape: const StadiumBorder(),
      labelStyle: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 13),
    ),
    snackBarTheme: const SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: Palette.surfaceHigh,
      contentTextStyle: TextStyle(color: Colors.white),
      actionTextColor: Palette.accent,
    ),
    popupMenuTheme: const PopupMenuThemeData(
      color: Palette.surfaceHigh,
      surfaceTintColor: Colors.transparent,
    ),
  );
}

// ═════════════════════════════════════════════════════════════════════════════
//  2 · DOMAIN MODELS
// ═════════════════════════════════════════════════════════════════════════════

enum GameStatus {
  playing('Playing', Icons.play_circle_rounded, Color(0xFFBB86FC)),
  toPlay('To Play', Icons.inventory_2_rounded, Color(0xFF4FC3F7)),
  completed('Completed', Icons.verified_rounded, Color(0xFF7DDC9C)),
  dropped('Dropped', Icons.block_rounded, Color(0xFFCF6679)),
  wishlist('Wishlist', Icons.bookmark_rounded, Color(0xFFFFC857));

  const GameStatus(this.label, this.icon, this.color);
  final String label;
  final IconData icon;
  final Color color;
}

enum GamePlatform {
  pc('PC', Icons.desktop_windows_rounded, Color(0xFF8AB4F8)),
  steamDeck('Steam Deck', Icons.gamepad_rounded, Color(0xFF66C0F4)),
  ps5('PS5', Icons.sports_esports_rounded, Color(0xFF5B8CFF)),
  ps4('PS4', Icons.sports_esports_outlined, Color(0xFF7BA4FF)),
  xbox('Xbox', Icons.videogame_asset_rounded, Color(0xFF6CC24A)),
  nswitch('Switch', Icons.videogame_asset_outlined, Color(0xFFFF6B6B)),
  mobile('Mobile', Icons.smartphone_rounded, Color(0xFFFFB74D));

  const GamePlatform(this.label, this.icon, this.color);
  final String label;
  final IconData icon;
  final Color color;
}

/// Catalog metadata + the user's tracking state for that game.
/// `status == null` means "in the catalog, not in my library".
@immutable
class Game {
  const Game({
    required this.id,
    required this.title,
    required this.publisher,
    required this.developer,
    required this.releaseYear,
    required this.platforms,
    required this.genres,
    required this.synopsis,
    required this.coverColors,
    required this.coverIcon,
    this.status,
    this.rating = 0,
    this.hoursPlayed = 0,
    this.targetHours = 0,
    this.playedOn,
    this.purchasePrice = 0,
    this.dateAdded,
  });

  final String id;
  final String title;
  final String publisher;
  final String developer;
  final int releaseYear;
  final List<GamePlatform> platforms;
  final List<String> genres;
  final String synopsis;
  final List<Color> coverColors;
  final IconData coverIcon;

  // user state
  final GameStatus? status;
  final double rating; // 0 = unrated, 0.5 steps up to 5
  final double hoursPlayed;
  final double targetHours; // 0 = no target
  final GamePlatform? playedOn;
  final double purchasePrice; // 0 = unknown
  final DateTime? dateAdded;

  bool get inLibrary => status != null;
  double get progress =>
      targetHours <= 0 ? 0 : (hoursPlayed / targetHours).clamp(0.0, 1.0).toDouble();
  double? get costPerHour =>
      (purchasePrice <= 0 || hoursPlayed <= 0) ? null : purchasePrice / hoursPlayed;

  Game copyWith({
    GameStatus? status,
    double? rating,
    double? hoursPlayed,
    double? targetHours,
    GamePlatform? playedOn,
    double? purchasePrice,
    DateTime? dateAdded,
  }) =>
      Game(
        id: id,
        title: title,
        publisher: publisher,
        developer: developer,
        releaseYear: releaseYear,
        platforms: platforms,
        genres: genres,
        synopsis: synopsis,
        coverColors: coverColors,
        coverIcon: coverIcon,
        status: status ?? this.status,
        rating: rating ?? this.rating,
        hoursPlayed: hoursPlayed ?? this.hoursPlayed,
        targetHours: targetHours ?? this.targetHours,
        playedOn: playedOn ?? this.playedOn,
        purchasePrice: purchasePrice ?? this.purchasePrice,
        dateAdded: dateAdded ?? this.dateAdded,
      );
}

/// One play session.
@immutable
class LogEntry {
  const LogEntry({
    required this.id,
    required this.gameId,
    required this.timestamp,
    required this.hours,
    required this.platform,
    this.note = '',
  });

  final String id;
  final String gameId;
  final DateTime timestamp;
  final double hours;
  final GamePlatform platform;
  final String note;
}

@immutable
class UserProfile {
  const UserProfile({
    required this.name,
    required this.handle,
    required this.bio,
    required this.joined,
    required this.weeklyGoalHours,
    this.followers = 248,
    this.following = 120,
  });

  final String name;
  final String handle;
  final String bio;
  final DateTime joined;
  final double weeklyGoalHours;
  final int followers; // mock
  final int following; // mock base; the store adds people followed in Search

  UserProfile copyWith({double? weeklyGoalHours}) => UserProfile(
        name: name,
        handle: handle,
        bio: bio,
        joined: joined,
        weeklyGoalHours: weeklyGoalHours ?? this.weeklyGoalHours,
        followers: followers,
        following: following,
      );
}

/// Another Checkpoint member (mock, no backend yet).
@immutable
class SocialUser {
  const SocialUser({
    required this.id,
    required this.name,
    required this.handle,
    required this.gamesLogged,
    required this.followers,
    this.startsFollowed = false,
  });
  final String id;
  final String name;
  final String handle;
  final int gamesLogged;
  final int followers;
  final bool startsFollowed;
}

/// Swap the icons for real brand logos once you add assets.
enum ConnectedService {
  steam('Steam', Icons.computer_rounded, Color(0xFF66C0F4)),
  psn('PSN', Icons.sports_esports_rounded, Color(0xFF5B8CFF)),
  xbox('Xbox', Icons.videogame_asset_rounded, Color(0xFF6CC24A));

  const ConnectedService(this.label, this.icon, this.color);
  final String label;
  final IconData icon;
  final Color color;
}

String fmtCount(int n) => n < 1000 ? '$n' : '${(n / 1000).toStringAsFixed(n < 10000 ? 1 : 0)}k';

abstract final class MockSocial {
  static const users = <SocialUser>[
    SocialUser(id: 'u1', name: 'Mara Lindqvist', handle: '@maraplays', gamesLogged: 312, followers: 4820, startsFollowed: true),
    SocialUser(id: 'u2', name: 'Jonas Weber', handle: '@jonasw', gamesLogged: 148, followers: 1260, startsFollowed: true),
    SocialUser(id: 'u3', name: 'Priya Nair', handle: '@priyaquests', gamesLogged: 421, followers: 9340),
    SocialUser(id: 'u4', name: 'Tomasz Kowal', handle: '@kowal.exe', gamesLogged: 96, followers: 310, startsFollowed: true),
    SocialUser(id: 'u5', name: 'Sofia Alvarez', handle: '@sofiaplaysslow', gamesLogged: 203, followers: 2175),
    SocialUser(id: 'u6', name: 'Kenji Mori', handle: '@kenjiloops', gamesLogged: 587, followers: 15200),
    SocialUser(id: 'u7', name: 'Hannah Cole', handle: '@cozyhannah', gamesLogged: 174, followers: 880),
    SocialUser(id: 'u8', name: 'Dmitri Volkov', handle: '@dmitri_gg', gamesLogged: 265, followers: 3640),
  ];
}

// ═════════════════════════════════════════════════════════════════════════════
//  3 · STATE  (ChangeNotifier + InheritedNotifier)
// ═════════════════════════════════════════════════════════════════════════════

/// Bottom-navigation destinations. Order must match `AppShell` destinations
/// and its `_screens` list.
abstract final class NavTab {
  static const home = 0;
  static const search = 1;
  static const library = 2;
  static const profile = 3;
}

enum LibraryView { grid, list }

enum SortField {
  dateAdded('Date Added'),
  rating('Rating'),
  hoursPlayed('Hours Played'),
  releaseYear('Release Year');

  const SortField(this.label);
  final String label;
}

class CheckpointStore extends ChangeNotifier {
  CheckpointStore({
    required List<Game> games,
    required List<LogEntry> logs,
    required UserProfile profile,
  })  : _games = List.of(games),
        _logs = List.of(logs)..sort((a, b) => b.timestamp.compareTo(a.timestamp)),
        _profile = profile;

  factory CheckpointStore.seeded() {
    final now = DateTime.now();
    final games = MockData.games(now);
    return CheckpointStore(
      games: games,
      logs: MockData.logs(games, now),
      profile: MockData.profile(),
    );
  }

  final List<Game> _games;
  final List<LogEntry> _logs; // always newest-first
  UserProfile _profile;
  int _logSeq = 1000;
  static final _epoch = DateTime.fromMillisecondsSinceEpoch(0);

  // ── navigation ─────────────────────────────────────────────────────────────
  // The store owns both levels of navigation so any widget can drive them:
  //   • currentBottomNavIndex  → which bottom-bar destination is visible (NavTab.*)
  //   • currentLibraryTabIndex → which status tab is open inside My Library
  //                              (index into GameStatus.values, same order as the TabBar)
  int _currentBottomNavIndex = NavTab.home;
  int _currentLibraryTabIndex = 0;

  int get currentBottomNavIndex => _currentBottomNavIndex;
  int get currentLibraryTabIndex => _currentLibraryTabIndex;
  GameStatus get currentLibraryStatus => GameStatus.values[_currentLibraryTabIndex];

  void setBottomNavIndex(int i) {
    if (i == _currentBottomNavIndex) return;
    _currentBottomNavIndex = i;
    notifyListeners();
  }

  /// Called by the Library's TabController when the user taps or swipes a tab,
  /// so the store never goes stale.
  void setLibraryTabIndex(int i) {
    if (i == _currentLibraryTabIndex) return;
    _currentLibraryTabIndex = i;
    notifyListeners();
  }

  /// THE navigation helper for stat cards: switches the bottom bar to My Library
  /// AND selects [status]'s tab, with a single `notifyListeners()`.
  ///
  /// • The platform filter is cleared, because stat-card counts are unfiltered —
  ///   otherwise "To Play 4" could land on a tab showing 1 game.
  /// • [sortBy] (optional) re-sorts high→low, for cards that aren't tied to one
  ///   status (e.g. hours → most-played first). Omit it to keep the current sort.
  void openLibraryTab(GameStatus status, {SortField? sortBy}) {
    _currentBottomNavIndex = NavTab.library;
    _currentLibraryTabIndex = GameStatus.values.indexOf(status);
    _platformFilter = null;
    if (sortBy != null) {
      _sortField = sortBy;
      _sortDescending = true;
    }
    notifyListeners();
  }

  // ── library view preferences ───────────────────────────────────────────────
  LibraryView _libraryView = LibraryView.grid;
  SortField _sortField = SortField.dateAdded;
  bool _sortDescending = true;
  GamePlatform? _platformFilter;

  LibraryView get libraryView => _libraryView;
  SortField get sortField => _sortField;
  bool get sortDescending => _sortDescending;
  GamePlatform? get platformFilter => _platformFilter;

  void setLibraryView(LibraryView v) {
    _libraryView = v;
    notifyListeners();
  }

  /// Picking the active field again flips the direction.
  void setSort(SortField f) {
    if (f == _sortField) {
      _sortDescending = !_sortDescending;
    } else {
      _sortField = f;
      _sortDescending = true;
    }
    notifyListeners();
  }

  void setPlatformFilter(GamePlatform? p) {
    _platformFilter = p;
    notifyListeners();
  }

    // ── auth (mock) ────────────────────────────────────────────────────────────
  bool _isLoggedIn = true; // set false to preview read-only mode
  bool get isLoggedIn => _isLoggedIn;

  void logIn() => _setLoggedIn(true);
  void logOut() => _setLoggedIn(false);

  void _setLoggedIn(bool v) {
    if (v == _isLoggedIn) return;
    _isLoggedIn = v;
    notifyListeners();
  }

  // ── social (mock) ──────────────────────────────────────────────────────────
  final Set<String> _followingIds = {
    for (final u in MockSocial.users)
      if (u.startsFollowed) u.id,
  };

  bool isFollowing(String userId) => _followingIds.contains(userId);
  int get followersCount => _profile.followers;
  int get followingCount => _profile.following + _followingIds.length;

  void toggleFollow(String userId) {
    if (!_isLoggedIn) return;
    if (!_followingIds.remove(userId)) _followingIds.add(userId);
    notifyListeners();
  }

  List<SocialUser> searchUsers(String query) {
    final q = query.trim().toLowerCase();
    return MockSocial.users
        .where((u) => q.isEmpty || '${u.name} ${u.handle}'.toLowerCase().contains(q))
        .toList()
      ..sort((a, b) => b.followers.compareTo(a.followers));
  }

  // Deterministic fake popularity so the Home lists look stable between runs.
  int _seed(Game g) => g.id.codeUnits.fold<int>(7, (s, c) => (s * 31 + c) & 0x7fffffff);

  List<Game> get popularThisMonth {
    final list = List.of(_games)
      ..sort((a, b) => ((_seed(b) * 37) % 101).compareTo((_seed(a) * 37) % 101));
    return list.take(10).toList();
  }

  List<Game> get trendingAmongFriends {
    final list = List.of(_games)
      ..sort((a, b) => ((_seed(b) * 53) % 97).compareTo((_seed(a) * 53) % 97));
    return list.take(10).toList();
  }

  String mockPlayersLabel(Game g) => '${12 + _seed(g) % 88}k playing';
  int mockFriendsPlaying(Game g) => 1 + _seed(g) % 5;

  // ── connected accounts (mock) ──────────────────────────────────────────────
  final Set<ConnectedService> _connected = {ConnectedService.steam};
  bool _isSyncing = false;

  bool get isSyncing => _isSyncing;
  int get connectedCount => _connected.length;
  bool isConnected(ConnectedService s) => _connected.contains(s);

  void toggleService(ConnectedService s) {
    if (!_connected.remove(s)) _connected.add(s);
    notifyListeners();
  }

  /// Mock sync: a 2 s spinner, no real import.
  Future<void> syncLibrary() async {
    if (_isSyncing || _connected.isEmpty) return;
    _isSyncing = true;
    notifyListeners();
    await Future<void>.delayed(const Duration(seconds: 2));
    _isSyncing = false;
    notifyListeners();
  }

  // ── reads ──────────────────────────────────────────────────────────────────
  List<Game> get games => List.unmodifiable(_games);
  UserProfile get profile => _profile;

  Game? maybeGame(String id) {
    for (final g in _games) {
      if (g.id == id) return g;
    }
    return null;
  }

  Game gameById(String id) => maybeGame(id)!;

  bool _matchesPlatform(Game g) {
    final p = _platformFilter;
    if (p == null) return true;
    return g.playedOn == p || (g.playedOn == null && g.platforms.contains(p));
  }

  int _compare(Game a, Game b) {
    final c = switch (_sortField) {
      SortField.dateAdded => (a.dateAdded ?? _epoch).compareTo(b.dateAdded ?? _epoch),
      SortField.rating => a.rating.compareTo(b.rating),
      SortField.hoursPlayed => a.hoursPlayed.compareTo(b.hoursPlayed),
      SortField.releaseYear => a.releaseYear.compareTo(b.releaseYear),
    };
    if (c != 0) return _sortDescending ? -c : c;
    return a.title.compareTo(b.title);
  }

  /// Library list for a tab — respects the active platform filter and sort.
  List<Game> libraryFor(GameStatus s) =>
      _games.where((g) => g.status == s && _matchesPlatform(g)).toList()..sort(_compare);

  /// Unfiltered, most-recently-played first (used by the Home hero).
  List<Game> playingNow() {
    final list = _games.where((g) => g.status == GameStatus.playing).toList();
    list.sort((a, b) => (lastPlayed(b.id) ?? _epoch).compareTo(lastPlayed(a.id) ?? _epoch));
    return list;
  }

  DateTime? lastPlayed(String gameId) {
    for (final l in _logs) {
      if (l.gameId == gameId) return l.timestamp;
    }
    return null;
  }

  List<LogEntry> logsFor(String gameId) => _logs.where((l) => l.gameId == gameId).toList();

  /// Newest session per distinct game.
  List<LogEntry> recentActivity({int limit = 10}) {
    final seen = <String>{};
    final out = <LogEntry>[];
    for (final l in _logs) {
      if (seen.add(l.gameId)) {
        out.add(l);
        if (out.length >= limit) break;
      }
    }
    return out;
  }

  // ── derived stats ──────────────────────────────────────────────────────────
  int count(GameStatus s) => _games.where((g) => g.status == s).length;
  double get totalHours => _games.fold<double>(0, (sum, g) => sum + g.hoursPlayed);

  double get hoursThisWeek {
    final cutoff = DateTime.now().subtract(const Duration(days: 7));
    return _logs.where((l) => l.timestamp.isAfter(cutoff)).fold<double>(0, (s, l) => s + l.hours);
  }

  double get averageRating {
    final rated = _games.where((g) => g.rating > 0).toList();
    if (rated.isEmpty) return 0;
    return rated.fold<double>(0, (s, g) => s + g.rating) / rated.length;
  }

  Map<GamePlatform, double> get hoursByPlatform {
    final m = <GamePlatform, double>{};
    for (final l in _logs) {
      m[l.platform] = (m[l.platform] ?? 0) + l.hours;
    }
    final entries = m.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    return Map.fromEntries(entries);
  }

  List<Game> get topRated {
    final rated = _games.where((g) => g.rating > 0).toList()
      ..sort((a, b) {
        final c = b.rating.compareTo(a.rating);
        return c != 0 ? c : b.hoursPlayed.compareTo(a.hoursPlayed);
      });
    return rated.take(8).toList();
  }

  // ── mutations ──────────────────────────────────────────────────────────────
  void _update(String id, Game Function(Game g) change) {
    final i = _games.indexWhere((g) => g.id == id);
    if (i < 0) return;
    _games[i] = change(_games[i]);
    notifyListeners();
  }

  void addToLibrary(String id, GameStatus status) => setStatus(id, status);

  void setStatus(String id, GameStatus status) => _update(
      id, (g) => g.copyWith(status: status, dateAdded: g.dateAdded ?? DateTime.now()));

  void setRating(String id, double rating) => _update(id, (g) => g.copyWith(rating: rating));

  void setPlayedOn(String id, GamePlatform platform) =>
      _update(id, (g) => g.copyWith(playedOn: platform));

  /// 0 (or empty field) clears the price.
  void setPurchasePrice(String id, double price) =>
      _update(id, (g) => g.copyWith(purchasePrice: math.max(0, price)));

  void setWeeklyGoal(double hours) {
    _profile = _profile.copyWith(weeklyGoalHours: hours.clamp(1.0, 120.0).toDouble());
    notifyListeners();
  }

  GameStatus _statusAfterLogging(GameStatus? s) =>
      s == GameStatus.completed ? GameStatus.completed : GameStatus.playing;

  /// Adds a session of [hours] on [platform] (defaults to last/first platform).
  void logSession({
    required String gameId,
    required double hours,
    GamePlatform? platform,
    String note = '',
  }) {
    if (hours <= 0) return;
    final g = gameById(gameId);
    final p = platform ?? g.playedOn ?? g.platforms.first;
    _logs.insert(
      0,
      LogEntry(
        id: 'log-${_logSeq++}',
        gameId: gameId,
        timestamp: DateTime.now(),
        hours: hours,
        platform: p,
        note: note.trim(),
      ),
    );
    _update(
      gameId,
      (cur) => cur.copyWith(
        hoursPlayed: cur.hoursPlayed + hours,
        playedOn: p,
        status: _statusAfterLogging(cur.status),
        dateAdded: cur.dateAdded ?? DateTime.now(),
      ),
    );
  }

  /// "Log Hours" modal: set the new total + target. A positive change is
  /// recorded as a session so activity and platform stats stay consistent.
  void updateTime({
    required String gameId,
    required double totalHours,
    required double targetHours,
    GamePlatform? platform,
    String note = '',
  }) {
    final g = gameById(gameId);
    final delta = totalHours - g.hoursPlayed;
    final p = platform ?? g.playedOn ?? g.platforms.first;
    if (delta > 0.01) {
      _logs.insert(
        0,
        LogEntry(
          id: 'log-${_logSeq++}',
          gameId: gameId,
          timestamp: DateTime.now(),
          hours: delta,
          platform: p,
          note: note.trim(),
        ),
      );
    }
    _update(
      gameId,
      (cur) => cur.copyWith(
        hoursPlayed: totalHours,
        targetHours: targetHours,
        playedOn: platform ?? cur.playedOn,
        status: delta > 0.01 ? _statusAfterLogging(cur.status) : cur.status,
        dateAdded: cur.dateAdded ?? DateTime.now(),
      ),
    );
  }
}

class StoreScope extends InheritedNotifier<CheckpointStore> {
  const StoreScope({super.key, required CheckpointStore store, required super.child})
      : super(notifier: store);

  /// Subscribes the caller to changes.
  static CheckpointStore of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<StoreScope>()!.notifier!;

  /// No subscription — for event handlers and initState.
  static CheckpointStore read(BuildContext context) =>
      (context.getElementForInheritedWidgetOfExactType<StoreScope>()!.widget as StoreScope)
          .notifier!;
}

extension StoreContext on BuildContext {
  CheckpointStore get store => StoreScope.of(this);
  CheckpointStore get actions => StoreScope.read(this);
}

// ═════════════════════════════════════════════════════════════════════════════
//  4 · MOCK DATA
// ═════════════════════════════════════════════════════════════════════════════

abstract final class MockData {
  static UserProfile profile() => UserProfile(
        name: 'Alex Nowak',
        handle: '@alexplays',
        bio: 'Soulslikes by day, cozy farms by night. Professional To Play list optimist.',
        joined: DateTime(2023, 3, 14),
        weeklyGoalHours: 20,
      );

  static List<Game> games(DateTime now) {
    DateTime ago(int days) => now.subtract(Duration(days: days));
    return [
      // ── Playing ──
      Game(
        id: 'elden-ring',
        title: 'Elden Ring',
        publisher: 'Bandai Namco',
        developer: 'FromSoftware',
        releaseYear: 2022,
        platforms: const [GamePlatform.pc, GamePlatform.steamDeck, GamePlatform.ps5, GamePlatform.ps4, GamePlatform.xbox],
        genres: const ['Action RPG', 'Open World'],
        synopsis: 'Wander a vast, broken realm, build your own champion and topple demigods in a world full of secrets.',
        coverColors: const [Color(0xFFB8860B), Color(0xFF1A1206)],
        coverIcon: Icons.auto_awesome_rounded,
        status: GameStatus.playing,
        hoursPlayed: 24,
        targetHours: 80,
        playedOn: GamePlatform.ps5,
        purchasePrice: 59.99,
        dateAdded: ago(40),
      ),
      Game(
        id: 'bg3',
        title: "Baldur's Gate 3",
        publisher: 'Larian Studios',
        developer: 'Larian Studios',
        releaseYear: 2023,
        platforms: const [GamePlatform.pc, GamePlatform.steamDeck, GamePlatform.ps5, GamePlatform.xbox],
        genres: const ['RPG', 'Turn-based'],
        synopsis: 'Gather a party, choose your origin and let dice and dialogue decide the fate of a sprawling fantasy saga.',
        coverColors: const [Color(0xFF7B2FBE), Color(0xFF12061F)],
        coverIcon: Icons.casino_rounded,
        status: GameStatus.playing,
        hoursPlayed: 41.5,
        targetHours: 100,
        playedOn: GamePlatform.pc,
        purchasePrice: 59.99,
        dateAdded: ago(75),
      ),
      Game(
        id: 'silksong',
        title: 'Hollow Knight: Silksong',
        publisher: 'Team Cherry',
        developer: 'Team Cherry',
        releaseYear: 2025,
        platforms: const [GamePlatform.pc, GamePlatform.steamDeck, GamePlatform.nswitch, GamePlatform.ps5, GamePlatform.xbox],
        genres: const ['Metroidvania', 'Platformer'],
        synopsis: 'Climb through a silk-spun kingdom as a nimble hunter in a hand-drawn, brutally charming adventure.',
        coverColors: const [Color(0xFFC62F4A), Color(0xFF1B0509)],
        coverIcon: Icons.bolt_rounded,
        status: GameStatus.playing,
        hoursPlayed: 9,
        targetHours: 35,
        playedOn: GamePlatform.steamDeck,
        purchasePrice: 19.99,
        dateAdded: ago(25),
      ),

      // ── Completed ──
      Game(
        id: 'hades',
        title: 'Hades',
        publisher: 'Supergiant Games',
        developer: 'Supergiant Games',
        releaseYear: 2020,
        platforms: const [GamePlatform.pc, GamePlatform.steamDeck, GamePlatform.nswitch, GamePlatform.ps5, GamePlatform.ps4, GamePlatform.xbox],
        genres: const ['Roguelike', 'Action'],
        synopsis: 'Fight out of the underworld again and again in a fast, stylish roguelike where every escape attempt tells a story.',
        coverColors: const [Color(0xFFD9381E), Color(0xFF260707)],
        coverIcon: Icons.local_fire_department_rounded,
        status: GameStatus.completed,
        rating: 5,
        hoursPlayed: 62,
        targetHours: 62,
        playedOn: GamePlatform.nswitch,
        purchasePrice: 24.99,
        dateAdded: ago(420),
      ),
      Game(
        id: 'celeste',
        title: 'Celeste',
        publisher: 'Maddy Makes Games',
        developer: 'Maddy Makes Games',
        releaseYear: 2018,
        platforms: const [GamePlatform.pc, GamePlatform.steamDeck, GamePlatform.nswitch, GamePlatform.ps4, GamePlatform.xbox],
        genres: const ['Platformer', 'Indie'],
        synopsis: 'Scale a haunted mountain in a precise, heartfelt platformer about anxiety, persistence and pixel-perfect jumps.',
        coverColors: const [Color(0xFF3DCBB1), Color(0xFF241A5E)],
        coverIcon: Icons.landscape_rounded,
        status: GameStatus.completed,
        rating: 4.5,
        hoursPlayed: 14,
        targetHours: 14,
        playedOn: GamePlatform.nswitch,
        purchasePrice: 19.99,
        dateAdded: ago(610),
      ),
      Game(
        id: 'hollow-knight',
        title: 'Hollow Knight',
        publisher: 'Team Cherry',
        developer: 'Team Cherry',
        releaseYear: 2017,
        platforms: const [GamePlatform.pc, GamePlatform.steamDeck, GamePlatform.nswitch, GamePlatform.ps4, GamePlatform.xbox],
        genres: const ['Metroidvania', 'Indie'],
        synopsis: 'Descend into a ruined insect kingdom and map its caverns, bosses and lonely melodies.',
        coverColors: const [Color(0xFF455A64), Color(0xFF05090B)],
        coverIcon: Icons.nightlight_round,
        status: GameStatus.completed,
        rating: 5,
        hoursPlayed: 48,
        targetHours: 48,
        playedOn: GamePlatform.pc,
        purchasePrice: 14.99,
        dateAdded: ago(900),
      ),
      Game(
        id: 'stardew',
        title: 'Stardew Valley',
        publisher: 'ConcernedApe',
        developer: 'ConcernedApe',
        releaseYear: 2016,
        platforms: const [GamePlatform.pc, GamePlatform.steamDeck, GamePlatform.nswitch, GamePlatform.ps4, GamePlatform.xbox, GamePlatform.mobile],
        genres: const ['Farming Sim', 'Cozy'],
        synopsis: 'Inherit a run-down farm and slowly turn it, and your relationships in town, into something thriving.',
        coverColors: const [Color(0xFF7CB342), Color(0xFF14260A)],
        coverIcon: Icons.agriculture_rounded,
        status: GameStatus.completed,
        rating: 4.5,
        hoursPlayed: 126,
        targetHours: 126,
        playedOn: GamePlatform.nswitch,
        purchasePrice: 14.99,
        dateAdded: ago(1100),
      ),
      Game(
        id: 'outer-wilds',
        title: 'Outer Wilds',
        publisher: 'Annapurna Interactive',
        developer: 'Mobius Digital',
        releaseYear: 2019,
        platforms: const [GamePlatform.pc, GamePlatform.ps4, GamePlatform.xbox],
        genres: const ['Exploration', 'Mystery'],
        synopsis: 'Explore a tiny solar system stuck in a 22-minute time loop and piece together an ancient mystery.',
        coverColors: const [Color(0xFFEF8A2A), Color(0xFF1C0E29)],
        coverIcon: Icons.rocket_launch_rounded,
        status: GameStatus.completed,
        rating: 5,
        hoursPlayed: 18,
        targetHours: 18,
        playedOn: GamePlatform.xbox,
        purchasePrice: 24.99,
        dateAdded: ago(500),
      ),

      // ── To Play ──
      Game(
        id: 'totk',
        title: 'The Legend of Zelda: Tears of the Kingdom',
        publisher: 'Nintendo',
        developer: 'Nintendo EPD',
        releaseYear: 2023,
        platforms: const [GamePlatform.nswitch],
        genres: const ['Adventure', 'Open World'],
        synopsis: 'Take to the skies and caverns of Hyrule and invent your own solutions with a toolbox of strange abilities.',
        coverColors: const [Color(0xFF2E9E6B), Color(0xFF08261B)],
        coverIcon: Icons.explore_rounded,
        status: GameStatus.toPlay,
        targetHours: 100,
        purchasePrice: 69.99,
        dateAdded: ago(210),
      ),
      Game(
        id: 'gow-ragnarok',
        title: 'God of War Ragnarök',
        publisher: 'Sony Interactive Entertainment',
        developer: 'Santa Monica Studio',
        releaseYear: 2022,
        platforms: const [GamePlatform.ps5, GamePlatform.ps4, GamePlatform.pc],
        genres: const ['Action Adventure'],
        synopsis: 'A father and son face the end of the world across the nine realms in a cinematic, axe-swinging epic.',
        coverColors: const [Color(0xFF3B8BEB), Color(0xFF0A1830)],
        coverIcon: Icons.ac_unit_rounded,
        status: GameStatus.toPlay,
        hoursPlayed: 3,
        targetHours: 35,
        playedOn: GamePlatform.ps5,
        purchasePrice: 49.99,
        dateAdded: ago(330),
      ),
      Game(
        id: 'p5r',
        title: 'Persona 5 Royal',
        publisher: 'Atlus',
        developer: 'Atlus',
        releaseYear: 2019,
        platforms: const [GamePlatform.pc, GamePlatform.steamDeck, GamePlatform.ps5, GamePlatform.ps4, GamePlatform.xbox, GamePlatform.nswitch],
        genres: const ['JRPG', 'Social Sim'],
        synopsis: 'Lead a band of phantom thieves by night and survive high-school life by day in a stylish, jazzy JRPG.',
        coverColors: const [Color(0xFFE5173F), Color(0xFF0D0003)],
        coverIcon: Icons.theater_comedy_rounded,
        status: GameStatus.toPlay,
        targetHours: 100,
        purchasePrice: 39.99,
        dateAdded: ago(150),
      ),
      Game(
        id: 'alan-wake-2',
        title: 'Alan Wake 2',
        publisher: 'Epic Games Publishing',
        developer: 'Remedy Entertainment',
        releaseYear: 2023,
        platforms: const [GamePlatform.pc, GamePlatform.ps5, GamePlatform.xbox],
        genres: const ['Survival Horror', 'Thriller'],
        synopsis: 'Two investigators, one nightmare: a layered horror story where writing the plot might change reality.',
        coverColors: const [Color(0xFF2B6F5E), Color(0xFF050D0B)],
        coverIcon: Icons.search_rounded,
        status: GameStatus.toPlay,
        targetHours: 20,
        purchasePrice: 59.99,
        dateAdded: ago(95),
      ),

      // ── Dropped ──
      Game(
        id: 'cyberpunk',
        title: 'Cyberpunk 2077',
        publisher: 'CD Projekt',
        developer: 'CD Projekt Red',
        releaseYear: 2020,
        platforms: const [GamePlatform.pc, GamePlatform.steamDeck, GamePlatform.ps5, GamePlatform.xbox],
        genres: const ['Action RPG', 'Open World'],
        synopsis: 'Hustle through Night City as a mercenary with a mysterious chip in your head and a ticking clock.',
        coverColors: const [Color(0xFFF2E600), Color(0xFF2A0B3F)],
        coverIcon: Icons.flare_rounded,
        status: GameStatus.dropped,
        rating: 3,
        hoursPlayed: 11,
        targetHours: 60,
        playedOn: GamePlatform.pc,
        purchasePrice: 29.99,
        dateAdded: ago(700),
      ),
      Game(
        id: 'rdr2',
        title: 'Red Dead Redemption 2',
        publisher: 'Rockstar Games',
        developer: 'Rockstar Games',
        releaseYear: 2018,
        platforms: const [GamePlatform.pc, GamePlatform.ps4, GamePlatform.xbox],
        genres: const ['Action Adventure', 'Open World'],
        synopsis: 'Ride with a gang of outlaws through a fading Wild West in a slow-burn, meticulously detailed epic.',
        coverColors: const [Color(0xFFB5542B), Color(0xFF200D07)],
        coverIcon: Icons.park_rounded,
        status: GameStatus.dropped,
        rating: 3.5,
        hoursPlayed: 9,
        targetHours: 60,
        playedOn: GamePlatform.ps4,
        purchasePrice: 39.99,
        dateAdded: ago(800),
      ),

      // ── Wishlist ──
      Game(
        id: 'clair-obscur',
        title: 'Clair Obscur: Expedition 33',
        publisher: 'Kepler Interactive',
        developer: 'Sandfall Interactive',
        releaseYear: 2025,
        platforms: const [GamePlatform.pc, GamePlatform.ps5, GamePlatform.xbox],
        genres: const ['RPG', 'Turn-based'],
        synopsis: 'A painterly, turn-based RPG about an expedition racing to stop a curse that erases a new age each year.',
        coverColors: const [Color(0xFF8E7CC3), Color(0xFF17142B)],
        coverIcon: Icons.auto_awesome_rounded,
        status: GameStatus.wishlist,
        targetHours: 40,
        dateAdded: ago(20),
      ),
      Game(
        id: 'sekiro',
        title: 'Sekiro: Shadows Die Twice',
        publisher: 'Activision',
        developer: 'FromSoftware',
        releaseYear: 2019,
        platforms: const [GamePlatform.pc, GamePlatform.steamDeck, GamePlatform.ps4, GamePlatform.xbox],
        genres: const ['Action', 'Soulslike'],
        synopsis: 'A one-armed shinobi in a crumbling Sengoku Japan, where posture and parry decide every duel.',
        coverColors: const [Color(0xFFD6502B), Color(0xFF14110F)],
        coverIcon: Icons.sports_martial_arts_rounded,
        status: GameStatus.wishlist,
        targetHours: 40,
        dateAdded: ago(12),
      ),

      // ── Catalog only (Discover) ──
      Game(
        id: 'balatro',
        title: 'Balatro',
        publisher: 'Playstack',
        developer: 'LocalThunk',
        releaseYear: 2024,
        platforms: const [GamePlatform.pc, GamePlatform.steamDeck, GamePlatform.nswitch, GamePlatform.ps5, GamePlatform.xbox, GamePlatform.mobile],
        genres: const ['Roguelike', 'Card Game'],
        synopsis: 'Build absurdly powerful poker hands with jokers that bend every rule in this addictive deckbuilder.',
        coverColors: const [Color(0xFF2E7D6B), Color(0xFF3B0F2E)],
        coverIcon: Icons.casino_rounded,
      ),
      Game(
        id: 'disco-elysium',
        title: 'Disco Elysium',
        publisher: 'ZA/UM',
        developer: 'ZA/UM',
        releaseYear: 2019,
        platforms: const [GamePlatform.pc, GamePlatform.steamDeck, GamePlatform.ps5, GamePlatform.ps4, GamePlatform.xbox, GamePlatform.nswitch],
        genres: const ['RPG', 'Mystery'],
        synopsis: 'A washed-up detective with a fractured mind and a talkative skill set investigates a murder in a decaying port city.',
        coverColors: const [Color(0xFFE0A030), Color(0xFF3A1B2B)],
        coverIcon: Icons.psychology_rounded,
      ),
      Game(
        id: 'vampire-survivors',
        title: 'Vampire Survivors',
        publisher: 'poncle',
        developer: 'poncle',
        releaseYear: 2022,
        platforms: const [GamePlatform.pc, GamePlatform.steamDeck, GamePlatform.nswitch, GamePlatform.ps5, GamePlatform.xbox, GamePlatform.mobile],
        genres: const ['Roguelike', 'Action'],
        synopsis: 'Survive endless gothic hordes with weapons that fire themselves, until the screen is pure chaos.',
        coverColors: const [Color(0xFF8E1B3A), Color(0xFF0E0B1F)],
        coverIcon: Icons.nightlight_round,
      ),
    ];
  }

  /// Splits each game's hours into plausible past sessions so that the sum of
  /// a game's logs equals its `hoursPlayed`.
  static List<LogEntry> logs(List<Game> games, DateTime now) {
    final out = <LogEntry>[];
    var seq = 0;
    for (var i = 0; i < games.length; i++) {
      final g = games[i];
      if (g.hoursPlayed <= 0) continue;
      final count = g.hoursPlayed > 40 ? 5 : (g.hoursPlayed > 10 ? 4 : 3);
      var remaining = g.hoursPlayed;
      final base = g.status == GameStatus.playing ? i % 3 : 4 + i * 3;
      for (var k = 0; k < count; k++) {
        final isLast = k == count - 1;
        var share = isLast
            ? remaining
            : ((g.hoursPlayed / count * (0.8 + 0.2 * ((i + k) % 3))) * 2).round() / 2;
        if (!isLast) {
          share = share.clamp(0.5, remaining - 0.5 * (count - 1 - k)).toDouble();
        }
        remaining -= share;
        final platform = (k.isOdd && g.platforms.length > 1 && i.isEven)
            ? g.platforms.first
            : (g.playedOn ?? g.platforms.first);
        out.add(LogEntry(
          id: 'seed-${seq++}',
          gameId: g.id,
          timestamp: now.subtract(Duration(days: base + (count - 1 - k) * 6, hours: (i * 5 + k * 3) % 20)),
          hours: share,
          platform: platform,
          note: k == 0 && isLast ? '' : (k == count - 2 ? 'Finally beat that boss' : ''),
        ));
      }
    }
    return out;
  }
}

// ═════════════════════════════════════════════════════════════════════════════
//  5 · HELPERS
// ═════════════════════════════════════════════════════════════════════════════

String fmtHours(double h) => (h - h.roundToDouble()).abs() < 0.05 ? h.round().toString() : h.toStringAsFixed(1);
String fmtMoney(double v) => '\$${v.toStringAsFixed(2)}';
double? parseNum(String s) => double.tryParse(s.trim().replaceAll(',', '.'));

String timeAgo(DateTime t) {
  final d = DateTime.now().difference(t);
  if (d.inMinutes < 60) return '${math.max(1, d.inMinutes)}m ago';
  if (d.inHours < 24) return '${d.inHours}h ago';
  if (d.inDays < 7) return '${d.inDays}d ago';
  if (d.inDays < 60) return '${d.inDays ~/ 7}w ago';
  return '${d.inDays ~/ 30}mo ago';
}

String initials(String name) => name
    .trim()
    .split(RegExp(r'\s+'))
    .where((p) => p.isNotEmpty)
    .take(2)
    .map((p) => p[0].toUpperCase())
    .join();

String greeting() {
  final h = DateTime.now().hour;
  if (h < 5) return 'Late night';
  if (h < 12) return 'Good morning';
  if (h < 18) return 'Good afternoon';
  return 'Good evening';
}

void openGame(BuildContext context, String id) =>
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => GameDetailScreen(gameId: id)));

double _textScale(BuildContext context) =>
    MediaQuery.textScalerOf(context).scale(1).clamp(1.0, 1.3).toDouble();

double posterCardHeight(BuildContext context, double width, {required bool subtitle}) =>
    width * 1.5 + 14 + (18 + 6 + 16 + (subtitle ? 18 : 0)) * _textScale(context);

InputDecoration fieldDecoration(
  String label, {
  String? prefix,
  String? suffix,
  String? hint,
  Widget? prefixIcon,
  Widget? suffixIcon,
}) =>
    InputDecoration(
      labelText: label,
      hintText: hint,
      prefixText: prefix,
      suffixText: suffix,
      prefixIcon: prefixIcon,
      suffixIcon: suffixIcon,
      filled: true,
      fillColor: Palette.surfaceHigh,
      labelStyle: const TextStyle(color: Palette.muted),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: Palette.accent, width: 1.5),
      ),
    );

final _decimalFormatter = FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'));
const _decimalKeyboard = TextInputType.numberWithOptions(decimal: true);

// ═════════════════════════════════════════════════════════════════════════════
//  6 · SHARED WIDGETS
// ═════════════════════════════════════════════════════════════════════════════

/// Pill selector with a high-contrast selected state:
/// solid accent fill + dark text/icon vs. dark surface + light text.
class AppChoiceChip extends StatelessWidget {
  const AppChoiceChip({
    super.key,
    required this.label,
    required this.selected,
    required this.onSelected,
    this.icon,
    this.iconColor,
  });
  final String label;
  final bool selected;
  final VoidCallback onSelected;
  final IconData? icon;
  final Color? iconColor; // icon tint when NOT selected

  @override
  Widget build(BuildContext context) {
    return ChoiceChip(
      showCheckmark: false,
      selected: selected,
      onSelected: (_) => onSelected(),
      backgroundColor: Palette.surfaceHigh,
      selectedColor: Palette.accent,
      shape: const StadiumBorder(),
      side: BorderSide(
        color: selected ? Palette.accent : Colors.white.withValues(alpha: 0.18),
        width: selected ? 1.5 : 1,
      ),
      avatar: icon == null
          ? null
          : Icon(icon, size: 18, color: selected ? Palette.onAccent : (iconColor ?? Palette.muted)),
      label: Text(
        label,
        style: TextStyle(
          fontSize: 13,
          fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
          color: selected ? Palette.onAccent : Colors.white70,
        ),
      ),
    );
  }
}

/// Poster art (2:3). Loads a mock network poster; the gradient + glyph
/// underneath is the loading / offline fallback.
class CoverArt extends StatelessWidget {
  const CoverArt({super.key, required this.game, this.radius = 12});
  final Game game;
  final double radius;

  /// Mock poster endpoint: a stable 2:3 image per game id.
  /// Swap for the real IGDB/RAWG cover URL when a backend is wired in.
  static String posterUrl(Game g) => 'https://picsum.photos/seed/${g.id}/400/600';

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: 2 / 3,
      child: LayoutBuilder(builder: (context, c) {
        final w = c.maxWidth;
        final showTitle = w >= 84;
        return ClipRRect(
          borderRadius: BorderRadius.circular(radius),
          child: Stack(fit: StackFit.expand, children: [
            // 1 · fallback (visible while loading or offline)
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: game.coverColors,
                ),
              ),
            ),
            Positioned(
              right: -w * 0.18,
              top: w * 0.10,
              child: Icon(game.coverIcon, size: w * 0.95, color: Colors.white.withValues(alpha: 0.14)),
            ),
            if (!showTitle) Center(child: Icon(game.coverIcon, size: w * 0.5, color: Colors.white70)),

            // 2 · network poster, fades in over the fallback
            Image(
              image: NetworkImage(posterUrl(game)),
              fit: BoxFit.cover,
              gaplessPlayback: true,
              frameBuilder: (context, child, frame, wasSynchronouslyLoaded) => AnimatedOpacity(
                opacity: (wasSynchronouslyLoaded || frame != null) ? 1 : 0,
                duration: const Duration(milliseconds: 300),
                child: child,
              ),
              errorBuilder: (_, __, ___) => const SizedBox.shrink(), // keep fallback
            ),

            // 3 · scrim + title
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Colors.transparent, Color(0xB3000000)],
                  stops: [0.45, 1],
                ),
              ),
            ),
            if (showTitle)
              Positioned(
                left: w * 0.08,
                right: w * 0.08,
                bottom: w * 0.08,
                child: Text(
                  game.title.toUpperCase(),
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.6,
                    height: 1.1,
                    fontSize: (w * 0.105).clamp(8.0, 18.0).toDouble(),
                    shadows: const [Shadow(color: Colors.black87, blurRadius: 6)],
                  ),
                ),
              ),
          ]),
        );
      }),
    );
  }
}

class StarRating extends StatelessWidget {
  const StarRating({super.key, required this.rating, this.size = 16, this.onChanged});
  final double rating;
  final double size;
  final ValueChanged<double>? onChanged; // null → read-only

  double _valueAt(double dx) {
    final raw = (dx / (size * 5)) * 5;
    return ((raw * 2).ceil() / 2).clamp(0.5, 5.0).toDouble();
  }

  void _emit(double dx) {
    final v = _valueAt(dx);
    if (v != rating) {
      HapticFeedback.selectionClick();
      onChanged!(v);
    }
  }

  @override
  Widget build(BuildContext context) {
    final stars = Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(5, (i) {
        final v = rating - i;
        final icon = v >= 1
            ? Icons.star_rounded
            : (v >= 0.5 ? Icons.star_half_rounded : Icons.star_outline_rounded);
        return Icon(icon, size: size, color: v > 0 ? Palette.star : Colors.white24);
      }),
    );
    if (onChanged == null) {
      return Semantics(label: '${fmtHours(rating)} out of 5 stars', child: stars);
    }
    return Semantics(
      label: 'Rating ${fmtHours(rating)} out of 5',
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (d) => _emit(d.localPosition.dx),
        onHorizontalDragUpdate: (d) => _emit(d.localPosition.dx),
        child: SizedBox(width: size * 5, height: size, child: stars),
      ),
    );
  }
}

class Panel extends StatelessWidget {
  const Panel({super.key, required this.child, this.title, this.trailing, this.padding = const EdgeInsets.all(16)});
  final Widget child;
  final String? title;
  final Widget? trailing;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: padding,
      decoration: BoxDecoration(
        color: Palette.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (title != null) ...[
            Row(children: [
              Expanded(
                child: Text(title!, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
              ),
              if (trailing != null) trailing!,
            ]),
            const SizedBox(height: 14),
          ],
          child,
        ],
      ),
    );
  }
}

class SectionHeader extends StatelessWidget {
  const SectionHeader(this.title, {super.key, this.actionLabel, this.onAction});
  final String title;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 24, 12, 12),
      child: Row(children: [
        Expanded(child: Text(title, style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w800))),
        if (actionLabel != null) TextButton(onPressed: onAction, child: Text(actionLabel!)),
      ]),
    );
  }
}

class EmptyState extends StatelessWidget {
  const EmptyState({super.key, required this.icon, required this.title, required this.message, this.actionLabel, this.onAction});
  final IconData icon;
  final String title;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(32),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            width: 72,
            height: 72,
            decoration: const BoxDecoration(color: Palette.surfaceHigh, shape: BoxShape.circle),
            child: Icon(icon, color: Palette.accent, size: 32),
          ),
          const SizedBox(height: 16),
          Text(title, textAlign: TextAlign.center, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          Text(message, textAlign: TextAlign.center, style: const TextStyle(color: Palette.muted, height: 1.35)),
          if (actionLabel != null) ...[
            const SizedBox(height: 16),
            FilledButton.tonal(onPressed: onAction, child: Text(actionLabel!)),
          ],
        ]),
      ),
    );
  }
}

class StatusPill extends StatelessWidget {
  const StatusPill(this.status, {super.key});
  final GameStatus status;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: status.color.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(status.icon, size: 14, color: status.color),
        const SizedBox(width: 5),
        Text(status.label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: status.color)),
      ]),
    );
  }
}

class PlatformBadge extends StatelessWidget {
  const PlatformBadge(this.platform, {super.key, this.dense = false});
  final GamePlatform platform;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: dense ? 7 : 9, vertical: dense ? 3 : 4),
      decoration: BoxDecoration(
        color: platform.color.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(platform.icon, size: dense ? 12 : 14, color: platform.color),
        const SizedBox(width: 5),
        Text(platform.label,
            style: TextStyle(fontSize: dense ? 11 : 12, fontWeight: FontWeight.w600, color: platform.color)),
      ]),
    );
  }
}

/// "Which platform did you play on?" selector.
class PlatformChips extends StatelessWidget {
  const PlatformChips({super.key, required this.platforms, required this.selected, required this.onSelected});
  final List<GamePlatform> platforms;
  final GamePlatform? selected;
  final ValueChanged<GamePlatform> onSelected;

  @override
  Widget build(BuildContext context) {
    return Wrap(spacing: 8, runSpacing: 8, children: [
      for (final p in platforms)
        AppChoiceChip(
          label: p.label,
          icon: p.icon,
          iconColor: p.color,
          selected: selected == p,
          onSelected: () {
            HapticFeedback.selectionClick();
            onSelected(p);
          },
        ),
    ]);
  }
}

/// Summary card. Pass [onTap] to make the whole card tappable (ripple + chevron).
class StatTile extends StatelessWidget {
  const StatTile({super.key, required this.icon, required this.value, required this.label, this.onTap});
  final IconData icon;
  final String value;
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final tap = onTap;
    return Material(
      color: Palette.surface,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: Colors.white.withValues(alpha: 0.06)),
      ),
      child: InkWell(
        splashColor: Palette.accent.withValues(alpha: 0.14),
        highlightColor: Palette.accent.withValues(alpha: 0.06),
        onTap: tap == null
            ? null
            : () {
                HapticFeedback.selectionClick();
                tap();
              },
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Icon(icon, size: 20, color: Palette.accent),
              const Spacer(),
              if (tap != null) const Icon(Icons.chevron_right_rounded, size: 20, color: Palette.muted),
            ]),
            const SizedBox(height: 10),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(value, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
            ),
            const SizedBox(height: 2),
            Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, color: Palette.muted)),
          ]),
        ),
      ),
    );
  }
}

/// Poster + title + stars (+ optional caption). Used in horizontal carousels.
class GamePosterCard extends StatelessWidget {
  const GamePosterCard({super.key, required this.game, required this.width, this.subtitle, this.subtitleIcon});
  final Game game;
  final double width;
  final String? subtitle;
  final IconData? subtitleIcon;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => openGame(context, game.id),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
          CoverArt(game: game),
          const SizedBox(height: 8),
          Text(game.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
          const SizedBox(height: 4),
          game.rating > 0
              ? StarRating(rating: game.rating, size: 14)
              : const Text('Not rated', style: TextStyle(fontSize: 11, color: Palette.muted)),
          if (subtitle != null) ...[
            const SizedBox(height: 4),
            Row(children: [
              if (subtitleIcon != null) ...[
                Icon(subtitleIcon, size: 12, color: Palette.muted),
                const SizedBox(width: 4),
              ],
              Expanded(
                child: Text(subtitle!, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11, color: Palette.muted)),
              ),
            ]),
          ],
        ]),
      ),
    );
  }
}

class SheetFrame extends StatelessWidget {
  const SheetFrame({super.key, required this.title, this.subtitle, required this.child});
  final String title;
  final String? subtitle;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final keyboard = MediaQuery.viewInsetsOf(context).bottom;
    final safe = MediaQuery.paddingOf(context).bottom;
    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(20, 4, 20, math.max(keyboard, safe) + 20),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(title, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
        if (subtitle != null) ...[
          const SizedBox(height: 4),
          Text(subtitle!, style: const TextStyle(color: Palette.muted)),
        ],
        const SizedBox(height: 18),
        child,
      ]),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
//  7 · APP SHELL & NAVIGATION
// ═════════════════════════════════════════════════════════════════════════════

class CheckpointApp extends StatefulWidget {
  const CheckpointApp({super.key});

  @override
  State<CheckpointApp> createState() => _CheckpointAppState();
}

class _CheckpointAppState extends State<CheckpointApp> {
  late final CheckpointStore _store = CheckpointStore.seeded();

  @override
  void dispose() {
    _store.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // StoreScope sits above MaterialApp so pushed routes and sheets can read it.
    return StoreScope(
      store: _store,
      child: MaterialApp(
        title: 'Checkpoint',
        debugShowCheckedModeBanner: false,
        theme: buildTheme(),
        builder: (context, child) => MediaQuery.withClampedTextScaling(
          minScaleFactor: 0.9,
          maxScaleFactor: 1.3,
          child: child!,
        ),
        home: const AppShell(),
      ),
    );
  }
}

class AppShell extends StatelessWidget {
  const AppShell({super.key});

  static const _screens = <Widget>[
    HomeScreen(),
    SearchScreen(),
    AuthGate(child: LibraryScreen()),
    AuthGate(child: ProfileScreen()),
  ];

  @override
  Widget build(BuildContext context) {
    final store = context.store;
    final navIndex = store.currentBottomNavIndex;
    return PopScope(
      canPop: navIndex == NavTab.home,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) context.actions.setBottomNavIndex(NavTab.home);
      },
      child: Scaffold(
        body: IndexedStack(index: navIndex, children: _screens),
        floatingActionButton: navIndex == NavTab.home && store.isLoggedIn
            ? FloatingActionButton.extended(
                onPressed: () => showQuickLogSheet(context),
                icon: const Icon(Icons.add_rounded),
                label: const Text('Log Game'),
              )
            : null,
        bottomNavigationBar: NavigationBar(
          selectedIndex: navIndex,
          onDestinationSelected: (i) {
            FocusManager.instance.primaryFocus?.unfocus();
            context.actions.setBottomNavIndex(i);
          },
          destinations: const [
            NavigationDestination(icon: Icon(Icons.home_outlined), selectedIcon: Icon(Icons.home_rounded), label: 'Home'),
            NavigationDestination(icon: Icon(Icons.search_rounded), selectedIcon: Icon(Icons.search_rounded), label: 'Search'),
            NavigationDestination(icon: Icon(Icons.collections_bookmark_outlined), selectedIcon: Icon(Icons.collections_bookmark_rounded), label: 'My Library'),
            NavigationDestination(icon: Icon(Icons.person_outline_rounded), selectedIcon: Icon(Icons.person_rounded), label: 'Profile'),
          ],
        ),
      ),
    );
  }
}

/// Read-only overlay. The child stays mounted underneath, so the Library's
/// TabController and scroll state survive logging in and out.
class AuthGate extends StatelessWidget {
  const AuthGate({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final loggedIn = context.store.isLoggedIn;
    return Stack(children: [
      Positioned.fill(child: child),
      if (!loggedIn)
        Positioned.fill(
          child: ColoredBox(
            color: Palette.background.withValues(alpha: 0.94),
            child: SafeArea(
              child: EmptyState(
                icon: Icons.lock_outline_rounded,
                title: 'Log in to track games',
                message: 'You can still browse and search. Log in to build your library and log your hours.',
                actionLabel: 'Log in',
                onAction: context.actions.logIn,
              ),
            ),
          ),
        ),
    ]);
  }
}

// ═════════════════════════════════════════════════════════════════════════════
//  8 · HOME (DASHBOARD)
// ═════════════════════════════════════════════════════════════════════════════

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final store = context.store;
    return SafeArea(
      bottom: false,
      child: ListView(
        padding: const EdgeInsets.only(bottom: 112),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 4),
            child: Row(children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('${greeting()},', style: const TextStyle(color: Palette.muted, fontSize: 15)),
                  Text(store.profile.name.split(' ').first,
                      style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w800)),
                ]),
              ),
              GestureDetector(
                onTap: () => context.actions.setBottomNavIndex(NavTab.profile),
                child: ProfileAvatar(name: store.profile.name, size: 44),
              ),
            ]),
          ),
          SectionHeader(
            'Currently Playing',
            actionLabel: 'See all',
            onAction: () => context.actions.openLibraryTab(GameStatus.playing),
          ),
          _HeroBanner(games: store.playingNow()),
          const SizedBox(height: 20),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(children: [
              Expanded(
                child: StatTile(
                  icon: Icons.schedule_rounded,
                  value: fmtHours(store.totalHours),
                  label: 'Hours logged',
                  onTap: () => context.actions.openLibraryTab(GameStatus.playing, sortBy: SortField.hoursPlayed),
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
          ),
          const SectionHeader('Recent Activity'),
          const _RecentActivityRow(),
                    const SectionHeader('Popular This Month'),
          _GameCarousel(
            games: store.popularThisMonth,
            icon: Icons.local_fire_department_rounded,
            caption: store.mockPlayersLabel,
          ),
          const SectionHeader('Trending Among Friends'),
          _GameCarousel(
            games: store.trendingAmongFriends,
            icon: Icons.group_rounded,
            caption: (g) {
              final n = store.mockFriendsPlaying(g);
              return '$n friend${n == 1 ? '' : 's'} playing';
            },
          ),
        ],
      ),
    );
  }
}

class _GameCarousel extends StatelessWidget {
  const _GameCarousel({required this.games, required this.caption, required this.icon});
  final List<Game> games;
  final String Function(Game) caption;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    const w = 124.0;
    return SizedBox(
      height: posterCardHeight(context, w, subtitle: true),
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        itemCount: games.length,
        separatorBuilder: (_, __) => const SizedBox(width: 14),
        itemBuilder: (_, i) => GamePosterCard(game: games[i], width: w, subtitle: caption(games[i]), subtitleIcon: icon),
      ),
    );
  }
}

class _HeroBanner extends StatefulWidget {
  const _HeroBanner({required this.games});
  final List<Game> games;

  @override
  State<_HeroBanner> createState() => _HeroBannerState();
}

class _HeroBannerState extends State<_HeroBanner> {
  final _controller = PageController(viewportFraction: 0.9);
  int _page = 0;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final games = widget.games;
    if (games.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: Panel(
          child: Row(children: [
            const Icon(Icons.hourglass_empty_rounded, color: Palette.muted),
            const SizedBox(width: 12),
            const Expanded(child: Text('Nothing in progress. Pick something from your To Play list.', style: TextStyle(color: Palette.muted))),
            TextButton(onPressed: () => context.actions.openLibraryTab(GameStatus.toPlay), child: const Text('To Play')),
          ]),
        ),
      );
    }
    final scale = _textScale(context);
    final page = _page.clamp(0, games.length - 1);
    return Column(children: [
      SizedBox(
        height: 196 + (scale - 1) * 120,
        child: PageView.builder(
          controller: _controller,
          itemCount: games.length,
          onPageChanged: (i) => setState(() => _page = i),
          itemBuilder: (_, i) => Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6),
            child: _HeroCard(game: games[i]),
          ),
        ),
      ),
      if (games.length > 1) ...[
        const SizedBox(height: 12),
        Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          for (var i = 0; i < games.length; i++)
            AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              margin: const EdgeInsets.symmetric(horizontal: 3),
              width: i == page ? 18 : 6,
              height: 6,
              decoration: BoxDecoration(
                color: i == page ? Palette.accent : Colors.white24,
                borderRadius: BorderRadius.circular(3),
              ),
            ),
        ]),
      ],
    ]);
  }
}

class _HeroCard extends StatelessWidget {
  const _HeroCard({required this.game});
  final Game game;

  @override
  Widget build(BuildContext context) {
    final platform = game.playedOn ?? game.platforms.first;
    return ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: Stack(fit: StackFit.expand, children: [
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: game.coverColors),
          ),
        ),
        Positioned(right: -30, top: -20, child: Icon(game.coverIcon, size: 220, color: Colors.white.withValues(alpha: 0.10))),
        const DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0x00000000), Color(0x99000000)],
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(16),
          child: Row(children: [
            SizedBox(width: 92, child: CoverArt(game: game)),
            const SizedBox(width: 14),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(game.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800, height: 1.15)),
                const SizedBox(height: 6),
                Row(children: [
                  Icon(platform.icon, size: 14, color: Colors.white70),
                  const SizedBox(width: 5),
                  Expanded(child: Text(platform.label, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white70, fontSize: 13))),
                ]),
                const Spacer(),
                Row(children: [
                  Expanded(
                    child: Text.rich(
                      TextSpan(children: [
                        TextSpan(text: '${fmtHours(game.hoursPlayed)} hrs', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 17)),
                        const TextSpan(text: ' logged', style: TextStyle(color: Colors.white70, fontSize: 13)),
                      ]),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  IconButton.filled(
                    tooltip: 'Log a session',
                    visualDensity: VisualDensity.compact,
                    onPressed: () => showQuickLogSheet(context, gameId: game.id),
                    icon: const Icon(Icons.add_rounded),
                  ),
                ]),
                const SizedBox(height: 6),
                ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: LinearProgressIndicator(
                    value: game.progress,
                    minHeight: 7,
                    color: Palette.accent,
                    backgroundColor: Colors.white24,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  game.targetHours > 0 ? '${(game.progress * 100).round()}% of ${fmtHours(game.targetHours)} hr target' : 'No target set',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 11, color: Colors.white70),
                ),
              ]),
            ),
          ]),
        ),
        Positioned.fill(
          child: Material(
            color: Colors.transparent,
            child: InkWell(onTap: () => openGame(context, game.id)),
          ),
        ),
      ]),
    );
  }
}

class _RecentActivityRow extends StatelessWidget {
  const _RecentActivityRow();

  @override
  Widget build(BuildContext context) {
    final store = context.store;
    final entries = store.recentActivity(limit: 10);
    if (entries.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(horizontal: 20),
        child: Panel(child: Text('Log your first session with the Log Game button.', style: TextStyle(color: Palette.muted))),
      );
    }
    const w = 124.0;
    return SizedBox(
      height: posterCardHeight(context, w, subtitle: true),
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        itemCount: entries.length,
        separatorBuilder: (_, __) => const SizedBox(width: 14),
        itemBuilder: (context, i) {
          final e = entries[i];
          return GamePosterCard(
            game: store.gameById(e.gameId),
            width: w,
            subtitle: '+${fmtHours(e.hours)}h · ${timeAgo(e.timestamp)}',
            subtitleIcon: e.platform.icon,
          );
        },
      ),
    );
  }
}

class ProfileAvatar extends StatelessWidget {
  const ProfileAvatar({super.key, required this.name, required this.size});
  final String name;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: const BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(colors: [Palette.accent, Palette.electric], begin: Alignment.topLeft, end: Alignment.bottomRight),
      ),
      child: Text(initials(name), style: TextStyle(color: Palette.onAccent, fontWeight: FontWeight.w800, fontSize: size * 0.38)),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
//  9 · SEARCH (DISCOVER)
// ═════════════════════════════════════════════════════════════════════════════

class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _GenreChipRow extends StatelessWidget {
  const _GenreChipRow({required this.genres, required this.selected, required this.onChanged});
  final List<String> genres;
  final String? selected;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 40,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        children: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: AppChoiceChip(label: 'All', selected: selected == null, onSelected: () => onChanged(null)),
          ),
          for (final g in genres)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: AppChoiceChip(
                label: g,
                selected: selected == g,
                onSelected: () => onChanged(selected == g ? null : g),
              ),
            ),
        ],
      ),
    );
  }
}

enum SearchKind { games, users }

class _SearchScreenState extends State<SearchScreen> {
  final _controller = TextEditingController();
  String _query = '';
  String? _genre;
  SearchKind _kind = SearchKind.games;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  List<Game> _filterGames(List<Game> all, String q) => all.where((g) {
        if (_genre != null && !g.genres.contains(_genre)) return false;
        if (q.isEmpty) return true;
        final hay = [g.title, g.publisher, g.developer, ...g.genres, ...g.platforms.map((p) => p.label)].join(' ').toLowerCase();
        return hay.contains(q);
      }).toList()
        ..sort((a, b) {
          final ai = a.inLibrary ? 1 : 0;
          final bi = b.inLibrary ? 1 : 0;
          if (ai != bi) return ai - bi; // new-to-you first
          return a.title.compareTo(b.title);
        });

  @override
  Widget build(BuildContext context) {
    final store = context.store;
    final isUsers = _kind == SearchKind.users;
    final all = store.games;
    final genres = ({for (final g in all) ...g.genres}.toList())..sort();
    final q = _query.trim().toLowerCase();

    final games = isUsers ? const <Game>[] : _filterGames(all, q);
    final users = isUsers ? store.searchUsers(_query) : const <SocialUser>[];
    final count = isUsers ? users.length : games.length;
    final browsing = q.isEmpty && (isUsers || _genre == null);
    final label = browsing
        ? (isUsers ? 'Suggested people' : 'Popular on Checkpoint')
        : '$count result${count == 1 ? '' : 's'}';

    return SafeArea(
      bottom: false,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(20, 16, 20, 12),
          child: Text('Discover', style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800)),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: TextField(
            controller: _controller,
            textInputAction: TextInputAction.search,
            onChanged: (v) => setState(() => _query = v),
            decoration: fieldDecoration(
              'Search',
              hint: isUsers ? 'Names or @handles…' : 'Games, studios, platforms…',
              prefixIcon: const Icon(Icons.search_rounded),
              suffixIcon: _query.isEmpty
                  ? null
                  : IconButton(
                      icon: const Icon(Icons.close_rounded),
                      onPressed: () {
                        _controller.clear();
                        setState(() => _query = '');
                      },
                    ),
            ).copyWith(labelText: null),
          ),
        ),
        const SizedBox(height: 12),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: SizedBox(
            width: double.infinity,
            child: SegmentedButton<SearchKind>(
              showSelectedIcon: false,
              segments: const [
                ButtonSegment(value: SearchKind.games, icon: Icon(Icons.sports_esports_rounded), label: Text('Games')),
                ButtonSegment(value: SearchKind.users, icon: Icon(Icons.people_alt_rounded), label: Text('Users')),
              ],
              selected: {_kind},
              onSelectionChanged: (s) => setState(() => _kind = s.first),
              style: SegmentedButton.styleFrom(
                backgroundColor: Palette.surfaceHigh,
                foregroundColor: Colors.white70,
                selectedBackgroundColor: Palette.accent,
                selectedForegroundColor: Palette.onAccent,
                side: BorderSide(color: Colors.white.withValues(alpha: 0.18)),
              ),
            ),
          ),
        ),
        if (!isUsers) ...[
          const SizedBox(height: 12),
          _GenreChipRow(genres: genres, selected: _genre, onChanged: (g) => setState(() => _genre = g)),
        ],
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 4),
          child: Text(label, style: const TextStyle(color: Palette.muted, fontWeight: FontWeight.w600)),
        ),
        Expanded(
          child: count == 0
              ? EmptyState(
                  icon: isUsers ? Icons.person_search_rounded : Icons.search_off_rounded,
                  title: isUsers ? 'No users found' : 'No games found',
                  message: isUsers ? 'Try a different name or @handle.' : 'Try a different title, studio or genre.',
                )
              : ListView.builder(
                  keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                  padding: const EdgeInsets.fromLTRB(12, 4, 12, 32),
                  itemCount: count,
                  itemBuilder: (_, i) => isUsers ? _UserTile(user: users[i]) : _SearchTile(game: games[i]),
                ),
        ),
      ]),
    );
  }
}

class _UserTile extends StatelessWidget {
  const _UserTile({required this.user});
  final SocialUser user;

  @override
  Widget build(BuildContext context) {
    final store = context.store;
    final following = store.isFollowing(user.id);

    void toggle() {
      if (!store.isLoggedIn) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(const SnackBar(content: Text('Log in to follow people')));
        return;
      }
      context.actions.toggleFollow(user.id);
    }

    return Padding(
      padding: const EdgeInsets.all(8),
      child: Row(children: [
        ProfileAvatar(name: user.name, size: 52),
        const SizedBox(width: 14),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(user.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
            Text(user.handle, style: const TextStyle(color: Palette.accent, fontSize: 12.5, fontWeight: FontWeight.w600)),
            const SizedBox(height: 2),
            Text('${user.gamesLogged} games · ${fmtCount(user.followers)} followers', style: const TextStyle(color: Palette.muted, fontSize: 12)),
          ]),
        ),
        const SizedBox(width: 8),
        following
            ? OutlinedButton(
                style: OutlinedButton.styleFrom(visualDensity: VisualDensity.compact),
                onPressed: toggle,
                child: const Text('Following'),
              )
            : FilledButton(
                style: FilledButton.styleFrom(visualDensity: VisualDensity.compact),
                onPressed: toggle,
                child: const Text('Follow'),
              ),
      ]),
    );
  }
}

class _SearchTile extends StatelessWidget {
  const _SearchTile({required this.game});
  final Game game;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: () => openGame(context, game.id),
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Row(children: [
          SizedBox(width: 60, child: CoverArt(game: game, radius: 10)),
          const SizedBox(width: 14),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(game.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
              const SizedBox(height: 2),
              Text('${game.publisher} · ${game.releaseYear}', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Palette.muted, fontSize: 12.5)),
              const SizedBox(height: 8),
              Wrap(spacing: 6, runSpacing: 4, children: [
                for (final p in game.platforms.take(4)) Icon(p.icon, size: 16, color: p.color),
                if (game.platforms.length > 4)
                  Text('+${game.platforms.length - 4}', style: const TextStyle(fontSize: 11, color: Palette.muted)),
              ]),
            ]),
          ),
          const SizedBox(width: 8),
          if (!context.store.isLoggedIn)
            const SizedBox.shrink()
          else if (game.status != null)
            StatusPill(game.status!)
          else
            PopupMenuButton<GameStatus>(
              tooltip: 'Add to library',
              icon: const Icon(Icons.add_circle_outline_rounded, color: Palette.accent, size: 28),
              onSelected: (s) {
                context.actions.addToLibrary(game.id, s);
                ScaffoldMessenger.of(context)
                  ..hideCurrentSnackBar()
                  ..showSnackBar(SnackBar(content: Text('${game.title} added to ${s.label}')));
              },
              itemBuilder: (_) => [
                for (final s in const [GameStatus.playing, GameStatus.toPlay, GameStatus.wishlist, GameStatus.completed])
                  PopupMenuItem(
                    value: s,
                    child: Row(children: [Icon(s.icon, color: s.color, size: 20), const SizedBox(width: 10), Text(s.label)]),
                  ),
              ],
            ),
        ]),
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
//  10 · MY LIBRARY
// ═════════════════════════════════════════════════════════════════════════════

class LibraryScreen extends StatefulWidget {
  const LibraryScreen({super.key});

  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

/// Owns the status-tab `TabController` and keeps it in lock-step with
/// `store.currentLibraryTabIndex` in both directions:
///   user taps/swipes a tab  → controller listener → store.setLibraryTabIndex
///   store.openLibraryTab()  → store listener      → controller.index = …
/// Both sides compare before writing, so the two listeners can never loop.
class _LibraryScreenState extends State<LibraryScreen> with SingleTickerProviderStateMixin {
  late final CheckpointStore _store;
  late final TabController _tabs;

  @override
  void initState() {
    super.initState();
    _store = context.actions; // non-subscribing lookup is allowed in initState
    _tabs = TabController(
      length: GameStatus.values.length,
      vsync: this,
      initialIndex: _store.currentLibraryTabIndex,
    )..addListener(_onTabsChanged);
    _store.addListener(_onStoreChanged);
  }

  @override
  void dispose() {
    _store.removeListener(_onStoreChanged);
    _tabs
      ..removeListener(_onTabsChanged)
      ..dispose();
    super.dispose();
  }

  void _onTabsChanged() {
    final i = _tabs.index;
    if (i != _store.currentLibraryTabIndex) _store.setLibraryTabIndex(i);
  }

  void _onStoreChanged() {
    final i = _store.currentLibraryTabIndex;
    if (i != _tabs.index) _tabs.index = i;
  }

  @override
  Widget build(BuildContext context) {
    final store = context.store;
    return SafeArea(
      bottom: false,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 8, 0),
          child: Row(children: [
            const Expanded(
              child: Text('My Library', maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800)),
            ),
            _PlatformFilterButton(selected: store.platformFilter),
            _SortButton(field: store.sortField, descending: store.sortDescending),
            const SizedBox(width: 4),
            _ViewToggle(view: store.libraryView),
            const SizedBox(width: 8),
          ]),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 2, 20, 10),
          child: Text(
            'Sorted by ${store.sortField.label} · ${store.sortDescending ? 'high to low' : 'low to high'}'
            '${store.platformFilter != null ? ' · ${store.platformFilter!.label}' : ''}',
            style: const TextStyle(color: Palette.muted, fontSize: 12.5),
          ),
        ),
        TabBar(
          controller: _tabs,
          isScrollable: true,
          tabAlignment: TabAlignment.start,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          dividerColor: Colors.transparent,
          indicatorSize: TabBarIndicatorSize.tab,
          indicatorPadding: const EdgeInsets.symmetric(vertical: 2),
          splashBorderRadius: BorderRadius.circular(20),
          labelPadding: const EdgeInsets.symmetric(horizontal: 3),
          labelColor: Palette.accent,
          unselectedLabelColor: Palette.muted,
          labelStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5),
          unselectedLabelStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13.5),
          indicator: BoxDecoration(
            color: Palette.accent.withValues(alpha: 0.16),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: Palette.accent.withValues(alpha: 0.5)),
          ),
          tabs: [
            for (final s in GameStatus.values)
              Tab(
                height: 38,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Text(s.label),
                    const SizedBox(width: 6),
                    Text('${store.libraryFor(s).length}', style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 12)),
                  ]),
                ),
              ),
          ],
        ),
        const SizedBox(height: 8),
        Expanded(
          child: TabBarView(controller: _tabs, children: [
            for (final s in GameStatus.values) LibraryCollection(status: s),
          ]),
        ),
      ]),
    );
  }
}

class _ViewToggle extends StatelessWidget {
  const _ViewToggle({required this.view});
  final LibraryView view;

  @override
  Widget build(BuildContext context) {
    Widget cell(LibraryView v, IconData icon, String tooltip) {
      final active = v == view;
      return Tooltip(
        message: tooltip,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => context.actions.setLibraryView(v),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            width: 38,
            height: 34,
            decoration: BoxDecoration(
              color: active ? Palette.accent.withValues(alpha: 0.20) : Colors.transparent,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, size: 20, color: active ? Palette.accent : Palette.muted),
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(color: Palette.surfaceHigh, borderRadius: BorderRadius.circular(13)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        cell(LibraryView.grid, Icons.grid_view_rounded, 'Poster grid'),
        cell(LibraryView.list, Icons.view_list_rounded, 'List'),
      ]),
    );
  }
}

class _SortButton extends StatelessWidget {
  const _SortButton({required this.field, required this.descending});
  final SortField field;
  final bool descending;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<SortField>(
      tooltip: 'Sort',
      icon: const Icon(Icons.sort_rounded),
      onSelected: context.actions.setSort,
      itemBuilder: (_) => [
        for (final f in SortField.values)
          PopupMenuItem(
            value: f,
            child: Row(children: [
              Expanded(child: Text(f.label, style: TextStyle(fontWeight: f == field ? FontWeight.w800 : FontWeight.w500, color: f == field ? Palette.accent : null))),
              if (f == field) Icon(descending ? Icons.arrow_downward_rounded : Icons.arrow_upward_rounded, size: 16, color: Palette.accent),
            ]),
          ),
      ],
    );
  }
}

class _PlatformFilterButton extends StatelessWidget {
  const _PlatformFilterButton({required this.selected});
  final GamePlatform? selected;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<Object>(
      tooltip: 'Filter by platform',
      icon: Icon(Icons.filter_list_rounded, color: selected != null ? Palette.accent : null),
      onSelected: (v) => context.actions.setPlatformFilter(v is GamePlatform ? v : null),
      itemBuilder: (_) => [
        PopupMenuItem<Object>(
          value: 'all',
          child: Text('All platforms', style: TextStyle(fontWeight: selected == null ? FontWeight.w800 : FontWeight.w500, color: selected == null ? Palette.accent : null)),
        ),
        for (final p in GamePlatform.values)
          PopupMenuItem<Object>(
            value: p,
            child: Row(children: [
              Icon(p.icon, size: 18, color: p.color),
              const SizedBox(width: 10),
              Text(p.label, style: TextStyle(fontWeight: selected == p ? FontWeight.w800 : FontWeight.w500, color: selected == p ? Palette.accent : null)),
            ]),
          ),
      ],
    );
  }
}

class LibraryCollection extends StatelessWidget {
  const LibraryCollection({super.key, required this.status});
  final GameStatus status;

  @override
  Widget build(BuildContext context) {
    final store = context.store;
    final games = store.libraryFor(status);
    if (games.isEmpty) {
      final p = store.platformFilter;
      return EmptyState(
        icon: status.icon,
        title: p != null ? 'No ${status.label.toLowerCase()} games on ${p.label}' : 'Nothing in ${status.label} yet',
        message: p != null ? 'Clear the platform filter to see everything.' : 'Find something new in Discover and add it here.',
        actionLabel: p != null ? 'Clear filter' : 'Discover games',
        onAction: () => p != null ? context.actions.setPlatformFilter(null) : context.actions.setBottomNavIndex(NavTab.search),
      );
    }
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 220),
      child: store.libraryView == LibraryView.grid
          ? _PosterGrid(key: ValueKey('grid-${status.name}'), games: games)
          : _GameList(key: ValueKey('list-${status.name}'), games: games),
    );
  }
}

class _PosterGrid extends StatelessWidget {
  const _PosterGrid({super.key, required this.games});
  final List<Game> games;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, c) {
      final cols = c.maxWidth >= 900 ? 6 : (c.maxWidth >= 600 ? 5 : 3);
      return GridView.builder(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: cols,
          mainAxisSpacing: 12,
          crossAxisSpacing: 12,
          childAspectRatio: 2 / 3,
        ),
        itemCount: games.length,
        itemBuilder: (_, i) => _PosterTile(game: games[i]),
      );
    });
  }
}

class _PosterTile extends StatelessWidget {
  const _PosterTile({required this.game});
  final Game game;

  Widget _badge(Widget child) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
        decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.62), borderRadius: BorderRadius.circular(8)),
        child: child,
      );

  @override
  Widget build(BuildContext context) {
    return Stack(children: [
      Positioned.fill(child: CoverArt(game: game)),
      if (game.rating > 0)
        Positioned(
          left: 6,
          top: 6,
          child: _badge(Row(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.star_rounded, size: 12, color: Palette.star),
            const SizedBox(width: 2),
            Text(fmtHours(game.rating), style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700)),
          ])),
        ),
      if (game.hoursPlayed > 0)
        Positioned(
          right: 6,
          top: 6,
          child: _badge(Text('${fmtHours(game.hoursPlayed)}h', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700))),
        ),
      Positioned.fill(
        child: Material(
          color: Colors.transparent,
          child: InkWell(borderRadius: BorderRadius.circular(12), onTap: () => openGame(context, game.id)),
        ),
      ),
    ]);
  }
}

class _GameList extends StatelessWidget {
  const _GameList({super.key, required this.games});
  final List<Game> games;

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 32),
      itemCount: games.length,
      separatorBuilder: (_, __) => Divider(height: 1, indent: 82, color: Colors.white.withValues(alpha: 0.06)),
      itemBuilder: (_, i) => _LibraryListTile(game: games[i]),
    );
  }
}

class _LibraryListTile extends StatelessWidget {
  const _LibraryListTile({required this.game});
  final Game game;

  @override
  Widget build(BuildContext context) {
    final platform = game.playedOn ?? (game.platforms.isNotEmpty ? game.platforms.first : null);
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: () => openGame(context, game.id),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
        child: Row(children: [
          SizedBox(width: 60, child: CoverArt(game: game, radius: 10)),
          const SizedBox(width: 14),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(game.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
              const SizedBox(height: 4),
              Row(children: [
                if (platform != null) ...[
                  Icon(platform.icon, size: 14, color: platform.color),
                  const SizedBox(width: 5),
                  Flexible(child: Text(platform.label, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12.5, color: platform.color))),
                  const Text('  ·  ', style: TextStyle(color: Palette.muted)),
                ],
                Text('${game.releaseYear}', style: const TextStyle(fontSize: 12.5, color: Palette.muted)),
              ]),
              const SizedBox(height: 8),
              Row(children: [
                game.rating > 0
                    ? StarRating(rating: game.rating, size: 15)
                    : const Text('Not rated', style: TextStyle(fontSize: 12, color: Palette.muted)),
                const Spacer(),
                const Icon(Icons.schedule_rounded, size: 14, color: Palette.muted),
                const SizedBox(width: 4),
                Text(game.hoursPlayed > 0 ? '${fmtHours(game.hoursPlayed)} h' : '—',
                    style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600)),
              ]),
            ]),
          ),
          const SizedBox(width: 4),
          const Icon(Icons.chevron_right_rounded, color: Palette.muted),
        ]),
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
//  11 · GAME DETAIL
// ═════════════════════════════════════════════════════════════════════════════

class GameDetailScreen extends StatelessWidget {
  const GameDetailScreen({super.key, required this.gameId});
  final String gameId;

  static const double _expanded = 372;

  @override
  Widget build(BuildContext context) {
    final store = context.store;
    final game = store.maybeGame(gameId);
    if (game == null) {
      return Scaffold(appBar: AppBar(), body: const EmptyState(icon: Icons.error_outline_rounded, title: 'Game not found', message: 'It may have been removed.'));
    }
    final bottom = MediaQuery.paddingOf(context).bottom;
    return Scaffold(
      body: CustomScrollView(slivers: [
        SliverAppBar(
          pinned: true,
          expandedHeight: _expanded,
          backgroundColor: Palette.background,
          surfaceTintColor: Colors.transparent,
          leadingWidth: 68,
          leading: Padding(
            padding: const EdgeInsets.only(left: 16),
            child: Center(child: _RoundIconButton(icon: Icons.arrow_back_ios_new_rounded, onTap: () => Navigator.maybePop(context))),
          ),
          flexibleSpace: LayoutBuilder(builder: (context, c) {
            final top = MediaQuery.paddingOf(context).top;
            final collapsed = kToolbarHeight + top;
            final t = ((c.maxHeight - collapsed) / (_expanded - kToolbarHeight)).clamp(0.0, 1.0).toDouble();
            // Full (un-collapsed) height of the bar; the hero is always laid out at
            // this height so it never gets squeezed while the bar collapses.
            final full = context.dependOnInheritedWidgetOfExactType<FlexibleSpaceBarSettings>()?.maxExtent ?? (_expanded + top);
            return Stack(fit: StackFit.expand, children: [
              ClipRect(
                child: OverflowBox(
                  alignment: Alignment.bottomCenter,
                  minHeight: full,
                  maxHeight: full,
                  child: Opacity(opacity: t, child: _DetailHeaderArt(game: game, topInset: top)),
                ),
              ),
              Positioned(
                left: 68,
                right: 20,
                bottom: 0,
                height: kToolbarHeight,
                child: Opacity(
                  opacity: 1 - t,
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(game.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                  ),
                ),
              ),
            ]);
          }),
        ),
        SliverToBoxAdapter(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 640),
              child: Padding(
                padding: EdgeInsets.fromLTRB(20, 4, 20, bottom + 32),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  _ProgressPanel(game: game),
                  const SizedBox(height: 14),
                  _RatingPanel(game: game),
                  const SizedBox(height: 14),
                  Panel(
                    title: 'Played on',
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      PlatformChips(
                        platforms: game.platforms,
                        selected: game.playedOn,
                        onSelected: (p) => context.actions.setPlayedOn(game.id, p),
                      ),
                      if (game.playedOn == null) ...[
                        const SizedBox(height: 10),
                        const Text('Pick the platform you play this on. It is used in your session log and profile stats.', style: TextStyle(color: Palette.muted, fontSize: 12.5, height: 1.35)),
                      ],
                    ]),
                  ),
                  const SizedBox(height: 14),
                  Panel(title: 'Update status', child: _StatusActions(game: game)),
                  const SizedBox(height: 14),
                  ValueRatioCalculator(game: game),
                  const SizedBox(height: 14),
                  _SessionsPanel(gameId: game.id),
                  _AboutPanel(game: game),
                ]),
              ),
            ),
          ),
        ),
      ]),
    );
  }
}

class _RoundIconButton extends StatelessWidget {
  const _RoundIconButton({required this.icon, required this.onTap});
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 40,
      height: 40,
      child: Material(
        color: Colors.black.withValues(alpha: 0.38),
        shape: const CircleBorder(),
        clipBehavior: Clip.antiAlias,
        child: InkWell(onTap: onTap, child: Icon(icon, size: 18, color: Colors.white)),
      ),
    );
  }
}

class _DetailHeaderArt extends StatelessWidget {
  const _DetailHeaderArt({required this.game, required this.topInset});
  final Game game;
  final double topInset;

  @override
  Widget build(BuildContext context) {
    return Stack(fit: StackFit.expand, children: [
      DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: game.coverColors),
        ),
      ),
      Positioned(right: -40, top: topInset + 30, child: Icon(game.coverIcon, size: 300, color: Colors.white.withValues(alpha: 0.10))),
      const DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0x59000000), Color(0x00000000), Palette.background],
            stops: [0, 0.45, 1],
          ),
        ),
      ),
      Padding(
        padding: EdgeInsets.fromLTRB(20, topInset + kToolbarHeight, 20, 20),
        // FittedBox(scaleDown) is a safety net: at normal sizes it does nothing, but a
        // long title + many platform chips + a large system font shrinks the block to
        // fit instead of overflowing/clipping.
        child: LayoutBuilder(
          builder: (context, c) => FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.bottomLeft,
            child: SizedBox(
              width: c.maxWidth,
              child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
                Container(
                  width: 118,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(14),
                    boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.5), blurRadius: 24, offset: const Offset(0, 10))],
                  ),
                  child: CoverArt(game: game, radius: 14),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(game.title, maxLines: 3, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w800, height: 1.1)),
                    const SizedBox(height: 6),
                    Text(game.publisher, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white70, fontSize: 14, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 2),
                    Text('Released ${game.releaseYear}', style: const TextStyle(color: Colors.white60, fontSize: 13)),
                    const SizedBox(height: 10),
                    Wrap(spacing: 6, runSpacing: 6, children: [for (final p in game.platforms) PlatformBadge(p, dense: true)]),
                  ]),
                ),
              ]),
            ),
          ),
        ),
      ),
    ]);
  }
}

class _ProgressPanel extends StatelessWidget {
  const _ProgressPanel({required this.game});
  final Game game;

  @override
  Widget build(BuildContext context) {
    Widget stat(String value, String label) => Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerLeft, child: Text(value, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800))),
            Text(label, style: const TextStyle(fontSize: 12, color: Palette.muted)),
          ]),
        );

    return Panel(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          if (game.status != null) StatusPill(game.status!) else const Text('Not in your library', style: TextStyle(color: Palette.muted)),
          const Spacer(),
          FilledButton.tonalIcon(
            onPressed: () => showLogHoursSheet(context, game.id),
            icon: const Icon(Icons.timer_outlined, size: 18),
            label: const Text('Log Hours'),
          ),
        ]),
        const SizedBox(height: 16),
        Row(children: [
          stat('${fmtHours(game.hoursPlayed)} h', 'Played'),
          stat(game.targetHours > 0 ? '${fmtHours(game.targetHours)} h' : '—', 'Target'),
          stat(game.targetHours > 0 ? '${(game.progress * 100).round()}%' : '—', 'Progress'),
        ]),
        if (game.targetHours > 0) ...[
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(value: game.progress, minHeight: 8, color: Palette.accent, backgroundColor: Colors.white12),
          ),
        ],
      ]),
    );
  }
}

class _RatingPanel extends StatelessWidget {
  const _RatingPanel({required this.game});
  final Game game;

  @override
  Widget build(BuildContext context) {
    return Panel(
      title: 'Your rating',
      trailing: game.rating > 0
          ? TextButton(onPressed: () => context.actions.setRating(game.id, 0), child: const Text('Clear'))
          : null,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        StarRating(rating: game.rating, size: 44, onChanged: (v) => context.actions.setRating(game.id, v)),
        const SizedBox(height: 8),
        Text(
          game.rating > 0 ? '${fmtHours(game.rating)} / 5' : 'Tap or drag across the stars (half-stars supported)',
          style: TextStyle(color: game.rating > 0 ? Palette.star : Palette.muted, fontWeight: FontWeight.w600, fontSize: 13),
        ),
      ]),
    );
  }
}

class _StatusActions extends StatelessWidget {
  const _StatusActions({required this.game});
  final Game game;

  @override
  Widget build(BuildContext context) {
    final store = context.actions;
    final messenger = ScaffoldMessenger.of(context);

    void change(GameStatus next, String message) {
      final prev = game.status;
      store.setStatus(game.id, next);
      HapticFeedback.mediumImpact();
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(
          content: Text(message),
          action: prev == null ? null : SnackBarAction(label: 'Undo', onPressed: () => store.setStatus(game.id, prev)),
        ));
    }

    return Wrap(spacing: 10, runSpacing: 10, children: [
      FilledButton.icon(
        onPressed: game.status == GameStatus.completed ? null : () => change(GameStatus.completed, 'Marked as completed'),
        icon: const Icon(Icons.verified_rounded, size: 18),
        label: const Text('Mark as Completed'),
      ),
      FilledButton.tonalIcon(
        onPressed: game.status == GameStatus.toPlay ? null : () => change(GameStatus.toPlay, 'Moved to To Play'),
        icon: const Icon(Icons.inventory_2_rounded, size: 18),
        label: const Text('Move to To Play'),
      ),
      OutlinedButton.icon(
        onPressed: game.status == GameStatus.dropped ? null : () => change(GameStatus.dropped, 'Dropped'),
        style: OutlinedButton.styleFrom(foregroundColor: Palette.danger, side: BorderSide(color: Palette.danger.withValues(alpha: 0.6))),
        icon: const Icon(Icons.block_rounded, size: 18),
        label: const Text('Drop'),
      ),
      if (game.status != GameStatus.playing)
        TextButton.icon(
          onPressed: () => change(GameStatus.playing, 'Started playing'),
          icon: const Icon(Icons.play_circle_rounded, size: 18),
          label: const Text('Start Playing'),
        ),
    ]);
  }
}

/// Purchase price → cost per hour, with a plain-language verdict.
class ValueRatioCalculator extends StatefulWidget {
  const ValueRatioCalculator({super.key, required this.game});
  final Game game;

  @override
  State<ValueRatioCalculator> createState() => _ValueRatioCalculatorState();
}

class _ValueRatioCalculatorState extends State<ValueRatioCalculator> {
  late final TextEditingController _price = TextEditingController(
    text: widget.game.purchasePrice > 0 ? widget.game.purchasePrice.toStringAsFixed(2) : '',
  );

  @override
  void dispose() {
    _price.dispose();
    super.dispose();
  }

  ({String label, Color color}) _verdict(double cph) {
    if (cph <= 1) return (label: 'Bargain', color: Palette.success);
    if (cph <= 3) return (label: 'Great value', color: Palette.success);
    if (cph <= 6) return (label: 'Fair', color: Palette.star);
    return (label: 'Pricey per hour', color: Palette.danger);
  }

  @override
  Widget build(BuildContext context) {
    final g = widget.game;
    final cph = g.costPerHour;
    final verdict = cph == null ? null : _verdict(cph);

    String hint;
    if (g.purchasePrice <= 0) {
      hint = 'Enter what you paid to see your cost per hour.';
    } else if (g.hoursPlayed <= 0) {
      hint = 'Log some hours to calculate cost per hour.';
    } else if (cph! > 1) {
      hint = 'Play ${fmtHours(g.purchasePrice - g.hoursPlayed)} more hours to get under ${fmtMoney(1)}/hr.';
    } else {
      hint = 'Already under ${fmtMoney(1)} per hour. Nice.';
    }

    return Panel(
      title: 'Value ratio',
      trailing: const Icon(Icons.savings_outlined, color: Palette.muted),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        TextField(
          controller: _price,
          keyboardType: _decimalKeyboard,
          inputFormatters: [_decimalFormatter],
          decoration: fieldDecoration('Purchase price', prefix: '\$ '),
          onChanged: (v) => context.actions.setPurchasePrice(g.id, parseNum(v) ?? 0),
        ),
        const SizedBox(height: 18),
        Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Cost per hour', style: TextStyle(color: Palette.muted, fontSize: 12.5)),
              const SizedBox(height: 2),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(
                  cph == null ? '—' : '${fmtMoney(cph)}/hr',
                  style: TextStyle(fontSize: 34, fontWeight: FontWeight.w800, color: verdict?.color ?? Colors.white),
                ),
              ),
            ]),
          ),
          if (verdict != null)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(color: verdict.color.withValues(alpha: 0.16), borderRadius: BorderRadius.circular(20)),
              child: Text(verdict.label, style: TextStyle(color: verdict.color, fontWeight: FontWeight.w700, fontSize: 12.5)),
            ),
        ]),
        const SizedBox(height: 10),
        Text(hint, style: const TextStyle(color: Palette.muted, fontSize: 12.5, height: 1.35)),
      ]),
    );
  }
}

class _SessionsPanel extends StatelessWidget {
  const _SessionsPanel({required this.gameId});
  final String gameId;

  @override
  Widget build(BuildContext context) {
    final logs = context.store.logsFor(gameId);
    if (logs.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Panel(
        title: 'Recent sessions',
        child: Column(children: [
          for (final l in logs.take(5))
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 7),
              child: Row(children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(color: l.platform.color.withValues(alpha: 0.16), shape: BoxShape.circle),
                  child: Icon(l.platform.icon, size: 18, color: l.platform.color),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('+${fmtHours(l.hours)} h on ${l.platform.label}', style: const TextStyle(fontWeight: FontWeight.w600)),
                    if (l.note.isNotEmpty) Text(l.note, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, color: Palette.muted)),
                  ]),
                ),
                Text(timeAgo(l.timestamp), style: const TextStyle(fontSize: 12, color: Palette.muted)),
              ]),
            ),
        ]),
      ),
    );
  }
}

class _AboutPanel extends StatelessWidget {
  const _AboutPanel({required this.game});
  final Game game;

  @override
  Widget build(BuildContext context) {
    return Panel(
      title: 'About',
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(game.synopsis, style: const TextStyle(height: 1.45, color: Colors.white70)),
        const SizedBox(height: 14),
        Wrap(spacing: 8, runSpacing: 8, children: [for (final g in game.genres) Chip(label: Text(g))]),
        const SizedBox(height: 12),
        Text('Developer: ${game.developer}', style: const TextStyle(color: Palette.muted, fontSize: 12.5)),
      ]),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
//  12 · LOG SHEETS
// ═════════════════════════════════════════════════════════════════════════════

/// Read-only guard: returns true (and shows a hint) when logged out.
bool _blockedByReadOnly(BuildContext context) {
  if (context.actions.isLoggedIn) return false;
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(const SnackBar(content: Text('Log in to track games')));
  return true;
}

Future<void> showQuickLogSheet(BuildContext context, {String? gameId}) async {
  if (_blockedByReadOnly(context)) return;
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => QuickLogSheet(initialGameId: gameId),
  );
}

Future<void> showLogHoursSheet(BuildContext context, String gameId) async {
  if (_blockedByReadOnly(context)) return;
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => LogHoursSheet(gameId: gameId),
  );
}

/// FAB sheet: pick a game, pick the platform you played on, add a session.
class QuickLogSheet extends StatefulWidget {
  const QuickLogSheet({super.key, this.initialGameId});
  final String? initialGameId;

  @override
  State<QuickLogSheet> createState() => _QuickLogSheetState();
}

class _QuickLogSheetState extends State<QuickLogSheet> {
  final _hours = TextEditingController(text: '1');
  final _note = TextEditingController();
  String? _gameId;
  GamePlatform? _platform;

  @override
  void initState() {
    super.initState();
    _gameId = widget.initialGameId;
    if (_gameId != null) _platform = _defaultPlatform(StoreScope.read(context).gameById(_gameId!));
  }

  @override
  void dispose() {
    _hours.dispose();
    _note.dispose();
    super.dispose();
  }

  GamePlatform _defaultPlatform(Game g) => g.playedOn ?? g.platforms.first;

  void _save(Game game, double hours) {
    final messenger = ScaffoldMessenger.of(context);
    context.actions.logSession(gameId: game.id, hours: hours, platform: _platform, note: _note.text);
    Navigator.pop(context);
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text('Logged ${fmtHours(hours)}h of ${game.title} on ${_platform?.label ?? 'your platform'}')));
  }

  @override
  Widget build(BuildContext context) {
    final store = context.store;
    final game = _gameId == null ? null : store.maybeGame(_gameId!);
    final hours = parseNum(_hours.text);
    final canSave = game != null && hours != null && hours > 0;

    final sorted = [...store.games]..sort((a, b) {
        int rank(Game g) => g.status == GameStatus.playing ? 0 : (g.inLibrary ? 1 : 2);
        final c = rank(a).compareTo(rank(b));
        return c != 0 ? c : a.title.compareTo(b.title);
      });

    return SheetFrame(
      title: 'Log a session',
      subtitle: 'Track your time and where you played.',
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        DropdownMenu<String>(
          initialSelection: _gameId,
          expandedInsets: EdgeInsets.zero,
          enableFilter: true,
          requestFocusOnTap: true,
          menuHeight: 280,
          label: const Text('Game'),
          leadingIcon: const Icon(Icons.sports_esports_rounded),
          dropdownMenuEntries: [
            for (final g in sorted)
              DropdownMenuEntry<String>(value: g.id, label: g.title, leadingIcon: Icon(g.coverIcon, color: g.coverColors.first, size: 20)),
          ],
          onSelected: (id) => setState(() {
            _gameId = id;
            _platform = id == null ? null : _defaultPlatform(store.gameById(id));
          }),
        ),
        if (game != null) ...[
          const SizedBox(height: 18),
          const Text('Played on', style: TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 10),
          PlatformChips(platforms: game.platforms, selected: _platform, onSelected: (p) => setState(() => _platform = p)),
        ],
        const SizedBox(height: 18),
        TextField(
          controller: _hours,
          keyboardType: _decimalKeyboard,
          inputFormatters: [_decimalFormatter],
          onChanged: (_) => setState(() {}),
          decoration: fieldDecoration('Hours played this session', suffix: 'hrs'),
        ),
        const SizedBox(height: 10),
        Wrap(spacing: 8, children: [
          for (final h in const <double>[0.5, 1, 2, 4])
            ActionChip(
              label: Text('+${fmtHours(h)}h'),
              onPressed: () => setState(() => _hours.text = fmtHours((parseNum(_hours.text) ?? 0) + h)),
            ),
        ]),
        const SizedBox(height: 14),
        TextField(controller: _note, textCapitalization: TextCapitalization.sentences, decoration: fieldDecoration('Note (optional)')),
        const SizedBox(height: 20),
        SizedBox(
          width: double.infinity,
          child: FilledButton(
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
            onPressed: canSave ? () => _save(game, hours) : null,
            child: const Text('Save session'),
          ),
        ),
      ]),
    );
  }
}

/// Game-detail sheet: set total time played + target total hours.
class LogHoursSheet extends StatefulWidget {
  const LogHoursSheet({super.key, required this.gameId});
  final String gameId;

  @override
  State<LogHoursSheet> createState() => _LogHoursSheetState();
}

class _LogHoursSheetState extends State<LogHoursSheet> {
  late final Game _game = StoreScope.read(context).gameById(widget.gameId);
  late final TextEditingController _total = TextEditingController(text: fmtHours(_game.hoursPlayed));
  late final TextEditingController _target = TextEditingController(text: _game.targetHours > 0 ? fmtHours(_game.targetHours) : '');
  final _note = TextEditingController();
  late GamePlatform? _platform = _game.playedOn ?? (_game.platforms.isEmpty ? null : _game.platforms.first);

  @override
  void dispose() {
    _total.dispose();
    _target.dispose();
    _note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final total = parseNum(_total.text);
    final targetText = _target.text.trim();
    final target = targetText.isEmpty ? 0.0 : parseNum(targetText);
    final valid = total != null && total >= 0 && target != null && target >= 0;
    final delta = total == null ? null : total - _game.hoursPlayed;

    String preview;
    if (delta == null) {
      preview = 'Enter a valid number of hours.';
    } else if (delta > 0.04) {
      preview = 'Adds a ${fmtHours(delta)} h session on ${_platform?.label ?? 'your platform'}.';
    } else if (delta < -0.04) {
      preview = 'Corrects your total by ${fmtHours(delta)} h.';
    } else {
      preview = 'No change to your total time.';
    }

    return SheetFrame(
      title: 'Log hours',
      subtitle: _game.title,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(
            child: TextField(
              controller: _total,
              keyboardType: _decimalKeyboard,
              inputFormatters: [_decimalFormatter],
              onChanged: (_) => setState(() {}),
              decoration: fieldDecoration('Total played', suffix: 'hrs'),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: TextField(
              controller: _target,
              keyboardType: _decimalKeyboard,
              inputFormatters: [_decimalFormatter],
              onChanged: (_) => setState(() {}),
              decoration: fieldDecoration('Target total', suffix: 'hrs'),
            ),
          ),
        ]),
        const SizedBox(height: 10),
        Wrap(spacing: 8, children: [
          for (final h in const <double>[0.5, 1, 2, 5])
            ActionChip(
              label: Text('+${fmtHours(h)}h'),
              onPressed: () => setState(() => _total.text = fmtHours((parseNum(_total.text) ?? 0) + h)),
            ),
        ]),
        const SizedBox(height: 6),
        Text(preview, style: TextStyle(color: valid ? Palette.muted : Palette.danger, fontSize: 12.5)),
        const SizedBox(height: 18),
        const Text('Played on', style: TextStyle(fontWeight: FontWeight.w700)),
        const SizedBox(height: 10),
        PlatformChips(platforms: _game.platforms, selected: _platform, onSelected: (p) => setState(() => _platform = p)),
        const SizedBox(height: 18),
        TextField(controller: _note, textCapitalization: TextCapitalization.sentences, decoration: fieldDecoration('Note (optional)')),
        const SizedBox(height: 20),
        SizedBox(
          width: double.infinity,
          child: FilledButton(
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
            onPressed: !valid
                ? null
                : () {
                    context.actions.updateTime(
                      gameId: _game.id,
                      totalHours: total,
                      targetHours: target,
                      platform: _platform,
                      note: _note.text,
                    );
                    Navigator.pop(context);
                  },
            child: const Text('Save'),
          ),
        ),
      ]),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
//  13 · PROFILE
// ═════════════════════════════════════════════════════════════════════════════

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
              Row(children: [
                Expanded(
                  child: StatTile(
                    icon: Icons.schedule_rounded,
                    value: fmtHours(store.totalHours),
                    label: 'Total hours',
                    onTap: () => context.actions.openLibraryTab(GameStatus.playing, sortBy: SortField.hoursPlayed),
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
                          onTap: () => context.actions.toggleService(s),
                        ),
                      ),
                    ],
                  ]),
                  const SizedBox(height: 14),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.tonalIcon(
                      onPressed: store.connectedCount == 0 || store.isSyncing
                          ? null
                          : () async {
                              final messenger = ScaffoldMessenger.of(context);
                              final n = store.connectedCount;
                              await context.actions.syncLibrary();
                              messenger
                                ..hideCurrentSnackBar()
                                ..showSnackBar(SnackBar(content: Text('Library synced · $n account${n == 1 ? '' : 's'}')));
                            },
                      icon: store.isSyncing
                          ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                          : const Icon(Icons.sync_rounded),
                      label: Text(store.isSyncing ? 'Syncing…' : 'Sync Library'),
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