import 'package:flutter/widgets.dart';
import 'package:intl/intl.dart';

import 'package:checkpoint/l10n/generated/app_localizations.dart';

export 'package:checkpoint/l10n/generated/app_localizations.dart';

/// The app's strings in the language it shows: the one picked in Settings >
/// Appearance, else the device's when the app has it, else English.
///
/// Widgets read them as `context.l10n`, so they rebuild when the language
/// changes. Code with no BuildContext (stores, services, models, formatters)
/// reads [L10n.current], which [AppearanceApp] keeps on the language the app
/// shows; it is English until then, which is what tests see.
abstract final class L10n {
  static const english = Locale('en');

  static AppLocalizations _current = lookupAppLocalizations(english);

  static AppLocalizations get current => _current;

  /// "en", "ru": the language of [current], as the server takes it.
  static String get languageCode => _current.localeName.split('_').first;

  /// Makes [locale] the language of [current] and of `intl`'s dates and
  /// numbers. Returns whether that changed anything.
  static bool use(Locale locale) {
    final next = lookupAppLocalizations(_supported(locale));
    // Always set, or `intl` would follow the device: German dates in the
    // English app of a German phone. en_US is the English it has built in.
    Intl.defaultLocale = next.localeName == 'en' ? 'en_US' : next.localeName;
    if (next.localeName == _current.localeName) return false;
    _current = next;
    return true;
  }

  /// The languages the app has, each named in its own language ("Русский").
  static List<Locale> get supportedLocales => AppLocalizations.supportedLocales;

  static String nativeName(Locale locale) =>
      lookupAppLocalizations(locale).languageName;

  /// [locale] when the app has its language, else English.
  static Locale _supported(Locale locale) =>
      AppLocalizations.supportedLocales.any(
        (l) => l.languageCode == locale.languageCode,
      )
      ? Locale(locale.languageCode)
      : english;
}

extension L10nContext on BuildContext {
  /// The strings in the app's language. Falls back to [L10n.current] where no
  /// [AppLocalizations] is in scope (a test's own MaterialApp).
  AppLocalizations get l10n =>
      Localizations.of<AppLocalizations>(this, AppLocalizations) ??
      L10n.current;
}
