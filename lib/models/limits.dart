/// The ranges the database accepts for what members type in
/// (20261019013500_value_limits_and_atomic_deletes.sql), and the tighter ones
/// the app asks for. The server checks its own; these keep a request it would
/// refuse from being sent.
library;

/// The most hours a game's total, or one session, can hold.
const maxTotalHours = 100000.0;

/// The longest session the app logs at once: one sitting. A bigger change is
/// made to the game's total (Log Hours), which logs the difference.
const maxSessionHours = 24.0;

/// The longest note on a play session.
const maxNoteLength = 1000;
