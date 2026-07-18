import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/models/deck.dart';
import 'package:ocideck/models/eis_entry.dart';
import 'package:ocideck/models/miauw_compliance.dart';
import 'package:ocideck/models/slide.dart';
import 'package:ocideck/services/markdown_service.dart';
import 'package:ocideck/services/miauw_compliance_analyzer.dart';
import 'package:ocideck/services/miauw_eis_catalog.dart';
import 'package:ocideck/services/reference_standards.dart';

void main() {
  final markdown = MarkdownService();

  Deck deckWith(List<String> standards) => Deck(
    title: 'Pentestrapport',
    slides: [Slide.create(SlideType.title)],
    standardsUsed: standards,
  );

  group('gebruikte standaarden round-trippen', () {
    test('schrijven en teruglezen levert dezelfde lijst', () {
      final deck = deckWith(['OWASP WSTG@4.2', 'MITRE CWE@4.20']);
      final text = markdown.generateDeck(deck);

      expect(text, contains('standards:'));
      final back = markdown.parseDeck(text);
      expect(back!.standardsUsed, ['OWASP WSTG@4.2', 'MITRE CWE@4.20']);
    });

    test('een leeg veld schrijft geen regel', () {
      expect(
        markdown.generateDeck(deckWith([])),
        isNot(contains('standards:')),
      );
    });

    test('losse spaties en een lege regel verdwijnen bij het lezen', () {
      final back = markdown.parseDeck(
        '---\ntitle: T\nstandards: OWASP WSTG@4.2 ,, MITRE CWE@4.20 ,\n---\n\n# A\n',
      );
      expect(back!.standardsUsed, ['OWASP WSTG@4.2', 'MITRE CWE@4.20']);
    });
  });

  group('parseUsedStandard', () {
    test('splitst naam en versie op de laatste @', () {
      final p = parseUsedStandard('OWASP WSTG@4.2');
      expect(p.name, 'OWASP WSTG');
      expect(p.version, '4.2');
    });

    test('een regel zonder versie blijft gewoon leesbaar', () {
      // Handgetypte regels en oudere decks mogen niet stukgaan.
      final p = parseUsedStandard('Een eigen methodiek');
      expect(p.name, 'Een eigen methodiek');
      expect(p.version, isEmpty);
    });
  });

  group('outdatedStandards — veroudering zonder netwerk', () {
    test('meldt een standaard die sindsdien is bijgewerkt', () {
      // Het deck legde 4.0 vast, deze build draagt 4.2: sinds dat onderzoek is
      // de standaard bijgewerkt, en dat hoort de lezer te weten.
      final stale = outdatedStandards(['OWASP WSTG@4.0']);
      expect(stale, hasLength(1));
      expect(stale.single.name, 'OWASP WSTG');
      expect(stale.single.recorded, '4.0');
      expect(stale.single.current, '4.2');
    });

    test('zwijgt wanneer het deck de huidige versie noemt', () {
      expect(outdatedStandards(currentStandardEntries()), isEmpty);
    });

    test('zwijgt over een standaard die wij niet kennen', () {
      // Een gok zou hier als feit gaan lezen. Over een eigen methodiek of een
      // standaard die OciDeck niet bundelt valt niets te zeggen.
      expect(outdatedStandards(['Eigen methodiek@1.0']), isEmpty);
    });

    test('zwijgt over een regel zonder versie', () {
      expect(outdatedStandards(['OWASP WSTG']), isEmpty);
    });
  });

  group('MIAUW EIS 4.3.2', () {
    EisResult resultFor(Deck deck) => MiauwComplianceAnalyzer()
        .analyze(deck)
        .results
        .firstWhere((r) => r.entry.id == '4.3.2');

    test('is nu inhoudelijk afleidbaar in plaats van handmatig', () {
      final eis = MiauwEisCatalog.instance.byId('4.3.2')!;
      expect(eis.derivation, EisDerivation.automatic);
      expect(eis.check, EisCheck.standardsRecorded);
    });

    test('is voldaan zodra het deck standaarden vastlegt', () {
      expect(resultFor(deckWith(['OWASP WSTG@4.2'])).status, EisStatus.voldaan);
    });

    test('is niet voldaan wanneer er niets is vastgelegd', () {
      expect(resultFor(deckWith([])).status, isNot(EisStatus.voldaan));
    });

    test('4.8.2.x blijft handmatig — dat gaat over hulpmiddelen', () {
      // Bewust vastgelegd: 4.8.2 vraagt naar de *tools* die de tester
      // gebruikte (naam, versie, URL), niet naar de standaarden waartegen is
      // getoetst. Die eis afleiden uit onze gebundelde catalogi zou compliance
      // claimen voor iets dat nooit is vastgelegd.
      for (final id in ['4.8.2', '4.8.2.1', '4.8.2.2', '4.8.2.3']) {
        final eis = MiauwEisCatalog.instance.byId(id)!;
        expect(
          eis.derivation,
          EisDerivation.manual,
          reason: '$id gaat over hulpmiddelen, niet over standaarden',
        );
      }
    });
  });
}
