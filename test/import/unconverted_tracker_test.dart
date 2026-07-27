import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/services/import/models/conversion_issue.dart';
import 'package:ocideck/services/import/pipeline/unconverted_tracker.dart';

void main() {
  test(
    'builds a note body listing every issue under a slide-numbered heading',
    () {
      final body = UnconvertedTracker.buildNoteBody(3, [
        const ConversionIssue(
          slideIndex: 2,
          feature: 'SmartArt "Organigram"',
          description: 'niet ondersteund',
        ),
        const ConversionIssue(
          slideIndex: 2,
          feature: 'Audio "intro.mp3"',
          description: 'niet overgenomen',
        ),
      ]);

      expect(body, contains('# Niet overgenomen van slide 3'));
      expect(body, contains('- SmartArt "Organigram": niet ondersteund'));
      expect(body, contains('- Audio "intro.mp3": niet overgenomen'));
    },
  );

  test('annotates partially salvaged issues', () {
    final body = UnconvertedTracker.buildNoteBody(5, [
      const ConversionIssue(
        slideIndex: 4,
        feature: 'SmartArt',
        description: 'visueel niet overgenomen',
        salvagedAs: 'tekst als bullets',
      ),
    ]);

    expect(body, contains('(deels overgenomen: tekst als bullets)'));
  });

  test('buildDeckNoteBody uses a document-level heading', () {
    final body = UnconvertedTracker.buildDeckNoteBody([
      const ConversionIssue(
        slideIndex: -1,
        feature: 'Keynote IWA-intern',
        description: 'niet overgenomen (pas in een volgende milestone)',
        salvagedAs: 'voorbeeldafbeelding',
      ),
    ]);
    expect(body, contains('# Niet overgenomen van dit document'));
    expect(body, contains('- Keynote IWA-intern: niet overgenomen'));
    expect(body, contains('(deels overgenomen: voorbeeldafbeelding)'));
  });

  // ── De vertaalnaad (#806) ───────────────────────────────────────────────────
  //
  // De notitiedia is inhoud die in het `.md` van de gebruiker wordt opgeslagen;
  // hij hoort dus op importmoment in diens taal te staan, niet in het
  // Nederlands. De UI geeft `l10n.d` als `translate`; deze tests gebruiken een
  // omkeer-functie als stand-in en controleren dat élk stuk tekst — kop,
  // feature, description én de "deels overgenomen"-frase — er langs gaat.

  // Een stand-in-vertaler: omhult de tekst met « », zodat de test ziet dát een
  // string door `translate` ging zonder een echte taal nodig te hebben. De
  // `{n}`-plaatshouders blijven staan — precies zoals een echte vertaling ze
  // laat staan, zodat de invulling erna ze nog vindt.
  String wrapped(String s) => '«$s»';

  test('elke tekst in een notitiedia gaat door de vertaalnaad', () {
    final body = UnconvertedTracker.buildNoteBody(3, [
      const ConversionIssue(
        slideIndex: 2,
        feature: 'Groepering',
        description: 'objecten uitgeklapt',
        salvagedAs: 'apart overgenomen',
      ),
    ], translate: wrapped);

    // Elk stuk tekst draagt de vertaalmarkering — kop, feature, description, de
    // "deels overgenomen"-frase én de salvage-tekst. De kop toont slide 3, want
    // de plaatshouder is ná het vertalen ingevuld.
    expect(body, contains('«Niet overgenomen van slide 3»'));
    expect(body, contains('«Groepering»'));
    expect(body, contains('«objecten uitgeklapt»'));
    expect(body, contains('«deels overgenomen»'));
    expect(body, contains('«apart overgenomen»'));
  });

  test('een plaatshouder wordt ná het vertalen ingevuld', () {
    // De vertaling bepaalt wáár `{n}` in de zin landt; de waarde komt erna. De
    // omhullende vertaler laat `{n}` staan, dus de invulling moet '7' opleveren.
    final body = UnconvertedTracker.buildNoteBody(
      7,
      const [],
      translate: wrapped,
    );
    expect(body, contains('«Niet overgenomen van slide 7»'));
    expect(body, isNot(contains('{n}')));
  });

  test('een ConversionIssue met args vult zijn plaatshouders', () {
    final body = UnconvertedTracker.buildNoteBody(1, [
      const ConversionIssue(
        slideIndex: 0,
        feature: 'Koppeling “{tekst}”',
        description: 'wees naar {url}',
        args: {'tekst': 'Handleiding', 'url': 'file:///geheim'},
      ),
    ]);
    expect(body, contains('Koppeling “Handleiding”'));
    expect(body, contains('wees naar file:///geheim'));
    expect(body, isNot(contains('{tekst}')));
    expect(body, isNot(contains('{url}')));
  });

  test(
    'een plaatshouder zonder waarde blijft staan in plaats van te vervallen',
    () {
      // Zo is in het document zichtbaar dát er iets misging, in plaats van een zin
      // met een stil gat.
      final body = UnconvertedTracker.buildNoteBody(1, [
        const ConversionIssue(
          slideIndex: 0,
          feature: '{n} alinea’s',
          description: 'niet overgenomen',
        ),
      ]);
      expect(body, contains('{n} alinea’s'));
    },
  );
}
