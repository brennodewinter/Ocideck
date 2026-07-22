import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/models/cockpit.dart';
import 'package:ocideck/models/slide.dart';

/// De module Informatieveiligheid staat standaard uit en belooft dan verborgen
/// te blijven (#646).
///
/// Die belofte was gebroken op een plek die niemand als "de module" herkent:
/// de cockpit-dia. Dat is een algemeen dashboard, niet iets van de module — maar
/// zijn voorbeelddata heette `pentestPreset` en toonde "Overall risk",
/// "Exploitability heat", "Evidence confidence" en "Findings trend". En die
/// preset was de **terugval op vijf plekken**: een nieuwe dia, een lege spec,
/// een onleesbare spec, de editor en de preview — plus de HTML-export, waar het
/// niet in een venster bleef maar in een uitgeleverd rapport belandde.
///
/// De reparatie is niet "verberg de cockpit". Het type hoort er te zijn; alleen
/// mag voorbeelddata voor een algemeen dashboard nergens naar verwijzen. Deze
/// test bewaakt dat woordelijk, want een volgende preset-schrijver kent de
/// geschiedenis niet.
void main() {
  /// Woorden die alleen in een pentestrapport thuishoren. Een cockpit die er
  /// één toont, verraadt een module die uit staat.
  const pentestwoorden = [
    'exploitability',
    'evidence confidence',
    'findings',
    'overall risk',
    'vulnerabilit',
    'cvss',
    'severity',
  ];

  void verwachtNeutraal(String tekst, {required String waar}) {
    final laag = tekst.toLowerCase();
    for (final woord in pentestwoorden) {
      expect(
        laag,
        isNot(contains(woord)),
        reason:
            '$waar toont "$woord". Dat is de module Informatieveiligheid, en '
            'die belooft verborgen te blijven zolang hij uit staat.',
      );
    }
  }

  test('de voorbeeldmeters noemen geen enkel pentestbegrip', () {
    final spec = CockpitSpec.samplePreset();

    expect(spec.meters, isNotEmpty, reason: 'lege preset toont niets');
    verwachtNeutraal(
      spec.meters.map((m) => '${m.label} ${m.unit}').join(' '),
      waar: 'De voorbeeldmeters',
    );
  });

  test('en een nieuwe cockpit-dia dus ook niet', () {
    // Het pad uit de melding: module uit, dia toevoegen, pentestmetrieken op
    // je scherm.
    final slide = Slide.create(SlideType.cockpit);

    verwachtNeutraal(slide.customMarkdown, waar: 'Een nieuwe cockpit-dia');
  });

  test('een onleesbare spec valt neutraal terug, niet naar de module', () {
    // De stilste van de vijf: een beschadigd of met de hand bewerkt blok viel
    // terug op de pentestpreset, dus juist bij een fout kwam er data
    // tevoorschijn die er niet hoorde te zijn.
    for (final rommel in ['', 'geen json', '[]', '{"meters": "kapot"}']) {
      verwachtNeutraal(
        CockpitSpec.parse(rommel).meters.map((m) => m.label).join(' '),
        waar: 'Een onleesbare spec ($rommel)',
      );
    }
  });

  test('de preset toont nog steeds vier verschillende metertypes', () {
    // Voorbeelddata is er om te laten zien wat er kan. Neutraal maken mag dat
    // niet uithollen tot vier keer dezelfde meter.
    //
    // Vier, niet alle zeven: dat is wat de preset altijd al toonde
    // (speedometer, thermometer, voltmeter, climbDescent). Deze test bewaakt
    // dat de neutralisatie niets wegnam — niet dat er iets bij moet.
    final types = CockpitSpec.samplePreset().meters.map((m) => m.type).toSet();

    expect(types, hasLength(4));
    expect(
      types,
      containsAll([
        CockpitMeterType.speedometer,
        CockpitMeterType.thermometer,
        CockpitMeterType.voltmeter,
        CockpitMeterType.climbDescent,
      ]),
    );
  });
}
