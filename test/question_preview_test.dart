import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/models/question.dart';
import 'package:ocideck/models/slide.dart';
import 'package:ocideck/widgets/slides/slide_preview.dart';

import 'support/question_answer_limit_fixture.dart';

Slide _questionSlide(QuestionSpec spec) =>
    Slide(id: 'q', type: SlideType.question, customMarkdown: spec.toBlock());

Future<void> _pump(
  WidgetTester tester,
  Slide slide, {
  double width = 800,
  double height = 450,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: width,
            height: height,
            child: SlidePreviewWidget(slide: slide),
          ),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('question with many options fits without overflow', (
    tester,
  ) async {
    final spec = QuestionSpec(
      prompt: 'Een vrij lange vraag die over de breedte van de slide loopt?',
      answers: [
        for (var i = 1; i <= 8; i++)
          QuestionAnswer(
            text: 'Antwoordoptie nummer $i met een wat langere tekst erbij',
            correct: i == 1,
          ),
      ],
      optionCount: 8,
    );
    await _pump(tester, _questionSlide(spec));

    // A RenderFlex/box overflow surfaces as a thrown FlutterError in tests;
    // the auto-fit (FittedBox) must keep everything on the fixed 16:9 surface.
    expect(tester.takeException(), isNull);
    expect(find.textContaining('Antwoordoptie nummer 8'), findsOneWidget);
  });

  testWidgets('10,000 answers show one invalid-question notice, not options', (
    tester,
  ) async {
    final slide = Slide(
      id: 'oversized',
      type: SlideType.question,
      customMarkdown: questionBlockWithAnswers(10000),
    );

    await _pump(tester, slide);

    expect(
      find.byKey(const Key('invalid-question-answer-count')),
      findsOneWidget,
    );
    expect(find.text('Ongeldige vraag'), findsOneWidget);
    expect(find.textContaining('Maximaal aantal items: 8'), findsOneWidget);
    expect(find.textContaining('Antwoord 9999'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('question with an image fits the narrower text column', (
    tester,
  ) async {
    final spec = QuestionSpec(
      prompt: 'Welke optie hoort bij deze afbeelding van een landschap?',
      answers: [
        for (var i = 1; i <= 6; i++)
          QuestionAnswer(
            text: 'Een vrij lang antwoord nummer $i dat de kolom flink vult',
            correct: i == 1,
          ),
      ],
      optionCount: 6,
    );
    final slide = _questionSlide(spec).copyWith(
      imagePath: 'does/not/exist.png', // valt terug op placeholder, geen error
      imageSize: 45,
    );
    await _pump(tester, slide);

    expect(tester.takeException(), isNull);
    expect(find.textContaining('antwoord nummer 6'), findsOneWidget);
  });

  testWidgets('tiny thumbnail with image and options does not overflow', (
    tester,
  ) async {
    final spec = QuestionSpec(
      prompt: 'Een wat langere vraag die in een miniatuur moet passen?',
      answers: [
        for (var i = 1; i <= 6; i++)
          QuestionAnswer(text: 'Antwoordoptie nummer $i', correct: i == 1),
      ],
      optionCount: 6,
    );
    final slide = _questionSlide(
      spec,
    ).copyWith(imagePath: 'does/not/exist.png', imageSize: 45);
    // Grid-/volgende-slide-miniatuur: heel klein, mag niet overflowen.
    await _pump(tester, slide, width: 180, height: 101);
    expect(tester.takeException(), isNull);
  });

  testWidgets('true/false authoring view shows Juist and Onjuist', (
    tester,
  ) async {
    final spec = const QuestionSpec(
      kind: QuestionKind.trueFalse,
      prompt: 'Nederland grenst aan Duitsland.',
      statementIsTrue: true,
    );
    await _pump(tester, _questionSlide(spec));
    expect(find.textContaining('Juist'), findsOneWidget);
    expect(find.textContaining('Onjuist'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('authoring view shows all answers, not a random subset', (
    tester,
  ) async {
    final spec = const QuestionSpec(
      prompt: 'Vraag?',
      answers: [
        QuestionAnswer(text: 'Alpha', correct: true),
        QuestionAnswer(text: 'Bravo'),
        QuestionAnswer(text: 'Charlie'),
        QuestionAnswer(text: 'Delta'),
        QuestionAnswer(text: 'Echo'),
      ],
      optionCount: 3,
    );
    await _pump(tester, _questionSlide(spec));

    // No QuestionView passed → editor/authoring view shows every answer.
    for (final t in ['Alpha', 'Bravo', 'Charlie', 'Delta', 'Echo']) {
      expect(find.textContaining(t), findsOneWidget, reason: t);
    }
    expect(tester.takeException(), isNull);
  });

  QuestionSpec orderingSpec() => const QuestionSpec(
    kind: QuestionKind.ordering,
    prompt: 'Zet de stappen in de juiste volgorde',
    answers: [
      QuestionAnswer(text: 'Stap een'),
      QuestionAnswer(text: 'Stap twee'),
      QuestionAnswer(text: 'Stap drie'),
    ],
    optionCount: 3,
  );

  Future<void> pumpWithView(
    WidgetTester tester,
    QuestionView view, {
    ValueChanged<int>? onSelected,
    VoidCallback? onSubmit,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 800,
              height: 450,
              child: SlidePreviewWidget(
                slide: _questionSlide(orderingSpec()),
                presentationMode: true,
                questionView: view,
                onAnswerSelected: onSelected ?? (_) {},
                onAnswerSubmit: onSubmit ?? () {},
              ),
            ),
          ),
        ),
      ),
    );
  }

  testWidgets('ordering authoring view shows the answers numbered in order', (
    tester,
  ) async {
    await _pump(tester, _questionSlide(orderingSpec()));
    for (final t in ['Stap een', 'Stap twee', 'Stap drie']) {
      expect(find.textContaining(t), findsOneWidget, reason: t);
    }
    // De badges tonen de juiste volgorde als nummers in plaats van letters.
    for (final n in ['1', '2', '3']) {
      expect(find.text(n), findsOneWidget, reason: 'badge $n');
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('ordering presentation shows instruction and position badges', (
    tester,
  ) async {
    // Getoond als: Stap twee, Stap drie, Stap een; 'Stap drie' is aangetikt
    // als eerste keuze.
    const view = QuestionView(
      options: ['Stap twee', 'Stap drie', 'Stap een'],
      correctIndices: [2, 0, 1],
      selectedIndices: [1],
      multi: true,
      ordering: true,
    );
    await pumpWithView(tester, view);

    expect(
      find.text('Tik de antwoorden aan in de juiste volgorde'),
      findsOneWidget,
    );
    // Aangetikte optie draagt positienummer 1; de rest een bullet.
    expect(find.text('1'), findsOneWidget);
    expect(find.text('•'), findsNWidgets(2));
    expect(tester.takeException(), isNull);
  });

  testWidgets('ordering reveal lists the correct order with clear feedback', (
    tester,
  ) async {
    // Juiste volgorde: een (idx 2), twee (idx 0), drie (idx 1). De kijker
    // tikte: twee, een, drie → alleen 'Stap drie' stond goed (positie 3).
    const view = QuestionView(
      options: ['Stap twee', 'Stap drie', 'Stap een'],
      correctIndices: [2, 0, 1],
      selectedIndices: [0, 2, 1],
      multi: true,
      ordering: true,
      result: QuestionResult.wrong,
      revealed: true,
      locked: true,
    );
    await pumpWithView(tester, view);

    // Fout geplaatste opties melden expliciet de eigen (foute) plek.
    expect(find.text('Jouw volgorde: 2'), findsOneWidget); // Stap een
    expect(find.text('Jouw volgorde: 1'), findsOneWidget); // Stap twee
    // De goed geplaatste optie krijgt geen feedbackregel.
    expect(find.textContaining('Jouw volgorde'), findsNWidgets(2));
    expect(find.text('Helaas, fout'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
