import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/l10n/app_localizations.dart';
import 'package:ocideck/models/question.dart';
import 'package:ocideck/models/slide.dart';
import 'package:ocideck/services/image_service.dart';
import 'package:ocideck/widgets/editors/_editor_field.dart';
import 'package:ocideck/widgets/editors/markdown_editor_field.dart';
import 'package:ocideck/widgets/editors/question_editor.dart';

import 'support/question_answer_limit_fixture.dart';

/// Widget host mirroring the real editor panel: a fixed-size surface with the
/// localization delegates the editor needs, wrapped in a [ProviderScope]
/// because the image picker below the fold reads Riverpod providers.
Widget _host(Slide slide, ValueChanged<Slide> onUpdate) {
  return ProviderScope(
    child: MaterialApp(
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        FlutterQuillLocalizations.delegate,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: SizedBox(
          width: 1000,
          height: 1600,
          child: QuestionEditor(
            slide: slide,
            onUpdate: onUpdate,
            imageService: ImageService(),
          ),
        ),
      ),
    ),
  );
}

Slide _questionSlide(QuestionSpec spec) =>
    Slide.create(SlideType.question).copyWith(customMarkdown: spec.toBlock());

/// Pumps on a surface tall enough for the full 1600px editor to be realised,
/// so the lazy [ListView] builds every row (and dropdown menus are not
/// scroll-clipped) rather than being cut off at the default test window.
Future<void> _pump(WidgetTester tester, Widget host) async {
  tester.view.physicalSize = const Size(1200, 2200);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
  await tester.pumpWidget(host);
}

void main() {
  setUp(() => AppLocalizations.setActiveLanguageCode('nl'));

  testWidgets('kind dropdown switches to true/false and hides answer options', (
    tester,
  ) async {
    var updated = _questionSlide(QuestionSpec.defaultMultipleChoice());

    await _pump(tester, _host(updated, (s) => updated = s));

    await tester.tap(find.byType(DropdownButtonFormField<QuestionKind>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Juist / Onjuist').last);
    await tester.pumpAndSettle();

    expect(
      QuestionSpec.parse(updated.customMarkdown).kind,
      QuestionKind.trueFalse,
    );
    // The true/false answer control appears; the option-count row is gone.
    expect(find.text('Juist'), findsOneWidget);
    expect(find.text('Onjuist'), findsOneWidget);
    expect(find.byTooltip('Optie toevoegen'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('true/false selecting Onjuist emits statementIsTrue false', (
    tester,
  ) async {
    var updated = _questionSlide(
      const QuestionSpec(
        kind: QuestionKind.trueFalse,
        prompt: 'De lucht is groen',
      ),
    );

    await _pump(tester, _host(updated, (s) => updated = s));

    await tester.tap(find.text('Onjuist'));
    await tester.pump();

    expect(QuestionSpec.parse(updated.customMarkdown).statementIsTrue, isFalse);
  });

  testWidgets('adding an answer appends an empty option', (tester) async {
    var updated = _questionSlide(
      const QuestionSpec(
        answers: [
          QuestionAnswer(text: 'Goed', correct: true),
          QuestionAnswer(text: 'Fout'),
        ],
      ),
    );

    await _pump(tester, _host(updated, (s) => updated = s));

    await tester.tap(find.text('Antwoord toevoegen'));
    await tester.pump();

    expect(QuestionSpec.parse(updated.customMarkdown).answers.length, 3);
  });

  testWidgets('exactly eight answers disables adding a ninth', (tester) async {
    var updated = Slide.create(
      SlideType.question,
    ).copyWith(customMarkdown: questionBlockWithAnswers(8));

    await _pump(tester, _host(updated, (s) => updated = s));

    final add = tester.widget<TextButton>(
      find.widgetWithText(TextButton, 'Antwoord toevoegen'),
    );
    expect(add.onPressed, isNull);
    expect(QuestionSpec.parse(updated.customMarkdown).answers, hasLength(8));
    expect(tester.takeException(), isNull);
  });

  testWidgets('an oversized question is reported without answer editors', (
    tester,
  ) async {
    final source = questionBlockWithAnswers(10000);
    var updates = 0;
    final slide = Slide.create(
      SlideType.question,
    ).copyWith(customMarkdown: source);

    await _pump(tester, _host(slide, (_) => updates++));

    expect(
      find.byKey(const Key('invalid-question-answer-count')),
      findsOneWidget,
    );
    expect(find.text('Ongeldige vraag'), findsOneWidget);
    expect(find.textContaining('Maximaal aantal items: 8'), findsOneWidget);
    expect(find.byType(TextField), findsNothing);
    expect(updates, 0);
    expect(slide.customMarkdown, source);
    expect(tester.takeException(), isNull);
  });

  testWidgets('checking an option marks it correct', (tester) async {
    var updated = _questionSlide(
      const QuestionSpec(
        answers: [
          QuestionAnswer(text: 'Alfa'),
          QuestionAnswer(text: 'Beta'),
        ],
      ),
    );

    await _pump(tester, _host(updated, (s) => updated = s));

    await tester.tap(find.byType(Checkbox).first);
    await tester.pump();

    final spec = QuestionSpec.parse(updated.customMarkdown);
    expect(spec.answers.first.correct, isTrue);
    expect(spec.answers[1].correct, isFalse);
  });

  testWidgets('removing an option drops it from the pool', (tester) async {
    var updated = _questionSlide(
      const QuestionSpec(
        answers: [
          QuestionAnswer(text: 'Een', correct: true),
          QuestionAnswer(text: 'Twee'),
          QuestionAnswer(text: 'Drie'),
        ],
      ),
    );

    await _pump(tester, _host(updated, (s) => updated = s));

    await tester.tap(find.byTooltip('Verwijder').first);
    await tester.pump();

    final spec = QuestionSpec.parse(updated.customMarkdown);
    expect(spec.answers.map((a) => a.text).toList(), ['Twee', 'Drie']);
  });

  testWidgets('multiple-correct kind shows its guidance and keeps checkboxes', (
    tester,
  ) async {
    var updated = _questionSlide(QuestionSpec.defaultMultipleChoice());

    await _pump(tester, _host(updated, (s) => updated = s));

    await tester.tap(find.byType(DropdownButtonFormField<QuestionKind>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Meerdere juiste antwoorden').last);
    await tester.pumpAndSettle();

    expect(
      QuestionSpec.parse(updated.customMarkdown).kind,
      QuestionKind.multipleCorrect,
    );
    expect(
      find.textContaining('Markeer alle juiste antwoorden'),
      findsOneWidget,
    );
    expect(find.byType(Checkbox), findsWidgets);
  });

  testWidgets('ordering kind reorders answers with the down arrow', (
    tester,
  ) async {
    var updated = _questionSlide(
      const QuestionSpec(
        answers: [
          QuestionAnswer(text: 'Een'),
          QuestionAnswer(text: 'Twee'),
          QuestionAnswer(text: 'Drie'),
        ],
      ),
    );

    await _pump(tester, _host(updated, (s) => updated = s));

    await tester.tap(find.byType(DropdownButtonFormField<QuestionKind>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Volgorde').last);
    await tester.pumpAndSettle();

    // Ordering rows expose up/down; there are no correctness checkboxes.
    expect(find.byType(Checkbox), findsNothing);
    await tester.tap(find.byTooltip('Omlaag').first);
    await tester.pump();

    final spec = QuestionSpec.parse(updated.customMarkdown);
    expect(spec.kind, QuestionKind.ordering);
    expect(spec.answers.map((a) => a.text).toList(), ['Twee', 'Een', 'Drie']);
  });

  testWidgets('option count can be increased and decreased', (tester) async {
    var updated = _questionSlide(
      const QuestionSpec(
        optionCount: 4,
        answers: [
          QuestionAnswer(text: 'A', correct: true),
          QuestionAnswer(text: 'B'),
        ],
      ),
    );

    await _pump(tester, _host(updated, (s) => updated = s));

    await tester.ensureVisible(find.byTooltip('Optie toevoegen'));
    await tester.tap(find.byTooltip('Optie toevoegen'));
    await tester.pump();
    expect(QuestionSpec.parse(updated.customMarkdown).optionCount, 5);

    await tester.tap(find.byTooltip('Optie verwijderen'));
    await tester.pump();
    expect(QuestionSpec.parse(updated.customMarkdown).optionCount, 4);
  });

  testWidgets('time-limit field flows into the spec', (tester) async {
    var updated = _questionSlide(
      const QuestionSpec(
        prompt: 'Vraag',
        answers: [
          QuestionAnswer(text: 'A', correct: true),
          QuestionAnswer(text: 'B'),
        ],
      ),
    );

    await _pump(tester, _host(updated, (s) => updated = s));

    // The prompt is a MarkdownEditorField; the time limit stays an EditorField.
    final timeLimitField = find.descendant(
      of: find.byType(EditorField).first,
      matching: find.byType(TextField),
    );
    await tester.ensureVisible(timeLimitField);
    await tester.enterText(timeLimitField, '45');
    await tester.pump();

    expect(QuestionSpec.parse(updated.customMarkdown).timeLimitSeconds, 45);
  });

  testWidgets('on-wrong toggle switches to lock-and-continue', (tester) async {
    var updated = _questionSlide(
      const QuestionSpec(
        answers: [
          QuestionAnswer(text: 'A', correct: true),
          QuestionAnswer(text: 'B'),
        ],
      ),
    );

    await _pump(tester, _host(updated, (s) => updated = s));

    await tester.ensureVisible(find.text('Doorgaan toestaan'));
    await tester.tap(find.text('Doorgaan toestaan'));
    await tester.pump();

    expect(
      QuestionSpec.parse(updated.customMarkdown).onWrong,
      QuestionOnWrong.lockAndContinue,
    );
    expect(
      find.text('Fout = wel doorgaan, maar niet opnieuw doen.'),
      findsOneWidget,
    );
  });

  // ── De twee soorten zonder antwoordlijst ─────────────────────────────────

  testWidgets(
    'kiezen voor twee afbeeldingen maakt twee plekken en één juiste',
    (tester) async {
      var updated = _questionSlide(QuestionSpec.defaultMultipleChoice());

      await _pump(tester, _host(updated, (s) => updated = s));

      await tester.tap(find.byType(DropdownButtonFormField<QuestionKind>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Twee afbeeldingen').last);
      await tester.pumpAndSettle();

      final spec = QuestionSpec.parse(updated.customMarkdown);
      expect(spec.kind, QuestionKind.imagePair);
      expect(spec.answers.length, greaterThanOrEqualTo(questionImagePairCount));
      // Precies één juiste, anders valt er niets aan te wijzen.
      expect(spec.answers.where((a) => a.correct).length, 1);
      expect(find.text('Afbeelding 1'), findsWidgets);
      expect(find.text('Afbeelding 2'), findsWidgets);
      // Geen getrokken opties, dus ook geen teller ervoor.
      expect(find.byTooltip('Optie toevoegen'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('de juiste kant omzetten verplaatst het vinkje', (tester) async {
    var updated = _questionSlide(
      const QuestionSpec(
        kind: QuestionKind.imagePair,
        answers: [
          QuestionAnswer(image: 'a.png', correct: true),
          QuestionAnswer(image: 'b.png'),
        ],
      ),
    );

    await _pump(tester, _host(updated, (s) => updated = s));

    await tester.tap(find.text('Afbeelding 2').last);
    await tester.pumpAndSettle();

    final spec = QuestionSpec.parse(updated.customMarkdown);
    expect(spec.answers[0].correct, isFalse);
    expect(spec.answers[1].correct, isTrue);
  });

  testWidgets('de overeenkomstdrempel is te verschuiven', (tester) async {
    var updated = _questionSlide(
      const QuestionSpec(
        kind: QuestionKind.openText,
        prompt: 'Waar hoort een wachtwoord?',
        answers: [QuestionAnswer(text: 'in de kluis', correct: true)],
        similarityThreshold: 0.9,
      ),
    );

    await _pump(tester, _host(updated, (s) => updated = s));

    expect(find.text('90%'), findsOneWidget);
    expect(
      find.text('Vereiste overeenkomst met het juiste antwoord'),
      findsOne,
    );

    // Naar het uiterste linkerpunt slepen zet de drempel op het minimum.
    final slider = find.byType(Slider);
    final box = tester.getRect(slider);
    await tester.dragFrom(box.center, Offset(-box.width, 0));
    await tester.pumpAndSettle();

    expect(
      QuestionSpec.parse(updated.customMarkdown).similarityThreshold,
      questionMinSimilarity,
    );
  });

  testWidgets('zonder aangevinkt antwoord waarschuwt de getypte vraag', (
    tester,
  ) async {
    var updated = _questionSlide(
      const QuestionSpec(
        kind: QuestionKind.openText,
        answers: [QuestionAnswer(text: 'iets')],
      ),
    );

    await _pump(tester, _host(updated, (s) => updated = s));

    expect(
      find.text('Vink minstens één goed gerekend antwoord aan.'),
      findsOneWidget,
    );
  });

  testWidgets('editing the prompt flows into the spec', (tester) async {
    var updated = _questionSlide(
      const QuestionSpec(
        prompt: 'Oude vraag',
        answers: [
          QuestionAnswer(text: 'A', correct: true),
          QuestionAnswer(text: 'B'),
        ],
      ),
    );

    await _pump(tester, _host(updated, (s) => updated = s));

    final promptField = find.descendant(
      of: find.byType(MarkdownEditorField).first,
      matching: find.byType(TextField),
    );
    await tester.enterText(promptField, 'Nieuwe vraag');
    await tester.pump();

    expect(QuestionSpec.parse(updated.customMarkdown).prompt, 'Nieuwe vraag');
  });
}
