// Elke regel in een tabel moet een echt label hebben (OCIWACHT §15.8).
//
// Er is geen centraal regelregister — dat is een bewuste keuze, want de
// regiopoort leidt het land uit het id af en een tweede lijst zou stilletjes uit
// de pas lopen. De prijs is dat niets afdwingt dat een nieuwe regel ook een
// label krijgt. `privacyRuleLabel` valt terug op `_ => ruleId`, dus een vergeten
// label maakt geen test rood: het toont de gebruiker `us.itin` in plaats van een
// naam, en dat merk je pas in een screenshot.
//
// De bestaande dekkingtest in `slide_quality_localization_coverage_test.dart`
// vangt dit niet, om twee redenen die elkaar versterken. Hij loopt over een
// handmatige lijst, dus een nieuwe regel staat er per definitie niet in. En hij
// toetst `isNotEmpty`, wat de fallback altijd haalt — `us.itin` is een prima
// niet-lege string. Twee gaten die precies samenvallen met het geval dat je
// wilt vangen.
//
// Deze test leidt de ids af uit de tabellen zélf en eist dat het label
// *verschilt* van het id. Dat dekt niet elke regel: de hardgecodeerde detectoren
// (contact.*, fin.*, special.*) staan in geen tabel en blijven op de handmatige
// lijst aangewezen. Het dekt wel precies de families waarin nieuwe landen en
// leveranciers bijkomen, en dat is waar het lek zit.

import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/l10n/app_localizations.dart';
import 'package:ocideck/l10n/slide_quality_localization.dart';
import 'package:ocideck/services/privacy/privacy_digital_rules.dart';
import 'package:ocideck/services/privacy/privacy_eu_rules.dart';
import 'package:ocideck/services/privacy/privacy_plate_rules.dart';
import 'package:ocideck/services/privacy/privacy_secret_rules.dart';
import 'package:ocideck/services/privacy/privacy_structural_rules.dart';
import 'package:ocideck/services/privacy/privacy_world_rules.dart';

void main() {
  const l10n = AppLocalizations(Locale('nl'));

  tearDown(() => AppLocalizations.setActiveLanguageCode('nl'));

  /// Alle regel-ids die als data in een tabel staan.
  List<String> tableRuleIds() => [
    ...euIdentifierRules.map((r) => r.id),
    ...worldIdentifierRules.map((r) => r.id),
    ...secretRules.map((r) => r.id),
    ...structuralRules.map((r) => r.id),
    ...digitalRules.map((r) => r.id),
    ...intlPostcodeRules.map((r) => r.ruleId),
  ];

  test('de tabellen leveren daadwerkelijk regels op', () {
    // Zonder deze ondergrens zou een hernoemde of leeggelopen tabel de test
    // groen laten door er niets meer in te stoppen — dezelfde valkuil als de
    // termCount-ondergrens in de vals-positievencorpus.
    expect(tableRuleIds().length, greaterThan(40));
  });

  test('geen enkel regel-id valt terug op zichzelf als label', () {
    AppLocalizations.setActiveLanguageCode('nl');
    final naamloos = <String>[];
    for (final id in tableRuleIds()) {
      if (privacyRuleLabel(l10n, id).trim() == id) naamloos.add(id);
    }
    expect(
      naamloos,
      isEmpty,
      reason:
          'deze regels tonen hun rauwe id aan de gebruiker; voeg ze toe aan '
          'privacyRuleLabel in lib/l10n/slide_quality_localization.dart',
    );
  });

  test('en dat geldt ook in een andere taal', () {
    AppLocalizations.setActiveLanguageCode('en');
    for (final id in tableRuleIds()) {
      expect(privacyRuleLabel(l10n, id).trim(), isNot(id), reason: 'regel $id');
    }
  });

  test('een werkelijk onbekend id valt nog steeds netjes terug', () {
    // De fallback zelf blijft gewenst gedrag: liever het rauwe id dan een crash
    // of een lege melding. Deze test bewaakt dat we hem niet per ongeluk
    // wegoptimaliseren bij het dichten van het gat hierboven.
    expect(privacyRuleLabel(l10n, 'totally.unknown'), 'totally.unknown');
  });
}
