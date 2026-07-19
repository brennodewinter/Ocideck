import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/models/markdown_validation.dart';
import 'package:ocideck/models/settings.dart';
import 'package:ocideck/models/slide.dart';
import 'package:ocideck/models/slide_quality.dart';
import 'package:ocideck/services/file_service.dart';
import 'package:ocideck/services/image_service.dart';
import 'package:ocideck/services/markdown_service.dart';
import 'package:ocideck/services/slide_quality_analyzer.dart';
import 'package:ocideck/state/deck_provider.dart';
import 'package:ocideck/widgets/slides/slide_preview.dart';

/// De melding en de fix voor een slide die klein rendert door zijn buren.
///
/// Aanleiding: een deck waarin een korte slide met vijf bullets microscopisch
/// klein stond. Niet omdat er te veel op stond, maar omdat de vólgende slide
/// `continuesSplit` droeg en tientallen alinea-lange bullets bevatte. De
/// gedeelde schaal van een split-run is het minimum, dus de korte slide zakte
/// mee naar de bodem — en de dichtheidscheck zweeg, want die kijkt naar de eigen
/// tekst van een slide, en die was prima.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const theme = ThemeProfile();
  final font = theme.fontFamily;

  DeckNotifier notifier() {
    final md = MarkdownService();
    return DeckNotifier(
      md,
      FileService(md, ImageService(), () => const ThemeProfile()),
    );
  }

  /// Een deck met [slides] achter de titelslide die `newDeck` aanmaakt, dus de
  /// eerste meegegeven slide staat op index 1.
  DeckNotifier deckWith(List<Slide> slides) {
    final n = notifier()..newDeck('Proef');
    for (var i = 0; i < slides.length; i++) {
      n.addSlide(slides[i].type, afterIndex: i);
      n.updateSlide(i + 1, slides[i]);
    }
    return n;
  }

  // Vijf korte bullets: past ruim.
  Slide short() => Slide.create(SlideType.bullets).copyWith(
    title: 'Wat maakt Ocideck bijzonder?',
    bullets: const [
      'Van scan naar verhaal',
      'Evidence-first compliance',
      'Levende rapportage',
      'Traceerbaarheid',
      'Bestuurlijke taal boven technische ruis',
    ],
  );

  // Een geplakte lap tekst als bullets, gemarkeerd als voortzetting.
  Slide overfull({
    bool continuesSplit = true,
  }) => Slide.create(SlideType.bullets).copyWith(
    title: 'Dit is een hele volle slide',
    bullets: List.generate(
      40,
      (i) =>
          'Bullet $i met een flinke lap tekst erin, want dit is een alinea '
          'die per ongeluk als bullet op de slide is beland en daar veel te '
          'veel ruimte opeist om nog leesbaar te blijven voor een zaal.',
    ),
    continuesSplit: continuesSplit,
  );

  List<SlideQualityIssue> analyze(List<Slide> slides) =>
      const SlideQualityAnalyzer()
          .analyzeSlides(slides: slides, theme: theme, font: font)
          .issues;

  test('de meegetrokken slide wordt gemeld, met de dader erbij', () {
    final slides = [short(), overfull()];
    final dragged = analyze(
      slides,
    ).where((i) => i.kind == SlideQualityIssueKind.splitRunDragged).toList();

    expect(dragged, hasLength(1));
    final issue = dragged.single;
    expect(issue.slideIndex, 0, reason: 'de melding hoort bij het slachtoffer');
    expect(issue.args['offender'], '1', reason: 'de fix wijst naar de dader');
    expect(issue.args['page'], '2', reason: 'menselijk slidenummer');
    expect(issue.category, SlideQualityCategory.textDensity);
    // De gedeelde schaal ligt op de bodem, dus dit is geen detail.
    expect(issue.severity, MarkdownValidationSeverity.error);
  });

  test('de gemelde percentages zijn de werkelijk gerenderde grootten', () {
    final slides = [short(), overfull()];
    final issue = analyze(
      slides,
    ).firstWhere((i) => i.kind == SlideQualityIssueKind.splitRunDragged);

    String pct(double v) => '${(v * 100).round()}%';
    // Wat de preview daadwerkelijk toont voor deze slide...
    expect(
      issue.args['percent'],
      pct(sharedSplitFitScale(slides, 0, theme, font)!),
    );
    // ...en wat hij zonder de reeks zou tonen.
    expect(issue.args['own'], pct(splitRunMemberScale(slides[0], theme, font)));
  });

  test('een echte splitsing van vergelijkbare pagina\'s meldt niets', () {
    // Dezelfde inhoud, netjes over drie pagina\'s: dat is precies waar de
    // gedeelde schaal voor bedoeld is.
    final page = List.generate(
      6,
      (i) => 'Een bullet van normale lengte, nr $i',
    );
    final slides = [
      Slide.create(SlideType.bullets).copyWith(bullets: page),
      Slide.create(
        SlideType.bullets,
      ).copyWith(bullets: page, continuesSplit: true),
      Slide.create(
        SlideType.bullets,
      ).copyWith(bullets: page, continuesSplit: true),
    ];
    expect(
      analyze(
        slides,
      ).where((i) => i.kind == SlideQualityIssueKind.splitRunDragged),
      isEmpty,
    );
  });

  test('zonder de vlag is er geen reeks en dus geen melding', () {
    final slides = [short(), overfull(continuesSplit: false)];
    expect(
      analyze(
        slides,
      ).where((i) => i.kind == SlideQualityIssueKind.splitRunDragged),
      isEmpty,
    );
  });

  test('detachSplitPage geeft de meegetrokken slide zijn grootte terug', () {
    final n = deckWith([short(), overfull()]); // korte slide op index 1

    final before = sharedSplitFitScale(n.state.deck!.slides, 1, theme, font)!;
    final alone = splitRunMemberScale(n.state.deck!.slides[1], theme, font);
    expect(before, lessThan(alone / 2), reason: 'eerst flink meegetrokken');

    // De knop uit het kwaliteitspaneel: haal de dader uit de reeks.
    n.detachSplitPage(2);

    final slides = n.state.deck!.slides;
    expect(slides[2].continuesSplit, isFalse);
    expect(slides, hasLength(3), reason: 'geen tekst verplaatst of gesplitst');
    expect(slides[1].bullets, short().bullets);
    expect(slides[2].bullets, overfull().bullets);
    // De korte slide staat weer op zijn eigen grootte.
    expect(sharedSplitFitScale(slides, 1, theme, font), isNull);
    expect(
      analyze(
        slides,
      ).where((i) => i.kind == SlideQualityIssueKind.splitRunDragged),
      isEmpty,
    );
  });

  test('detachSplitPage knipt de reeks aan beide kanten door', () {
    final n = deckWith([
      short(),
      overfull(),
      short().copyWith(continuesSplit: true),
    ]);

    n.detachSplitPage(2);

    final slides = n.state.deck!.slides;
    expect(slides[2].continuesSplit, isFalse, reason: 'losgeknipt van ervoor');
    expect(slides[3].continuesSplit, isFalse, reason: 'losgeknipt van erna');
  });

  test('detachSplitPage doet niets aan een slide die al los staat', () {
    final n = deckWith([short(), overfull(continuesSplit: false)]);
    final before = n.state.deck!.slides;

    n.detachSplitPage(2);

    expect(n.state.deck!.slides, same(before), reason: 'geen lege mutatie');
  });
}
