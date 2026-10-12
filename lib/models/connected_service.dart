import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

/// Services the user can connect, each with its brand icon and color.
enum ConnectedService {
  steam('Steam', FontAwesomeIcons.steam, Color(0xFF66C0F4), true),
  discord('Discord', FontAwesomeIcons.discord, Color(0xFF5865F2), true),
  psn('PSN', FontAwesomeIcons.playstation, Color(0xFF00439C), false),
  xbox('Xbox', FontAwesomeIcons.xbox, Color(0xFF107C10), false),
  nintendo('Nintendo', FontAwesomeIcons.gamepad, Color(0xFFE60012), false);

  const ConnectedService(this.label, this.icon, this.color, this.supportsSync);
  final String label;
  final dynamic icon;
  final Color color;
  final bool supportsSync;
}