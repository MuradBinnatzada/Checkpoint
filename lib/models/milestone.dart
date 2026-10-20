import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// How hard a milestone is to reach: the colour of its badge and the points it
/// gives towards the member's level ([MilestoneLevel]).
enum MilestoneTier {
  bronze('Bronze', Color(0xFFD08C57), 10),
  silver('Silver', Color(0xFFB9C3CF), 25),
  gold('Gold', Color(0xFFFFC857), 50),
  platinum('Platinum', Color(0xFF8FE3EC), 100);

  const MilestoneTier(this.label, this.color, this.points);
  final String label;

  /// Picked for the dark theme; pass it through `Palette.legible` for text and
  /// icons on the light one.
  final Color color;
  final int points;
}

/// The sections of the Milestones screen, in the order it lists them.
enum MilestoneCategory {
  library('Library', Icons.collections_bookmark_rounded),
  logbook('Logbook', Icons.edit_calendar_rounded),
  playtime('Playtime', Icons.schedule_rounded),
  finisher('Finisher', Icons.verified_rounded),
  streaks('Streaks', Icons.local_fire_department_rounded),
  critic('Critic', Icons.star_rounded),
  curator('Curator', Icons.format_list_bulleted_rounded),
  variety('Variety', Icons.explore_rounded),
  social('Social', Icons.people_alt_rounded),
  membership('Membership', Icons.cake_rounded),
  account('Account', Icons.person_rounded);

  const MilestoneCategory(this.label, this.icon);
  final String label;
  final IconData icon;
}

/// What a milestone counts: `milestones.metric` in the database, where
/// `award_milestones` works each one out (20261020120100_milestones.sql).
/// [unit] names what is counted in a progress line ("37 / 50 games"); empty for
/// a milestone that is a yes or no.
enum MilestoneMetric {
  libraryGames('library_games', 'games'),
  sessions('sessions', 'sessions'),
  hours('hours', 'hours'),
  gameHours('game_hours', 'hours'),
  completed('completed', 'completed'),
  completionTimes('completion_times', 'times'),
  streakDays('streak_days', 'days'),
  nightSessions('night_sessions', ''),
  rated('rated', 'rated'),
  reviews('reviews', 'reviews'),
  lists('lists', 'lists'),
  publicLists('public_lists', ''),
  listSize('list_size', 'games'),
  platforms('platforms', 'platforms'),
  genres('genres', 'genres'),
  retroGames('retro_games', ''),
  decades('decades', 'decades'),
  following('following', ''),
  followers('followers', 'followers'),
  memberMonths('member_months', 'months'),
  foundingMember('founding_member', ''),
  profileComplete('profile_complete', ''),
  favorites('favorites', 'favorites'),
  wishlist('wishlist', 'wishlisted'),
  dropped('dropped', ''),
  steamConnected('steam_connected', ''),
  twoFactor('two_factor', ''),
  perfectGames('perfect_games', '');

  const MilestoneMetric(this.wire, this.unit);
  final String wire;
  final String unit;
}

/// A ring drawn around a member's photo, unlocked by one milestone
/// ([Milestone.frame]). [id] is what `profiles.avatar_frame` stores.
enum AvatarFrame {
  bronze('bronze', 'Bronze', [Color(0xFFB87333), Color(0xFFE6B07E)]),
  silver('silver', 'Silver', [Color(0xFF8E99A6), Color(0xFFE6EBF0)]),
  gold('gold', 'Gold', [Color(0xFFFFA000), Color(0xFFFFE082)]),
  prism('prism', 'Prism', [
    Color(0xFFBB86FC),
    Color(0xFF4FC3F7),
    Color(0xFF7DDC9C),
    Color(0xFFBB86FC),
  ]),
  platinum('platinum', 'Platinum', [
    Color(0xFF80DEEA),
    Color(0xFFFFFFFF),
    Color(0xFF9FA8DA),
    Color(0xFF80DEEA),
  ], animated: true),
  neon('neon', 'Neon', [Color(0xFFBB86FC), Color(0xFF4FC3F7)]),
  laurel('laurel', 'Laurel', [Color(0xFF2E7D32), Color(0xFF9CE5B3)]),
  ember('ember', 'Ember', [Color(0xFFFF5722), Color(0xFFFFC857)]),
  shield('shield', 'Shield', [Color(0xFF1565C0), Color(0xFF4FC3F7)]),
  veteran('veteran', 'Veteran', [Color(0xFF7B1FA2), Color(0xFFFFC857)]),
  founder('founder', 'Founder', [
    Color(0xFFFFC857),
    Color(0xFFBB86FC),
    Color(0xFF4FC3F7),
    Color(0xFFFFC857),
  ], animated: true);

  const AvatarFrame(this.id, this.label, this.colors, {this.animated = false});
  final String id;
  final String label;

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
    required this.title,
    required this.description,
    required this.category,
    required this.tier,
    required this.icon,
    required this.metric,
    required this.threshold,
    this.frame,
    this.rewardTitle,
  });

  /// `milestones.id` and `user_milestones.milestone_id`.
  final String id;
  final String title;
  final String description;
  final MilestoneCategory category;
  final MilestoneTier tier;
  final IconData icon;
  final MilestoneMetric metric;

  /// How much of [metric] it takes.
  final int threshold;

  /// The avatar frame it unlocks, if any.
  final AvatarFrame? frame;

  /// The title it lets the member show under their name, if any.
  final String? rewardTitle;

  int get points => tier.points;

  /// Reached or not, with nothing to count towards it.
  bool get isYesNo => metric.unit.isEmpty;
}

/// Every milestone, by category, easiest first. Must match the `milestones` rows
/// of 20261020120100_milestones.sql (ids, metrics, thresholds, frames, titles);
/// test/milestones_test.dart compares them. Ids are stored: never rename one.
const List<Milestone> milestones = [
  // Library
  Milestone(
    id: 'library_1',
    title: 'First Pick',
    description: 'Add your first game to your library.',
    category: MilestoneCategory.library,
    tier: MilestoneTier.bronze,
    icon: Icons.add_box_rounded,
    metric: MilestoneMetric.libraryGames,
    threshold: 1,
  ),
  Milestone(
    id: 'library_10',
    title: 'Shelf Starter',
    description: 'Have 10 games in your library.',
    category: MilestoneCategory.library,
    tier: MilestoneTier.bronze,
    icon: Icons.collections_bookmark_rounded,
    metric: MilestoneMetric.libraryGames,
    threshold: 10,
    frame: AvatarFrame.bronze,
  ),
  Milestone(
    id: 'library_50',
    title: 'Bookshelf',
    description: 'Have 50 games in your library.',
    category: MilestoneCategory.library,
    tier: MilestoneTier.silver,
    icon: Icons.library_books_rounded,
    metric: MilestoneMetric.libraryGames,
    threshold: 50,
    frame: AvatarFrame.silver,
  ),
  Milestone(
    id: 'library_100',
    title: 'Collector',
    description: 'Have 100 games in your library.',
    category: MilestoneCategory.library,
    tier: MilestoneTier.gold,
    icon: Icons.inventory_2_rounded,
    metric: MilestoneMetric.libraryGames,
    threshold: 100,
    frame: AvatarFrame.gold,
    rewardTitle: 'Collector',
  ),
  Milestone(
    id: 'library_200',
    title: 'Archivist',
    description: 'Have 200 games in your library.',
    category: MilestoneCategory.library,
    tier: MilestoneTier.gold,
    icon: Icons.warehouse_rounded,
    metric: MilestoneMetric.libraryGames,
    threshold: 200,
    frame: AvatarFrame.prism,
  ),
  Milestone(
    id: 'library_500',
    title: 'Hoarder',
    description: 'Have 500 games in your library.',
    category: MilestoneCategory.library,
    tier: MilestoneTier.platinum,
    icon: Icons.museum_rounded,
    metric: MilestoneMetric.libraryGames,
    threshold: 500,
    frame: AvatarFrame.platinum,
    rewardTitle: 'Hoarder',
  ),
  Milestone(
    id: 'library_1000',
    title: 'Living Museum',
    description: 'Have 1,000 games in your library.',
    category: MilestoneCategory.library,
    tier: MilestoneTier.platinum,
    icon: Icons.account_balance_rounded,
    metric: MilestoneMetric.libraryGames,
    threshold: 1000,
  ),

  // Logbook
  Milestone(
    id: 'sessions_1',
    title: 'Checkpoint Reached',
    description: 'Log your first play session.',
    category: MilestoneCategory.logbook,
    tier: MilestoneTier.bronze,
    icon: Icons.flag_rounded,
    metric: MilestoneMetric.sessions,
    threshold: 1,
  ),
  Milestone(
    id: 'sessions_10',
    title: 'Getting Into It',
    description: 'Log 10 play sessions.',
    category: MilestoneCategory.logbook,
    tier: MilestoneTier.bronze,
    icon: Icons.edit_note_rounded,
    metric: MilestoneMetric.sessions,
    threshold: 10,
  ),
  Milestone(
    id: 'sessions_50',
    title: 'Regular Logger',
    description: 'Log 50 play sessions.',
    category: MilestoneCategory.logbook,
    tier: MilestoneTier.silver,
    icon: Icons.menu_book_rounded,
    metric: MilestoneMetric.sessions,
    threshold: 50,
  ),
  Milestone(
    id: 'sessions_100',
    title: 'Diarist',
    description: 'Log 100 play sessions.',
    category: MilestoneCategory.logbook,
    tier: MilestoneTier.gold,
    icon: Icons.auto_stories_rounded,
    metric: MilestoneMetric.sessions,
    threshold: 100,
  ),
  Milestone(
    id: 'sessions_500',
    title: 'Chronicler',
    description: 'Log 500 play sessions.',
    category: MilestoneCategory.logbook,
    tier: MilestoneTier.platinum,
    icon: Icons.history_edu_rounded,
    metric: MilestoneMetric.sessions,
    threshold: 500,
    rewardTitle: 'Chronicler',
  ),

  // Playtime
  Milestone(
    id: 'hours_10',
    title: 'Warming Up',
    description: 'Play 10 hours in total.',
    category: MilestoneCategory.playtime,
    tier: MilestoneTier.bronze,
    icon: Icons.hourglass_bottom_rounded,
    metric: MilestoneMetric.hours,
    threshold: 10,
  ),
  Milestone(
    id: 'hours_100',
    title: 'Hundred Hours',
    description: 'Play 100 hours in total.',
    category: MilestoneCategory.playtime,
    tier: MilestoneTier.silver,
    icon: Icons.schedule_rounded,
    metric: MilestoneMetric.hours,
    threshold: 100,
  ),
  Milestone(
    id: 'hours_500',
    title: 'Dedicated',
    description: 'Play 500 hours in total.',
    category: MilestoneCategory.playtime,
    tier: MilestoneTier.gold,
    icon: Icons.timer_rounded,
    metric: MilestoneMetric.hours,
    threshold: 500,
    frame: AvatarFrame.neon,
  ),
  Milestone(
    id: 'hours_1000',
    title: 'Touch Grass',
    description: 'Play 1,000 hours in total.',
    category: MilestoneCategory.playtime,
    tier: MilestoneTier.platinum,
    icon: Icons.nature_people_rounded,
    metric: MilestoneMetric.hours,
    threshold: 1000,
    rewardTitle: 'Touch Grass',
  ),
  Milestone(
    id: 'game_hours_100',
    title: 'Devoted',
    description: 'Play one game for 100 hours.',
    category: MilestoneCategory.playtime,
    tier: MilestoneTier.gold,
    icon: Icons.favorite_rounded,
    metric: MilestoneMetric.gameHours,
    threshold: 100,
    rewardTitle: 'Devoted',
  ),

  // Finisher
  Milestone(
    id: 'completed_1',
    title: 'The End',
    description: 'Complete your first game.',
    category: MilestoneCategory.finisher,
    tier: MilestoneTier.bronze,
    icon: Icons.verified_rounded,
    metric: MilestoneMetric.completed,
    threshold: 1,
  ),
  Milestone(
    id: 'completed_10',
    title: 'Credits Roll',
    description: 'Complete 10 games.',
    category: MilestoneCategory.finisher,
    tier: MilestoneTier.silver,
    icon: Icons.movie_filter_rounded,
    metric: MilestoneMetric.completed,
    threshold: 10,
  ),
  Milestone(
    id: 'completed_25',
    title: 'Finisher',
    description: 'Complete 25 games.',
    category: MilestoneCategory.finisher,
    tier: MilestoneTier.gold,
    icon: Icons.military_tech_rounded,
    metric: MilestoneMetric.completed,
    threshold: 25,
    frame: AvatarFrame.laurel,
    rewardTitle: 'Finisher',
  ),
  Milestone(
    id: 'completed_50',
    title: 'Closer',
    description: 'Complete 50 games.',
    category: MilestoneCategory.finisher,
    tier: MilestoneTier.gold,
    icon: Icons.workspace_premium_rounded,
    metric: MilestoneMetric.completed,
    threshold: 50,
  ),
  Milestone(
    id: 'completed_100',
    title: 'Completionist',
    description: 'Complete 100 games.',
    category: MilestoneCategory.finisher,
    tier: MilestoneTier.platinum,
    icon: Icons.emoji_events_rounded,
    metric: MilestoneMetric.completed,
    threshold: 100,
    rewardTitle: 'Completionist',
  ),
  Milestone(
    id: 'completion_time_1',
    title: 'Stopwatch',
    description: 'Add how long a game took you to finish.',
    category: MilestoneCategory.finisher,
    tier: MilestoneTier.bronze,
    icon: Icons.av_timer_rounded,
    metric: MilestoneMetric.completionTimes,
    threshold: 1,
  ),

  // Streaks
  Milestone(
    id: 'streak_3',
    title: 'Hat Trick',
    description: 'Log a session 3 days in a row.',
    category: MilestoneCategory.streaks,
    tier: MilestoneTier.bronze,
    icon: Icons.whatshot_rounded,
    metric: MilestoneMetric.streakDays,
    threshold: 3,
  ),
  Milestone(
    id: 'streak_7',
    title: 'On a Roll',
    description: 'Log a session 7 days in a row.',
    category: MilestoneCategory.streaks,
    tier: MilestoneTier.silver,
    icon: Icons.bolt_rounded,
    metric: MilestoneMetric.streakDays,
    threshold: 7,
  ),
  Milestone(
    id: 'streak_30',
    title: 'Unstoppable',
    description: 'Log a session 30 days in a row.',
    category: MilestoneCategory.streaks,
    tier: MilestoneTier.gold,
    icon: Icons.local_fire_department_rounded,
    metric: MilestoneMetric.streakDays,
    threshold: 30,
    frame: AvatarFrame.ember,
    rewardTitle: 'Marathoner',
  ),
  Milestone(
    id: 'night_owl',
    title: 'Night Owl',
    description: 'Log a session between midnight and 4 am.',
    category: MilestoneCategory.streaks,
    tier: MilestoneTier.bronze,
    icon: Icons.nights_stay_rounded,
    metric: MilestoneMetric.nightSessions,
    threshold: 1,
    rewardTitle: 'Night Owl',
  ),

  // Critic
  Milestone(
    id: 'rated_1',
    title: 'First Impressions',
    description: 'Rate a game.',
    category: MilestoneCategory.critic,
    tier: MilestoneTier.bronze,
    icon: Icons.star_half_rounded,
    metric: MilestoneMetric.rated,
    threshold: 1,
  ),
  Milestone(
    id: 'rated_25',
    title: 'Opinionated',
    description: 'Rate 25 games.',
    category: MilestoneCategory.critic,
    tier: MilestoneTier.silver,
    icon: Icons.star_rounded,
    metric: MilestoneMetric.rated,
    threshold: 25,
  ),
  Milestone(
    id: 'rated_100',
    title: 'Tastemaker',
    description: 'Rate 100 games.',
    category: MilestoneCategory.critic,
    tier: MilestoneTier.gold,
    icon: Icons.stars_rounded,
    metric: MilestoneMetric.rated,
    threshold: 100,
  ),
  Milestone(
    id: 'reviews_1',
    title: 'First Review',
    description: 'Write a review.',
    category: MilestoneCategory.critic,
    tier: MilestoneTier.bronze,
    icon: Icons.rate_review_rounded,
    metric: MilestoneMetric.reviews,
    threshold: 1,
  ),
  Milestone(
    id: 'reviews_10',
    title: 'Critic',
    description: 'Write 10 reviews.',
    category: MilestoneCategory.critic,
    tier: MilestoneTier.silver,
    icon: Icons.reviews_rounded,
    metric: MilestoneMetric.reviews,
    threshold: 10,
    rewardTitle: 'Critic',
  ),
  Milestone(
    id: 'reviews_50',
    title: 'Columnist',
    description: 'Write 50 reviews.',
    category: MilestoneCategory.critic,
    tier: MilestoneTier.gold,
    icon: Icons.newspaper_rounded,
    metric: MilestoneMetric.reviews,
    threshold: 50,
  ),

  // Curator
  Milestone(
    id: 'lists_1',
    title: 'Curator',
    description: 'Make your first list.',
    category: MilestoneCategory.curator,
    tier: MilestoneTier.bronze,
    icon: Icons.playlist_add_rounded,
    metric: MilestoneMetric.lists,
    threshold: 1,
    rewardTitle: 'Curator',
  ),
  Milestone(
    id: 'public_list',
    title: 'On Display',
    description: 'Make a list public.',
    category: MilestoneCategory.curator,
    tier: MilestoneTier.bronze,
    icon: Icons.public_rounded,
    metric: MilestoneMetric.publicLists,
    threshold: 1,
  ),
  Milestone(
    id: 'list_size_25',
    title: 'Big List',
    description: 'Put 25 games on one list.',
    category: MilestoneCategory.curator,
    tier: MilestoneTier.silver,
    icon: Icons.format_list_numbered_rounded,
    metric: MilestoneMetric.listSize,
    threshold: 25,
  ),

  // Variety
  Milestone(
    id: 'platforms_3',
    title: 'Multi-Platform',
    description: 'Play on 3 different platforms.',
    category: MilestoneCategory.variety,
    tier: MilestoneTier.silver,
    icon: Icons.devices_rounded,
    metric: MilestoneMetric.platforms,
    threshold: 3,
  ),
  Milestone(
    id: 'platforms_5',
    title: 'Platform Hopper',
    description: 'Play on 5 different platforms.',
    category: MilestoneCategory.variety,
    tier: MilestoneTier.gold,
    icon: Icons.devices_other_rounded,
    metric: MilestoneMetric.platforms,
    threshold: 5,
  ),
  Milestone(
    id: 'genres_10',
    title: 'Genre Hopper',
    description: 'Play games from 10 different genres.',
    category: MilestoneCategory.variety,
    tier: MilestoneTier.silver,
    icon: Icons.category_rounded,
    metric: MilestoneMetric.genres,
    threshold: 10,
  ),
  Milestone(
    id: 'retro_1',
    title: 'Old School',
    description: 'Play a game released before 1995.',
    category: MilestoneCategory.variety,
    tier: MilestoneTier.bronze,
    icon: Icons.videogame_asset_rounded,
    metric: MilestoneMetric.retroGames,
    threshold: 1,
  ),
  Milestone(
    id: 'decades_4',
    title: 'Time Traveler',
    description: 'Play games from 4 different decades.',
    category: MilestoneCategory.variety,
    tier: MilestoneTier.gold,
    icon: Icons.history_rounded,
    metric: MilestoneMetric.decades,
    threshold: 4,
    rewardTitle: 'Time Traveler',
  ),

  // Social
  Milestone(
    id: 'following_1',
    title: 'Say Hi',
    description: 'Follow another member.',
    category: MilestoneCategory.social,
    tier: MilestoneTier.bronze,
    icon: Icons.waving_hand_rounded,
    metric: MilestoneMetric.following,
    threshold: 1,
  ),
  Milestone(
    id: 'followers_1',
    title: 'Fan Club',
    description: 'Get your first follower.',
    category: MilestoneCategory.social,
    tier: MilestoneTier.bronze,
    icon: Icons.person_add_alt_1_rounded,
    metric: MilestoneMetric.followers,
    threshold: 1,
  ),
  Milestone(
    id: 'followers_10',
    title: 'Rising Star',
    description: 'Have 10 followers.',
    category: MilestoneCategory.social,
    tier: MilestoneTier.silver,
    icon: Icons.trending_up_rounded,
    metric: MilestoneMetric.followers,
    threshold: 10,
  ),
  Milestone(
    id: 'followers_50',
    title: 'Socialite',
    description: 'Have 50 followers.',
    category: MilestoneCategory.social,
    tier: MilestoneTier.gold,
    icon: Icons.groups_rounded,
    metric: MilestoneMetric.followers,
    threshold: 50,
    rewardTitle: 'Socialite',
  ),

  // Membership
  Milestone(
    id: 'member_1m',
    title: 'Welcome Aboard',
    description: 'Be a member for a month.',
    category: MilestoneCategory.membership,
    tier: MilestoneTier.bronze,
    icon: Icons.celebration_rounded,
    metric: MilestoneMetric.memberMonths,
    threshold: 1,
  ),
  Milestone(
    id: 'member_3m',
    title: 'Settling In',
    description: 'Be a member for 3 months.',
    category: MilestoneCategory.membership,
    tier: MilestoneTier.bronze,
    icon: Icons.event_available_rounded,
    metric: MilestoneMetric.memberMonths,
    threshold: 3,
  ),
  Milestone(
    id: 'member_6m',
    title: 'Regular',
    description: 'Be a member for 6 months.',
    category: MilestoneCategory.membership,
    tier: MilestoneTier.silver,
    icon: Icons.calendar_month_rounded,
    metric: MilestoneMetric.memberMonths,
    threshold: 6,
  ),
  Milestone(
    id: 'member_1y',
    title: 'Veteran',
    description: 'Be a member for a year.',
    category: MilestoneCategory.membership,
    tier: MilestoneTier.gold,
    icon: Icons.cake_rounded,
    metric: MilestoneMetric.memberMonths,
    threshold: 12,
    frame: AvatarFrame.veteran,
    rewardTitle: 'Veteran',
  ),
  Milestone(
    id: 'member_2y',
    title: 'Two Years Strong',
    description: 'Be a member for 2 years.',
    category: MilestoneCategory.membership,
    tier: MilestoneTier.gold,
    icon: Icons.event_repeat_rounded,
    metric: MilestoneMetric.memberMonths,
    threshold: 24,
  ),
  Milestone(
    id: 'member_3y',
    title: 'Old Guard',
    description: 'Be a member for 3 years.',
    category: MilestoneCategory.membership,
    tier: MilestoneTier.platinum,
    icon: Icons.shield_moon_rounded,
    metric: MilestoneMetric.memberMonths,
    threshold: 36,
    rewardTitle: 'Old Guard',
  ),
  Milestone(
    id: 'member_5y',
    title: 'Legend',
    description: 'Be a member for 5 years.',
    category: MilestoneCategory.membership,
    tier: MilestoneTier.platinum,
    icon: Icons.diamond_rounded,
    metric: MilestoneMetric.memberMonths,
    threshold: 60,
    rewardTitle: 'Legend',
  ),
  Milestone(
    id: 'founding_member',
    title: 'Founding Member',
    description: 'Join Checkpoint in its first year, 2026.',
    category: MilestoneCategory.membership,
    tier: MilestoneTier.gold,
    icon: Icons.rocket_launch_rounded,
    metric: MilestoneMetric.foundingMember,
    threshold: 1,
    frame: AvatarFrame.founder,
    rewardTitle: 'Founder',
  ),

  // Account
  Milestone(
    id: 'profile_complete',
    title: 'Looking Sharp',
    description: 'Add a profile photo and a bio.',
    category: MilestoneCategory.account,
    tier: MilestoneTier.bronze,
    icon: Icons.face_retouching_natural_rounded,
    metric: MilestoneMetric.profileComplete,
    threshold: 1,
  ),
  Milestone(
    id: 'favorites_4',
    title: 'Top Four',
    description: 'Pick 4 favorite games.',
    category: MilestoneCategory.account,
    tier: MilestoneTier.bronze,
    icon: Icons.looks_4_rounded,
    metric: MilestoneMetric.favorites,
    threshold: 4,
  ),
  Milestone(
    id: 'wishlist_10',
    title: 'Window Shopper',
    description: 'Wishlist 10 games.',
    category: MilestoneCategory.account,
    tier: MilestoneTier.bronze,
    icon: Icons.bookmark_add_rounded,
    metric: MilestoneMetric.wishlist,
    threshold: 10,
  ),
  Milestone(
    id: 'dropped_1',
    title: 'Know When to Fold',
    description: 'Drop a game.',
    category: MilestoneCategory.account,
    tier: MilestoneTier.bronze,
    icon: Icons.do_not_disturb_on_rounded,
    metric: MilestoneMetric.dropped,
    threshold: 1,
  ),
  Milestone(
    id: 'steam_connected',
    title: 'Steam Powered',
    description: 'Connect your Steam account.',
    category: MilestoneCategory.account,
    tier: MilestoneTier.bronze,
    icon: Icons.cloud_sync_rounded,
    metric: MilestoneMetric.steamConnected,
    threshold: 1,
  ),
  Milestone(
    id: 'two_factor',
    title: 'Locked Down',
    description: 'Turn on two-factor authentication.',
    category: MilestoneCategory.account,
    tier: MilestoneTier.silver,
    icon: Icons.verified_user_rounded,
    metric: MilestoneMetric.twoFactor,
    threshold: 1,
    frame: AvatarFrame.shield,
  ),
  Milestone(
    id: 'perfect_game',
    title: 'Perfectionist',
    description: 'Unlock every Steam achievement in a game.',
    category: MilestoneCategory.account,
    tier: MilestoneTier.gold,
    icon: Icons.fact_check_rounded,
    metric: MilestoneMetric.perfectGames,
    threshold: 1,
    rewardTitle: 'Perfectionist',
  ),
];

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
