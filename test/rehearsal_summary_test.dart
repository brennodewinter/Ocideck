import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/models/question.dart';
import 'package:ocideck/models/rehearsal.dart';
import 'package:ocideck/models/settings.dart';
import 'package:ocideck/models/slide.dart';
import 'package:ocideck/widgets/presentation/fullscreen_presenter.dart';
import 'package:ocideck/widgets/presentation/rehearsal_summary.dart';

/// Het tijdenoverzicht na afloop: wat er in staat, en wanneer het er juist
/// niet hoort te zijn.
Widget _wrap(Widget child) => MaterialApp(
  localizationsDelegates: const [
    ...GlobalMaterialLocalizations.delegates,
    FlutterQuillLocalizations.delegate,
  ],
  home: child,
);

Slide _slide(String id, String title) =>
    Slide(id: id, type: SlideType.bullets, title: title, bullets: const ['a']);

Future<void> _showSummary(
  WidgetTester tester, {
  required RehearsalRun run,
  required List<Slide> slides,
}) async {
  await tester.pumpWidget(
    _wrap(
      Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () =>
                showRehearsalSummary(context, run: run, slides: slides),
            child: const Text('toon'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('toon'));
  await tester.pumpAndSettle();
}

void main() {
  final slides = [
    _slide('s1', 'Inleiding'),
    _slide('q1', 'Vraag over kluizen'),
  ];

  testWidgets('zonder beantwoorde vragen staat er geen vragenblok', (
    tester,
  ) async {
    await _showSummary(
      tester,
      run: const RehearsalRun(
        total: Duration(minutes: 2),
        target: null,
        perSlide: [
          SlideTiming(slideId: 's1', index: 0, spent: Duration(minutes: 2)),
        ],
      ),
      slides: slides,
    );

    expect(find.text('Oefenrun'), findsOneWidget);
    expect(find.text('1. Inleiding'), findsOneWidget);
    expect(find.text('Vragen'), findsNothing);
  });

  testWidgets('elke poging op een vraag krijgt een eigen regel', (
    tester,
  ) async {
    await _showSummary(
      tester,
      run: const RehearsalRun(
        total: Duration(minutes: 3),
        target: null,
        perSlide: [
          SlideTiming(slideId: 's1', index: 0, spent: Duration(minutes: 1)),
          SlideTiming(slideId: 'q1', index: 1, spent: Duration(minutes: 2)),
        ],
        questionAttempts: [
          QuestionAttempt(
            slideId: 'q1',
            index: 1,
            spent: Duration(seconds: 42),
            correct: false,
          ),
          QuestionAttempt(
            slideId: 'q1',
            index: 1,
            spent: Duration(seconds: 8),
            correct: true,
          ),
        ],
      ),
      slides: slides,
    );

    expect(find.text('Vragen'), findsOneWidget);
    // De eerste poging zonder nummer, de tweede met — zo is te zien dat het
    // dezelfde vraag was en niet twee verschillende. Twee treffers: de regel in
    // het slide-overzicht én de eerste poging eronder.
    expect(find.text('2. Vraag over kluizen'), findsNWidgets(2));
    expect(find.text('2. Vraag over kluizen  (2)'), findsOneWidget);
    expect(find.text('00:42'), findsOneWidget);
    expect(find.text('00:08'), findsOneWidget);
  });

  testWidgets('kopiëren neemt de vragen mee', (tester) async {
    final copied = <String>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          copied.add((call.arguments as Map)['text'].toString());
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );

    await _showSummary(
      tester,
      run: const RehearsalRun(
        total: Duration(minutes: 1),
        target: null,
        perSlide: [
          SlideTiming(slideId: 'q1', index: 1, spent: Duration(minutes: 1)),
        ],
        questionAttempts: [
          QuestionAttempt(
            slideId: 'q1',
            index: 1,
            spent: Duration(seconds: 20),
            correct: true,
          ),
        ],
      ),
      slides: slides,
    );

    await tester.tap(find.text('Kopieer'));
    await tester.pumpAndSettle();

    expect(copied, hasLength(1));
    expect(copied.first, contains('Vragen'));
    expect(copied.first, contains('00:20'));
    expect(copied.first, contains('goed'));
  });

  // ── 'Alleen afspelen' ──────────────────────────────────────────────────────

  Widget presenterOverLauncher({required bool playOnly}) => _wrap(
    Scaffold(
      body: Builder(
        builder: (context) => TextButton(
          onPressed: () => Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => FullscreenPresenter(
                slides: [
                  Slide(
                    id: 'q',
                    type: SlideType.question,
                    customMarkdown: const QuestionSpec(
                      kind: QuestionKind.trueFalse,
                      prompt: 'Klopt dit?',
                    ).toBlock(),
                  ),
                ],
                projectPath: null,
                themeProfile: const ThemeProfile(),
                initialIndex: 0,
                showRehearsalSummary: true,
                playOnly: playOnly,
              ),
            ),
          ),
          child: const Text('open'),
        ),
      ),
    ),
  );

  testWidgets('een vergrendeld deck toont het overzicht nooit', (tester) async {
    // De schakelaar staat expliciet aan; de vergrendeling hoort er dwars
    // doorheen te gaan. Wie een deck afspeelt hoort achteraf geen meetrapport
    // over zichzelf te krijgen.
    await tester.pumpWidget(presenterOverLauncher(playOnly: true));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();

    expect(find.text('Oefenrun'), findsNothing);
    expect(find.text('open'), findsOneWidget); // presentatie is gewoon gesloten
  });

  testWidgets('zonder vergrendeling verschijnt het overzicht wél', (
    tester,
  ) async {
    await tester.pumpWidget(presenterOverLauncher(playOnly: false));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();

    expect(find.text('Oefenrun'), findsOneWidget);

    await tester.tap(find.text('Sluiten'));
    await tester.pumpAndSettle();
  });
}
