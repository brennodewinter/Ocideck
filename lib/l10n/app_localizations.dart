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
  };

  /// Language options sorted by display name, for pickers (the map itself keeps
  /// its own order for lookups). Locale-aware compare so accented names sort
  /// naturally.
  static List<MapEntry<String, String>> get languageOptions =>
      languageNames.entries.toList()..sort(
        (a, b) => a.value.toLowerCase().compareTo(b.value.toLowerCase()),
      );

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
};

const _dutchSourceStringAdditions = {
  'en': _dutchSourceAddEn,
  'it': _dutchSourceAddIt,
  'de': _dutchSourceAddDe,
  'fr': _dutchSourceAddFr,
  'es': _dutchSourceAddEs,
  'fy': _dutchSourceAddFy,
  'pap': _dutchSourceAddPap,
};
