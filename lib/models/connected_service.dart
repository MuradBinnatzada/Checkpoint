import 'package:flutter/material.dart';

/// Swap the icons for real brand logos once you add assets.
enum ConnectedService {
  steam('Steam', Icons.laptop_chromebook_rounded, Color(0xFF66C0F4), true),
  discord('Discord', Icons.discord, Color(0xFF5865F2), true),
  psn('PSN', Icons.sports_esports_rounded, Color(0xFF00439C), false),
  xbox('Xbox', Icons.videogame_asset_rounded, Color(0xFF107C10), false),
  nintendo('Nintendo', Icons.videogame_asset_rounded, Color(0xFFE60012), false);

  const ConnectedService(this.label, this.icon, this.color, this.supportsSync);
  final String label;
  final IconData icon;
  final Color color;
  final bool supportsSync;
}