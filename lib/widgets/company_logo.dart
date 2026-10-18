import 'package:cached_network_image/cached_network_image.dart';
import 'package:cached_network_image_platform_interface/cached_network_image_platform_interface.dart' show ImageRenderMethodForWeb;
import 'package:flutter/material.dart';

import 'package:checkpoint/theme/palette.dart';
import 'package:checkpoint/utils/formatters.dart';

/// A company's logo in a rounded square, or its initials when it has none (or
/// the logo can't be loaded). Logos are drawn on a light tile: most are dark
/// lettering on a transparent background.
class CompanyLogo extends StatelessWidget {
  const CompanyLogo({
    super.key,
    required this.name,
    required this.size,
    this.logoUrl,
  });

  final String name;
  final double size;
  final String? logoUrl;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(size * 0.22);
    final fallback = Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        borderRadius: radius,
        gradient: const LinearGradient(
          colors: [Palette.accent, Palette.electric],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Text(
        initials(name),
        style: TextStyle(
          color: Palette.onAccent,
          fontWeight: FontWeight.w800,
          fontSize: size * 0.34,
        ),
      ),
    );
    final url = logoUrl;
    if (url == null) return fallback;
    return CachedNetworkImage(
      imageRenderMethodForWeb: ImageRenderMethodForWeb.HttpGet,
      imageUrl: url,
      fadeInDuration: Duration.zero,
      fadeOutDuration: Duration.zero,
      memCacheWidth: (size * MediaQuery.devicePixelRatioOf(context)).round(),
      placeholder: (_, _) => fallback,
      errorWidget: (_, _, _) => fallback,
      imageBuilder: (_, image) => Container(
        width: size,
        height: size,
        padding: EdgeInsets.all(size * 0.12),
        decoration: BoxDecoration(
          color: const Color(0xFFF2F2F5),
          borderRadius: radius,
        ),
        child: Image(image: image, fit: BoxFit.contain),
      ),
    );
  }
}
