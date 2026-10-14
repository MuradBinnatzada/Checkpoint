import 'package:flutter/material.dart';

import 'package:checkpoint/theme/palette.dart';
import 'package:checkpoint/utils/formatters.dart';

class ProfileAvatar extends StatelessWidget {
  const ProfileAvatar({
    super.key,
    required this.name,
    required this.size,
    this.imageUrl,
  });

  final String name;
  final double size;

  /// Public URL of the user's photo. When null/empty, or if it fails to load,
  /// the gradient circle with the user's initials is shown instead.
  final String? imageUrl;

  @override
  Widget build(BuildContext context) {
    final url = imageUrl;
    final initialsText = Text(
      initials(name),
      style: TextStyle(
        color: Palette.onAccent,
        fontWeight: FontWeight.w800,
        fontSize: size * 0.38,
      ),
    );

    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      clipBehavior: Clip.antiAlias,
      decoration: const BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          colors: [Palette.accent, Palette.electric],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: url == null || url.isEmpty
          ? initialsText
          : Image.network(
              url,
              width: size,
              height: size,
              fit: BoxFit.cover,
              // Keep the initials visible while loading and if the load fails.
              loadingBuilder: (_, child, progress) =>
                  progress == null ? child : initialsText,
              errorBuilder: (_, __, ___) => initialsText,
            ),
    );
  }
}