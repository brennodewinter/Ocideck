import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/models/deck.dart';
import 'package:ocideck/models/eis_entry.dart';
import 'package:ocideck/models/slide.dart';
import 'package:ocideck/models/used_tool.dart';
import 'package:ocideck/services/markdown_service.dart';
import 'package:ocideck/services/miauw_eis_catalog.dart';

void main() {
  final markdown = MarkdownService();

  const burp = UsedTool(
    name: 'Burp Suite',
    version: '2026.4',
    url: 'https://portswigger.net',
    description: 'Webproxy',
  );

  group('UsedTool.parse en format', () {
    test('een volledige regel round-trippt', () {
      final back = UsedTool.parse(burp.format())!;
      expect(back.name, 'Burp Suite');
      expect(back.version, '2026.4');
      expect(back.url, 'https://portswigger.net');
      expect(back.description, 'Webproxy');
    });

    test('alleen een naam mag ook', () {
      // Het veld wordt met de hand getypt; halverwege invullen hoort niet tot
      // verlies van de regel te leiden.
      final t = UsedTool.parse('nmap')!;
      expect(t.name, 'nmap');
      expect(t.version, isEmpty);
      expect(t.isIncomplete, isTrue);
    });

    test('een pijp in de beschrijving overleeft', () {
      final t = UsedTool.parse('x@1 | https://a | doet a | en b')!;
      expect(t.description, 'doet a | en b');
    });

    test('lege staartvelden verdwijnen uit de vorm', () {
      const t = UsedTool(name: 'nmap', version: '7.9');
      expect(t.format(), 'nmap@7.9');
    });

    test('een lege regel levert niets op', () {
      expect(UsedTool.parse('   '), isNull);
      expect(UsedTool.parseAll('a\n\n  \nb'), hasLength(2));
    });

    test('een naam met @ erin knipt op de laatste', () {
      final t = UsedTool.parse('mail@host tool@2.0')!;
      expect(t.name, 'mail@host tool');
      expect(t.version, '2.0');
    });
  });

  group('hulpmiddelen round-trippen door het bestand', () {
    test('twee hulpmiddelen worden twee regels en komen terug', () {
      const nmap = UsedTool(name: 'nmap', version: '7.9');
      final deck = Deck(
        title: 'Rapport',
        slides: [Slide.create(SlideType.title)],
        toolsUsed: [burp, nmap],
      );

      final text = markdown.generateDeck(deck);
      // Eén regel per hulpmiddel: een toegevoegde tool is één regel diff.
      expect('tool:'.allMatches(text), hasLength(2));

      final back = markdown.parseDeck(text)!;
      expect(back.toolsUsed.map((t) => t.name), ['Burp Suite', 'nmap']);
      expect(back.toolsUsed.first.url, 'https://portswigger.net');
    });

    test('meerdere tool-regels overschrijven elkaar niet', () {
      // De front-matter-parser is een key/value-switch; zonder opzettelijk
      // stapelen houdt een deck maar één hulpmiddel over.
      final back = markdown.parseDeck(
        '---\ntitle: T\ntool: a@1\ntool: b@2\ntool: c@3\n---\n\n# A\n',
      )!;
      expect(back.toolsUsed.map((t) => t.name), ['a', 'b', 'c']);
    });

    test('geen hulpmiddelen schrijft geen enkele regel', () {
      final deck = Deck(
        title: 'Rapport',
        slides: [Slide.create(SlideType.title)],
      );
      expect(markdown.generateDeck(deck), isNot(contains('tool:')));
    });
  });

  group('de bijlagetabel', () {
    test('kop plus één rij per hulpmiddel, in eisvolgorde', () {
      final rows = toolsAppendixRows(
        [burp],
        nameHeader: 'Hulpmiddel',
        descriptionHeader: 'Beschrijving',
        versionHeader: 'Versie',
        referenceHeader: 'Referentie',
      );
      expect(rows, hasLength(2));
      expect(rows.first, [
        'Hulpmiddel',
        'Beschrijving',
        'Versie',
        'Referentie',
      ]);
      // 4.8.2.1 beschrijving, .2 versie, .3 referentie — in die volgorde.
      expect(rows[1], [
        'Burp Suite',
        'Webproxy',
        '2026.4',
        'https://portswigger.net',
      ]);
    });

    test('een half ingevuld hulpmiddel levert lege cellen, geen gat', () {
      final rows = toolsAppendixRows(
        [const UsedTool(name: 'nmap')],
        nameHeader: 'H',
        descriptionHeader: 'B',
        versionHeader: 'V',
        referenceHeader: 'R',
      );
      expect(rows[1], ['nmap', '', '', '']);
    });
  });

  group('EIS 4.8.2 blijft handmatig', () {
    test('vastleggen en invoegen vinken de eis niet af', () {
      // Het hele ontwerp van deze feature: OciDeck maakt de bijlage makkelijk,
      // maar bevestigt niet dat hij klopt. Na het invoegen kan de tester de
      // slide nog wijzigen of verwijderen, dus alleen hij kan verklaren dat
      // 4.8.2 gedekt is. Automatisch afvinken zou een claim zijn die OciDeck
      // niet kan waarmaken.
      for (final id in ['4.8.2', '4.8.2.1', '4.8.2.2', '4.8.2.3']) {
        final eis = MiauwEisCatalog.instance.byId(id)!;
        expect(eis.derivation, EisDerivation.manual);
        expect(eis.check, isNull);
      }
    });
  });
}
