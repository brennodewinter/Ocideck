import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/models/deck.dart';
import 'package:ocideck/models/image_callout.dart';
import 'package:ocideck/models/slide.dart';
import 'package:ocideck/models/settings.dart';
import 'package:ocideck/services/export_metadata.dart';
import 'package:ocideck/services/latex/latex_preamble.dart';
import 'package:ocideck/services/markdown_service.dart';
import 'package:ocideck/services/slide_anchors.dart';

/// Wat een gebruiker in de interface maakt moet één keer opslaan en heropenen
/// overleven. Dat deed het niet: de editor schreef geen `(A)` in de bullet en
/// de dia kreeg geen anker, dus het front-matter-blok belandde onder een lege
/// sleutel en bij het heropenen hoorde het bij geen enkele dia. Alles wat je in
/// de dialoog deed was daarmee weg.
///
/// Deze toets loopt de hele keten: dia met verwijzing → markdown → terug.

Slide _madeInTheEditor() => Slide.create(SlideType.bulletsImage).copyWith(
  title: 'Onderdelen van de pomp',
  // Wat de dialoog nu oplevert: de letter staat in de bullet.
  bullets: const ['De regelaar zit hier (A)', 'Deze regel heeft er geen'],
  imagePath: 'media/pomp.png',
  callouts: const [
    ImageCallout(
      reference: 'A',
      targets: [CalloutPoint(0.279, 0.180)],
      description: 'de regelaar',
    ),
  ],
);

void main() {
  final svc = MarkdownService();

  test('een dia met verwijzingen krijgt een anker toegekend', () {
    // Wat `updateSlide` doet wanneer de dia er nog geen heeft.
    final slide = _madeInTheEditor();
    expect(slide.anchor, isEmpty);
    final withAnchor = slide.copyWith(
      anchor: uniqueAnchor(slugifyAnchor(slide.title), const {}),
    );
    expect(withAnchor.anchor, 'onderdelen-van-de-pomp');
  });

  test('een naamloze dia botst niet met een andere naamloze dia', () {
    final eerste = uniqueAnchor(slugifyAnchor(''), const {});
    final tweede = uniqueAnchor(slugifyAnchor(''), {eerste});
    expect(eerste, 'dia');
    expect(tweede, isNot(eerste));
  });

  test('opslaan en heropenen behoudt de verwijzing', () {
    final slide = _madeInTheEditor().copyWith(anchor: 'onderdelen-van-de-pomp');
    final deck = Deck(title: 'Reis', slides: [slide]);

    final markdown = svc.generateDeck(deck);
    // Het blok hangt aan het anker, niet aan een lege sleutel.
    expect(markdown, contains('ocideck_callouts:'));
    expect(markdown, contains('  onderdelen-van-de-pomp:'));
    expect(markdown, isNot(contains('\n  :\n')));
    // En de zichtbare koppelsleutel staat in de tekst.
    expect(markdown, contains('De regelaar zit hier (A)'));

    final terug = svc.parseDeck(markdown)!;
    final dia = terug.slides.firstWhere((s) => s.callouts.isNotEmpty);
    expect(dia.callouts, hasLength(1));
    expect(dia.callouts.first.reference, 'A');
    expect(dia.callouts.first.description, 'de regelaar');
    expect((dia.callouts.first.targets.first as CalloutPoint).x, 0.279);
  });

  test('zonder anker valt de verwijzing weg — de fout die dit voorkomt', () {
    // Precies wat de app schreef vóór de reparatie: geen anker, geen `(A)`.
    final kapot = _madeInTheEditor().copyWith(
      bullets: const ['De regelaar zit hier', 'Deze regel heeft er geen'],
    );
    final markdown = svc.generateDeck(Deck(title: 'Reis', slides: [kapot]));
    final terug = svc.parseDeck(markdown)!;
    expect(
      terug.slides.first.callouts,
      isEmpty,
      reason:
          'dit is de uitkomst die de reparatie onmogelijk moet maken; blijft '
          'hij hier leeg, dan weet je dat het anker het verschil maakt',
    );
  });

  group('LaTeX/Beamer: de kleur van de markeringen bestaat', () {
    test('de beamer-preamble definieert ocideckTableAccent', () {
      // De TikZ-code van de beeldverwijzingen tekent met
      // `fill=ocideckTableAccent`. Die kleur stond alleen in de
      // article-preamble, dus een geëxporteerde presentatie verwees naar een
      // kleur die xcolor niet kende en compileerde helemaal niet.
      final preamble = beamerPreamble(const ExportDocumentMetadata());
      expect(preamble, contains(r'\definecolor{ocideckTableAccent}'));
    });

    test('de accentkleur van het deck reist mee', () {
      final preamble = beamerPreamble(
        const ExportDocumentMetadata(),
        themeProfile: const ThemeProfile(accentColor: '#FF0000'),
      );
      expect(
        preamble,
        contains(r'\definecolor{ocideckTableAccent}{HTML}{FF0000}'),
      );
    });
  });
}
