import 'package:flutter/material.dart';

import 'package:checkpoint/theme/palette.dart';

ThemeData buildTheme() {
  const scheme = ColorScheme.dark(
    primary: Palette.accent,
    onPrimary: Palette.onAccent,
    secondary: Palette.electric,
    onSecondary: Color(0xFF00212E),
    surface: Palette.surface,
    onSurface: Colors.white,
    error: Palette.danger,
    onError: Colors.black,
    surfaceContainerHighest: Palette.surfaceHigh,
    outline: Color(0xFF3A3A3F),
    outlineVariant: Color(0xFF2C2C30),
  );

  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: Palette.background,
    canvasColor: Palette.background,
    appBarTheme: const AppBarTheme(
      backgroundColor: Palette.background,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: Palette.navBar,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      height: 68,
      indicatorColor: Palette.accent.withValues(alpha: 0.20),
      iconTheme: WidgetStateProperty.resolveWith((s) => IconThemeData(
            size: 26,
            color: s.contains(WidgetState.selected) ? Palette.accent : Palette.muted,
          )),
      labelTextStyle: WidgetStateProperty.resolveWith((s) => TextStyle(
            fontSize: 12,
            fontWeight: s.contains(WidgetState.selected) ? FontWeight.w700 : FontWeight.w500,
            color: s.contains(WidgetState.selected) ? Palette.accent : Palette.muted,
          )),
    ),
    floatingActionButtonTheme: const FloatingActionButtonThemeData(
      backgroundColor: Palette.accent,
      foregroundColor: Palette.onAccent,
      extendedTextStyle: TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
    ),
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: Palette.surface,
      surfaceTintColor: Colors.transparent,
      showDragHandle: true,
      dragHandleColor: Colors.white24,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
    ),
    chipTheme: ChipThemeData(
      backgroundColor: Palette.surfaceHigh,
      selectedColor: Palette.accent.withValues(alpha: 0.22),
      side: BorderSide(color: Colors.white.withValues(alpha: 0.08)),
      shape: const StadiumBorder(),
      labelStyle: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 13),
    ),
    snackBarTheme: const SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: Palette.surfaceHigh,
      contentTextStyle: TextStyle(color: Colors.white),
      actionTextColor: Palette.accent,
    ),
    popupMenuTheme: const PopupMenuThemeData(
      color: Palette.surfaceHigh,
      surfaceTintColor: Colors.transparent,
    ),
  );
}
