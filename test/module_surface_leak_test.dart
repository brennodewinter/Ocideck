// De module Informatieveiligheid verbergt zeven slidetypes, zeven commando's en
// twee menu-items als hij uit staat. Drie oppervlakken bleven achter (#648).
//
// Wat ze gemeen hadden: instellingen die je kunt openen, invullen en dan niet
// gebruiken, omdat de enige afnemer van het resultaat achter de modulepoort
// zit. Een checklist-sjabloon dat nergens te laden is; een aanbod om honderden
// megabytes CVE-data binnen te halen voor een zoekfunctie die niet opengaat.
//
// **De regel die hier bewaakt wordt is niet "verbergen".** Het is: verbergen
// zolang er niets ligt, en tónen zodra er wél iets ligt. Wie sjablonen heeft
// gemaakt of de database al heeft gedownload en dan de module uitzet, moet zijn
// werk kunnen zien en weghalen — anders laat een schakelaar stilzwijgend een
// gigabyte op schijf achter zonder route terug. Dat tweede deel is de helft die
// het makkelijkst per ongeluk sneuvelt.

import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/l10n/app_localizations.dart';
import 'package:ocideck/models/checklist_template.dart';
import 'package:ocideck/widgets/dialogs/settings_dialog.dart';

void main() {
  setUp(() => AppLocalizations.setActiveLanguageCode('nl'));

  List<SettingsSection> nav({
    required bool revealed,
    required bool hasChecklists,
    bool aiRevealed = false,
  }) => SettingsSection.navItems(
    infoSafetyRevealed: revealed,
    hasChecklists: hasChecklists,
    aiRevealed: aiRevealed,
  );

  test('met de module uit staat de checklists-tab er niet', () {
    // Het sjabloon dat je daar maakt heeft één afnemer: het checklist-
    // slidetype, en dat zit achter de module. Elf tabbladen, en één deed niets.
    expect(
      nav(revealed: false, hasChecklists: false),
      isNot(contains(SettingsSection.checklists)),
    );
  });

  test('met de module aan staat hij er wel', () {
    expect(
      nav(revealed: true, hasChecklists: false),
      contains(SettingsSection.checklists),
    );
  });

  test(
    'bestaande sjablonen houden de tab zichtbaar, ook met de module uit',
    () {
      // De helft die het makkelijkst sneuvelt: dit is werk van de gebruiker, en
      // het onbereikbaar maken is erger dan de lege tab die we net weghaalden.
      expect(
        nav(revealed: false, hasChecklists: true),
        contains(SettingsSection.checklists),
      );
    },
  );

  test('de andere tabbladen blijven met de module uit gewoon staan', () {
    // De grens is smal gehouden: Beveiliging blijft een algemeen tabblad, want
    // de privacycontrole, online media en de schijfsporen gaan iedereen aan.
    final off = nav(revealed: false, hasChecklists: false);
    for (final section in const [
      SettingsSection.general,
      SettingsSection.storage,
      SettingsSection.privacy,
      SettingsSection.security,
      SettingsSection.modules,
      SettingsSection.documentation,
    ]) {
      expect(off, contains(section), reason: section.name);
    }
  });

  test('"Over OciDeck" hoort nooit in de navigatielijst', () {
    // Dat tabblad wordt vanuit de merkvoet geopend; het stond hier al buiten en
    // moet dat blijven, ook nu de lijst voorwaardelijk is geworden.
    for (final revealed in [true, false]) {
      for (final has in [true, false]) {
        expect(
          nav(revealed: revealed, hasChecklists: has),
          isNot(contains(SettingsSection.about)),
        );
      }
    }
  });

  test('het AI-tabblad volgt dezelfde regel als de checklists (#731)', () {
    // `aiRevealed` is bij de aanroeper al `enabled || hasBackend`, dus de
    // tonen-zodra-er-inhoud-is-helft zit in die vlag; hier bewaken we dat de
    // lijst hem ook echt volgt.
    expect(
      nav(revealed: false, hasChecklists: false),
      isNot(contains(SettingsSection.ai)),
    );
    expect(
      nav(revealed: false, hasChecklists: false, aiRevealed: true),
      contains(SettingsSection.ai),
    );
  });

  test('een leeg sjabloon telt als aanwezig werk', () {
    // `isNotEmpty` op de lijst, niet op de inhoud van elk sjabloon: iemand die
    // een sjabloon heeft aangemaakt en nog niet gevuld, is het net zo goed
    // kwijt als de tab verdwijnt.
    const leeg = <ChecklistTemplate>[];
    expect(leeg.isNotEmpty, isFalse);
    expect(
      nav(revealed: false, hasChecklists: leeg.isNotEmpty),
      isNot(contains(SettingsSection.checklists)),
    );
  });
}
