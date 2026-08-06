import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/models/deck.dart';
import 'package:ocideck/models/markdown_validation.dart';
import 'package:ocideck/models/slide.dart';
import 'package:ocideck/models/slide_quality.dart';
import 'package:ocideck/services/slide_quality/split_run_density_summary.dart';
import 'package:ocideck/services/slide_quality_analyzer.dart';
import 'package:ocideck/state/deck_provider.dart';
import 'package:ocideck/state/deck_quality_provider.dart';
import 'package:ocideck/utils/bullet_fixes.dart';

// #1289: na 'Splits slide' herhaalt elke deelpagina van dezelfde gesplitste
// lijst dezelfde lengte-gedreven dichtheidsmeldingen (veel woorden, lange
// bullets, meerzins, verkleind). Splitsen lost de dichtheid-per-aantal op, niet
// de lengte-per-bullet — dus vermenigvuldigen die meldingen over de pagina's, en
// wie de aanbeveling opvolgt wordt met een veelvoud aan meldingen bestraft. Deze
// laag vat ze samen tot één per soort per reeks; de tests bewaken zowel de
// samenvatting als de grenzen (alleen echte runs, nooit fouten of aantal-per-dia).
void main() {
  Slide bulletPage({required bool continues}) => Slide.create(
    SlideType.bullets,
  ).copyWith(bullets: const ['a', 'b'], continuesSplit: continues);

  // Een gesplitste reeks van [n] bulletslides: de eerste is de start, elke
  // volgende draagt de continuation-vlag.
  List<Slide> run(int n) => [
    for (var i = 0; i < n; i++) bulletPage(continues: i > 0),
  ];

  SlideQualityIssue density(
    int slideIndex,
    SlideQualityIssueKind kind, {
    MarkdownValidationSeverity severity = MarkdownValidationSeverity.warning,
    Map<String, String> args = const {},
  }) => SlideQualityIssue(
    slideIndex: slideIndex,
    kind: kind,
    category: SlideQualityCategory.textDensity,
    severity: severity,
    args: args,
  );

  bool hasRunPages(SlideQualityIssue i) => i.args.containsKey('runPages');

  group('collapseSplitRunDensity', () {
    test('vat een lengte-melding op elke reekspagina samen tot één', () {
      final slides = run(3); // indexen 0,1,2 vormen één reeks
      final issues = [
        for (var i = 0; i < 3; i++)
          density(
            i,
            SlideQualityIssueKind.bulletAverageLengthHigh,
            args: {'average': '20'},
          ),
      ];
      final out = collapseSplitRunDensity(slides, issues);
      expect(out.length, 1);
      expect(out.single.kind, SlideQualityIssueKind.bulletAverageLengthHigh);
      expect(out.single.slideIndex, 0); // anker = eerste getroffen pagina
      expect(out.single.args['runPages'], '3');
      expect(out.single.args['average'], '20'); // originele arg blijft
    });

    test('anker is de eerste getroffen pagina, niet per se de reeks-start', () {
      final slides = run(3);
      final issues = [
        density(
          1,
          SlideQualityIssueKind.bulletWordCountHigh,
          args: {'words': '100'},
        ),
        density(
          2,
          SlideQualityIssueKind.bulletWordCountHigh,
          args: {'words': '100'},
        ),
      ];
      final out = collapseSplitRunDensity(slides, issues);
      expect(out.length, 1);
      expect(out.single.slideIndex, 1);
      expect(out.single.args['runPages'], '2');
    });

    test('laat één losse treffer met rust (pas vanaf twee pagina\'s)', () {
      final slides = run(3);
      final issues = [
        density(
          1,
          SlideQualityIssueKind.bulletMultiSentence,
          args: {'count': '4'},
        ),
      ];
      final out = collapseSplitRunDensity(slides, issues);
      expect(out.length, 1);
      expect(hasRunPages(out.single), isFalse);
    });

    test('vat niet samen over los geschreven dia\'s (geen continuesSplit)', () {
      final slides = [for (var i = 0; i < 3; i++) bulletPage(continues: false)];
      final issues = [
        for (var i = 0; i < 3; i++)
          density(
            i,
            SlideQualityIssueKind.bulletWordCountHigh,
            args: {'words': '100'},
          ),
      ];
      final out = collapseSplitRunDensity(slides, issues);
      expect(out.length, 3);
      expect(out.any(hasRunPages), isFalse);
    });

    test('laat fouten (critical) per pagina staan', () {
      final slides = run(3);
      final issues = [
        for (var i = 0; i < 3; i++)
          density(
            i,
            SlideQualityIssueKind.bulletWordCountCritical,
            severity: MarkdownValidationSeverity.error,
            args: {'words': '200'},
          ),
      ];
      final out = collapseSplitRunDensity(slides, issues);
      // Critical is een eigen soort en valt buiten de samenvatbare set.
      expect(out.length, 3);
    });

    test(
      'laat aantal-gedreven meldingen (te veel bullets) per pagina staan',
      () {
        final slides = run(3);
        final issues = [
          for (var i = 0; i < 3; i++)
            density(
              i,
              SlideQualityIssueKind.bulletCountHigh,
              args: {'count': '10'},
            ),
        ];
        final out = collapseSplitRunDensity(slides, issues);
        expect(out.length, 3);
      },
    );

    test('samengevatte severity is de zwaarste van de groep', () {
      final slides = run(2);
      final issues = [
        density(
          0,
          SlideQualityIssueKind.bulletAverageLengthHigh,
          severity: MarkdownValidationSeverity.informational,
          args: {'average': '16'},
        ),
        density(
          1,
          SlideQualityIssueKind.bulletAverageLengthHigh,
          severity: MarkdownValidationSeverity.warning,
          args: {'average': '26'},
        ),
      ];
      final out = collapseSplitRunDensity(slides, issues);
      expect(out.length, 1);
      expect(out.single.severity, MarkdownValidationSeverity.warning);
    });

    test('vat elke soort apart samen en behoudt andere meldingen', () {
      final slides = run(2);
      final issues = [
        density(
          0,
          SlideQualityIssueKind.textDensityWarning,
          args: {'percent': '60%'},
        ),
        density(
          0,
          SlideQualityIssueKind.bulletMultiSentence,
          args: {'count': '2'},
        ),
        density(
          1,
          SlideQualityIssueKind.textDensityWarning,
          args: {'percent': '60%'},
        ),
        density(
          1,
          SlideQualityIssueKind.bulletMultiSentence,
          args: {'count': '2'},
        ),
      ];
      final out = collapseSplitRunDensity(slides, issues);
      expect(out.length, 2);
      expect(out.map((i) => i.kind).toSet(), {
        SlideQualityIssueKind.textDensityWarning,
        SlideQualityIssueKind.bulletMultiSentence,
      });
      expect(out.every((i) => i.args['runPages'] == '2'), isTrue);
    });

    test('twee losse reeksen worden onafhankelijk samengevat', () {
      final slides = [
        bulletPage(continues: false), // reeks A: 0,1
        bulletPage(continues: true),
        Slide.create(SlideType.image), // losse dia 2
        bulletPage(continues: false), // reeks B: 3,4
        bulletPage(continues: true),
      ];
      final issues = [
        for (final i in [0, 1, 3, 4])
          density(
            i,
            SlideQualityIssueKind.bulletWordCountHigh,
            args: {'words': '100'},
          ),
      ];
      final out = collapseSplitRunDensity(slides, issues);
      expect(out.length, 2);
      expect(out.map((i) => i.slideIndex).toList(), [0, 3]);
    });
  });

  group('collapseSplitRunDensity — echte analyse na Splits slide (#1289)', () {
    String longBullet(int i) =>
        'Dit is een tamelijk lange opsomming over onderwerp $i met veel '
        'woorden erin. De zin loopt door met een tweede deel dat uitleg geeft.';
    final overfull = Slide.create(SlideType.bulletsImage).copyWith(
      title: 'Overvol',
      imagePath: 'foto.png',
      bullets: [for (var i = 0; i < 40; i++) longBullet(i)],
    );
    const analyzer = SlideQualityAnalyzer();

    test('de meldingen exploderen niet meer per deelpagina', () {
      final pages = splitBulletSlidePages(overfull)!;
      expect(pages.length, greaterThan(2));
      final raw = analyzer.analyze(Deck(title: 'T', slides: pages)).issues;

      int countOf(List<SlideQualityIssue> xs, SlideQualityIssueKind k) =>
          xs.where((i) => i.kind == k).length;

      // Reproductie: minstens één lengte-gedreven soort staat op ≥2 pagina's.
      expect(
        kLengthDrivenRunDensityKinds.any((k) => countOf(raw, k) >= 2),
        isTrue,
        reason: 'de lengte-meldingen horen per deelpagina te herhalen',
      );

      final collapsed = collapseSplitRunDensity(pages, raw);

      // Na samenvatten staat elke lengte-gedreven soort nog hooguit één keer.
      for (final k in kLengthDrivenRunDensityKinds) {
        expect(
          countOf(collapsed, k),
          lessThanOrEqualTo(1),
          reason: '$k hoort samengevat te zijn tot één melding',
        );
      }
      // De samenvatting draagt op over hoeveel pagina's ze gaat.
      for (final i in collapsed.where(
        (i) => kLengthDrivenRunDensityKinds.contains(i.kind),
      )) {
        expect(int.parse(i.args['runPages']!), greaterThanOrEqualTo(2));
      }
      // De totale telling daalt echt.
      expect(collapsed.length, lessThan(raw.length));

      // Niet-samenvatbare soorten (fouten, te-veel-bullets) blijven ongemoeid.
      bool notCollapsible(SlideQualityIssue i) =>
          !kLengthDrivenRunDensityKinds.contains(i.kind);
      expect(
        collapsed.where(notCollapsible).length,
        raw.where(notCollapsible).length,
      );
    });

    test(
      'een niet-gesplitste reeks (geen continuesSplit) blijft ongemoeid',
      () {
        // Dezelfde pagina's, maar zonder continuation-vlaggen: geen run, geen
        // samenvatting — de collapse pakt uitsluitend echte split-reeksen.
        final pages = splitBulletSlidePages(
          overfull,
        )!.map((s) => s.copyWith(continuesSplit: false)).toList();
        final raw = analyzer.analyze(Deck(title: 'T', slides: pages)).issues;
        final collapsed = collapseSplitRunDensity(pages, raw);
        expect(collapsed.length, raw.length);
      },
    );
  });

  group('providers: ruw blijft exploderen, weergave vat samen (#1289)', () {
    String longBullet(int i) =>
        'Dit is een tamelijk lange opsomming over onderwerp $i met veel '
        'woorden erin. De zin loopt door met een tweede deel dat uitleg geeft.';

    // testWidgets (niet test): newDeck start asynchrone providers die een
    // Flutter-binding nodig hebben; zonder binding valt het om op een
    // completeError. We lezen de synchrone kwaliteitsproviders direct na de
    // splitsing, dus er is verder niets te pompen.
    testWidgets(
      'na Splits slide ziet de fix-motor elke pagina, het paneel één per soort',
      (tester) async {
        final container = ProviderContainer();
        addTearDown(container.dispose);
        final notifier = container.read(deckProvider.notifier);
        notifier.newDeck('Test');
        notifier.updateSlide(
          0,
          Slide.create(SlideType.bulletsImage).copyWith(
            title: 'Overvol',
            imagePath: 'foto.png',
            bullets: [for (var i = 0; i < 40; i++) longBullet(i)],
          ),
        );

        // De echte gebruikersactie: 'Splits slide'.
        notifier.splitSlide(0);
        expect(
          container.read(deckProvider).deck!.slides.length,
          greaterThan(2),
          reason: 'de dia hoort over meerdere deelpagina\'s verdeeld te zijn',
        );

        int countOf(SlideQualityResult r, SlideQualityIssueKind k) =>
            r.issues.where((i) => i.kind == k).length;

        final raw = container.read(deckQualityRawProvider);
        final shown = container.read(deckQualityProvider);

        // De ruwe analyse — waar de fix-motor op draait — houdt elke pagina apart.
        final explodedKind = kLengthDrivenRunDensityKinds.firstWhere(
          (k) => countOf(raw, k) >= 2,
          orElse: () => SlideQualityIssueKind.bulletAverageLengthHigh,
        );
        expect(countOf(raw, explodedKind), greaterThanOrEqualTo(2));

        // Het paneel — de weergave — vat elke lengte-gedreven soort samen tot één.
        for (final k in kLengthDrivenRunDensityKinds) {
          expect(countOf(shown, k), lessThanOrEqualTo(1));
        }
        // En het is echt minder dan de ruwe telling.
        expect(shown.warningCount, lessThan(raw.warningCount));
      },
    );
  });
}
