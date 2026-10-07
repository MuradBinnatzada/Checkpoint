import 'package:flutter/material.dart';

import 'package:checkpoint/theme/palette.dart';
import 'package:checkpoint/utils/formatters.dart';

class ProfileAvatar extends StatelessWidget {
  const ProfileAvatar({super.key, required this.name, required this.size});
  final String name;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: const BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(colors: [Palette.accent, Palette.electric], begin: Alignment.topLeft, end: Alignment.bottomRight),
      ),
      child: Text(initials(name), style: TextStyle(color: Palette.onAccent, fontWeight: FontWeight.w800, fontSize: size * 0.38)),
    );
  }
}
