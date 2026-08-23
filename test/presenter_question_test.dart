import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/models/question.dart';
import 'package:ocideck/models/settings.dart';
import 'package:ocideck/models/slide.dart';
import 'package:ocideck/widgets/presentation/fullscreen_presenter.dart';

import 'support/question_answer_limit_fixture.dart';

/// Vraag-slides tijdens het presenteren: een quiz die de zaal vasthoudt tot er
/// (juist) geantwoord is. Het blokkeren is het hele punt van de slide, dus het
/// hoort getoetst: wie hier per ongeluk doorbladert, presenteert het antwoord
/// vóór de vraag.
Slide _question(QuestionSpec spec) =>
    Slide(id: 'q', type: SlideType.question, customMarkdown: spec.toBlock());

/// Waar/onwaar met één juist antwoord — de eenvoudigste vraag die niet toevallig
/// goed te raden valt door de opties te tellen.
QuestionSpec _trueFalse({
  QuestionOnWrong onWrong = QuestionOnWrong.retry,
  int timeLimitSeconds = 0,
}) => QuestionSpec(
  kind: QuestionKind.trueFalse,
  prompt: 'Een wachtwoord hoort in de kluis?',
  statementIsTrue: true,
  onWrong: onWrong,
  timeLimitSeconds: timeLimitSeconds,
);

Widget _host(List<Slide> slides) => MaterialApp(
  localizationsDelegates: const [
    ...GlobalMaterialLocalizations.delegates,
    FlutterQuillLocalizations.delegate,
  ],
  home: FullscreenPresenter(
    slides: slides,
    projectPath: null,
    themeProfile: const ThemeProfile(),
    initialIndex: 0,
  ),
);

/// De optietegel is een InkWell om de tekst heen; tikken op de tekst zelf raakt
/// niet altijd het aanraakvlak.
Finder _option(String text) =>
    find.ancestor(of: find.text(text), matching: find.byType(InkWell)).first;

void main() {
  final after = Slide.create(
    SlideType.bullets,
  ).copyWith(title: 'Daarna', bullets: ['a']);

  testWidgets('an unanswered question holds the presentation in place', (
    tester,
  ) async {
    await tester.pumpWidget(_host([_question(_trueFalse()), after]));
    await tester.pump();

    expect(find.text('Juist'), findsOneWidget);
    expect(find.text('Onjuist'), findsOneWidget);

    // Doorbladeren doet niets zolang er geen antwoord ligt.
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    expect(find.text('Daarna'), findsNothing);

    await tester.tap(_option('Juist'));
    await tester.pump();

    // Beantwoord: nu geeft dezelfde toets wél mee.
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pumpAndSettle();
    expect(find.text('Daarna'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('a wrong answer in retry mode starts a fresh round, not a skip', (
    tester,
  ) async {
    await tester.pumpWidget(_host([_question(_trueFalse()), after]));
    await tester.pump();

    await tester.tap(_option('Onjuist'));
    await tester.pump();

    // Fout: de slide blijft staan en de volgende tik geeft een nieuwe poging
    // in plaats van door te bladeren.
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    expect(find.text('Daarna'), findsNothing);
    expect(find.text('Juist'), findsOneWidget);

    // En die nieuwe poging is weer te beantwoorden.
    await tester.tap(_option('Juist'));
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pumpAndSettle();
    expect(find.text('Daarna'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('a wrong answer that locks lets the presentation continue', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host([
        _question(_trueFalse(onWrong: QuestionOnWrong.lockAndContinue)),
        after,
      ]),
    );
    await tester.pump();

    await tester.tap(_option('Onjuist'));
    await tester.pump();

    // Vergrendeld: het juiste antwoord is getoond en je mag verder — anders
    // stond een spreker die zich vergiste muurvast voor de zaal.
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pumpAndSettle();
    expect(find.text('Daarna'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('an expiring timer resolves the question as wrong', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host([
        _question(
          _trueFalse(
            onWrong: QuestionOnWrong.lockAndContinue,
            timeLimitSeconds: 1,
          ),
        ),
        after,
      ]),
    );
    await tester.pump();

    // Niets aantikken; de klok loopt af.
    await tester.pump(const Duration(milliseconds: 1200));
    await tester.pump();

    // Verlopen telt als fout, en met lockAndContinue mag de presentatie door.
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pumpAndSettle();
    expect(find.text('Daarna'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('a multi-answer question only resolves once confirmed', (
    tester,
  ) async {
    // Eén juist en één fout antwoord bij optionCount 2: dan is de trekking niet
    // willekeurig meer. De ronde kiest normaal een wisselend aantal juiste
    // antwoorden uit de pool, dus een rijkere vraag maakt de test wankel — hij
    // slaagt of faalt op de dobbelsteen, niet op het gedrag.
    final spec = QuestionSpec(
      kind: QuestionKind.multipleCorrect,
      prompt: 'Wat hoort in een risicoregister?',
      answers: const [
        QuestionAnswer(text: 'Kans', correct: true),
        QuestionAnswer(text: 'Lunchbestelling'),
      ],
      optionCount: 2,
    );
    await tester.pumpWidget(_host([_question(spec), after]));
    await tester.pump();

    // Eén aantik onthult nog niets: bij meerdere juiste antwoorden wisselt een
    // tik alleen de selectie, bevestigen is een aparte handeling.
    await tester.tap(_option('Kans'));
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    expect(find.text('Daarna'), findsNothing);
    expect(find.text('Bevestig'), findsOneWidget);

    // Bevestigen met precies de juiste verzameling laat de presentatie door.
    await tester.tap(_option('Bevestig'));
    await tester.pump();

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pumpAndSettle();
    expect(find.text('Daarna'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('exactly eight answers reach the full presenter', (tester) async {
    final spec = QuestionSpec.parse(questionBlockWithAnswers(8));

    await tester.pumpWidget(_host([_question(spec), after]));
    await tester.pump();

    for (var i = 0; i < 8; i++) {
      expect(find.text('Antwoord $i'), findsOneWidget);
    }
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('a twenty-answer bank presents only the four drawn options', (
    tester,
  ) async {
    final spec = QuestionSpec.parse(multipleChoiceBeerQuestionBlock(20));

    await tester.pumpWidget(_host([_question(spec), after]));
    await tester.pump();

    expect(
      find.byKey(const Key('invalid-question-answer-count')),
      findsNothing,
    );
    expect(find.text('Wat is geen bier?'), findsOneWidget);
    final shown = [
      for (final answer in spec.answers)
        if (find.text(answer.text).evaluate().isNotEmpty) answer.text,
    ];
    expect(shown, hasLength(4));

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    expect(find.text('Daarna'), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('an oversized question reports invalid and never blocks', (
    tester,
  ) async {
    final invalid = Slide(
      id: 'q-invalid',
      type: SlideType.question,
      customMarkdown: questionBlockWithAnswers(9),
    );

    await tester.pumpWidget(_host([invalid, after]));
    await tester.pump();

    expect(
      find.byKey(const Key('invalid-question-answer-count')),
      findsOneWidget,
    );
    expect(find.text('Ongeldige vraag'), findsOneWidget);
    expect(find.text('Antwoord 8'), findsNothing);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pumpAndSettle();
    expect(find.text('Daarna'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('a question without a wrong answer never blocks', (tester) async {
    // Onbeantwoordbaar (geen goed/fout paar): zo'n slide mag de presentatie
    // niet gijzelen — er is niets te winnen.
    final spec = QuestionSpec(
      prompt: 'Waar denk je aan?',
      answers: const [
        QuestionAnswer(text: 'Van alles'),
        QuestionAnswer(text: 'Niets'),
      ],
      optionCount: 2,
    );
    await tester.pumpWidget(_host([_question(spec), after]));
    await tester.pump();

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pumpAndSettle();
    expect(find.text('Daarna'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
  });
}
