import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/l10n/app_localizations.dart';
import 'package:ocideck/services/import/models/slide_failure_policy.dart';
import 'package:ocideck/services/import/pipeline/problem_slide.dart';
import 'package:ocideck/widgets/dialogs/import_decision_dialog.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// De beslisdialoog van #812.
///
/// Het scherpste punt zit in [ImportDecisionDialog.ask]: afbreken moet ook
/// werkelijk afbreken. Een eerdere versie zette een `null` (afbreken, of het
/// venster wegklikken) stilzwijgend om in "ga door met de standaardkeuze" —
/// waarmee de vraag een schijnvertoning was.
void main() {
  setUp(() {
    AppLocalizations.setActiveLanguageCode('nl');
    SharedPreferences.setMockInitialValues(const {});
  });

  /// Een echt vensterformaat: de standaard 800x600 van de testomgeving is
  /// smaller dan elk scherm waarop dit dialoog werkelijk verschijnt.
  Future<void> roomyWindow(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(1200, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
  }

  const problems = [
    ProblemSlide(
      sourceSlideNumber: 3,
      title: 'Kwartaalcijfers',
      issueDescriptions: ['Audio "intro.m4a": niet overgenomen'],
      hadImage: true,
      suggestedPolicy: SlideFailurePolicy.imageOnly,
    ),
    ProblemSlide(
      sourceSlideNumber: 5,
      issueDescriptions: ['Animatie: niet overgenomen'],
      hadImage: false,
    ),
  ];

  Future<Map<int, SlideFailurePolicy>?> show(
    WidgetTester tester, {
    List<ProblemSlide> given = problems,
  }) async {
    Map<int, SlideFailurePolicy>? result;
    var done = false;
    await roomyWindow(tester);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () async {
                result = await ImportDecisionDialog.ask(context, given);
                done = true;
              },
              child: const Text('start'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('start'));
    await tester.pumpAndSettle();
    return Future.value(done ? result : null);
  }

  testWidgets('zonder probleemdia’s verschijnt er niets', (tester) async {
    await show(tester, given: const []);
    expect(find.byType(AlertDialog), findsNothing);
  });

  testWidgets('de dia’s staan erin, met de reden erbij', (tester) async {
    await show(tester);
    expect(find.textContaining('Kwartaalcijfers'), findsOneWidget);
    expect(find.textContaining('intro.m4a'), findsOneWidget);
    expect(find.textContaining('Animatie'), findsOneWidget);
  });

  testWidgets('alleen-de-afbeelding wordt niet aangeboden zonder afbeelding', (
    tester,
  ) async {
    await show(tester);
    // Dia 3 heeft een afbeelding, dia 5 niet: de keuze hoort dus één keer te
    // bestaan, niet twee keer. Een knop die niets kan doen is een knop die liegt.
    expect(
      find.widgetWithText(ChoiceChip, 'Alleen de afbeelding'),
      findsOneWidget,
    );
    expect(find.widgetWithText(ChoiceChip, 'Overslaan'), findsNWidgets(2));
  });

  testWidgets('het voorstel staat voorgeselecteerd', (tester) async {
    await show(tester);
    final chip = tester.widget<ChoiceChip>(
      find.widgetWithText(ChoiceChip, 'Alleen de afbeelding'),
    );
    expect(chip.selected, isTrue);
  });

  testWidgets('afbreken breekt af — en levert géén standaardkeuze op', (
    tester,
  ) async {
    Map<int, SlideFailurePolicy>? captured;
    var called = false;
    await roomyWindow(tester);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () async {
                captured = await ImportDecisionDialog.ask(context, problems);
                called = true;
              },
              child: const Text('start'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('start'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Import afbreken'));
    await tester.pumpAndSettle();

    expect(called, isTrue);
    expect(captured, isNull, reason: 'null betekent: niet importeren');
  });

  testWidgets('"voor alle dia’s" zet alles in één keer om', (tester) async {
    Map<int, SlideFailurePolicy>? captured;
    await roomyWindow(tester);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () async {
                captured = await ImportDecisionDialog.ask(context, problems);
              },
              child: const Text('start'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('start'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(OutlinedButton, 'Overslaan'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Importeren'));
    await tester.pumpAndSettle();

    expect(captured, {2: SlideFailurePolicy.skip, 4: SlideFailurePolicy.skip});
  });

  testWidgets('"niet meer vragen" slaat de vraag voortaan over', (
    tester,
  ) async {
    await roomyWindow(tester);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () => ImportDecisionDialog.ask(context, problems),
              child: const Text('start'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('start'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Niet meer vragen'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Importeren'));
    await tester.pumpAndSettle();

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool('importDecisionSkipAsking'), isTrue);

    // En de volgende keer verschijnt er niets meer.
    await tester.tap(find.text('start'));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
  });
}
