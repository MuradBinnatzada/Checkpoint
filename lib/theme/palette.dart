import 'package:flutter/material.dart';

/// The app's colors, one set per theme. Widgets read them with
/// `context.palette`, so they follow the theme picked in Settings > Appearance.
///
/// Every text color reads at [minContrast] or more on its theme's [background]
/// and [surface], and those that sit on controls ([text], [textSoft], [muted],
/// [accent]) on [surfaceHigh] too; so does whatever [legible] returns. That is
/// 4.5:1 (WCAG AA), or 7:1 (AAA) with Increase contrast on.
/// test/appearance_test.dart checks it.
@immutable
class Palette extends ThemeExtension<Palette> {
  const Palette._({
    required this.brightness,
    this.highContrast = false,
    required this.background,
    required this.surface,
    required this.surfaceHigh,
    required this.navBar,
    required this.accent,
    required this.onAccent,
    required this.electric,
    required this.star,
    required this.muted,
    required this.danger,
    required this.success,
    required this.text,
    required this.textSoft,
    required this.faint,
    required this.hairline,
    required this.outline,
    required this.track,
  });

  static const dark = Palette._(
    brightness: Brightness.dark,
    background: Color(0xFF121212),
    surface: Color(0xFF1C1C1E),
    surfaceHigh: Color(0xFF2A2A2E),
    navBar: Color(0xFF171719),
    accent: Color(0xFFBB86FC), // neon purple
    onAccent: Color(0xFF22103A),
    electric: Color(0xFF4FC3F7), // electric blue
    star: Color(0xFFFFC857),
    muted: Color(0xFF9B9BA5),
    danger: Color(0xFFCF6679),
    success: Color(0xFF7DDC9C),
    text: Colors.white,
    textSoft: Colors.white70,
    faint: Colors.white38,
    hairline: Color.from(alpha: 0.06, red: 1, green: 1, blue: 1),
    outline: Color.from(alpha: 0.18, red: 1, green: 1, blue: 1),
    track: Color.from(alpha: 0.08, red: 1, green: 1, blue: 1),
  );

  /// The dark theme's colors made deep enough to read on white: the same hues,
  /// darker.
  static const light = Palette._(
    brightness: Brightness.light,
    background: Color(0xFFF3F3F6),
    surface: Color(0xFFFFFFFF),
    surfaceHigh: Color(0xFFEBEBF0),
    navBar: Color(0xFFFFFFFF),
    accent: Color(0xFF8028D8),
    onAccent: Colors.white,
    electric: Color(0xFF06668F),
    star: Color(0xFF875500),
    muted: Color(0xFF63636E),
    danger: Color(0xFFB3261E),
    success: Color(0xFF1D6E37),
    text: Color(0xFF1B1B1F),
    textSoft: Color(0xFF45454E),
    faint: Color(0xFF8A8A94),
    hairline: Color.from(alpha: 0.09, red: 0, green: 0, blue: 0),
    outline: Color.from(alpha: 0.20, red: 0, green: 0, blue: 0),
    track: Color.from(alpha: 0.08, red: 0, green: 0, blue: 0),
  );

  /// [dark] with Increase contrast: brighter text and colors, stronger borders.
  static const darkHighContrast = Palette._(
    brightness: Brightness.dark,
    highContrast: true,
    background: Color(0xFF0C0C0D),
    surface: Color(0xFF161618),
    surfaceHigh: Color(0xFF232327),
    navBar: Color(0xFF0C0C0D),
    accent: Color(0xFFD3B0FD),
    onAccent: Color(0xFF1A0A30),
    electric: Color(0xFF63CAF8),
    star: Color(0xFFFFC857),
    muted: Color(0xFFBEBEC4),
    danger: Color(0xFFE7B2BB),
    success: Color(0xFF7DDC9C),
    text: Colors.white,
    textSoft: Color.from(alpha: 0.88, red: 1, green: 1, blue: 1),
    faint: Color.from(alpha: 0.6, red: 1, green: 1, blue: 1),
    hairline: Color.from(alpha: 0.24, red: 1, green: 1, blue: 1),
    outline: Color.from(alpha: 0.55, red: 1, green: 1, blue: 1),
    track: Color.from(alpha: 0.18, red: 1, green: 1, blue: 1),
  );

  /// [light] with Increase contrast: darker text and colors, stronger borders.
  static const lightHighContrast = Palette._(
    brightness: Brightness.light,
    highContrast: true,
    background: Color(0xFFF2F2F5),
    surface: Color(0xFFFFFFFF),
    surfaceHigh: Color(0xFFE6E6EC),
    navBar: Color(0xFFFFFFFF),
    accent: Color(0xFF581B96),
    onAccent: Colors.white,
    electric: Color(0xFF044561),
    star: Color(0xFF593800),
    muted: Color(0xFF404047),
    danger: Color(0xFF7A1A14),
    success: Color(0xFF134A25),
    text: Colors.black,
    textSoft: Color(0xFF1F1F24),
    faint: Color(0xFF6B6B75),
    hairline: Color.from(alpha: 0.26, red: 0, green: 0, blue: 0),
    outline: Color.from(alpha: 0.6, red: 0, green: 0, blue: 0),
    track: Color.from(alpha: 0.16, red: 0, green: 0, blue: 0),
  );

  /// The palette for [brightness], with or without Increase contrast.
  static Palette of(Brightness brightness, {bool highContrast = false}) =>
      switch ((brightness, highContrast)) {
        (Brightness.dark, false) => dark,
        (Brightness.light, false) => light,
        (Brightness.dark, true) => darkHighContrast,
        (Brightness.light, true) => lightHighContrast,
      };

  final Brightness brightness;

  /// Increase contrast is on (Settings > Appearance, or the device's setting).
  final bool highContrast;
  final Color background;

  /// Panels and sheets.
  final Color surface;

  /// Chips, text fields and other controls, on a [surface] or the [background].
  final Color surfaceHigh;
  final Color navBar;
  final Color accent;

  /// Text and icons on [accent].
  final Color onAccent;
  final Color electric;
  final Color star;

  /// Secondary text: captions, hints, labels.
  final Color muted;
  final Color danger;
  final Color success;

  /// Body text and icons.
  final Color text;

  /// Text a step back from [text], brighter than [muted]: descriptions, bios.
  final Color textSoft;

  /// What is locked, unset or turned off: an empty star, a locked achievement.
  final Color faint;

  /// The border of a panel, and the dividers in one.
  final Color hairline;

  /// The border of an outlined button or a chip that is not selected.
  final Color outline;

  /// The empty part of a progress bar.
  final Color track;

  bool get isDark => brightness == Brightness.dark;

  /// The least contrast text gets: 4.5:1 (WCAG AA), 7:1 (AAA) with Increase
  /// contrast.
  double get minContrast => highContrast ? 7 : 4.5;

  /// [color] as text or an icon on this theme's surfaces, at [minContrast] or
  /// more. The status, platform and service colors were picked for the dark
  /// theme, and most are too pale on white: the dark palette's own colors become
  /// this palette's counterparts, and any color is then darkened (or, on a dark
  /// theme, lightened) just enough.
  Color legible(Color color) =>
      _legible[(brightness, highContrast, color)] ??= _makeLegible(color);

  static final _legible = <(Brightness, bool, Color), Color>{};

  Color _makeLegible(Color color) {
    final own = of(brightness, highContrast: highContrast);
    final counterpart = {
      dark.accent: own.accent,
      dark.electric: own.electric,
      dark.star: own.star,
      dark.danger: own.danger,
      dark.success: own.success,
    }[color];
    final step = isDark ? 0.01 : -0.01;
    var hsl = HSLColor.fromColor(counterpart ?? color);
    while (!_reads(hsl.toColor())) {
      final lightness = hsl.lightness + step;
      if (lightness < 0 || lightness > 1) break;
      hsl = hsl.withLightness(lightness);
    }
    return hsl.toColor();
  }

  /// Whether [color] reads at [minContrast] where such colors go: on a control,
  /// and on a pill tinted with it (see [pill]) on the page or a panel.
  bool _reads(Color color) {
    final own = of(brightness, highContrast: highContrast);
    return contrastRatio(color, own.surfaceHigh) >= minContrast &&
        contrastRatio(color, pill(color, own.background)) >= minContrast &&
        contrastRatio(color, pill(color, own.surface)) >= minContrast;
  }

  /// The background of a status pill or platform badge in [color], on [ground].
  static Color pill(Color color, Color ground) =>
      Color.alphaBlend(color.withValues(alpha: 0.16), ground);

  @override
  Palette copyWith({
    Brightness? brightness,
    bool? highContrast,
    Color? background,
    Color? surface,
    Color? surfaceHigh,
    Color? navBar,
    Color? accent,
    Color? onAccent,
    Color? electric,
    Color? star,
    Color? muted,
    Color? danger,
    Color? success,
    Color? text,
    Color? textSoft,
    Color? faint,
    Color? hairline,
    Color? outline,
    Color? track,
  }) {
    return Palette._(
      brightness: brightness ?? this.brightness,
      highContrast: highContrast ?? this.highContrast,
      background: background ?? this.background,
      surface: surface ?? this.surface,
      surfaceHigh: surfaceHigh ?? this.surfaceHigh,
      navBar: navBar ?? this.navBar,
      accent: accent ?? this.accent,
      onAccent: onAccent ?? this.onAccent,
      electric: electric ?? this.electric,
      star: star ?? this.star,
      muted: muted ?? this.muted,
      danger: danger ?? this.danger,
      success: success ?? this.success,
      text: text ?? this.text,
      textSoft: textSoft ?? this.textSoft,
      faint: faint ?? this.faint,
      hairline: hairline ?? this.hairline,
      outline: outline ?? this.outline,
      track: track ?? this.track,
    );
  }

  /// The colors part way to [other]'s, while the app moves between themes.
  @override
  Palette lerp(Palette? other, double t) {
    if (other == null) return this;
    Color mix(Color a, Color b) => Color.lerp(a, b, t)!;
    return Palette._(
      brightness: t < 0.5 ? brightness : other.brightness,
      highContrast: t < 0.5 ? highContrast : other.highContrast,
      background: mix(background, other.background),
      surface: mix(surface, other.surface),
      surfaceHigh: mix(surfaceHigh, other.surfaceHigh),
      navBar: mix(navBar, other.navBar),
      accent: mix(accent, other.accent),
      onAccent: mix(onAccent, other.onAccent),
      electric: mix(electric, other.electric),
      star: mix(star, other.star),
      muted: mix(muted, other.muted),
      danger: mix(danger, other.danger),
      success: mix(success, other.success),
      text: mix(text, other.text),
      textSoft: mix(textSoft, other.textSoft),
      faint: mix(faint, other.faint),
      hairline: mix(hairline, other.hairline),
      outline: mix(outline, other.outline),
      track: mix(track, other.track),
    );
  }
}

extension PaletteContext on BuildContext {
  /// The colors of the theme in use. Outside the app's theme (a bare test
  /// widget), the dark ones.
  Palette get palette => Theme.of(this).extension<Palette>() ?? Palette.dark;
}

/// How far apart [a] and [b] are in lightness, as WCAG measures it: from 1 (the
/// same) to 21 (black on white). Text needs 4.5, large text and icons 3.
double contrastRatio(Color a, Color b) {
  final la = a.computeLuminance();
  final lb = b.computeLuminance();
  return la > lb ? (la + 0.05) / (lb + 0.05) : (lb + 0.05) / (la + 0.05);
}
