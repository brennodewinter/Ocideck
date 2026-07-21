import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/models/deck.dart';
import 'package:ocideck/models/document_signature.dart';
import 'package:ocideck/models/privacy_disposition.dart';
import 'package:ocideck/models/slide.dart';
import 'package:ocideck/models/used_tool.dart';
import 'package:ocideck/services/front_matter_merge.dart';
import 'package:ocideck/services/markdown_service.dart';

/// Het formaatcontract van het `.md`-bestand, getoetst als contract en niet als
/// functie: wat OciDeck belooft over andermans front matter en over de
/// formaatversie moet blijven gelden, ook als de serialisatie eronder verandert.

/// De front-matter-regels van [markdown] (zonder de `---`-hekken).
List<String> _frontMatter(String markdown) {
  expect(markdown, startsWith('---\n'));
  final einde = markdown.indexOf('\n---\n', 4);
  expect(einde, greaterThan(0), reason: 'front matter niet afgesloten');
  return markdown.substring(4, einde).split('\n');
}

/// Openen en opslaan, precies zoals de app het doet.
String _openenEnOpslaan(String markdown) {
  final service = MarkdownService();
  final deck = service.parseDeck(markdown);
  expect(deck, isNotNull, reason: 'parseDeck gaf null voor:\n$markdown');
  return service.generateDeck(deck!);
}

void main() {
  group('onbekende front-matter-sleutels overleven het opslaan', () {
    // Een met de hand geschreven Marp-bestand: gewone Marp-opties die OciDeck
    // niet implementeert, een commentaarregel, een lege regel en een genest
    // blok. Niets daarvan is van OciDeck.
    const handgeschreven = '''
---
marp: true
theme: gaia
# de kop en voet van dit rapport
header: 'Kwartaalrapport'
footer: "vertrouwelijk — niet verspreiden"
size: 16:9

style: |
  section {
    color: #222;
  }
---

# Kwartaalrapport

- Eerste punt
''';

    test('elke onbekende regel komt byte-voor-byte terug', () {
      final opnieuw = _frontMatter(_openenEnOpslaan(handgeschreven));
      expect(
        opnieuw,
        containsAllInOrder([
          '# de kop en voet van dit rapport',
          "header: 'Kwartaalrapport'",
          'footer: "vertrouwelijk — niet verspreiden"',
          'size: 16:9',
          '',
          'style: |',
          '  section {',
          '    color: #222;',
          '  }',
        ]),
      );
    });

    test('de aanhalingstekens blijven zoals de auteur ze zette', () {
      // OciDeck citeert zelf met dubbele aanhalingstekens. Een enkel gequote
      // waarde van iemand anders mag daar niet naar toe herschreven worden.
      final opnieuw = _openenEnOpslaan(handgeschreven);
      expect(opnieuw, contains("header: 'Kwartaalrapport'"));
    });

    test('een tweede ronde verandert er niets meer aan', () {
      // Het zegel leunt hierop: openen-en-opslaan mag de gecanonicaliseerde
      // inhoud niet verschuiven.
      final eerste = _openenEnOpslaan(handgeschreven);
      expect(_openenEnOpslaan(eerste), eerste);
    });

    test('een sleutel die OciDeck bezit wordt wél bijgewerkt', () {
      const bron = '---\nmarp: true\ntheme: gaia\nfooter: voet\n---\n\n# T\n';
      final service = MarkdownService();
      final deck = service.parseDeck(bron)!.copyWith(theme: 'ocideck');
      final opnieuw = _frontMatter(service.generateDeck(deck));
      // Vervangen op de eigen plek, niet achteraan aangeplakt.
      expect(opnieuw.indexOf('theme: ocideck'), 1);
      expect(opnieuw, isNot(contains('theme: gaia')));
      expect(opnieuw, contains('footer: voet'));
    });
  });

  group('formaatversie ocideck_format', () {
    test('afwezig is versie 1 en nooit een fout', () {
      final deck = MarkdownService().parseDeck('---\nmarp: true\n---\n\n# T\n');
      expect(deck, isNotNull);
      expect(deck!.formatVersion, 1);
    });

    test('openen waardeert niet op — pas opslaan zet de sleutel', () {
      const bron = '---\nmarp: true\n---\n\n# Titel\n';
      final service = MarkdownService();
      final deck = service.parseDeck(bron)!;
      // Andermans bestand raak je niet aan door het te bekijken: het deck draagt
      // de bronregels onveranderd, zonder versiesleutel.
      expect(deck.frontMatterSource, ['marp: true']);
      expect(deck.frontMatterSource.join('\n'), isNot(contains('ocideck_')));
      // Pas bij opslaan verschijnt hij.
      expect(service.generateDeck(deck), contains('ocideck_format: 1'));
    });

    test('een nieuwere versie wordt niet verlaagd', () {
      // Zonder deze regel liegt het bestand na één keer opslaan over zichzelf.
      const bron =
          '---\n'
          'marp: true\n'
          'ocideck_format: 2\n'
          'ocideck_iets_van_later: waarde\n'
          '---\n\n# T\n';
      final opnieuw = _openenEnOpslaan(bron);
      expect(opnieuw, contains('ocideck_format: 2'));
      expect(opnieuw, isNot(contains('ocideck_format: 1')));
      // En dit werkt alleen doordat de onbekende sleutel van die versie blijft.
      expect(opnieuw, contains('ocideck_iets_van_later: waarde'));
    });

    test(
      'een ouder of onleesbaar getal wordt opgewaardeerd, niet geweigerd',
      () {
        for (final ruw in ['0', '-3', 'twee', '']) {
          final deck = MarkdownService().parseDeck(
            '---\nmarp: true\nocideck_format: $ruw\n---\n\n# T\n',
          );
          expect(deck, isNotNull, reason: 'ocideck_format: $ruw weigerde');
          expect(deck!.formatVersion, kOldestFormatVersion);
        }
      },
    );

    test('de formaatversie valt buiten de gecanonicaliseerde inhoud', () {
      // De versie beschrijft de codering, niet de inhoud. Zat hij in de hash,
      // dan zou een verzegeld deck breken zodra een nieuwere build het opnieuw
      // uitschrijft (bijvoorbeeld bij het bouwen van een pakket).
      final service = MarkdownService();
      final deck = Deck(title: 'T', slides: [Slide.create(SlideType.title)]);
      expect(
        service.canonicalContentForSeal(deck),
        isNot(contains(kFormatVersionKey)),
      );
    });
  });

  group('de lijst met eigen sleutels loopt niet uit de pas', () {
    test(
      'elke geschreven sleutel staat in kOwnedFrontMatterKeys, en andersom',
      () {
        // Een sleutel die OciDeck schrijft maar niet bezit, wordt bij élke opslag
        // opnieuw aangeplakt terwijl de oude blijft staan. Die drift is niet uit
        // de code af te lezen, dus hij wordt hier bewaakt.
        final deck = Deck(
          title: 'Titel',
          theme: 'ocideck',
          slides: [Slide.create(SlideType.title)],
          author: 'A. Auteur',
          organization: 'LibreKAT',
          version: '1.0',
          date: '2026-07-21',
          description: 'Beschrijving',
          keywords: 'een, twee',
          language: 'nl',
          standardsUsed: const ['OWASP WSTG@4.2'],
          toolsUsed: const [UsedTool(name: 'Burp', version: '2026.4')],
          tlp: TlpLevel.amber,
          privacy: PrivacyDisposition.redact,
          presentationTargetSeconds: 600,
          showRehearsalSummary: false,
          playOnly: true,
          finalized: true,
          sealHash: 'abc',
          sealAlgo: 'sha-512',
          sealAt: '2026-07-21T10:00:00Z',
          sealTimestampToken: 'dG9rZW4',
          signature: const DocumentSignature(
            name: 'A. Auteur',
            role: 'Onderzoeker',
            certification: 'OSCP',
            date: '2026-07-21',
            statement: 'Naar waarheid opgesteld.',
            typedSignature: 'A. Auteur',
            imagePath: 'images/sig.png',
          ),
          miauwWaivers: const {'1.6': 'reden'},
          miauwConfirmations: const {'2.3': 'bevestigd'},
        );
        final markdown = MarkdownService().generateDeck(
          deck,
          inlineStyleProfile: true,
        );
        final geschreven = _frontMatter(
          markdown,
        ).map(frontMatterKeyOf).whereType<String>().toSet();
        expect(geschreven, kOwnedFrontMatterKeys);
      },
    );
  });
}
