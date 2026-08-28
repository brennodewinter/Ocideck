import 'dart:io';

import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/l10n/app_localizations.dart';

import '../tool/check_hardcoded_text.dart' show sourceKeysIn;

/// Leenwoorden die in het Engels letterlijk gelijk blijven aan het Nederlands.
///
/// Staat bovenaan het bestand en niet in de test, omdat `make add-l10n` deze
/// lijst bijwerkt (het "unchanged"-deel van de spec) en meerdere tests hem
/// delen.
const unchangedInEnglish = {
  'LaTeX (.tex)',
  'HTML',
  'Markdown (.md)',
  'Mermaid',
  'Server: {name}',
  'https://openkat.voorbeeld.nl',
  'Gantt',
  'Auto',
  'Week',
  // Toetsnaam: 'Esc' blijft 'Esc', ook in het Engels (zie unchangedInAllLanguages).
  'Esc',
  'A.5.1',
  '2026-Q4',
  'ABCD-EFGH-…',
  'Matrix',
  // Het chatpaneel: het Engels houdt het leenwoord 'Chat', maar andere talen
  // vertalen het wél (Grieks Συνομιλία, Hongaars Csevegés, Sloveens Klepet, …),
  // dus alleen op de Engelse witte lijst — niet op unchangedInAllLanguages.
  'Chat',
  // De sectiekop van de dia-footer in de stijlbouwer. Engels en Italiaans
  // houden het leenwoord 'Footer'; de meeste andere talen vertalen het wél
  // (Duits Fußzeile, Frans Pied de page, Zweeds Sidfot, …), dus alleen op de
  // Engelse witte lijst.
  'Footer',
  // De media-preflighttegel: het Engels houdt 'Media (WebRTC)' identiek aan het
  // Nederlands, maar andere talen vertalen 'Media' wél (Duits Medien, Frans
  // Médias, Grieks Πολυμέσα, …), dus alleen op de Engelse witte lijst — niet op
  // unchangedInAllLanguages.
  'Media (WebRTC)',
  // Image callouts: het Engels houdt het leenwoord 'Callout'/'Callouts'
  // identiek aan het Nederlands, maar andere talen vertalen het wél.
  'Callout',
  'Callouts',
  // Callout-editor: technische term 'target(s)' blijft gelijk in het Engels.
  'target(s)',
  'CVSS',
  // Het documenttabblad: het Engels houdt 'Document' identiek aan het
  // Nederlands, maar andere talen vertalen het wél (Italiaans Documento, Duits
  // Dokument, Fins Asiakirja, …), dus alleen op de Engelse witte lijst — niet op
  // unchangedInAllLanguages.
  'Document',
  // De standaard-exportnaam van een naamloos document: het Engels houdt
  // 'document' identiek aan het Nederlands, maar andere talen vertalen het wél
  // (Duits Dokument, Fins asiakirja, Grieks έγγραφο, …), dus alleen op de
  // Engelse witte lijst — niet op unchangedInAllLanguages.
  'document',
  'https://matrix.to/#/…',
  'https://matrix.example.org',
  '@jij:matrix.example.org',
  // LibrePlan-connector: voorbeeld-URL en -gebruikersnaam (#1240)
  'https://libreplan.example.org/libreplan/',
  'wsreader',
  'Homeserver',
  'SWOT',
  'A3',
  'FMEA',
  'RACI',
  'SIPOC',
  '5× Why',
  'S',
  'O',
  'D',
  'R',
  'A',
  'C',
  'I',
  'Backlog',
  'Baseline',
  'Part × Operator interaction pooled into repeatability',
  'Part × Operator interaction kept separate',
  'RPN',
  'AD p=',
  'Probability plot',
  'Gage R&R (ANOVA)',
  'Gage R&R…',
  'Intercept',
  'Distinct categories (ndc)',
  '% contribution',
  '% study variation',
  '% tolerance',
  'Eenweg-ANOVA',
  'VSM',
  'Histogram',
  'Pareto',
  'Run chart',
  'CC-BY-SA-4.0',
  'CC-BY-4.0',
  'EUPL-1.2',
  'MITRE Terms of Use',
  'OpenKAT',
  'Vigilis',
  'http://127.0.0.1:11434/v1',
  'gemma3:4b',
  'https://git.librekat.nl',
  'librekat',
  'decks',
  'main',
  'https://s3.eu-central-1.amazonaws.com',
  'eu-central-1',
  'https://cloud.librekat.nl',
  'https://dav.librekat.nl/dav/files',
  'OciDeck',
  'Stichting LibreKAT',
  // 'slides' is in het Engels hetzelfde woord als in het Nederlands. Het staat
  // hier omdat het óók een `t()`-sleutel is: `add_l10n` keek bestandsbreed en
  // sloeg de `d()`-variant daardoor in alle 31 talen over.
  'slides',
  // Net als 'slides': in het Engels hetzelfde woord. Kwam pas boven toen het
  // woord in de kwaliteitsmelding door `d()` ging in plaats van hardgecodeerd
  // in de zin te staan (#677) — de andere 31 talen vertalen het wél.
  'bullets',
  'GitHub',
  'GitLab',
  'TLP',
  'SHA-512:',
  '#33FF33',
  '#2563EB',
  'v1.0',
  'https://...',
  'MASWE',
  'MASWE-0005',
  'WSTG-ATHN-07',
  'Testing for Weak Password Policy',
  'CVSS:4.0/AV:N/AC:L/AT:N/PR:N/UI:N/VC:H/VI:H/VA:L/SC:N/SI:N/SA:N',
  'CWE',
  'CVE',
  'F-03',
  'CVE-2024-1234, CVE-2024-5678',
  'CWE-89 — Improper Neutralization of SQL',
  'IBAN',
  // De registratie- en contactgegevens van de uitgever in het Over-venster. Een
  // postadres, een rekeningnummer, een KvK-inschrijving en een domeinnaam zijn
  // wat de uitgevende instantie ervan geregistreerd heeft; een vertaalde versie
  // verwijst naar niets. Ze kwamen pas met #803 in beeld: tot dan keek de poort
  // langs een aanroep binnen een extension heen.
  'Weidemolen 12, 2211 PW Noordwijkerhout\nWilhelminaplein 12, 8911 BS Leeuwarden',
  'stichting@librekat.nl',
  'KvK',
  'NL63 TRIO 0321 2051 89',
  'BIC',
  'TRIONL2U',
  'Triodos N.V.',
  'www.pilotinformatieautonomie.nl',
  'Server',
  'Deadline',
  'Access key ID',
  'Bucket',
  'Endpoint',
  'Secret access key',
  'WebDAV',
  'Repository',
  'Personal access token',
  'ID',
  'Test',
  'Checklists',
  'Context',
  'Accent / bullets',
  'Audio',
  'Bank',
  'Bullet',
  'Code',
  'Combo',
  'Donut',
  'Heatmap',
  'Video',
  'Contact',
  'Coverflow',
  'Label',
  'Link',
  'Laser (X)',
  'Logo',
  'Logo px',
  'Max',
  'Media',
  'Meter',
  'Pen (D)',
  'Min',
  'Nextcloud',
  'Object',
  'Online',
  'Online media',
  'Status',
  'PREVIEW',
  'Pitch',
  'Preview',
  'Privacy',
  'SLIDES',
  'Slide',
  'slide',
  'Spider',
  'Type',
  'Contrast',
  ':1).',
  // The scorecard's "was 375" line. Dutch and English happen to spell it
  // the same; it is genuinely translated everywhere else.
  'was',
  // Het Help-menu in de macOS-menubalk. Nederlands en Engels schrijven dit
  // menu identiek, dus valt de Engelse vertaling samen met de bronstring.
  // Alleen hier: de overige dertig talen dragen hun eigen woord — Duits
  // 'Hilfe', Frans 'Aide', Tsjechisch 'Nápověda', Klingon 'QaH' — en die
  // dekking blijft door `unchangedInAllLanguages` bewust ongemoeid.
  'Help',
  // Toetskappen en de minuut-afkorting: het Nederlandse toetsenbord draagt de
  // Engelse opschriften, dus de bronstring ís al Engels. Elders wel echt
  // vertaald — Frans zet 'échap' en 'Entrée', Spaans 'Intro', Italiaans
  // 'Invio', Turks 'dk', Klingon 'tup'.
  'esc',
  'Enter',
  'OK',
  'min',
  // De twee vertaalbare helften van een sneltoetsaanduiding (zie
  // lib/utils/shortcut_label.dart). Het Nederlandse toetsenbord draagt hier de
  // Engelse opschriften, dus vallen bron en Engelse vertaling samen. Elders wel
  // echt anders: Duits leest 'Strg/Cmd' en 'Umschalt', Frans 'Maj', Spaans
  // 'Mayús', Italiaans 'Maiusc'.
  'Ctrl/Cmd',
  'Shift',
  // De teksten op de cockpitglazen. P/B (pitch/bank) en ACT/TGT zijn de
  // luchtvaartafkortingen zoals ze op een echt instrument staan, en dat is in
  // het Engels hetzelfde als in het Nederlands. Talen met een eigen
  // instrumententaal krijgen die wel: Duits leest IST/SOLL, Grieks Π/Κ,
  // Frans T/I.
  'P {pitch}  B {bank}',
  'ACT {value}°',
  'TGT {heading}°',
};

/// Idem, maar voor ALLE talen: termen die overal letterlijk gelijk blijven —
/// leenwoorden en technische identifiers (CWE, MASWE, F-03, een CVSS-vector).
/// Vertalen zou ze onvindbaar maken.
const unchangedInAllLanguages = {
  'LaTeX (.tex)',
  'HTML',
  'Markdown (.md)',
  'Mermaid',
  'Server: {name}',
  'https://openkat.voorbeeld.nl',
  'Gantt',
  'Auto',
  'Week',
  // Toetsnaam, geen tekst: de 'Esc'-sneltoetshint in de vergroot-markdown-dialoog
  // is een identifier die in elke taal 'Esc' blijft (zie shortcut_label.dart).
  'Esc',
  'A.5.1',
  '2026-Q4',
  'ABCD-EFGH-…',
  'Matrix',
  'CVSS',
  'https://matrix.to/#/…',
  'https://matrix.example.org',
  '@jij:matrix.example.org',
  'Homeserver',
  'SWOT',
  'A3',
  'FMEA',
  'RACI',
  'SIPOC',
  '5× Why',
  'S',
  'O',
  'D',
  'R',
  'A',
  'C',
  'I',
  'Backlog',
  'Baseline',
  'Probability plot',
  'Gage R&R (ANOVA)',
  'Gage R&R…',
  'Intercept',
  'Distinct categories (ndc)',
  '% contribution',
  '% study variation',
  '% tolerance',
  'Eenweg-ANOVA',
  'VSM',
  'RPN',
  'AD p=',
  'Histogram',
  'Pareto',
  'Run chart',
  'CC-BY-SA-4.0',
  'CC-BY-4.0',
  'EUPL-1.2',
  'MITRE Terms of Use',
  'OpenKAT',
  'Vigilis',
  'http://127.0.0.1:11434/v1',
  'gemma3:4b',
  'https://git.librekat.nl',
  'librekat',
  'decks',
  'main',
  'https://s3.eu-central-1.amazonaws.com',
  'eu-central-1',
  'https://cloud.librekat.nl',
  'https://dav.librekat.nl/dav/files',
  'OciDeck',
  'Stichting LibreKAT',
  'GitHub',
  'GitLab',
  'TLP',
  'SHA-512:',
  '#33FF33',
  '#2563EB',
  'v1.0',
  'https://...',
  'MASWE',
  'MASWE-0005',
  'WSTG-ATHN-07',
  'Testing for Weak Password Policy',
  'CVSS:4.0/AV:N/AC:L/AT:N/PR:N/UI:N/VC:H/VI:H/VA:L/SC:N/SI:N/SA:N',
  'CWE',
  'CVE',
  'F-03',
  'CVE-2024-1234, CVE-2024-5678',
  'CWE-89 — Improper Neutralization of SQL',
  'IBAN',
  // De registratie- en contactgegevens van de uitgever in het Over-venster. Een
  // postadres, een rekeningnummer, een KvK-inschrijving en een domeinnaam zijn
  // wat de uitgevende instantie ervan geregistreerd heeft; een vertaalde versie
  // verwijst naar niets. Ze kwamen pas met #803 in beeld: tot dan keek de poort
  // langs een aanroep binnen een extension heen.
  'Weidemolen 12, 2211 PW Noordwijkerhout\nWilhelminaplein 12, 8911 BS Leeuwarden',
  'stichting@librekat.nl',
  'KvK',
  'NL63 TRIO 0321 2051 89',
  'BIC',
  'TRIONL2U',
  'Triodos N.V.',
  'www.pilotinformatieautonomie.nl',
  'Server',
  'Access key ID',
  'Bucket',
  'Endpoint',
  'Secret access key',
  'WebDAV',
  'Repository',
  'Personal access token',
  'ID',
  'Test',
  'Checklists',
  'Context',
  'Accent / bullets',
  'Bullet',
  'Code',
  'Combo',
  'Coverflow',
  'Donut',
  'Heatmap',
  'Label',
  'Link',
  'Logo',
  'Logo px',
  'Media',
  'PREVIEW',
  'Preview',
  'SLIDES',
  'Slide',
  'slide',
  'Contrast',
  ':1).',
};

void main() {
  tearDown(() => AppLocalizations.setActiveLanguageCode('nl'));

  group('startup language for an installation without a choice', () {
    test('takes the first system locale the app actually speaks', () {
      expect(
        AppLocalizations.preferredLanguageCode(const [Locale('de')]),
        'de',
      );
      expect(
        AppLocalizations.preferredLanguageCode(const [
          Locale('de', 'DE'),
          Locale('en'),
        ]),
        'de',
      );
    });

    test(
      'skips locales it does not speak instead of stopping at the first',
      () {
        expect(
          AppLocalizations.preferredLanguageCode(const [
            Locale('ja'),
            Locale('ar'),
            Locale('pl'),
          ]),
          'pl',
        );
      },
    );

    // Engels, niet Nederlands: wie een taal opgeeft die wij niet spreken leest
    // met veel grotere kans Engels. Dit is de regel die maakte dat elke
    // eerste gebruiker ter wereld een Nederlands toestemmingsscherm kreeg.
    test(
      'falls back to English, not Dutch, for a language it does not have',
      () {
        expect(
          AppLocalizations.preferredLanguageCode(const [Locale('ja')]),
          'en',
        );
        expect(AppLocalizations.preferredLanguageCode(const []), 'en');
      },
    );

    test('still returns Dutch when the system asks for Dutch', () {
      expect(
        AppLocalizations.preferredLanguageCode(const [Locale('nl')]),
        'nl',
      );
    });
  });

  test('supports Frisian and Papiamento language choices', () {
    expect(AppLocalizations.languageNames['fy'], 'Frysk');
    expect(AppLocalizations.languageNames['pap'], 'Papiamento');
    expect(AppLocalizations.supportedLocales, contains(const Locale('fy')));
    expect(AppLocalizations.supportedLocales, contains(const Locale('pap')));
  });

  test('uses app translations while Material falls back safely', () {
    AppLocalizations.setActiveLanguageCode('fy');
    expect(const AppLocalizations(Locale('en')).t('settings'), 'Ynstellingen');
    expect(
      const AppLocalizations(Locale('en')).d('Toetsenlegenda'),
      'Toetsleginda',
    );
    expect(AppLocalizations.materialLocaleFor('fy'), const Locale('en'));

    AppLocalizations.setActiveLanguageCode('pap');
    expect(
      const AppLocalizations(Locale('en')).t('settings'),
      'Preferensianan',
    );
    expect(
      const AppLocalizations(Locale('en')).d('Toetsenlegenda'),
      'Legenda di tekla',
    );
    expect(AppLocalizations.materialLocaleFor('pap'), const Locale('en'));
  });

  test('all literal Dutch source strings have an English fallback', () {
    AppLocalizations.setActiveLanguageCode('en');

    final expression = RegExp(r'''\.d\(\s*('(?:\\.|[^'])*'|"(?:\\.|[^"])*")''');
    final files = Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((file) => file.path.endsWith('.dart'));
    final sources = <String>{};

    for (final file in files) {
      final content = file.readAsStringSync();
      for (final match in expression.allMatches(content)) {
        sources.add(_unquoteDartString(match.group(1)!));
      }
    }

    final english = const AppLocalizations(Locale('en'));
    final missing = sources.where((source) {
      final translated = english.d(source);
      return translated == source && !unchangedInEnglish.contains(source);
    }).toList()..sort();

    expect(missing, isEmpty);
  });

  test('all literal Dutch source strings are translated in every language', () {
    final expression = RegExp(r'''\.d\(\s*('(?:\\.|[^'])*'|"(?:\\.|[^"])*")''');
    final files = Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((file) => file.path.endsWith('.dart'));
    final sources = <String>{};

    for (final file in files) {
      final content = file.readAsStringSync();
      for (final match in expression.allMatches(content)) {
        sources.add(_unquoteDartString(match.group(1)!));
      }
    }

    final missingByLanguage = <String, List<String>>{};
    for (final languageCode in AppLocalizations.languageNames.keys) {
      if (languageCode == 'nl') continue;
      final missing = sources.where((source) {
        if (unchangedInAllLanguages.contains(source)) return false;
        return !AppLocalizations.hasDirectDutchSourceTranslation(
          languageCode,
          source,
        );
      }).toList()..sort();
      if (missing.isNotEmpty) missingByLanguage[languageCode] = missing;
    }

    expect(missingByLanguage, isEmpty);
  });

  test('every indirect Dutch source key is translated in every language', () {
    // De andere helft van dezelfde belofte. De test hierboven leest alleen een
    // LETTERLIJKE `d('…')`; een bronstring die via een doorgeefluik in `d()`
    // belandt — `EditorField(label: 'Titel (H1)')`, `SectionLabel('Bullets')`,
    // `SettingsSearchEntry(label: …)` — ziet hij niet. Precies daar zaten
    // honderden onvertaalde labels: de string stond op de goede plek, maar in
    // 31 talen was hij Nederlands.
    //
    // De datastroomanalyse van tool/check_hardcoded_text.dart weet welke
    // literals langs zo'n weg lopen, en levert ze hier aan. Zo staat de eis op
    // één plek in plaats van als een lijst doorgeefluiken die iemand met de
    // hand moet bijhouden: een NIEUW doorgeefluik komt er vanzelf bij.
    final sources = sourceKeysIn('lib');

    // Een stilgevallen analyse meldt niets en zou dus groen zijn — dat is de
    // ene manier waarop deze test kan liegen.
    expect(sources, isNotEmpty);

    final missingByLanguage = <String, List<String>>{};
    for (final languageCode in AppLocalizations.languageNames.keys) {
      if (languageCode == 'nl') continue;
      final missing = sources.where((source) {
        if (unchangedInAllLanguages.contains(source)) return false;
        return !AppLocalizations.hasDirectDutchSourceTranslation(
          languageCode,
          source,
        );
      }).toList()..sort();
      if (missing.isNotEmpty) missingByLanguage[languageCode] = missing;
    }

    expect(missingByLanguage, isEmpty);
  });

  test('every t() key used in lib is present in every language', () {
    // Keyed t() strings reach the table by a string literal; scan the source
    // the same way the d() coverage tests do. A key missing in a language
    // would silently fall back to English/Dutch instead of the chosen
    // language — the one gap the d() tests could not catch.
    final expression = RegExp(r'''\.t\(\s*('[A-Za-z0-9_]+'|"[A-Za-z0-9_]+")''');
    final files = Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((file) => file.path.endsWith('.dart'));
    final keys = <String>{};

    for (final file in files) {
      final content = file.readAsStringSync();
      for (final match in expression.allMatches(content)) {
        keys.add(_unquoteDartString(match.group(1)!));
      }
    }

    // Guard against a broken scan silently passing (empty keys → no misses).
    expect(keys, isNotEmpty);

    final missingByLanguage = <String, List<String>>{};
    for (final languageCode in AppLocalizations.languageNames.keys) {
      final missing =
          keys
              .where(
                (key) => !AppLocalizations.hasTranslationKey(languageCode, key),
              )
              .toList()
            ..sort();
      if (missing.isNotEmpty) missingByLanguage[languageCode] = missing;
    }

    expect(missingByLanguage, isEmpty);
  });

  group('language registration is consistent', () {
    test('every language is a supported locale', () {
      for (final code in AppLocalizations.languageNames.keys) {
        expect(
          AppLocalizations.supportedLocales.map((l) => l.languageCode),
          contains(code),
          reason: '$code missing from supportedLocales',
        );
      }
      // ...and no stray supported locale lacks a name.
      for (final locale in AppLocalizations.supportedLocales) {
        expect(
          AppLocalizations.languageNames.containsKey(locale.languageCode),
          isTrue,
          reason: '${locale.languageCode} supported but unnamed',
        );
      }
    });

    test('every language has a flag', () {
      for (final code in AppLocalizations.languageNames.keys) {
        final flag = AppLocalizations.languageFlags[code];
        expect(
          flag != null && flag.isNotEmpty,
          isTrue,
          reason: '$code has no flag',
        );
      }
    });

    test('every Material fallback locale is one Flutter can localize', () {
      for (final code in AppLocalizations.languageNames.keys) {
        final locale = AppLocalizations.materialLocaleFor(code);
        expect(
          GlobalMaterialLocalizations.delegate.isSupported(locale),
          isTrue,
          reason: '$code → $locale is not a Material-supported locale',
        );
      }
    });
  });

  group('languageOptions ordering', () {
    List<String> order() =>
        AppLocalizations.languageOptions.map((e) => e.key).toList();

    test('lists every language exactly once', () {
      final keys = order();
      expect(keys.length, AppLocalizations.languageNames.length);
      expect(keys.toSet(), AppLocalizations.languageNames.keys.toSet());
    });

    test('non-Latin/diacritic names fold to their Latin position', () {
      final keys = order();
      int i(String c) => keys.indexOf(c);
      // Greek "Ελληνικά" → "ellinika", between Deutsch and English.
      expect(i('de'), lessThan(i('el')));
      expect(i('el'), lessThan(i('en')));
      // Czech "Čeština" → "cestina": near the front, before Dansk.
      expect(i('cs'), lessThan(i('da')));
      // Ukrainian "Українська" → "ukrainska": sorts to the very end.
      expect(i('uk'), keys.length - 1);
    });
  });
}

String _unquoteDartString(String value) {
  final quote = value[0];
  final body = value.substring(1, value.length - 1);
  return body
      .replaceAll(r'\\', r'\')
      .replaceAll('\\$quote', quote)
      .replaceAll(r'\n', '\n')
      .replaceAll(r'\r', '\r')
      .replaceAll(r'\t', '\t');
}
