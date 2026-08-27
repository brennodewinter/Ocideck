// Regressie voor #1815: een spreeknotitie die met `Woord:` begint mag geen
// Marp-directive worden.
//
// De bewaarroute (`requiresWholeMarpBlockPreservation`) bestaat voor
// Marp-syntaxis die OciDeck niet modelleert: dan is het hele blok vrije
// Markdown, want getypeerd terugschrijven zou de constructie weggooien. De
// toets daarop keek naar "elk woord gevolgd door een dubbele punt", en dat is
// precies de vorm van een gewone Nederlandse notitie — `Antwoord: onwaar.`,
// `Pareto: de balken staan gesorteerd.`. Drie dia's van een handgeschreven deck
// verloren daardoor stil hun type.
//
// De twee kanten staan hier samen, want ze houden elkaar in evenwicht: te breed
// en een notitie sloopt een dia, te smal en een echte Marp-directive verdwijnt
// bij het opslaan.
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/models/markdown_validation.dart';
import 'package:ocideck/models/slide.dart';
import 'package:ocideck/services/markdown_service.dart';
import 'package:ocideck/services/markdown_validator.dart';

/// Eén dia met [body], in een minimaal maar geldig deck.
String deckWith(String body) =>
    '---\nmarp: true\ntheme: ocideck\n---\n\n$body\n';

void main() {
  final markdown = MarkdownService();

  group('een prozanotitie blijft een notitie', () {
    // De drie die het op 27-08-2026 echt deden, met hun eigen diatype erbij.
    const gevallen = <String, (String, SlideType)>{
      'question': (
        '<!-- _class: question -->\n\n'
            '# Even toetsen\n\n'
            '```question\n'
            '{"kind": "trueFalse", "prompt": "Mag dat?", "statementIsTrue": false}\n'
            '```\n\n'
            '<!-- Antwoord: onwaar. Herstel is alleen toegestaan bij verduidelijking. -->',
        SlideType.question,
      ),
      'chart': (
        '<!-- _class: chart -->\n\n'
            '```chart\n'
            '{"type": "pareto", "title": "Tekortkomingen", "x": ["A", "B"], '
            '"series": [{"name": "Aantal", "data": [3, 1]}]}\n'
            '```\n\n'
            '<!-- Pareto: de balken staan gesorteerd, de kop is de vitale minderheid. -->',
        SlideType.chart,
      ),
      'matrix': (
        '<!-- _class: matrix -->\n'
            '<!-- ocideck_template: fmea -->\n\n'
            '# FMEA\n\n'
            '| Process step | Failure mode | Effect | S | Cause | O | Control | D |\n'
            '| --- | --- | --- | --- | --- | --- | --- | --- |\n'
            '| Intake | Gemist | Vertraging | 7 | Haast | 6 | Vier ogen | 5 |\n\n'
            '<!-- Verdiepingsdia: valt weg in de beknopte export. -->',
        SlideType.matrix,
      ),
    };

    for (final entry in gevallen.entries) {
      test('${entry.key}-dia houdt haar type', () {
        final (body, verwacht) = entry.value;
        final deck = markdown.parseDeck(deckWith(body));

        expect(deck, isNotNull);
        expect(deck!.slides, hasLength(1));
        expect(
          deck.slides.single.type,
          verwacht,
          reason:
              'de notitie begint met een woord plus dubbele punt; dat is proza, '
              'geen Marp-directive',
        );
        // De notitie hoort in de notities te staan, niet in de body.
        expect(deck.slides.single.notes, isNotEmpty);
      });
    }

    test('de notitie overleeft het terugschrijven', () {
      final (body, _) = gevallen['question']!;
      final deck = markdown.parseDeck(deckWith(body))!;
      final opnieuw = markdown.parseDeck(markdown.generateDeck(deck))!;

      expect(opnieuw.slides.single.type, SlideType.question);
      expect(opnieuw.slides.single.notes, contains('Antwoord: onwaar.'));
    });

    test('hoofdletters tellen: `Footer:` is proza, `footer:` is Marp', () {
      final proza = markdown.parseDeck(
        deckWith('# Kop\n\n- Punt\n\n<!-- Footer: laat deze staan. -->'),
      )!;
      expect(proza.slides.single.type, SlideType.bullets);

      final directive = markdown.parseDeck(
        deckWith('# Kop\n\n- Punt\n\n<!-- footer: Vertrouwelijk -->'),
      )!;
      expect(directive.slides.single.type, SlideType.freeMarkdown);
    });
  });

  group('een echte Marp-directive bewaart het blok', () {
    // Marpit honoreert deze sleutels; getypeerd terugschrijven zou ze weggooien.
    // Dit is de tegenhanger die verhindert dat de reparatie te ver knijpt.
    for (final directive in const [
      'backgroundPosition: top',
      'backgroundRepeat: repeat',
      'backgroundSize: cover',
      'paginate: false',
      'transition: fade',
      'size: 4:3',
      'class: lead',
      'color: #123456',
    ]) {
      test('`$directive` houdt de dia als vrije Markdown', () {
        final deck = markdown.parseDeck(
          deckWith('# Kop\n\n- Punt\n\n<!-- $directive -->'),
        );

        expect(deck, isNotNull);
        expect(
          deck!.slides.single.type,
          SlideType.freeMarkdown,
          reason: 'Marp doet hier iets mee, dus de bron moet blijven staan',
        );
        expect(deck.slides.single.customMarkdown, contains(directive));
      });
    }
  });

  group('de structuurcontrole zwijgt niet meer', () {
    test('meldt de directive die de dia op vrije Markdown zet', () {
      final result = MarkdownValidator().validate(
        deckWith('# Kop\n\n- Punt\n\n<!-- backgroundPosition: top -->'),
      );

      final gemeld = result.issues.where(
        (i) => i.message.contains('backgroundPosition'),
      );
      expect(
        gemeld,
        isNotEmpty,
        reason: 'een dia die stil haar type verliest hoort zichtbaar te zijn',
      );
      expect(gemeld.first.severity, MarkdownValidationSeverity.warning);
    });

    test('zwijgt wel over een gewone notitie', () {
      final result = MarkdownValidator().validate(
        deckWith('# Kop\n\n- Punt\n\n<!-- Antwoord: onwaar. -->'),
      );

      expect(
        result.issues.where((i) => i.message.contains('Antwoord')),
        isEmpty,
      );
    });
  });
}
