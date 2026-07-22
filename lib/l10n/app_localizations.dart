import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

part 'translations/nl.dart';
part 'translations/en.dart';
part 'translations/it.dart';
part 'translations/de.dart';
part 'translations/fr.dart';
part 'translations/es.dart';
part 'translations/fy.dart';
part 'translations/pap.dart';
part 'translations/la.dart';
part 'translations/id.dart';
part 'translations/pl.dart';
part 'translations/uk.dart';
part 'translations/gsw.dart';
part 'translations/el.dart';
part 'translations/da.dart';
part 'translations/sv.dart';
part 'translations/hr.dart';
part 'translations/cs.dart';
part 'translations/fi.dart';
part 'translations/bg.dart';
part 'translations/lv.dart';
part 'translations/lt.dart';
part 'translations/mt.dart';
part 'translations/et.dart';
part 'translations/hu.dart';
part 'translations/ga.dart';
part 'translations/pt.dart';
part 'translations/ro.dart';
part 'translations/sl.dart';
part 'translations/sk.dart';
part 'translations/tlh.dart';
part 'translations/tr.dart';

class AppLocalizations {
  final Locale locale;

  const AppLocalizations(this.locale);

  static const supportedLocales = [
    Locale('nl'),
    Locale('en'),
    Locale('it'),
    Locale('de'),
    Locale('fr'),
    Locale('es'),
    Locale('fy'),
    Locale('pap'),
    Locale('la'),
    Locale('id'),
    Locale('pl'),
    Locale('uk'),
    Locale('gsw'),
    Locale('el'),
    Locale('da'),
    Locale('sv'),
    Locale('hr'),
    Locale('cs'),
    Locale('fi'),
    Locale('bg'),
    Locale('lv'),
    Locale('lt'),
    Locale('mt'),
    Locale('et'),
    Locale('hu'),
    Locale('ga'),
    Locale('pt'),
    Locale('ro'),
    Locale('sl'),
    Locale('sk'),
    Locale('tlh'),
    Locale('tr'),
  ];

  static const languageNames = {
    'nl': 'Nederlands',
    'en': 'English',
    'it': 'Italiano',
    'de': 'Deutsch',
    'fr': 'Français',
    'es': 'Español',
    'fy': 'Frysk',
    'pap': 'Papiamento',
    'la': 'Latina',
    'id': 'Bahasa Indonesia',
    'pl': 'Polski',
    'uk': 'Українська',
    'gsw': 'Schwiizerdütsch',
    'el': 'Ελληνικά',
    'da': 'Dansk',
    'sv': 'Svenska',
    'hr': 'Hrvatski',
    'cs': 'Čeština',
    'fi': 'Suomi',
    'bg': 'Български',
    'lv': 'Latviešu',
    'lt': 'Lietuvių',
    'mt': 'Malti',
    'et': 'Eesti',
    'hu': 'Magyar',
    'ga': 'Gaeilge',
    'pt': 'Português',
    'ro': 'Română',
    'sl': 'Slovenščina',
    'sk': 'Slovenčina',
    'tlh': 'tlhIngan Hol',
    'tr': 'Türkçe',
  };

  /// A country flag (emoji) per language, shown in the language pickers. Some
  /// choices are by convention: English → United Kingdom, Latin → Vatican City,
  /// Frisian → Netherlands (Friesland), Papiamento → Curaçao, Swiss German →
  /// Switzerland.
  static const languageFlags = {
    'nl': '🇳🇱',
    'en': '🇬🇧',
    'it': '🇮🇹',
    'de': '🇩🇪',
    'fr': '🇫🇷',
    'es': '🇪🇸',
    'fy': '🇳🇱',
    'pap': '🇨🇼',
    'la': '🇻🇦',
    'id': '🇮🇩',
    'pl': '🇵🇱',
    'uk': '🇺🇦',
    'gsw': '🇨🇭',
    'el': '🇬🇷',
    'da': '🇩🇰',
    'sv': '🇸🇪',
    'hr': '🇭🇷',
    'cs': '🇨🇿',
    'fi': '🇫🇮',
    'bg': '🇧🇬',
    'lv': '🇱🇻',
    'lt': '🇱🇹',
    'mt': '🇲🇹',
    'et': '🇪🇪',
    'hu': '🇭🇺',
    'ga': '🇮🇪',
    'pt': '🇵🇹',
    'ro': '🇷🇴',
    'sl': '🇸🇮',
    'sk': '🇸🇰',
    // Klingon has no country flag. The picker shows a neutral `tlh` letter
    // badge instead (see languageFlag()); this emoji is only a text fallback
    // for places that render a flag as plain text.
    'tlh': '🖖',
    'tr': '🇹🇷',
  };

  // Transliteration to a Latin sort key, so names in other scripts (Greek,
  // Cyrillic) or with diacritics fold to where a reader expects them —
  // Ελληνικά → "ellinika" (near E), Українська → "ukrainska" (near U), Čeština
  // → "cestina" (near C) — instead of being dumped after all Latin names by
  // raw Unicode code-point order.
  static const _translitMap = {
    'á': 'a', 'à': 'a', 'â': 'a', 'ä': 'a', 'ã': 'a', 'å': 'a', 'ą': 'a',
    'é': 'e', 'è': 'e', 'ê': 'e', 'ë': 'e', 'ě': 'e', 'ę': 'e',
    'í': 'i', 'ì': 'i', 'î': 'i', 'ï': 'i', 'ı': 'i',
    'ó': 'o', 'ò': 'o', 'ô': 'o', 'ö': 'o', 'õ': 'o', 'ø': 'o',
    'ú': 'u', 'ù': 'u', 'û': 'u', 'ü': 'u', 'ů': 'u',
    'ý': 'y', 'ÿ': 'y',
    'ç': 'c', 'ć': 'c', 'č': 'c', 'ñ': 'n', 'ń': 'n',
    'š': 's', 'ś': 's', 'ş': 's', 'ž': 'z', 'ź': 'z', 'ż': 'z',
    'đ': 'd', 'ď': 'd', 'ł': 'l', 'ř': 'r', 'ť': 't', 'ň': 'n', 'ğ': 'g',
    'æ': 'ae', 'ß': 'ss',
    // Greek
    'α': 'a', 'ά': 'a', 'β': 'v', 'γ': 'g', 'δ': 'd', 'ε': 'e', 'έ': 'e',
    'ζ': 'z', 'η': 'i', 'ή': 'i', 'θ': 'th', 'ι': 'i', 'ί': 'i', 'ϊ': 'i',
    'ΐ': 'i', 'κ': 'k', 'λ': 'l', 'μ': 'm', 'ν': 'n', 'ξ': 'x', 'ο': 'o',
    'ό': 'o', 'π': 'p', 'ρ': 'r', 'σ': 's', 'ς': 's', 'τ': 't', 'υ': 'y',
    'ύ': 'y', 'ϋ': 'y', 'φ': 'f', 'χ': 'ch', 'ψ': 'ps', 'ω': 'o', 'ώ': 'o',
    // Cyrillic
    'а': 'a', 'б': 'b', 'в': 'v', 'г': 'h', 'ґ': 'g', 'д': 'd', 'е': 'e',
    'є': 'ie', 'ж': 'zh', 'з': 'z', 'и': 'y', 'і': 'i', 'ї': 'i', 'й': 'i',
    'к': 'k', 'л': 'l', 'м': 'm', 'н': 'n', 'о': 'o', 'п': 'p', 'р': 'r',
    'с': 's', 'т': 't', 'у': 'u', 'ф': 'f', 'х': 'kh', 'ц': 'ts', 'ч': 'ch',
    'ш': 'sh', 'щ': 'shch', 'ю': 'iu', 'я': 'ia', 'ь': '', 'ъ': '', 'ы': 'y',
    'э': 'e', 'ё': 'e',
  };

  /// Latin-folded, lowercased sort key of [s] (see [_translitMap]). Public so
  /// other pickers (e.g. the template chooser) sort display names the same way
  /// the language list does — diacritics and other scripts land where a reader
  /// expects them instead of after all plain-Latin names.
  static String sortKey(String s) {
    final buf = StringBuffer();
    for (final ch in s.toLowerCase().split('')) {
      buf.write(_translitMap[ch] ?? ch);
    }
    return buf.toString();
  }

  /// Language options sorted by a Latin-folded key of the display name, for
  /// pickers (the map itself keeps its own order for lookups).
  static List<MapEntry<String, String>> get languageOptions =>
      languageNames.entries.toList()
        ..sort((a, b) => sortKey(a.value).compareTo(sortKey(b.value)));

  static const _materialLocaleFallbacks = {
    'nl': Locale('nl'),
    'en': Locale('en'),
    'it': Locale('it'),
    'de': Locale('de'),
    'fr': Locale('fr'),
    'es': Locale('es'),
    'fy': Locale('en'),
    'pap': Locale('en'),
    // Indonesian and Polish have Material localizations; Latin does not, so it
    // borrows English for the framework widgets while the app UI is Latin.
    'la': Locale('en'),
    'id': Locale('id'),
    'pl': Locale('pl'),
    'uk': Locale('uk'),
    // Swiss German has no Material localization; borrow standard German.
    'gsw': Locale('de'),
    'el': Locale('el'),
    'da': Locale('da'),
    'sv': Locale('sv'),
    'hr': Locale('hr'),
    'cs': Locale('cs'),
    'fi': Locale('fi'),
    'bg': Locale('bg'),
    'lv': Locale('lv'),
    'lt': Locale('lt'),
    // Maltese, Irish and Klingon have no Material localization; borrow English
    // for the framework widgets while the app UI is in the chosen language.
    'mt': Locale('en'),
    'et': Locale('et'),
    'hu': Locale('hu'),
    'ga': Locale('en'),
    'pt': Locale('pt'),
    'ro': Locale('ro'),
    'sl': Locale('sl'),
    'sk': Locale('sk'),
    'tlh': Locale('en'),
    'tr': Locale('tr'),
  };

  static String _activeLanguageCode = 'nl';

  static void setActiveLanguageCode(String code) {
    _activeLanguageCode = languageNames.containsKey(code) ? code : 'nl';
  }

  static Locale materialLocaleFor(String code) {
    return _materialLocaleFallbacks[code] ?? const Locale('nl');
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations) ??
        const AppLocalizations(Locale('nl'));
  }

  String get languageCode => _activeLanguageCode;

  String t(String key) {
    if (languageCode == 'nl') return _strings['nl']![key] ?? key;
    return _strings[languageCode]?[key] ??
        _strings['en']?[key] ??
        _strings['nl']![key] ??
        key;
  }

  String d(String dutchText) {
    if (languageCode == 'nl') return dutchText;
    return _dutchSourceStringAdditions[languageCode]?[dutchText] ??
        _dutchSourceStrings[languageCode]?[dutchText] ??
        _dutchSourceStringAdditions['en']?[dutchText] ??
        _dutchSourceStrings['en']?[dutchText] ??
        dutchText;
  }

  static String sourceFor(String languageCode, String dutchText) {
    if (languageCode == 'nl') return dutchText;
    return _dutchSourceStringAdditions[languageCode]?[dutchText] ??
        _dutchSourceStrings[languageCode]?[dutchText] ??
        _dutchSourceStringAdditions['en']?[dutchText] ??
        _dutchSourceStrings['en']?[dutchText] ??
        dutchText;
  }

  static bool hasDirectDutchSourceTranslation(
    String languageCode,
    String dutchText,
  ) {
    if (languageCode == 'nl') return true;
    return _dutchSourceStringAdditions[languageCode]?.containsKey(dutchText) ==
            true ||
        _dutchSourceStrings[languageCode]?.containsKey(dutchText) == true;
  }

  /// Whether [languageCode] carries its own [key] in the keyed `t()` table
  /// (no fall-through to English/Dutch). A guard test uses this to enforce
  /// that every `t()` key used in the app is present in every language.
  static bool hasTranslationKey(String languageCode, String key) {
    return _strings[languageCode]?.containsKey(key) == true;
  }
}

extension AppLocalizationsX on BuildContext {
  AppLocalizations get l10n => AppLocalizations.of(this);
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  bool isSupported(Locale locale) {
    return AppLocalizations.languageNames.containsKey(locale.languageCode);
  }

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture(AppLocalizations(locale));
  }

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

const _strings = {
  'nl': _stringsNl,
  'en': _stringsEn,
  'it': _stringsIt,
  'de': _stringsDe,
  'fr': _stringsFr,
  'es': _stringsEs,
  'fy': _stringsFy,
  'pap': _stringsPap,
  'la': _stringsLa,
  'id': _stringsId,
  'pl': _stringsPl,
  'uk': _stringsUk,
  'gsw': _stringsGsw,
  'el': _stringsEl,
  'da': _stringsDa,
  'sv': _stringsSv,
  'hr': _stringsHr,
  'cs': _stringsCs,
  'fi': _stringsFi,
  'bg': _stringsBg,
  'lv': _stringsLv,
  'lt': _stringsLt,
  'mt': _stringsMt,
  'et': _stringsEt,
  'hu': _stringsHu,
  'ga': _stringsGa,
  'pt': _stringsPt,
  'ro': _stringsRo,
  'sl': _stringsSl,
  'sk': _stringsSk,
  'tlh': _stringsTlh,
  'tr': _stringsTr,
};

const _dutchSourceStrings = {
  'en': _dutchSourceEn,
  'it': _dutchSourceIt,
  'de': _dutchSourceDe,
  'fr': _dutchSourceFr,
  'es': _dutchSourceEs,
  'fy': _dutchSourceFy,
  'pap': _dutchSourcePap,
  'la': _dutchSourceLa,
  'id': _dutchSourceId,
  'pl': _dutchSourcePl,
  'uk': _dutchSourceUk,
  'gsw': _dutchSourceGsw,
  'el': _dutchSourceEl,
  'da': _dutchSourceDa,
  'sv': _dutchSourceSv,
  'hr': _dutchSourceHr,
  'cs': _dutchSourceCs,
  'fi': _dutchSourceFi,
  'bg': _dutchSourceBg,
  'lv': _dutchSourceLv,
  'lt': _dutchSourceLt,
  'mt': _dutchSourceMt,
  'et': _dutchSourceEt,
  'hu': _dutchSourceHu,
  'ga': _dutchSourceGa,
  'pt': _dutchSourcePt,
  'ro': _dutchSourceRo,
  'sl': _dutchSourceSl,
  'sk': _dutchSourceSk,
  'tlh': _dutchSourceTlh,
  'tr': _dutchSourceTr,
};

const _dutchSourceStringAdditions = {
  'en': _dutchSourceAddEn,
  'it': _dutchSourceAddIt,
  'de': _dutchSourceAddDe,
  'fr': _dutchSourceAddFr,
  'es': _dutchSourceAddEs,
  'fy': _dutchSourceAddFy,
  'pap': _dutchSourceAddPap,
  'la': _dutchSourceAddLa,
  'id': _dutchSourceAddId,
  'pl': _dutchSourceAddPl,
  'uk': _dutchSourceAddUk,
  'gsw': _dutchSourceAddGsw,
  'el': _dutchSourceAddEl,
  'da': _dutchSourceAddDa,
  'sv': _dutchSourceAddSv,
  'hr': _dutchSourceAddHr,
  'cs': _dutchSourceAddCs,
  'fi': _dutchSourceAddFi,
  'bg': _dutchSourceAddBg,
  'lv': _dutchSourceAddLv,
  'lt': _dutchSourceAddLt,
  'mt': _dutchSourceAddMt,
  'et': _dutchSourceAddEt,
  'hu': _dutchSourceAddHu,
  'ga': _dutchSourceAddGa,
  'pt': _dutchSourceAddPt,
  'ro': _dutchSourceAddRo,
  'sl': _dutchSourceAddSl,
  'sk': _dutchSourceAddSk,
  'tlh': _dutchSourceAddTlh,
  'tr': _dutchSourceAddTr,
};
