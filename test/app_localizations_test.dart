import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/l10n/app_localizations.dart';

void main() {
  tearDown(() => AppLocalizations.setActiveLanguageCode('nl'));

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

    const unchangedInEnglish = {
      'CWE',
      'CVE',
      'F-03',
      'CVE-2024-1234, CVE-2024-5678',
      'CWE-89 — Improper Neutralization of SQL',
      'IBAN',
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
    };
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
    const unchangedInAllLanguages = {
      'CWE',
      'CVE',
      'F-03',
      'CVE-2024-1234, CVE-2024-5678',
      'CWE-89 — Improper Neutralization of SQL',
      'IBAN',
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
