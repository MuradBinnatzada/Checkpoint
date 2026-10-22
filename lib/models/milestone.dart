import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'package:checkpoint/l10n/l10n.dart';

/// How hard a milestone is to reach: the colour of its badge and the points it
/// gives towards the member's level ([MilestoneLevel]).
enum MilestoneTier {
  bronze(Color(0xFFD08C57), 10),
  silver(Color(0xFFB9C3CF), 25),
  gold(Color(0xFFFFC857), 50),
  platinum(Color(0xFF8FE3EC), 100);

  const MilestoneTier(this.color, this.points);

  String get label => switch (this) {
    bronze => L10n.current.tierBronze,
    silver => L10n.current.tierSilver,
    gold => L10n.current.tierGold,
    platinum => L10n.current.tierPlatinum,
  };

  /// Picked for the dark theme; pass it through `Palette.legible` for text and
  /// icons on the light one.
  final Color color;
  final int points;
}

/// The sections of the Milestones screen, in the order it lists them.
enum MilestoneCategory {
  library(Icons.collections_bookmark_rounded),
  logbook(Icons.edit_calendar_rounded),
  playtime(Icons.schedule_rounded),
  finisher(Icons.verified_rounded),
  streaks(Icons.local_fire_department_rounded),
  critic(Icons.star_rounded),
  curator(Icons.format_list_bulleted_rounded),
  variety(Icons.explore_rounded),
  social(Icons.people_alt_rounded),
  membership(Icons.cake_rounded),
  account(Icons.person_rounded);

  const MilestoneCategory(this.icon);
  final IconData icon;

  String get label {
    final l10n = L10n.current;
    return switch (this) {
      library => l10n.milestoneCategoryLibrary,
      logbook => l10n.milestoneCategoryLogbook,
      playtime => l10n.milestoneCategoryPlaytime,
      finisher => l10n.milestoneCategoryFinisher,
      streaks => l10n.milestoneCategoryStreaks,
      critic => l10n.milestoneCategoryCritic,
      curator => l10n.milestoneCategoryCurator,
      variety => l10n.milestoneCategoryVariety,
      social => l10n.milestoneCategorySocial,
      membership => l10n.milestoneCategoryMembership,
      account => l10n.milestoneCategoryAccount,
    };
  }
}

/// What a milestone counts: `milestones.metric` in the database, where
/// `award_milestones` works each one out (20261020120100_milestones.sql, as
/// changed by 20261020140337_milestones_without_steam.sql).
/// [unit] names what is counted in a progress line ("37 / 50 games"); a
/// milestone that is a yes or no counts nothing ([counted] false).
enum MilestoneMetric {
  libraryGames('library_games'),
  sessions('sessions'),
  hours('hours'),
  gameHours('game_hours'),
  completed('completed'),
  completionTimes('completion_times'),
  streakDays('streak_days'),
  nightSessions('night_sessions', counted: false),
  rated('rated'),
  reviews('reviews'),
  lists('lists'),
  publicLists('public_lists', counted: false),
  listSize('list_size'),
  platforms('platforms'),
  genres('genres'),
  retroGames('retro_games', counted: false),
  decades('decades'),
  following('following', counted: false),
  followers('followers'),
  memberMonths('member_months'),
  foundingMember('founding_member', counted: false),
  profileComplete('profile_complete', counted: false),
  favorites('favorites'),
  wishlist('wishlist'),
  dropped('dropped', counted: false),
  gameAccount('game_account', counted: false),
  twoFactor('two_factor', counted: false),
  perfectGames('perfect_games', counted: false);

  const MilestoneMetric(this.wire, {this.counted = true});
  final String wire;
  final bool counted;

  /// What [count] of it is called: "games" in "37 / 50 games". Empty when not
  /// [counted].
  String unit(int count) {
    final l10n = L10n.current;
    return switch (this) {
      libraryGames || listSize => l10n.milestoneUnitGames(count),
      sessions => l10n.milestoneUnitSessions(count),
      hours || gameHours => l10n.milestoneUnitHours(count),
      completed => l10n.milestoneUnitCompleted(count),
      completionTimes => l10n.milestoneUnitTimes(count),
      streakDays => l10n.milestoneUnitDays(count),
      rated => l10n.milestoneUnitRated(count),
      reviews => l10n.milestoneUnitReviews(count),
      lists => l10n.milestoneUnitLists(count),
      platforms => l10n.milestoneUnitPlatforms(count),
      genres => l10n.milestoneUnitGenres(count),
      decades => l10n.milestoneUnitDecades(count),
      followers => l10n.milestoneUnitFollowers(count),
      memberMonths => l10n.milestoneUnitMonths(count),
      favorites => l10n.milestoneUnitFavorites(count),
      wishlist => l10n.milestoneUnitWishlisted(count),
      _ => '',
    };
  }
}

/// A ring drawn around a member's photo, unlocked by one milestone
/// ([Milestone.frame]). [id] is what `profiles.avatar_frame` stores.
enum AvatarFrame {
  bronze('bronze', [Color(0xFFB87333), Color(0xFFE6B07E)]),
  silver('silver', [Color(0xFF8E99A6), Color(0xFFE6EBF0)]),
  gold('gold', [Color(0xFFFFA000), Color(0xFFFFE082)]),
  prism('prism', [
    Color(0xFFBB86FC),
    Color(0xFF4FC3F7),
    Color(0xFF7DDC9C),
    Color(0xFFBB86FC),
  ]),
  platinum('platinum', [
    Color(0xFF80DEEA),
    Color(0xFFFFFFFF),
    Color(0xFF9FA8DA),
    Color(0xFF80DEEA),
  ], animated: true),
  neon('neon', [Color(0xFFBB86FC), Color(0xFF4FC3F7)]),
  laurel('laurel', [Color(0xFF2E7D32), Color(0xFF9CE5B3)]),
  ember('ember', [Color(0xFFFF5722), Color(0xFFFFC857)]),
  shield('shield', [Color(0xFF1565C0), Color(0xFF4FC3F7)]),
  veteran('veteran', [Color(0xFF7B1FA2), Color(0xFFFFC857)]),
  founder('founder', [
    Color(0xFFFFC857),
    Color(0xFFBB86FC),
    Color(0xFF4FC3F7),
    Color(0xFFFFC857),
  ], animated: true);

  const AvatarFrame(this.id, this.colors, {this.animated = false});
  final String id;

  String get label {
    final l10n = L10n.current;
    return switch (this) {
      bronze => l10n.frameBronze,
      silver => l10n.frameSilver,
      gold => l10n.frameGold,
      prism => l10n.framePrism,
      platinum => l10n.framePlatinum,
      neon => l10n.frameNeon,
      laurel => l10n.frameLaurel,
      ember => l10n.frameEmber,
      shield => l10n.frameShield,
      veteran => l10n.frameVeteran,
      founder => l10n.frameFounder,
    };
  }

  /// The ring's gradient, swept around the photo.
  final List<Color> colors;

  /// The gradient turns slowly: the rarest frames.
  final bool animated;

  /// The milestone that unlocks it.
  Milestone get milestone => milestones.firstWhere((m) => m.frame == this);

  static AvatarFrame? fromId(String? id) {
    for (final frame in values) {
      if (frame.id == id) return frame;
    }
    return null;
  }
}

/// Something a member earns by using the app: a number of games, a streak, a
/// year as a member. Once earned it is kept (`user_milestones`).
@immutable
class Milestone {
  const Milestone({
    required this.id,
    required this.category,
    required this.tier,
    required this.icon,
    required this.metric,
    required this.threshold,
    this.frame,
    this.rewardsTitle = false,
  });

  /// `milestones.id` and `user_milestones.milestone_id`.
  final String id;
  final MilestoneCategory category;
  final MilestoneTier tier;
  final IconData icon;
  final MilestoneMetric metric;

  /// How much of [metric] it takes.
  final int threshold;

  /// The avatar frame it unlocks, if any.
  final AvatarFrame? frame;

  /// Whether it lets the member show a title under their name ([rewardTitle]).
  final bool rewardsTitle;

  /// Its name, in the app's language ("Shelf Starter").
  String get title => _titleOf(L10n.current, id) ?? id;

  /// What it asks for, in the app's language ("Have 10 games in your library.").
  String get description => _descriptionOf(L10n.current, id) ?? '';

  /// The title it lets the member show under their name, if any: mostly its
  /// own name. The English ones are `milestones.title` on the server.
  String? get rewardTitle => rewardsTitle ? _rewardTitleOf(L10n.current, id) ?? title : null;

  int get points => tier.points;

  /// Reached or not, with nothing to count towards it.
  bool get isYesNo => !metric.counted;
}

/// Every milestone, by category, easiest first. Must match the `milestones` rows
/// the migrations seed (20261020120100_milestones.sql and the later ones that
/// change it: ids, metrics, thresholds, frames, titles); test/milestones_test.dart
/// compares them. Ids are stored: never rename one.
const List<Milestone> milestones = [
  // Library
  Milestone(
    id: 'library_1',
    category: MilestoneCategory.library,
    tier: MilestoneTier.bronze,
    icon: Icons.add_box_rounded,
    metric: MilestoneMetric.libraryGames,
    threshold: 1,
  ),
  Milestone(
    id: 'library_10',
    category: MilestoneCategory.library,
    tier: MilestoneTier.bronze,
    icon: Icons.collections_bookmark_rounded,
    metric: MilestoneMetric.libraryGames,
    threshold: 10,
    frame: AvatarFrame.bronze,
  ),
  Milestone(
    id: 'library_50',
    category: MilestoneCategory.library,
    tier: MilestoneTier.silver,
    icon: Icons.library_books_rounded,
    metric: MilestoneMetric.libraryGames,
    threshold: 50,
    frame: AvatarFrame.silver,
  ),
  Milestone(
    id: 'library_100',
    category: MilestoneCategory.library,
    tier: MilestoneTier.gold,
    icon: Icons.inventory_2_rounded,
    metric: MilestoneMetric.libraryGames,
    threshold: 100,
    frame: AvatarFrame.gold,
    rewardsTitle: true,
  ),
  Milestone(
    id: 'library_200',
    category: MilestoneCategory.library,
    tier: MilestoneTier.gold,
    icon: Icons.warehouse_rounded,
    metric: MilestoneMetric.libraryGames,
    threshold: 200,
    frame: AvatarFrame.prism,
  ),
  Milestone(
    id: 'library_500',
    category: MilestoneCategory.library,
    tier: MilestoneTier.platinum,
    icon: Icons.museum_rounded,
    metric: MilestoneMetric.libraryGames,
    threshold: 500,
    frame: AvatarFrame.platinum,
    rewardsTitle: true,
  ),
  Milestone(
    id: 'library_1000',
    category: MilestoneCategory.library,
    tier: MilestoneTier.platinum,
    icon: Icons.account_balance_rounded,
    metric: MilestoneMetric.libraryGames,
    threshold: 1000,
  ),

  // Logbook
  Milestone(
    id: 'sessions_1',
    category: MilestoneCategory.logbook,
    tier: MilestoneTier.bronze,
    icon: Icons.flag_rounded,
    metric: MilestoneMetric.sessions,
    threshold: 1,
  ),
  Milestone(
    id: 'sessions_10',
    category: MilestoneCategory.logbook,
    tier: MilestoneTier.bronze,
    icon: Icons.edit_note_rounded,
    metric: MilestoneMetric.sessions,
    threshold: 10,
  ),
  Milestone(
    id: 'sessions_50',
    category: MilestoneCategory.logbook,
    tier: MilestoneTier.silver,
    icon: Icons.menu_book_rounded,
    metric: MilestoneMetric.sessions,
    threshold: 50,
  ),
  Milestone(
    id: 'sessions_100',
    category: MilestoneCategory.logbook,
    tier: MilestoneTier.gold,
    icon: Icons.auto_stories_rounded,
    metric: MilestoneMetric.sessions,
    threshold: 100,
  ),
  Milestone(
    id: 'sessions_500',
    category: MilestoneCategory.logbook,
    tier: MilestoneTier.platinum,
    icon: Icons.history_edu_rounded,
    metric: MilestoneMetric.sessions,
    threshold: 500,
    rewardsTitle: true,
  ),

  // Playtime
  Milestone(
    id: 'hours_10',
    category: MilestoneCategory.playtime,
    tier: MilestoneTier.bronze,
    icon: Icons.hourglass_bottom_rounded,
    metric: MilestoneMetric.hours,
    threshold: 10,
  ),
  Milestone(
    id: 'hours_100',
    category: MilestoneCategory.playtime,
    tier: MilestoneTier.silver,
    icon: Icons.schedule_rounded,
    metric: MilestoneMetric.hours,
    threshold: 100,
  ),
  Milestone(
    id: 'hours_500',
    category: MilestoneCategory.playtime,
    tier: MilestoneTier.gold,
    icon: Icons.timer_rounded,
    metric: MilestoneMetric.hours,
    threshold: 500,
    frame: AvatarFrame.neon,
  ),
  Milestone(
    id: 'hours_1000',
    category: MilestoneCategory.playtime,
    tier: MilestoneTier.platinum,
    icon: Icons.nature_people_rounded,
    metric: MilestoneMetric.hours,
    threshold: 1000,
    rewardsTitle: true,
  ),
  Milestone(
    id: 'game_hours_100',
    category: MilestoneCategory.playtime,
    tier: MilestoneTier.gold,
    icon: Icons.favorite_rounded,
    metric: MilestoneMetric.gameHours,
    threshold: 100,
    rewardsTitle: true,
  ),

  // Finisher
  Milestone(
    id: 'completed_1',
    category: MilestoneCategory.finisher,
    tier: MilestoneTier.bronze,
    icon: Icons.verified_rounded,
    metric: MilestoneMetric.completed,
    threshold: 1,
  ),
  Milestone(
    id: 'completed_10',
    category: MilestoneCategory.finisher,
    tier: MilestoneTier.silver,
    icon: Icons.movie_filter_rounded,
    metric: MilestoneMetric.completed,
    threshold: 10,
  ),
  Milestone(
    id: 'completed_25',
    category: MilestoneCategory.finisher,
    tier: MilestoneTier.gold,
    icon: Icons.military_tech_rounded,
    metric: MilestoneMetric.completed,
    threshold: 25,
    frame: AvatarFrame.laurel,
    rewardsTitle: true,
  ),
  Milestone(
    id: 'completed_50',
    category: MilestoneCategory.finisher,
    tier: MilestoneTier.gold,
    icon: Icons.workspace_premium_rounded,
    metric: MilestoneMetric.completed,
    threshold: 50,
  ),
  Milestone(
    id: 'completed_100',
    category: MilestoneCategory.finisher,
    tier: MilestoneTier.platinum,
    icon: Icons.emoji_events_rounded,
    metric: MilestoneMetric.completed,
    threshold: 100,
    rewardsTitle: true,
  ),
  Milestone(
    id: 'completion_time_1',
    category: MilestoneCategory.finisher,
    tier: MilestoneTier.bronze,
    icon: Icons.av_timer_rounded,
    metric: MilestoneMetric.completionTimes,
    threshold: 1,
  ),

  // Streaks
  Milestone(
    id: 'streak_3',
    category: MilestoneCategory.streaks,
    tier: MilestoneTier.bronze,
    icon: Icons.whatshot_rounded,
    metric: MilestoneMetric.streakDays,
    threshold: 3,
  ),
  Milestone(
    id: 'streak_7',
    category: MilestoneCategory.streaks,
    tier: MilestoneTier.silver,
    icon: Icons.bolt_rounded,
    metric: MilestoneMetric.streakDays,
    threshold: 7,
  ),
  Milestone(
    id: 'streak_30',
    category: MilestoneCategory.streaks,
    tier: MilestoneTier.gold,
    icon: Icons.local_fire_department_rounded,
    metric: MilestoneMetric.streakDays,
    threshold: 30,
    frame: AvatarFrame.ember,
    rewardsTitle: true,
  ),
  Milestone(
    id: 'night_owl',
    category: MilestoneCategory.streaks,
    tier: MilestoneTier.bronze,
    icon: Icons.nights_stay_rounded,
    metric: MilestoneMetric.nightSessions,
    threshold: 1,
    rewardsTitle: true,
  ),

  // Critic
  Milestone(
    id: 'rated_1',
    category: MilestoneCategory.critic,
    tier: MilestoneTier.bronze,
    icon: Icons.star_half_rounded,
    metric: MilestoneMetric.rated,
    threshold: 1,
  ),
  Milestone(
    id: 'rated_25',
    category: MilestoneCategory.critic,
    tier: MilestoneTier.silver,
    icon: Icons.star_rounded,
    metric: MilestoneMetric.rated,
    threshold: 25,
  ),
  Milestone(
    id: 'rated_100',
    category: MilestoneCategory.critic,
    tier: MilestoneTier.gold,
    icon: Icons.stars_rounded,
    metric: MilestoneMetric.rated,
    threshold: 100,
  ),
  Milestone(
    id: 'reviews_1',
    category: MilestoneCategory.critic,
    tier: MilestoneTier.bronze,
    icon: Icons.rate_review_rounded,
    metric: MilestoneMetric.reviews,
    threshold: 1,
  ),
  Milestone(
    id: 'reviews_10',
    category: MilestoneCategory.critic,
    tier: MilestoneTier.silver,
    icon: Icons.reviews_rounded,
    metric: MilestoneMetric.reviews,
    threshold: 10,
    rewardsTitle: true,
  ),
  Milestone(
    id: 'reviews_50',
    category: MilestoneCategory.critic,
    tier: MilestoneTier.gold,
    icon: Icons.newspaper_rounded,
    metric: MilestoneMetric.reviews,
    threshold: 50,
  ),

  // Curator
  Milestone(
    id: 'lists_1',
    category: MilestoneCategory.curator,
    tier: MilestoneTier.bronze,
    icon: Icons.playlist_add_rounded,
    metric: MilestoneMetric.lists,
    threshold: 1,
    rewardsTitle: true,
  ),
  Milestone(
    id: 'public_list',
    category: MilestoneCategory.curator,
    tier: MilestoneTier.bronze,
    icon: Icons.public_rounded,
    metric: MilestoneMetric.publicLists,
    threshold: 1,
  ),
  Milestone(
    id: 'list_size_25',
    category: MilestoneCategory.curator,
    tier: MilestoneTier.silver,
    icon: Icons.format_list_numbered_rounded,
    metric: MilestoneMetric.listSize,
    threshold: 25,
  ),

  // Variety
  Milestone(
    id: 'platforms_3',
    category: MilestoneCategory.variety,
    tier: MilestoneTier.silver,
    icon: Icons.devices_rounded,
    metric: MilestoneMetric.platforms,
    threshold: 3,
  ),
  Milestone(
    id: 'platforms_5',
    category: MilestoneCategory.variety,
    tier: MilestoneTier.gold,
    icon: Icons.devices_other_rounded,
    metric: MilestoneMetric.platforms,
    threshold: 5,
  ),
  Milestone(
    id: 'genres_10',
    category: MilestoneCategory.variety,
    tier: MilestoneTier.silver,
    icon: Icons.category_rounded,
    metric: MilestoneMetric.genres,
    threshold: 10,
  ),
  Milestone(
    id: 'retro_1',
    category: MilestoneCategory.variety,
    tier: MilestoneTier.bronze,
    icon: Icons.videogame_asset_rounded,
    metric: MilestoneMetric.retroGames,
    threshold: 1,
  ),
  Milestone(
    id: 'decades_4',
    category: MilestoneCategory.variety,
    tier: MilestoneTier.gold,
    icon: Icons.history_rounded,
    metric: MilestoneMetric.decades,
    threshold: 4,
    rewardsTitle: true,
  ),

  // Social
  Milestone(
    id: 'following_1',
    category: MilestoneCategory.social,
    tier: MilestoneTier.bronze,
    icon: Icons.waving_hand_rounded,
    metric: MilestoneMetric.following,
    threshold: 1,
  ),
  Milestone(
    id: 'followers_1',
    category: MilestoneCategory.social,
    tier: MilestoneTier.bronze,
    icon: Icons.person_add_alt_1_rounded,
    metric: MilestoneMetric.followers,
    threshold: 1,
  ),
  Milestone(
    id: 'followers_10',
    category: MilestoneCategory.social,
    tier: MilestoneTier.silver,
    icon: Icons.trending_up_rounded,
    metric: MilestoneMetric.followers,
    threshold: 10,
  ),
  Milestone(
    id: 'followers_50',
    category: MilestoneCategory.social,
    tier: MilestoneTier.gold,
    icon: Icons.groups_rounded,
    metric: MilestoneMetric.followers,
    threshold: 50,
    rewardsTitle: true,
  ),

  // Membership
  Milestone(
    id: 'member_1m',
    category: MilestoneCategory.membership,
    tier: MilestoneTier.bronze,
    icon: Icons.celebration_rounded,
    metric: MilestoneMetric.memberMonths,
    threshold: 1,
  ),
  Milestone(
    id: 'member_3m',
    category: MilestoneCategory.membership,
    tier: MilestoneTier.bronze,
    icon: Icons.event_available_rounded,
    metric: MilestoneMetric.memberMonths,
    threshold: 3,
  ),
  Milestone(
    id: 'member_6m',
    category: MilestoneCategory.membership,
    tier: MilestoneTier.silver,
    icon: Icons.calendar_month_rounded,
    metric: MilestoneMetric.memberMonths,
    threshold: 6,
  ),
  Milestone(
    id: 'member_1y',
    category: MilestoneCategory.membership,
    tier: MilestoneTier.gold,
    icon: Icons.cake_rounded,
    metric: MilestoneMetric.memberMonths,
    threshold: 12,
    frame: AvatarFrame.veteran,
    rewardsTitle: true,
  ),
  Milestone(
    id: 'member_2y',
    category: MilestoneCategory.membership,
    tier: MilestoneTier.gold,
    icon: Icons.event_repeat_rounded,
    metric: MilestoneMetric.memberMonths,
    threshold: 24,
  ),
  Milestone(
    id: 'member_3y',
    category: MilestoneCategory.membership,
    tier: MilestoneTier.platinum,
    icon: Icons.shield_moon_rounded,
    metric: MilestoneMetric.memberMonths,
    threshold: 36,
    rewardsTitle: true,
  ),
  Milestone(
    id: 'member_5y',
    category: MilestoneCategory.membership,
    tier: MilestoneTier.platinum,
    icon: Icons.diamond_rounded,
    metric: MilestoneMetric.memberMonths,
    threshold: 60,
    rewardsTitle: true,
  ),
  Milestone(
    id: 'founding_member',
    category: MilestoneCategory.membership,
    tier: MilestoneTier.gold,
    icon: Icons.rocket_launch_rounded,
    metric: MilestoneMetric.foundingMember,
    threshold: 1,
    frame: AvatarFrame.founder,
    rewardsTitle: true,
  ),

  // Account
  Milestone(
    id: 'profile_complete',
    category: MilestoneCategory.account,
    tier: MilestoneTier.bronze,
    icon: Icons.face_retouching_natural_rounded,
    metric: MilestoneMetric.profileComplete,
    threshold: 1,
  ),
  Milestone(
    id: 'favorites_4',
    category: MilestoneCategory.account,
    tier: MilestoneTier.bronze,
    icon: Icons.looks_4_rounded,
    metric: MilestoneMetric.favorites,
    threshold: 4,
  ),
  Milestone(
    id: 'wishlist_10',
    category: MilestoneCategory.account,
    tier: MilestoneTier.bronze,
    icon: Icons.bookmark_add_rounded,
    metric: MilestoneMetric.wishlist,
    threshold: 10,
  ),
  Milestone(
    id: 'dropped_1',
    category: MilestoneCategory.account,
    tier: MilestoneTier.bronze,
    icon: Icons.do_not_disturb_on_rounded,
    metric: MilestoneMetric.dropped,
    threshold: 1,
  ),
  // Was "Steam Powered", for Steam only; the id stayed, so those who earned
  // it kept it (20261020140337_milestones_without_steam.sql).
  Milestone(
    id: 'steam_connected',
    category: MilestoneCategory.account,
    tier: MilestoneTier.bronze,
    icon: Icons.cable_rounded,
    metric: MilestoneMetric.gameAccount,
    threshold: 1,
  ),
  Milestone(
    id: 'two_factor',
    category: MilestoneCategory.account,
    tier: MilestoneTier.silver,
    icon: Icons.verified_user_rounded,
    metric: MilestoneMetric.twoFactor,
    threshold: 1,
    frame: AvatarFrame.shield,
  ),
  Milestone(
    id: 'perfect_game',
    category: MilestoneCategory.account,
    tier: MilestoneTier.gold,
    icon: Icons.fact_check_rounded,
    metric: MilestoneMetric.perfectGames,
    threshold: 1,
    rewardsTitle: true,
  ),
];

/// [id]'s name, in the app's language (app_en.arb: `milestone<Id>`).
String? _titleOf(AppLocalizations l10n, String id) => switch (id) {
    'library_1' => l10n.milestoneLibrary1,
    'library_10' => l10n.milestoneLibrary10,
    'library_50' => l10n.milestoneLibrary50,
    'library_100' => l10n.milestoneLibrary100,
    'library_200' => l10n.milestoneLibrary200,
    'library_500' => l10n.milestoneLibrary500,
    'library_1000' => l10n.milestoneLibrary1000,
    'sessions_1' => l10n.milestoneSessions1,
    'sessions_10' => l10n.milestoneSessions10,
    'sessions_50' => l10n.milestoneSessions50,
    'sessions_100' => l10n.milestoneSessions100,
    'sessions_500' => l10n.milestoneSessions500,
    'hours_10' => l10n.milestoneHours10,
    'hours_100' => l10n.milestoneHours100,
    'hours_500' => l10n.milestoneHours500,
    'hours_1000' => l10n.milestoneHours1000,
    'game_hours_100' => l10n.milestoneGameHours100,
    'completed_1' => l10n.milestoneCompleted1,
    'completed_10' => l10n.milestoneCompleted10,
    'completed_25' => l10n.milestoneCompleted25,
    'completed_50' => l10n.milestoneCompleted50,
    'completed_100' => l10n.milestoneCompleted100,
    'completion_time_1' => l10n.milestoneCompletionTime1,
    'streak_3' => l10n.milestoneStreak3,
    'streak_7' => l10n.milestoneStreak7,
    'streak_30' => l10n.milestoneStreak30,
    'night_owl' => l10n.milestoneNightOwl,
    'rated_1' => l10n.milestoneRated1,
    'rated_25' => l10n.milestoneRated25,
    'rated_100' => l10n.milestoneRated100,
    'reviews_1' => l10n.milestoneReviews1,
    'reviews_10' => l10n.milestoneReviews10,
    'reviews_50' => l10n.milestoneReviews50,
    'lists_1' => l10n.milestoneLists1,
    'public_list' => l10n.milestonePublicList,
    'list_size_25' => l10n.milestoneListSize25,
    'platforms_3' => l10n.milestonePlatforms3,
    'platforms_5' => l10n.milestonePlatforms5,
    'genres_10' => l10n.milestoneGenres10,
    'retro_1' => l10n.milestoneRetro1,
    'decades_4' => l10n.milestoneDecades4,
    'following_1' => l10n.milestoneFollowing1,
    'followers_1' => l10n.milestoneFollowers1,
    'followers_10' => l10n.milestoneFollowers10,
    'followers_50' => l10n.milestoneFollowers50,
    'member_1m' => l10n.milestoneMember1m,
    'member_3m' => l10n.milestoneMember3m,
    'member_6m' => l10n.milestoneMember6m,
    'member_1y' => l10n.milestoneMember1y,
    'member_2y' => l10n.milestoneMember2y,
    'member_3y' => l10n.milestoneMember3y,
    'member_5y' => l10n.milestoneMember5y,
    'founding_member' => l10n.milestoneFoundingMember,
    'profile_complete' => l10n.milestoneProfileComplete,
    'favorites_4' => l10n.milestoneFavorites4,
    'wishlist_10' => l10n.milestoneWishlist10,
    'dropped_1' => l10n.milestoneDropped1,
    'steam_connected' => l10n.milestoneSteamConnected,
    'two_factor' => l10n.milestoneTwoFactor,
    'perfect_game' => l10n.milestonePerfectGame,
    _ => null,
};

/// What [id] asks for, in the app's language (`milestone<Id>Description`).
String? _descriptionOf(AppLocalizations l10n, String id) => switch (id) {
    'library_1' => l10n.milestoneLibrary1Description,
    'library_10' => l10n.milestoneLibrary10Description,
    'library_50' => l10n.milestoneLibrary50Description,
    'library_100' => l10n.milestoneLibrary100Description,
    'library_200' => l10n.milestoneLibrary200Description,
    'library_500' => l10n.milestoneLibrary500Description,
    'library_1000' => l10n.milestoneLibrary1000Description,
    'sessions_1' => l10n.milestoneSessions1Description,
    'sessions_10' => l10n.milestoneSessions10Description,
    'sessions_50' => l10n.milestoneSessions50Description,
    'sessions_100' => l10n.milestoneSessions100Description,
    'sessions_500' => l10n.milestoneSessions500Description,
    'hours_10' => l10n.milestoneHours10Description,
    'hours_100' => l10n.milestoneHours100Description,
    'hours_500' => l10n.milestoneHours500Description,
    'hours_1000' => l10n.milestoneHours1000Description,
    'game_hours_100' => l10n.milestoneGameHours100Description,
    'completed_1' => l10n.milestoneCompleted1Description,
    'completed_10' => l10n.milestoneCompleted10Description,
    'completed_25' => l10n.milestoneCompleted25Description,
    'completed_50' => l10n.milestoneCompleted50Description,
    'completed_100' => l10n.milestoneCompleted100Description,
    'completion_time_1' => l10n.milestoneCompletionTime1Description,
    'streak_3' => l10n.milestoneStreak3Description,
    'streak_7' => l10n.milestoneStreak7Description,
    'streak_30' => l10n.milestoneStreak30Description,
    'night_owl' => l10n.milestoneNightOwlDescription,
    'rated_1' => l10n.milestoneRated1Description,
    'rated_25' => l10n.milestoneRated25Description,
    'rated_100' => l10n.milestoneRated100Description,
    'reviews_1' => l10n.milestoneReviews1Description,
    'reviews_10' => l10n.milestoneReviews10Description,
    'reviews_50' => l10n.milestoneReviews50Description,
    'lists_1' => l10n.milestoneLists1Description,
    'public_list' => l10n.milestonePublicListDescription,
    'list_size_25' => l10n.milestoneListSize25Description,
    'platforms_3' => l10n.milestonePlatforms3Description,
    'platforms_5' => l10n.milestonePlatforms5Description,
    'genres_10' => l10n.milestoneGenres10Description,
    'retro_1' => l10n.milestoneRetro1Description,
    'decades_4' => l10n.milestoneDecades4Description,
    'following_1' => l10n.milestoneFollowing1Description,
    'followers_1' => l10n.milestoneFollowers1Description,
    'followers_10' => l10n.milestoneFollowers10Description,
    'followers_50' => l10n.milestoneFollowers50Description,
    'member_1m' => l10n.milestoneMember1mDescription,
    'member_3m' => l10n.milestoneMember3mDescription,
    'member_6m' => l10n.milestoneMember6mDescription,
    'member_1y' => l10n.milestoneMember1yDescription,
    'member_2y' => l10n.milestoneMember2yDescription,
    'member_3y' => l10n.milestoneMember3yDescription,
    'member_5y' => l10n.milestoneMember5yDescription,
    'founding_member' => l10n.milestoneFoundingMemberDescription,
    'profile_complete' => l10n.milestoneProfileCompleteDescription,
    'favorites_4' => l10n.milestoneFavorites4Description,
    'wishlist_10' => l10n.milestoneWishlist10Description,
    'dropped_1' => l10n.milestoneDropped1Description,
    'steam_connected' => l10n.milestoneSteamConnectedDescription,
    'two_factor' => l10n.milestoneTwoFactorDescription,
    'perfect_game' => l10n.milestonePerfectGameDescription,
    _ => null,
};

/// The title [id] unlocks where it is not the milestone's own name
/// (`milestone<Id>RewardTitle`).
String? _rewardTitleOf(AppLocalizations l10n, String id) => switch (id) {
    'streak_30' => l10n.milestoneStreak30RewardTitle,
    'founding_member' => l10n.milestoneFoundingMemberRewardTitle,
    _ => null,
};

final Map<String, Milestone> _byId = {for (final m in milestones) m.id: m};

/// The milestone with [id], or null for one this build doesn't know (added by a
/// newer one).
Milestone? milestoneById(String? id) => id == null ? null : _byId[id];

/// A member's level, from the points of the milestones they earned. Level n
/// starts at 25·n·(n−1) points: 0, 50, 150, 300, 500, 750...
@immutable
class MilestoneLevel {
  const MilestoneLevel._(this.level, this.points);

  factory MilestoneLevel.of(int points) {
    var level = 1;
    while (startOf(level + 1) <= points) {
      level++;
    }
    return MilestoneLevel._(level, points);
  }

  /// The points a member needs to reach [level].
  static int startOf(int level) => 25 * level * (level - 1);

  final int level;
  final int points;

  int get levelStart => startOf(level);
  int get nextLevelAt => startOf(level + 1);

  /// How far into this level, 0 to 1.
  double get progress => (points - levelStart) / (nextLevelAt - levelStart);
}

/// The milestones one member has earned, with when (`user_milestones`). Ids
/// this build doesn't know are kept, so they are not lost from the cache, but
/// count for nothing.
@immutable
class EarnedMilestones {
  const EarnedMilestones([this.unlockedAt = const {}]);

  factory EarnedMilestones.fromJson(Object? json) {
    if (json is! Map) return const EarnedMilestones();
    return EarnedMilestones({
      for (final MapEntry(:key, :value) in json.entries)
        if (DateTime.tryParse('$value') case final at?) '$key': at.toLocal(),
    });
  }

  final Map<String, DateTime> unlockedAt;

  Map<String, String> toJson() => {
    for (final MapEntry(:key, :value) in unlockedAt.entries)
      key: value.toUtc().toIso8601String(),
  };

  bool has(String id) => unlockedAt.containsKey(id);

  /// The ones this build knows, the most recently earned first.
  List<Milestone> get list {
    final known = [for (final id in unlockedAt.keys) ?_byId[id]];
    known.sort((a, b) {
      final byDate = unlockedAt[b.id]!.compareTo(unlockedAt[a.id]!);
      // The same moment (the backfill dates many at once): the harder first.
      return byDate != 0 ? byDate : b.points.compareTo(a.points);
    });
    return known;
  }

  int get count => list.length;
  bool get isEmpty => count == 0;

  int get points => list.fold(0, (sum, m) => sum + m.points);
  MilestoneLevel get level => MilestoneLevel.of(points);

  /// The frames and the titles they unlocked.
  List<AvatarFrame> get frames => [
    for (final frame in AvatarFrame.values)
      if (has(frame.milestone.id)) frame,
  ];
  List<Milestone> get titles => [
    for (final m in milestones)
      if (m.rewardTitle != null && has(m.id)) m,
  ];

  /// These plus [more]; a milestone in both keeps the earlier date.
  EarnedMilestones plus(Map<String, DateTime> more) {
    final merged = Map.of(unlockedAt);
    for (final MapEntry(:key, :value) in more.entries) {
      final before = merged[key];
      if (before == null || value.isBefore(before)) merged[key] = value;
    }
    return EarnedMilestones(Map.unmodifiable(merged));
  }
}

/// What a member shows off on their profile and next to their name in lists:
/// the frame around their photo, the title under their name and up to
/// [maxShowcase] badges (`profiles.avatar_frame`, `title_milestone`,
/// `showcased_milestones`). The server lets them pick only what they earned.
@immutable
class ProfileFlair {
  const ProfileFlair({this.frameId, this.titleId, this.showcaseIds = const []});

  static const maxShowcase = 3;
  static const none = ProfileFlair();

  /// A frame id ([AvatarFrame.id]); null: none.
  final String? frameId;

  /// The milestone whose [Milestone.rewardTitle] shows; null: none.
  final String? titleId;
  final List<String> showcaseIds;

  AvatarFrame? get frame => AvatarFrame.fromId(frameId);
  String? get title => milestoneById(titleId)?.rewardTitle;

  /// The showcased milestones this build knows, in the member's order.
  List<Milestone> get showcase => [
    for (final id in showcaseIds) ?milestoneById(id),
  ];

  bool get isEmpty => frameId == null && titleId == null && showcaseIds.isEmpty;

  @override
  bool operator ==(Object other) =>
      other is ProfileFlair &&
      other.frameId == frameId &&
      other.titleId == titleId &&
      listEquals(other.showcaseIds, showcaseIds);

  @override
  int get hashCode =>
      Object.hash(frameId, titleId, Object.hashAll(showcaseIds));
}

/// [ProfileFlair] as the offline cache keeps it, read back by
/// [profileFlairFromJson].
Map<String, dynamic> profileFlairToJson(ProfileFlair flair) => {
  'frame': flair.frameId,
  'title': flair.titleId,
  'showcase': flair.showcaseIds,
};

/// Anything that isn't what [profileFlairToJson] writes (a copy saved before
/// flair existed) is no flair.
ProfileFlair profileFlairFromJson(Object? json) {
  if (json is! Map) return ProfileFlair.none;
  final showcase = json['showcase'];
  return ProfileFlair(
    frameId: json['frame'] as String?,
    titleId: json['title'] as String?,
    showcaseIds: showcase is List
        ? [for (final id in showcase) '$id']
        : const [],
  );
}
