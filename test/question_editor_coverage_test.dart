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
import 'package:ocideck/widgets/editors/question_editor.dart';

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

    // EditorFields in order: [prompt, time-limit].
    final timeLimitField = find.descendant(
      of: find.byType(EditorField).at(1),
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
      of: find.byType(EditorField).first,
      matching: find.byType(TextField),
    );
    await tester.enterText(promptField, 'Nieuwe vraag');
    await tester.pump();

    expect(QuestionSpec.parse(updated.customMarkdown).prompt, 'Nieuwe vraag');
  });
}
