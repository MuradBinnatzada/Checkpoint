import 'package:flutter/material.dart';

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
