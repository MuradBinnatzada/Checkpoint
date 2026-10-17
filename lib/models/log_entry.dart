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

  factory LogEntry.fromJson(Map<String, dynamic> json) => LogEntry(
        id: json['id'] as String,
        gameId: json['gameId'] as String,
        timestamp: DateTime.parse(json['timestamp'] as String).toLocal(),
        hours: (json['hours'] as num).toDouble(),
        platform: gamePlatformFromDb(json['platform']) ?? GamePlatform.pc,
        note: json['note'] as String? ?? '',
      );

  final String id;
  final String gameId;
  final DateTime timestamp;
  final double hours;
  final GamePlatform platform;
  final String note;

  /// What the offline cache keeps of this session; read back by [LogEntry.fromJson].
  Map<String, dynamic> toJson() => {
        'id': id,
        'gameId': gameId,
        'timestamp': timestamp.toUtc().toIso8601String(),
        'hours': hours,
        'platform': gamePlatformToDb(platform),
        'note': note,
      };
}
