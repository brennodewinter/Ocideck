import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/l10n/app_localizations.dart';
import 'package:ocideck/l10n/language_registry.dart';

void main() {
  test('registry is the single source AppLocalizations re-exposes', () {
    // The app API and the Flutter-free registry must be the same data — the
    // whole point of the split is that build tooling reads exactly what the app
    // resolves (translate_docs.dart depends on this).
    expect(AppLocalizations.languageNames, same(kLanguageNames));
  });

  test('the docs base language is one of the registered languages', () {
    // translate_docs.dart excludes kDocsBaseLanguage from the languages it
    // translates into, so it must be a real interface-language code.
    expect(kLanguageNames.containsKey(kDocsBaseLanguage), isTrue);
    expect(kDocsBaseLanguage, 'en');
  });

  test('every language code is a non-empty lowercase key with a name', () {
    expect(kLanguageNames, isNotEmpty);
    for (final entry in kLanguageNames.entries) {
      expect(entry.key, isNotEmpty);
      expect(entry.key, equals(entry.key.toLowerCase()));
      expect(entry.value.trim(), isNotEmpty);
    }
    // Dutch is the source language and English the docs base — both present.
    expect(kLanguageNames.containsKey('nl'), isTrue);
    expect(kLanguageNames.containsKey('en'), isTrue);
  });
}
