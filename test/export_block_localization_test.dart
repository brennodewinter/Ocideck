// De weigering van het classificatiebeleid, als zin.
//
// Deze toetsen stonden tot #576 op de dienst: die bouwde het Nederlandse proza
// zelf. Dat kón niet vertaald worden — de vertaallaag sleutelt op letterlijke
// brontekst, en een zin die een TLP-niveau interpoleert heeft geen letterlijke
// vorm. Wat de gebruiker las was dus Nederlands, welke taal hij ook koos, en
// dat trof precies de verkeerde categorie: dit zijn de meldingen die je
// tegenhouden.
//
// De assertie op de inhoud is niet verdwenen maar verhuisd naar de laag waar de
// zin nu gemaakt wordt. Dat is het punt van deze hele wijziging.

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/l10n/app_localizations.dart';
import 'package:ocideck/l10n/export_block_localization.dart';
import 'package:ocideck/models/deck.dart';
import 'package:ocideck/services/classification_policy.dart';

void main() {
  const l10n = AppLocalizations(Locale('nl'));

  setUp(() => AppLocalizations.setActiveLanguageCode('nl'));

  test('een toegestane export levert geen melding op', () {
    expect(exportBlockMessage(l10n, const ExportDecision.allow()), isNull);
    expect(exportBlockMessage(l10n, null), isNull);
  });

  test('het plafond noemt beide niveaus', () {
    final msg = exportBlockMessage(
      l10n,
      const ExportDecision.block(
        ExportBlockReason.aboveCeiling,
        deckLevel: TlpLevel.red,
        limit: TlpLevel.amber,
      ),
    )!;
    expect(msg, contains(TlpLevel.red.label));
    expect(msg, contains(TlpLevel.amber.label));
    expect(
      msg,
      isNot(contains('{')),
      reason: 'geen plaatshouder blijven staan',
    );
  });

  test('een ongeclassificeerd deck heet ook zo', () {
    // Het niveau `none` heeft geen bruikbaar label voor een zin; hier stond
    // "niet geclassificeerd" en dat hoort te blijven staan.
    final msg = exportBlockMessage(
      l10n,
      const ExportDecision.block(
        ExportBlockReason.belowMinimum,
        deckLevel: TlpLevel.none,
        limit: TlpLevel.green,
      ),
    )!;
    expect(msg, contains('niet geclassificeerd'));
    expect(msg, contains(TlpLevel.green.label));
  });

  test('de ontbrekende classificatie vraagt om een niveau', () {
    final msg = exportBlockMessage(
      l10n,
      const ExportDecision.block(ExportBlockReason.classificationMissing),
    )!;
    expect(msg, contains('TLP'));
    expect(msg, isNot(contains('{')));
  });

  test('de zin volgt de taal van de gebruiker', () {
    // De kern van #576: deze melding was Nederlands in élke taal.
    //
    // De taal komt uit de statische `setActiveLanguageCode`, niet uit de Locale
    // in de constructor — die is alleen een Flutter-handvat. Dat kostte me een
    // groene test die niets bewees: met alleen `AppLocalizations(Locale('de'))`
    // zocht de opzoeking gewoon in de Nederlandse tak.
    const decision = ExportDecision.block(
      ExportBlockReason.classificationMissing,
    );
    final nl = exportBlockMessage(l10n, decision);

    AppLocalizations.setActiveLanguageCode('de');
    addTearDown(() => AppLocalizations.setActiveLanguageCode('nl'));
    final de = exportBlockMessage(
      const AppLocalizations(Locale('de')),
      decision,
    );

    expect(de, isNotNull);
    expect(
      de,
      isNot(nl),
      reason: 'Duits en Nederlands horen niet dezelfde zin op te leveren',
    );
  });
}
