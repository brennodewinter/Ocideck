import 'dart:io';

import 'package:flutter/material.dart';
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
      'Accent / bullets',
      'Bullet',
      'Coverflow',
      'Label',
      'Logo',
      'Logo px',
      'PREVIEW',
      'Preview',
      'SLIDES',
      'Slide',
      'slide',
      'Spider',
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
      'Accent / bullets',
      'Bullet',
      'Coverflow',
      'Label',
      'Logo',
      'Logo px',
      'PREVIEW',
      'Preview',
      'SLIDES',
      'Slide',
      'slide',
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
