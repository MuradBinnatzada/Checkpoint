abstract final class Db {
  static const profiles = 'profiles';

  /// View over `profiles` with only the public columns (id, handle,
  /// display_name, avatar_url). Use it for any query that reads OTHER members;
  /// `profiles` itself is readable only for the signed-in user's own row.
  static const publicProfiles = 'public_profiles';

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
}