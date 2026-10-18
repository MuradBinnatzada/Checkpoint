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

  /// A member's play sessions (game, hours, platform, when) with the catalog data
  /// of the game. No notes.
  static const publicRecentActivity = 'public_recent_activity';

  /// Functions (called with `rpc`). Achievements of another member are only
  /// reachable through the last three; no table or view carries them.
  static const rpcProfileStats = 'public_profile_stats';
  static const rpcAchievementTotals = 'public_achievement_totals';
  static const rpcAchievementSummary = 'public_achievement_summary';
  static const rpcGameAchievements = 'public_game_achievements';

  /// The members the signed-in one follows who have a game, with their status
  /// and rating: the Friends panel on a game's screen.
  static const rpcFollowingGameActivity = 'following_game_activity';

  /// The newest sessions, completions and ratings of the members the signed-in
  /// one follows: "From people you follow" on Home.
  static const rpcFollowingRecentActivity = 'following_recent_activity';

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

  /// `public_profiles` only: whether a Steam ID is set.
  static const steamConnected = 'steam_connected';

  /// Names of the services connected besides Steam (`psn`, `xbox`, `nintendo`,
  /// `discord`, `instagram`, `twitch`). Readable in `public_profiles` and
  /// writable on your own `profiles` row.
  static const connectedServices = 'connected_services';

  /// The account names behind the services: PSN id, Xbox gamertag, Discord,
  /// Instagram and Twitch usernames. Public to signed-in members (the profile
  /// links open them).
  static const psnId = 'psn_id';
  static const xboxId = 'xbox_id';
  static const discordId = 'discord_id';
  static const instagramId = 'instagram_id';
  static const twitchId = 'twitch_id';

  /// `public_profiles` only: `profiles.created_at`, the member's join date.
  static const joinedAt = 'joined_at';

  /// `public_profiles` only: how many games the member has, how many members
  /// follow them, and whether the signed-in member is one of those.
  static const gamesCount = 'games_count';
  static const followersCount = 'followers_count';
  static const viewerFollows = 'viewer_follows';

  /// Whether other members may see the member's Steam achievements (Settings >
  /// Privacy). Written on your own `profiles` row, readable in `public_profiles`.
  static const showSteamAchievements = 'show_steam_achievements';

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

  /// When `igdb-handler` last filled the row in from IGDB; NULL: never.
  static const igdbSyncedAt = 'igdb_synced_at';

  /// What `igdb-handler` keeps of a game besides `platforms` and `genres`: text
  /// arrays on `games`, empty until the row was filled in.
  static const developers = 'developers';
  static const publishers = 'publishers';
  static const themes = 'themes';
  static const gameModes = 'game_modes';
  static const playerPerspectives = 'player_perspectives';
  static const gameEngines = 'game_engines';

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

  /// `user_games` (and `public_user_games`): the member's own backdrop for the
  /// game, an IGDB image URL; NULL: the blurred cover.
  static const customBackdropUrl = 'custom_backdrop_url';

  static const followerId = 'follower_id';
  static const followeeId = 'followee_id';

  /// `public_followers` / `public_following`: when the follow happened.
  static const followedAt = 'followed_at';
}