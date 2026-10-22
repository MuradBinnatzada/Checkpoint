import 'package:checkpoint/l10n/l10n.dart';

/// The name of the country whose ISO 3166-1 numeric code is [code] (what IGDB
/// gives a company), in the app's language, or null for none or one not listed
/// here. Only the countries game companies are commonly based in are listed.
String? countryName(int? code) => code == null ? null : _countryName(L10n.current, code);

/// The countries game companies are most often based in, first in the studio
/// filter's list.
const _commonCodes = [840, 392, 826, 124, 250, 276, 752, 156, 410, 616, 643, 380, 724, 804, 208, 246, 528, 36, 76];

/// Every country [countryName] knows, as ISO 3166-1 numeric codes: the common
/// ones first, in that order, then the rest by name in the app's language. What
/// the studio filter offers.
List<int> countryCodes() {
  final l10n = L10n.current;
  final others = [
    for (var code = 1; code < 1000; code++)
      if (!_commonCodes.contains(code) && _countryName(l10n, code) != null) code,
  ]..sort((a, b) => _countryName(l10n, a)!.compareTo(_countryName(l10n, b)!));
  return [..._commonCodes, ...others];
}

String? _countryName(AppLocalizations l10n, int code) => switch (code) {
  32 => l10n.countryArgentina,
  36 => l10n.countryAustralia,
  40 => l10n.countryAustria,
  51 => l10n.countryArmenia,
  56 => l10n.countryBelgium,
  76 => l10n.countryBrazil,
  100 => l10n.countryBulgaria,
  112 => l10n.countryBelarus,
  124 => l10n.countryCanada,
  152 => l10n.countryChile,
  156 => l10n.countryChina,
  158 => l10n.countryTaiwan,
  170 => l10n.countryColombia,
  191 => l10n.countryCroatia,
  196 => l10n.countryCyprus,
  203 => l10n.countryCzechia,
  208 => l10n.countryDenmark,
  233 => l10n.countryEstonia,
  246 => l10n.countryFinland,
  250 => l10n.countryFrance,
  268 => l10n.countryGeorgia,
  276 => l10n.countryGermany,
  300 => l10n.countryGreece,
  344 => l10n.countryHongKong,
  348 => l10n.countryHungary,
  352 => l10n.countryIceland,
  356 => l10n.countryIndia,
  360 => l10n.countryIndonesia,
  364 => l10n.countryIran,
  372 => l10n.countryIreland,
  376 => l10n.countryIsrael,
  380 => l10n.countryItaly,
  392 => l10n.countryJapan,
  398 => l10n.countryKazakhstan,
  410 => l10n.countrySouthKorea,
  428 => l10n.countryLatvia,
  440 => l10n.countryLithuania,
  442 => l10n.countryLuxembourg,
  458 => l10n.countryMalaysia,
  470 => l10n.countryMalta,
  484 => l10n.countryMexico,
  498 => l10n.countryMoldova,
  528 => l10n.countryNetherlands,
  554 => l10n.countryNewZealand,
  578 => l10n.countryNorway,
  604 => l10n.countryPeru,
  608 => l10n.countryPhilippines,
  616 => l10n.countryPoland,
  620 => l10n.countryPortugal,
  642 => l10n.countryRomania,
  643 => l10n.countryRussia,
  682 => l10n.countrySaudiArabia,
  688 => l10n.countrySerbia,
  702 => l10n.countrySingapore,
  703 => l10n.countrySlovakia,
  704 => l10n.countryVietnam,
  705 => l10n.countrySlovenia,
  710 => l10n.countrySouthAfrica,
  724 => l10n.countrySpain,
  752 => l10n.countrySweden,
  756 => l10n.countrySwitzerland,
  764 => l10n.countryThailand,
  784 => l10n.countryUnitedArabEmirates,
  792 => l10n.countryTrkiye,
  804 => l10n.countryUkraine,
  818 => l10n.countryEgypt,
  826 => l10n.countryUnitedKingdom,
  840 => l10n.countryUnitedStates,
  858 => l10n.countryUruguay,
  862 => l10n.countryVenezuela,
  _ => null,
};
