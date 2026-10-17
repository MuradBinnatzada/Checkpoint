abstract final class Db {
  static const profiles = 'profiles';

  /// View over `profiles` with only the public columns (id, handle,
  /// display_name, avatar_url). Use it for any query that reads OTHER members;
  /// `profiles` itself is readable only for the signed-in user's own row.
  static const publicProfiles = 'public_profiles';

  /// What other members may see of a library: tracking fields plus catalog data
  /// in one row, without `purchase_price` or `achievements`.
  static const publicUserGames = 'public_user_games';

  /// Follow edges joined to the other member's public fields: `public_followers`
  /// are the members who follow `user_id`, `public_following` those they follow.
  static const publicFollowers = 'public_followers';
  static const publicFollowing = 'public_following';

  /// Functions (called with `rpc`). Achievements of another member are only
  /// reachable through the last two; no table or view carries them.
  static const rpcProfileStats = 'public_profile_stats';
  static const rpcAchievementSummary = 'public_achievement_summary';
  static const rpcGameAchievements = 'public_game_achievements';

  static const games = 'games';
  static const userGames = 'user_games';
  static const logEntries = 'log_entries';
  static const socialFollows = 'social_follows';

  static const id = 'id';
  static const createdAt = 'created_at';
  static const updatedAt = 'updated_at';

  static const handle = 'handle';
  static const email = 'email';
  static const displayName = 'display_name';
  static const bio = 'bio';
  static const avatarUrl = 'avatar_url';
  static const steamId = 'steam_id';

  /// `public_profiles` only: whether a Steam ID is set (the ID itself is private).
  static const steamConnected = 'steam_connected';

  /// Names of the services connected besides Steam (`psn`, `xbox`, `discord`,
  /// `nintendo`). Readable in `public_profiles` and writable on your own
  /// `profiles` row. The account names behind them are never stored.
  static const connectedServices = 'connected_services';

  static const weeklyGoalHours = 'weekly_goal_hours';

  static const igdbId = 'igdb_id';
  static const steamAppId = 'steam_app_id';
  static const slug = 'slug';
  static const title = 'title';
  static const publisher = 'publisher';
  static const developer = 'developer';
  static const releaseYear = 'release_year';
  static const platforms = 'platforms';
  static const genres = 'genres';
  static const summary = 'summary';
  static const coverUrl = 'cover_url';
  static const createdBy = 'created_by';

  static const userId = 'user_id';
  static const gameId = 'game_id';
  static const status = 'status';
  static const rating = 'rating';
  static const hoursPlayed = 'hours_played';
  static const playedOn = 'played_on';
  static const purchasePrice = 'purchase_price';
  static const dateAdded = 'date_added';

  static const loggedAt = 'logged_at';
  static const hours = 'hours';
  static const platform = 'platform';
  static const note = 'note';
  static const isFavorite = 'is_favorite';

  static const followerId = 'follower_id';
  static const followeeId = 'followee_id';

  /// `public_followers` / `public_following`: when the follow happened.
  static const followedAt = 'followed_at';
}