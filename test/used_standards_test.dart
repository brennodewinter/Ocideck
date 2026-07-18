import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/models/deck.dart';
import 'package:ocideck/models/eis_entry.dart';
import 'package:ocideck/models/slide.dart';
import 'package:ocideck/services/markdown_service.dart';
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

  group('MIAUW EIS 4.3.2 en 4.8.2 blijven handmatig', () {
    // Vastgelegd omdat het twee keer bijna misging. Beide eisen gaan over wat er
    // ín het rapport staat, en dat kan OciDeck nu niet vaststellen:
    //
    // - 4.3.2 vraagt een overzicht van gebruikte standaarden in de
    //   managementsamenvatting. Het deck kán ze vastleggen, maar die vastlegging
    //   wordt nergens in de slides gerenderd — alleen in het auditdossier en een
    //   dialoog. Vastleggen is dus niet hetzelfde als voldoen.
    // - 4.8.2.x gaat over de *hulpmiddelen* die de tester gebruikte, niet over
    //   de standaarden waartegen is getoetst. Dat is een andere lijst.
    //
    // Zodra de bijlage echt als rapportinhoud bestaat en herkenbaar is, mogen
    // deze omgezet worden — niet eerder.
    test('geen van beide claimt automatische afleiding', () {
      for (final id in ['4.3.2', '4.8.2', '4.8.2.1', '4.8.2.2', '4.8.2.3']) {
        final eis = MiauwEisCatalog.instance.byId(id)!;
        expect(
          eis.derivation,
          EisDerivation.manual,
          reason:
              '$id gaat over rapportinhoud die nog niet aantoonbaar aanwezig is',
        );
        expect(eis.check, isNull, reason: '$id heeft geen inhoudscontrole');
      }
    });

    test('vastleggen blijft wel gewoon werken', () {
      // De vastlegging zelf is niet teruggedraaid: die draagt de bevroren
      // versies en voedt de verouderingsmelding bij verzegelen.
      final deck = deckWith(['OWASP WSTG@4.2']);
      expect(deck.standardsUsed, ['OWASP WSTG@4.2']);
    });
  });
}
