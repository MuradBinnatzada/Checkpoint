import 'dart:async';

import 'package:flutter/material.dart';

import 'package:checkpoint/l10n/l10n.dart';
import 'package:checkpoint/state/appearance_store.dart';
import 'package:checkpoint/state/store_scope.dart';
import 'package:checkpoint/theme/palette.dart';
import 'package:checkpoint/widgets/panel.dart';

/// How the app looks on this device: the language and the theme, which start out
/// following the device's, and the accessibility switches.
class AppearanceSection extends StatelessWidget {
  const AppearanceSection({super.key});

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
      children: [
        Panel(title: context.l10n.appearanceLanguage, child: const _LanguageChoice()),
        const SizedBox(height: 14),
        Panel(title: context.l10n.appearanceTheme, child: const _ThemeChoice()),
        const SizedBox(height: 14),
        Panel(title: context.l10n.appearanceAccessibility, child: const _AccessibilitySwitches()),
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 12, 4, 0),
          child: Text(
            context.l10n.appearanceSavedOnDevice,
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

/// The language the app shows: one row naming it, which opens the choices (the
/// device's language, then each language the app has, by its own name). Picking
/// one switches the whole app at once.
class _LanguageChoice extends StatelessWidget {
  const _LanguageChoice();

  Future<void> _pick(BuildContext context, AppearanceStore store) async {
    final picked = await showDialog<String>(
      context: context,
      builder: (context) => _LanguageDialog(current: store.locale?.languageCode ?? ''),
    );
    if (picked == null) return;
    await store.setLocale(picked.isEmpty ? null : Locale(picked));
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<AppearanceStore>();
    final l10n = context.l10n;
    final locale = store.locale;
    // Its own Material, so the tap splash shows over the panel's background.
    return Material(
      type: MaterialType.transparency,
      child: ListTile(
        contentPadding: EdgeInsets.zero,
        leading: Icon(Icons.translate_rounded, color: context.palette.accent),
        title: Text(
          locale == null ? l10n.appearanceLanguageDevice : L10n.nativeName(locale),
          style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700),
        ),
        subtitle: Text(
          locale == null ? l10n.appearanceLanguageDeviceSubtitle : l10n.appearanceLanguagePicked,
          style: TextStyle(color: context.palette.muted, fontSize: 12.5, height: 1.35),
        ),
        trailing: Icon(Icons.chevron_right_rounded, color: context.palette.muted),
        onTap: () => unawaited(_pick(context, store)),
      ),
    );
  }
}

/// The languages as radio buttons; pops with the one picked ('' for the
/// device's).
class _LanguageDialog extends StatelessWidget {
  const _LanguageDialog({required this.current});

  /// The language code picked now, or '' for the device's language.
  final String current;

  @override
  Widget build(BuildContext context) {
    return SimpleDialog(
      title: Text(context.l10n.appearanceLanguage),
      children: [
        RadioGroup<String>(
          groupValue: current,
          onChanged: (code) => Navigator.pop(context, code),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              RadioListTile<String>(
                value: '',
                title: Text(context.l10n.appearanceLanguageDevice),
              ),
              for (final locale in L10n.supportedLocales)
                RadioListTile<String>(
                  value: locale.languageCode,
                  title: Text(L10n.nativeName(locale)),
                ),
            ],
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

  static String _title(AppLocalizations l10n, ThemeMode mode) => switch (mode) {
    ThemeMode.system => l10n.appearanceThemeSystem,
    ThemeMode.light => l10n.appearanceThemeLight,
    ThemeMode.dark => l10n.appearanceThemeDark,
  };

  static String _subtitle(AppLocalizations l10n, ThemeMode mode) => switch (mode) {
    ThemeMode.system => l10n.appearanceThemeSystemSubtitle,
    ThemeMode.light => l10n.appearanceThemeLightSubtitle,
    ThemeMode.dark => l10n.appearanceThemeDarkSubtitle,
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
                  _title(context.l10n, mode),
                  style: const TextStyle(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                subtitle: Text(
                  _subtitle(context.l10n, mode),
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
            title: context.l10n.appearanceIncreaseContrast,
            subtitle: deviceContrast
                ? context.l10n.appearanceOnInDeviceSettings
                : context.l10n.appearanceIncreaseContrastSubtitle,
            value: deviceContrast || store.highContrast,
            onChanged: deviceContrast
                ? null
                : (on) => unawaited(store.setHighContrast(on)),
          ),
          _Switch(
            icon: Icons.motion_photos_off_rounded,
            title: context.l10n.appearanceReduceMotion,
            subtitle: deviceMotion
                ? context.l10n.appearanceOnInDeviceSettings
                : context.l10n.appearanceReduceMotionSubtitle,
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
