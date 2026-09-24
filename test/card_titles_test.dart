@TestOn('vm')
library;

import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/l10n/app_localizations.dart';
import 'package:ocideck/state/integration_registry.dart';
import 'package:ocideck/state/module_registry.dart';
import 'package:ocideck/widgets/dialogs/settings/card_titles.dart';

/// De alfabetische kaartvolgorde op Uitbreidingen en Integraties (#2187).
///
/// De regel: sorteer op de VERTAALDE titel in de actieve taal, niet op
/// registervolgorde en niet op de Nederlandse bron. Daarvoor delen sorteren
/// en tonen dezelfde titelbron — deze test pint dat, en dat de volgorde met
/// de taal meebeweegt.
void main() {
  // d() leest de statische actieve taal, niet de locale van de instantie —
  // dus die zetten we hier per test.
  AppLocalizations l10nFor(String code) {
    AppLocalizations.setActiveLanguageCode(code);
    addTearDown(() => AppLocalizations.setActiveLanguageCode('nl'));
    return const AppLocalizations(Locale('nl'));
  }

  List<String> moduleTitels(AppLocalizations l10n) {
    final cards = [
      for (final entry in moduleRegistry)
        (title: moduleCardTitle(entry.id, l10n), card: const SizedBox()),
    ];
    sortCardsByTitle(cards);
    return [for (final c in cards) c.title];
  }

  List<String> integratieTitels(AppLocalizations l10n) {
    final cards = [
      for (final entry in integrationRegistry)
        (title: integrationCardTitle(entry.id, l10n), card: const SizedBox()),
    ];
    sortCardsByTitle(cards);
    return [for (final c in cards) c.title];
  }

  test('nl: kaarten staan alfabetisch op de Nederlandse titel', () {
    final l10n = l10nFor('nl');
    final titels = moduleTitels(l10n);
    // Afbeeldingsrechten (a-f) voor AI-assistentie (a-i), en het hele rijtje
    // is op oplopende sorteersleutel.
    expect(
      titels.indexOf('Afbeeldingsrechten'),
      lessThan(titels.indexOf('AI-assistentie')),
    );
    final keys = [for (final t in titels) AppLocalizations.sortKey(t)];
    expect(keys, orderedEquals([...keys]..sort()));
  });

  test('en: dezelfde kaarten schuiven mee met de taal', () {
    final l10n = l10nFor('en');
    final titels = moduleTitels(l10n);
    // In het Engels kantelt het paar: "AI assistance" (a-i) komt vóór
    // "Image rights" (i). Wie op de Nederlandse bron sorteerde had de
    // omgekeerde volgorde getoond — precies de fout die #2187 meldt.
    expect(
      titels.indexOf('AI assistance'),
      lessThan(titels.indexOf('Image rights')),
    );
    final keys = [for (final t in titels) AppLocalizations.sortKey(t)];
    expect(keys, orderedEquals([...keys]..sort()));
  });

  test('elke module en integratie heeft een titel uit de gedeelde bron', () {
    final l10n = l10nFor('nl');
    // Geen switch-coverage-doorgeefluik: de compiler dwingt de switch af, dus
    // hier bewaken we alleen dat er geen lege titel in zit.
    for (final entry in moduleRegistry) {
      expect(moduleCardTitle(entry.id, l10n), isNotEmpty);
    }
    for (final entry in integrationRegistry) {
      expect(integrationCardTitle(entry.id, l10n), isNotEmpty);
    }
  });

  test('integraties sorteren op dezelfde sleutel', () {
    final l10n = l10nFor('nl');
    final titels = integratieTitels(l10n);
    // nl: "eLearning volgen" (e) voor "OpenKAT" (o).
    expect(
      titels.indexOf('eLearning volgen'),
      lessThan(titels.indexOf('OpenKAT')),
    );
  });
}
