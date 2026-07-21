import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/models/question.dart';
import 'package:ocideck/models/settings.dart';
import 'package:ocideck/models/slide.dart';
import 'package:ocideck/widgets/presentation/fullscreen_presenter.dart';

/// De twee vraagsoorten die er bij kwamen (twee afbeeldingen, getypt antwoord)
/// en de reparatie aan 'meerdere juiste antwoorden'.
///
/// Het zwaartepunt ligt op wat de kijker te zien krijgt, niet op de
/// tekenroutine: of álle antwoorden op het scherm staan, of het juiste antwoord
/// pas ná het antwoorden verschijnt, en of een tikfout goed gerekend wordt.
Slide _question(QuestionSpec spec) =>
    Slide(id: 'q', type: SlideType.question, customMarkdown: spec.toBlock());

Widget _host(List<Slide> slides) => MaterialApp(
  localizationsDelegates: const [
    GlobalMaterialLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
    FlutterQuillLocalizations.delegate,
  ],
  home: FullscreenPresenter(
    slides: slides,
    projectPath: null,
    themeProfile: const ThemeProfile(),
    initialIndex: 0,
  ),
);

Finder _option(String text) =>
    find.ancestor(of: find.text(text), matching: find.byType(InkWell)).first;

void main() {
  final after = Slide.create(
    SlideType.bullets,
  ).copyWith(title: 'Daarna', bullets: ['a']);

  // ── Meerdere juiste antwoorden: álle antwoorden ─────────────────────────────

  group('meerdere juiste antwoorden', () {
    final spec = QuestionSpec(
      kind: QuestionKind.multipleCorrect,
      prompt: 'Welke horen in de kluis?',
      // Bewust meer antwoorden dan optionCount: de oude tekenroutine trok er
      // een greep uit, waardoor "selecteer alle juiste" niet te doen was.
      optionCount: 3,
      answers: const [
        QuestionAnswer(text: 'Sleutel', correct: true),
        QuestionAnswer(text: 'Wachtwoord', correct: true),
        QuestionAnswer(text: 'Paspoort', correct: true),
        QuestionAnswer(text: 'Boodschappenlijst'),
        QuestionAnswer(text: 'Krant'),
        QuestionAnswer(text: 'Paraplu'),
      ],
    );

    testWidgets('toont élk antwoord, niet een greep', (tester) async {
      await tester.pumpWidget(_host([_question(spec), after]));
      await tester.pump();

      for (final text in [
        'Sleutel',
        'Wachtwoord',
        'Paspoort',
        'Boodschappenlijst',
        'Krant',
        'Paraplu',
      ]) {
        expect(find.text(text), findsOneWidget, reason: '$text ontbreekt');
      }

      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('alle juiste aanvinken en bevestigen geeft goed', (
      tester,
    ) async {
      await tester.pumpWidget(_host([_question(spec), after]));
      await tester.pump();

      for (final text in ['Sleutel', 'Wachtwoord', 'Paspoort']) {
        await tester.tap(_option(text));
        await tester.pump();
      }
      await tester.tap(find.text('Bevestig'));
      await tester.pump();

      expect(find.text('Goed!'), findsOneWidget);

      await tester.pumpWidget(const SizedBox());
    });
  });

  // ── Twee afbeeldingen ──────────────────────────────────────────────────────

  group('twee afbeeldingen', () {
    QuestionSpec spec({QuestionOnWrong onWrong = QuestionOnWrong.retry}) =>
        QuestionSpec(
          kind: QuestionKind.imagePair,
          prompt: 'Welke schermafdruk toont een phishingmail?',
          onWrong: onWrong,
          answers: const [
            QuestionAnswer(text: 'De echte', image: 'echt.png'),
            QuestionAnswer(text: 'De valse', image: 'vals.png', correct: true),
          ],
        );

    test('de afbeelding is het antwoord, dus telt die als ingevuld', () {
      const withoutText = QuestionSpec(
        kind: QuestionKind.imagePair,
        answers: [
          QuestionAnswer(image: 'a.png'),
          QuestionAnswer(image: 'b.png', correct: true),
        ],
      );
      // Geen tekst, wel twee beelden: presenteerbaar.
      expect(withoutText.filledAnswers.length, 2);
      expect(withoutText.isPresentable, isTrue);

      // Eén beeld weg: niet meer presenteerbaar.
      const halfEmpty = QuestionSpec(
        kind: QuestionKind.imagePair,
        answers: [QuestionAnswer(image: 'a.png', correct: true)],
      );
      expect(halfEmpty.isPresentable, isFalse);
    });

    test('het beeldpad reist mee door het blok en terug', () {
      final parsed = QuestionSpec.parse(spec().toBlock());
      expect(parsed.kind, QuestionKind.imagePair);
      expect(parsed.answers[0].image, 'echt.png');
      expect(parsed.answers[1].image, 'vals.png');
      expect(parsed.answers[1].correct, isTrue);
    });

    test('een tekstantwoord krijgt geen lege beeldsleutel in het blok', () {
      const text = QuestionSpec(
        answers: [QuestionAnswer(text: 'Alleen tekst', correct: true)],
      );
      expect(text.toBlock().contains('"image"'), isFalse);
    });

    testWidgets('beide bijschriften staan op de dia', (tester) async {
      await tester.pumpWidget(_host([_question(spec()), after]));
      await tester.pump();

      expect(find.text('De echte'), findsOneWidget);
      expect(find.text('De valse'), findsOneWidget);
      expect(find.text('Tik de juiste afbeelding aan'), findsOneWidget);

      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('de juiste aantikken geeft goed, de andere fout', (
      tester,
    ) async {
      await tester.pumpWidget(_host([_question(spec()), after]));
      await tester.pump();

      await tester.tap(_option('De valse'));
      await tester.pump();
      expect(find.text('Goed!'), findsOneWidget);

      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('de kant van het juiste antwoord wisselt over rondes', (
      tester,
    ) async {
      // Fout antwoorden geeft in de retry-stand een verse ronde. Over genoeg
      // rondes hoort het juiste beeld op beide plekken te belanden — anders is
      // het na één keer kijken te onthouden welke kant het is.
      await tester.pumpWidget(_host([_question(spec()), after]));
      await tester.pump();

      final sides = <int>{};
      for (var round = 0; round < 25 && sides.length < 2; round++) {
        final captions = tester
            .widgetList<Text>(find.byType(Text))
            .map((t) => t.data)
            .where((d) => d == 'De echte' || d == 'De valse')
            .toList();
        sides.add(captions.indexOf('De valse'));
        // Fout antwoorden en doorklikken start een nieuwe ronde.
        await tester.tap(_option('De echte'));
        await tester.pump();
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
        await tester.pump();
      }
      expect(
        sides.length,
        2,
        reason: 'het juiste beeld stond 25 rondes lang aan dezelfde kant',
      );

      await tester.pumpWidget(const SizedBox());
    });
  });

  testWidgets('meer dan twee beelden levert elke ronde een echt paar op', (
    tester,
  ) async {
    // De editor biedt twee plekken, maar in de Markdown kan er meer staan.
    // Dan hoort er per ronde één juiste en één foute getrokken te worden —
    // gewoon de eerste twee nemen kon twee foute opleveren, en dan is de vraag
    // niet te halen terwijl hij wél blokkeert.
    const spec = QuestionSpec(
      kind: QuestionKind.imagePair,
      prompt: 'Welke is echt?',
      answers: [
        QuestionAnswer(text: 'Vals A', image: 'a.png'),
        QuestionAnswer(text: 'Vals B', image: 'b.png'),
        QuestionAnswer(text: 'Echt', image: 'c.png', correct: true),
      ],
    );

    await tester.pumpWidget(
      _host([
        Slide(
          id: 'q',
          type: SlideType.question,
          customMarkdown: spec.toBlock(),
        ),
        after,
      ]),
    );
    await tester.pump();

    // Het juiste beeld staat er, en precies één van de twee foute.
    expect(find.text('Echt'), findsOneWidget);
    expect(
      find.text('Vals A').evaluate().length +
          find.text('Vals B').evaluate().length,
      1,
    );

    await tester.pumpWidget(const SizedBox());
  });

  // ── Getypt antwoord ────────────────────────────────────────────────────────

  group('getypt antwoord', () {
    QuestionSpec spec({double threshold = questionDefaultSimilarity}) =>
        QuestionSpec(
          kind: QuestionKind.openText,
          prompt: 'Waar hoort een wachtwoord thuis?',
          similarityThreshold: threshold,
          answers: const [QuestionAnswer(text: 'in de kluis', correct: true)],
        );

    test('de drempel reist mee en wordt begrensd', () {
      final parsed = QuestionSpec.parse(spec(threshold: 0.7).toBlock());
      expect(parsed.similarityThreshold, closeTo(0.7, 0.0001));

      // Buiten de grenzen wordt teruggeklemd in plaats van geweigerd.
      expect(
        QuestionSpec.parse(
          '{"kind":"openText","similarityThreshold":5}',
        ).similarityThreshold,
        questionMaxSimilarity,
      );
      expect(
        QuestionSpec.parse(
          '{"kind":"openText","similarityThreshold":-1}',
        ).similarityThreshold,
        questionMinSimilarity,
      );
    });

    test('alleen een juist antwoord is nodig om te kunnen presenteren', () {
      expect(spec().isPresentable, isTrue);
      const zonder = QuestionSpec(
        kind: QuestionKind.openText,
        answers: [QuestionAnswer(text: 'iets fouts')],
      );
      expect(zonder.isPresentable, isFalse);
    });

    testWidgets('het juiste antwoord staat er niet vóór het antwoorden', (
      tester,
    ) async {
      await tester.pumpWidget(_host([_question(spec()), after]));
      await tester.pump();

      expect(find.text('Typ je antwoord en bevestig'), findsOneWidget);
      expect(find.text('in de kluis'), findsNothing);

      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('een tikfout telt als goed', (tester) async {
      await tester.pumpWidget(_host([_question(spec()), after]));
      await tester.pump();

      await tester.enterText(find.byType(TextField), 'in de klius');
      await tester.pump();
      await tester.tap(find.text('Bevestig'));
      await tester.pump();

      expect(find.text('Goed!'), findsOneWidget);

      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('een ander antwoord is fout en onthult het juiste', (
      tester,
    ) async {
      await tester.pumpWidget(_host([_question(spec()), after]));
      await tester.pump();

      await tester.enterText(find.byType(TextField), 'in mijn agenda');
      await tester.pump();
      await tester.tap(find.text('Bevestig'));
      await tester.pump();

      expect(find.text('Helaas, fout'), findsOneWidget);
      expect(find.text('in de kluis'), findsOneWidget);
      expect(find.text('Het juiste antwoord'), findsOneWidget);

      await tester.pumpWidget(const SizedBox());
    });

    testWidgets(
      'de correctie zet beide teksten naast elkaar met het verschil',
      (tester) async {
        // "fout" met een percentage leert niemand iets. De kijker hoort te zien
        // wélke letters er te veel stonden en welke er misten.
        await tester.pumpWidget(_host([_question(spec()), after]));
        await tester.pump();

        await tester.enterText(find.byType(TextField), 'in de klius');
        await tester.pump();
        await tester.tap(find.text('Bevestig'));
        await tester.pump();

        expect(find.text('Jouw antwoord'), findsOneWidget);
        expect(find.text('in de klius'), findsOneWidget); // met markering erin
        expect(find.text('in de kluis'), findsOneWidget);

        // Het percentage staat naast de drempel, anders is het een getal zonder
        // maatstaf.
        expect(find.textContaining('Overeenkomst'), findsOneWidget);
        expect(find.textContaining('nodig'), findsOneWidget);

        // Het invoerveld maakt plaats voor de correctie; twee keer hetzelfde
        // antwoord op de dia leest als een fout.
        expect(find.byType(TextField), findsNothing);

        await tester.pumpWidget(const SizedBox());
      },
    );

    testWidgets('een letterlijk goed antwoord krijgt geen vergelijking', (
      tester,
    ) async {
      await tester.pumpWidget(_host([_question(spec()), after]));
      await tester.pump();

      await tester.enterText(find.byType(TextField), 'In De Kluis');
      await tester.pump();
      await tester.tap(find.text('Bevestig'));
      await tester.pump();

      expect(find.text('Goed!'), findsOneWidget);
      // Hoofdletters tellen niet mee, dus er valt niets aan te wijzen.
      expect(find.text('Jouw antwoord'), findsNothing);

      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('de correctie zet het antwoord af tegen het best passende', (
      tester,
    ) async {
      // Bij meerdere goed gerekende antwoorden is corrigeren tegen het eerste
      // in de lijst onnavolgbaar: je krijgt dan een antwoord aangewezen waar je
      // helemaal niet naar op weg was.
      const meerdere = QuestionSpec(
        kind: QuestionKind.openText,
        prompt: 'Waar hoort een wachtwoord thuis?',
        answers: [
          QuestionAnswer(text: 'in de kluis', correct: true),
          QuestionAnswer(text: 'in een wachtwoordbeheerder', correct: true),
        ],
      );

      await tester.pumpWidget(
        _host([
          Slide(
            id: 'q',
            type: SlideType.question,
            customMarkdown: meerdere.toBlock(),
          ),
          after,
        ]),
      );
      await tester.pump();

      await tester.enterText(
        find.byType(TextField),
        'in een wachtwoordbeheerdr',
      );
      await tester.pump();
      await tester.tap(find.text('Bevestig'));
      await tester.pump();

      expect(find.text('in een wachtwoordbeheerder'), findsOneWidget);
      expect(find.text('in de kluis'), findsNothing);

      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('een strengere drempel keurt dezelfde tikfout af', (
      tester,
    ) async {
      await tester.pumpWidget(
        _host([_question(spec(threshold: questionMaxSimilarity)), after]),
      );
      await tester.pump();

      await tester.enterText(find.byType(TextField), 'in de klius');
      await tester.pump();
      await tester.tap(find.text('Bevestig'));
      await tester.pump();

      expect(find.text('Helaas, fout'), findsOneWidget);

      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('een cijfer in het antwoord springt niet naar die slide', (
      tester,
    ) async {
      // De sneltoetsen mogen niet meeluisteren zolang er getypt wordt; een "2"
      // in het antwoord sprong anders naar slide 2.
      await tester.pumpWidget(_host([_question(spec()), after]));
      await tester.pump();

      await tester.enterText(find.byType(TextField), 'kluis 2');
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.digit2);
      await tester.pump();

      expect(find.text('Daarna'), findsNothing);

      await tester.pumpWidget(const SizedBox());
    });
  });
}
