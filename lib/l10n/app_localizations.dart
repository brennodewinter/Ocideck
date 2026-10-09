import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';
import 'package:app_localizations/app_localizations.dart' as foundation;

import 'language_registry.dart';

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
part 'translations/tr.dart';

const _sharedTranslationKeys = <String, String>{
  'save': 'Opslaan',
  'saveSettings': 'Opslaan',
  'cancel': 'Annuleren',
  'close': 'Sluiten',
  'settings': 'Instellingen',
  'language': 'Taal',
  'applicationLanguage': 'Applicatietaal',
};

class AppLocalizations {
  final Locale locale;

  const AppLocalizations(this.locale);

  static final supportedLocales =
      foundation.FlutterAppLanguages.supportedLocales;

  /// Display name per interface-language code. The map itself lives in
  /// [kLanguageNames] — a Flutter-free file so build tooling can read the set of
  /// languages without compiling Flutter (see `language_registry.dart`).
  static const languageNames = kLanguageNames;

  /// A country flag (emoji) per language, shown in the language pickers. Some
  /// choices are by convention: English → United Kingdom, Latin → Vatican City,
  /// Frisian → Netherlands (Friesland), Papiamento → Curaçao, Swiss German →
  /// Switzerland.
  static const languageFlags = foundation.AppLanguages.flags;

  /// Latin-folded, lowercased sort key of [s] (see [_translitMap]). Public so
  /// other pickers (e.g. the template chooser) sort display names the same way
  /// the language list does — diacritics and other scripts land where a reader
  /// expects them instead of after all plain-Latin names.
  static String sortKey(String s) => foundation.AppLanguages.sortKey(s);

  /// Language options sorted by a Latin-folded key of the display name, for
  /// pickers (the map itself keeps its own order for lookups).
  static List<MapEntry<String, String>> get languageOptions =>
      foundation.AppLanguages.options;

  static String _activeLanguageCode = 'nl';

  static void setActiveLanguageCode(String code) {
    _activeLanguageCode = languageNames.containsKey(code) ? code : 'nl';
  }

  /// De actieve interface-taalcode, zoals [setActiveLanguageCode] het laatst
  /// zette. De HTML-export bewaart deze, stelt tijdelijk de taal van het deck
  /// in voor de chrome-strings, en zet hem in `finally` terug — zie
  /// [MarpHtmlService.build].
  static String get activeLanguageCode => _activeLanguageCode;

  /// De localisatie die de actieve interface-taal leest. [d] en [t] sleutelen
  /// op de statisch gezette taal ([setActiveLanguageCode]), niet op de
  /// [Locale] die de constructor meekrijgt — dus `const
  /// AppLocalizations(Locale('nl')).d('Nieuw')` volgt wél de actieve taal,
  /// ondanks dat de `Locale('nl')` hardcoded Nederlands suggereert. Dat
  /// handvat heeft al twee lezers in de val laten lopen (zie #1251), dus dit
  /// is het eerlijke handvat: de [Locale] klopt hier bij de taal die `d()`
  /// ook echt leest. Geen `const`: de actieve taal staat niet vast op
  /// compileertijd.
  static AppLocalizations get active =>
      AppLocalizations(Locale(_activeLanguageCode));

  static Locale materialLocaleFor(String code) {
    return foundation.FlutterAppLanguages.materialLocaleFor(code);
  }

  /// De taal waarin de app opstart als de gebruiker er nog geen koos.
  ///
  /// [systemLocales] is de voorkeurslijst van het besturingssysteem, op
  /// volgorde van voorkeur; de eerste die wij spreken wint. Spreken we er geen
  /// enkele, dan wordt het Engels — niet Nederlands. Dat is geen bescheidenheid
  /// maar rekenkunde: wie een taal opgeeft die hier niet in staat, leest met
  /// veel grotere kans Engels dan Nederlands.
  ///
  /// Dit gaat alléén over de startwaarde. Zodra de gebruiker zelf kiest, staat
  /// die keuze in de voorkeuren en komt deze functie er niet meer aan te pas.
  static String preferredLanguageCode(Iterable<Locale> systemLocales) {
    return foundation.FlutterAppLanguages.preferredLanguageCode(systemLocales);
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations) ??
        const AppLocalizations(Locale('nl'));
  }

  String get languageCode => _activeLanguageCode;

  String t(String key) {
    if (_sharedTranslationKeys[key] case final source?) return d(source);
    if (languageCode == 'nl') return _strings['nl']![key] ?? key;
    return _strings[languageCode]?[key] ??
        _strings['en']?[key] ??
        _strings['nl']![key] ??
        key;
  }

  String d(String dutchText) {
    return foundation.translateDutch(
      languageCode,
      dutchText,
      productLayers: _productTranslationLayers,
    );
  }

  static String sourceFor(String languageCode, String dutchText) {
    return foundation.translateDutch(
      languageCode,
      dutchText,
      productLayers: _productTranslationLayers,
    );
  }

  static bool hasDirectDutchSourceTranslation(
    String languageCode,
    String dutchText,
  ) {
    return foundation.hasDirectTranslation(
      languageCode,
      dutchText,
      productLayers: _productTranslationLayers,
    );
  }

  /// Whether [languageCode] carries its own [key] in the keyed `t()` table
  /// (no fall-through to English/Dutch). A guard test uses this to enforce
  /// that every `t()` key used in the app is present in every language.
  static bool hasTranslationKey(String languageCode, String key) {
    if (_sharedTranslationKeys.containsKey(key)) return true;
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
  'tr': _dutchSourceAddTr,
};

const _productTranslationLayers = <Map<String, Map<String, String>>>[
  _dutchSourceStringAdditions,
  _dutchSourceStrings,
];
