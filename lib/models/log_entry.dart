import 'package:flutter/foundation.dart';

import 'package:checkpoint/models/game.dart';

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
