import 'dart:async';

import 'package:flutter/material.dart';

import 'package:checkpoint/state/appearance_store.dart';
import 'package:checkpoint/state/store_scope.dart';
import 'package:checkpoint/theme/palette.dart';
import 'package:checkpoint/widgets/panel.dart';

/// How the app looks on this device: the theme, which starts out following the
/// device's light or dark setting, and the accessibility switches.
class AppearanceSection extends StatelessWidget {
  const AppearanceSection({super.key});

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
      children: [
        const Panel(title: 'Theme', child: _ThemeChoice()),
        const SizedBox(height: 14),
        const Panel(title: 'Accessibility', child: _AccessibilitySwitches()),
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 12, 4, 0),
          child: Text(
            'These are saved on this device only, so each of your devices can '
            'look its own way. Text size follows your device\'s setting, up to '
            'twice the normal size.',
            style: TextStyle(
              color: context.palette.muted,
              fontSize: 12.5,
              height: 1.4,
            ),
          ),
        ),
      ],
    );
  }
}

/// The three themes as radio buttons, in the order of [ThemeMode]: the device's,
/// light, dark.
class _ThemeChoice extends StatelessWidget {
  const _ThemeChoice();

  static String _title(ThemeMode mode) => switch (mode) {
    ThemeMode.system => 'Same as device',
    ThemeMode.light => 'Light',
    ThemeMode.dark => 'Dark',
  };

  static String _subtitle(ThemeMode mode) => switch (mode) {
    ThemeMode.system => "Switches with your device's light or dark mode.",
    ThemeMode.light => 'Dark text on a light background.',
    ThemeMode.dark => 'Light text on a dark background.',
  };

  static IconData _icon(ThemeMode mode) => switch (mode) {
    ThemeMode.system => Icons.brightness_auto_rounded,
    ThemeMode.light => Icons.light_mode_rounded,
    ThemeMode.dark => Icons.dark_mode_rounded,
  };

  @override
  Widget build(BuildContext context) {
    final store = context.watch<AppearanceStore>();
    // Its own Material, so the tap splash shows over the panel's background.
    return Material(
      type: MaterialType.transparency,
      child: RadioGroup<ThemeMode>(
        groupValue: store.themeMode,
        onChanged: (mode) {
          if (mode != null) unawaited(store.setThemeMode(mode));
        },
        child: Column(
          children: [
            for (final mode in ThemeMode.values)
              RadioListTile<ThemeMode>(
                value: mode,
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.trailing,
                secondary: Icon(_icon(mode), color: context.palette.accent),
                title: Text(
                  _title(mode),
                  style: const TextStyle(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                subtitle: Text(
                  _subtitle(mode),
                  style: TextStyle(
                    color: context.palette.muted,
                    fontSize: 12.5,
                    height: 1.35,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Increase contrast and Reduce motion. When the device's own setting already
/// asks for one, its switch shows on, and can't be turned off here.
class _AccessibilitySwitches extends StatelessWidget {
  const _AccessibilitySwitches();

  @override
  Widget build(BuildContext context) {
    final store = context.watch<AppearanceStore>();
    final device = MediaQuery.of(context);
    final features = View.of(context).platformDispatcher.accessibilityFeatures;
    final deviceContrast = device.highContrast;
    final deviceMotion = features.disableAnimations || features.reduceMotion;
    // Its own Material, so the tap splash shows over the panel's background.
    return Material(
      type: MaterialType.transparency,
      child: Column(
        children: [
          _Switch(
            icon: Icons.contrast_rounded,
            title: 'Increase contrast',
            subtitle: deviceContrast
                ? "On in your device's settings."
                : 'Darker text and colors on light, brighter on dark, and '
                      'stronger borders.',
            value: deviceContrast || store.highContrast,
            onChanged: deviceContrast
                ? null
                : (on) => unawaited(store.setHighContrast(on)),
          ),
          _Switch(
            icon: Icons.motion_photos_off_rounded,
            title: 'Reduce motion',
            subtitle: deviceMotion
                ? "On in your device's settings."
                : 'Pages fade in instead of sliding, and nothing animates just '
                      'for show.',
            value: deviceMotion || store.reduceMotion,
            onChanged: deviceMotion
                ? null
                : (on) => unawaited(store.setReduceMotion(on)),
          ),
        ],
      ),
    );
  }
}

class _Switch extends StatelessWidget {
  const _Switch({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    return SwitchListTile(
      contentPadding: EdgeInsets.zero,
      secondary: Icon(icon, color: context.palette.accent),
      title: Text(
        title,
        style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700),
      ),
      subtitle: Text(
        subtitle,
        style: TextStyle(
          color: context.palette.muted,
          fontSize: 12.5,
          height: 1.35,
        ),
      ),
      value: value,
      onChanged: onChanged,
    );
  }
}
