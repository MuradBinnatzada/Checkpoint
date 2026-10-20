import 'package:flutter/cupertino.dart' show CupertinoPageTransitionsBuilder;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:checkpoint/theme/palette.dart';

/// The themes, built once. Settings > Appearance picks between light and dark,
/// or leaves it to the device's setting; Increase contrast (there or on the
/// device) switches to the high contrast pair.
final ThemeData darkTheme = buildTheme();
final ThemeData lightTheme = buildTheme(brightness: Brightness.light);
final ThemeData darkHighContrastTheme = buildTheme(highContrast: true);
final ThemeData lightHighContrastTheme = buildTheme(brightness: Brightness.light, highContrast: true);

ThemeData buildTheme({Brightness brightness = Brightness.dark, bool highContrast = false}) {
  final p = Palette.of(brightness, highContrast: highContrast);
  final scheme = p.isDark
      ? ColorScheme.dark(
          primary: p.accent,
          onPrimary: p.onAccent,
          secondary: p.electric,
          onSecondary: const Color(0xFF00212E),
          surface: p.surface,
          onSurface: p.text,
          error: p.danger,
          onError: Colors.black,
          surfaceContainerHighest: p.surfaceHigh,
          onSurfaceVariant: p.highContrast ? p.textSoft : null,
          outline: p.highContrast ? const Color(0xFF8E8E98) : const Color(0xFF3A3A3F),
          outlineVariant: p.highContrast ? const Color(0xFF55555E) : const Color(0xFF2C2C30),
        )
      : ColorScheme.light(
          primary: p.accent,
          onPrimary: p.onAccent,
          secondary: p.electric,
          onSecondary: Colors.white,
          surface: p.surface,
          onSurface: p.text,
          onSurfaceVariant: p.textSoft,
          error: p.danger,
          onError: Colors.white,
          // Plain greys: Material's defaults are tinted purple.
          surfaceContainerLowest: Colors.white,
          surfaceContainerLow: const Color(0xFFF9F9FB),
          surfaceContainer: const Color(0xFFF5F5F8),
          surfaceContainerHigh: const Color(0xFFF0F0F4),
          surfaceContainerHighest: p.surfaceHigh,
          // 3:1 on white, the least a control's edge needs.
          outline: p.highContrast ? const Color(0xFF55555E) : const Color(0xFF8A8A94),
          outlineVariant: p.highContrast ? const Color(0xFF9A9AA4) : const Color(0xFFDCDCE2),
        );

  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    extensions: [p],
    scaffoldBackgroundColor: p.background,
    canvasColor: p.background,
    appBarTheme: AppBarTheme(
      backgroundColor: p.background,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      systemOverlayStyle: systemBarsStyle(p),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: p.navBar,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      height: 68,
      indicatorColor: p.accent.withValues(alpha: p.isDark ? 0.20 : 0.14),
      iconTheme: WidgetStateProperty.resolveWith((s) => IconThemeData(
            size: 26,
            color: s.contains(WidgetState.selected) ? p.accent : p.muted,
          )),
      labelTextStyle: WidgetStateProperty.resolveWith((s) => TextStyle(
            fontSize: 12,
            fontWeight: s.contains(WidgetState.selected) ? FontWeight.w700 : FontWeight.w500,
            color: s.contains(WidgetState.selected) ? p.accent : p.muted,
          )),
    ),
    floatingActionButtonTheme: FloatingActionButtonThemeData(
      backgroundColor: p.accent,
      foregroundColor: p.onAccent,
      extendedTextStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: p.surface,
      surfaceTintColor: Colors.transparent,
      showDragHandle: true,
      dragHandleColor: p.isDark ? Colors.white24 : Colors.black26,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
    ),
    chipTheme: ChipThemeData(
      backgroundColor: p.surfaceHigh,
      selectedColor: p.accent.withValues(alpha: p.isDark ? 0.22 : 0.16),
      side: BorderSide(color: p.text.withValues(alpha: p.highContrast ? 0.3 : 0.08)),
      shape: const StadiumBorder(),
      labelStyle: TextStyle(color: p.text, fontWeight: FontWeight.w600, fontSize: 13),
    ),
    // On the light theme a snack bar is dark, so it stands out from the page.
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: Palette.dark.surfaceHigh,
      contentTextStyle: const TextStyle(color: Colors.white),
      actionTextColor: Palette.dark.accent,
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: p.isDark ? p.surfaceHigh : p.surface,
      surfaceTintColor: Colors.transparent,
    ),
    // With less motion asked for, pages fade instead of sliding or zooming.
    // iOS and macOS keep their slide, which the swipe back follows (iOS itself
    // keeps it with Reduce Motion on).
    pageTransitionsTheme: const PageTransitionsTheme(
      builders: {
        TargetPlatform.android: _CalmPageTransitions(PredictiveBackPageTransitionsBuilder()),
        TargetPlatform.fuchsia: _CalmPageTransitions(ZoomPageTransitionsBuilder()),
        TargetPlatform.windows: _CalmPageTransitions(ZoomPageTransitionsBuilder()),
        TargetPlatform.linux: _CalmPageTransitions(ZoomPageTransitionsBuilder()),
        TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
        TargetPlatform.macOS: CupertinoPageTransitionsBuilder(),
      },
    ),
  );
}

/// [normal]'s page transition, or a fade when less motion is asked for (see
/// [motion]).
class _CalmPageTransitions extends PageTransitionsBuilder {
  const _CalmPageTransitions(this.normal);

  final PageTransitionsBuilder normal;

  @override
  Duration get transitionDuration => normal.transitionDuration;

  @override
  Duration get reverseTransitionDuration => normal.reverseTransitionDuration;

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    if (MediaQuery.disableAnimationsOf(context)) {
      return FadeTransition(opacity: animation, child: child);
    }
    return normal.buildTransitions(route, context, animation, secondaryAnimation, child);
  }
}

/// The status bar and the system navigation bar for [p]'s theme: icons that
/// show on its background.
SystemUiOverlayStyle systemBarsStyle(Palette p) => SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: p.isDark ? Brightness.light : Brightness.dark,
      // iOS names the status bar's background, not its icons.
      statusBarBrightness: p.brightness,
      systemNavigationBarColor: p.navBar,
      systemNavigationBarIconBrightness: p.isDark ? Brightness.light : Brightness.dark,
    );

/// [duration], or none when less motion is asked for: by the device (Android's
/// Remove animations, iOS's Reduce Motion) or in Settings > Appearance.
/// CheckpointApp folds all three into [MediaQueryData.disableAnimations].
Duration motion(BuildContext context, Duration duration) =>
    MediaQuery.disableAnimationsOf(context) ? Duration.zero : duration;

/// Lays [child] out in the dark theme, whatever the app's: for the text and
/// buttons drawn on cover art under a dark scrim (the game header, the Home hero
/// card), where the light theme's dark text would not show.
class DarkArtTheme extends StatelessWidget {
  const DarkArtTheme({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final highContrast = context.palette.highContrast;
    return Theme(
      data: highContrast ? darkHighContrastTheme : darkTheme,
      // A Material sets the default text style from its theme; Theme alone doesn't.
      child: Material(type: MaterialType.transparency, child: child),
    );
  }
}
