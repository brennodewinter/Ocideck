import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/app.dart';
import 'package:ocideck/l10n/app_localizations.dart';
import 'package:ocideck/models/deck.dart';
import 'package:ocideck/models/slide.dart';
import 'package:ocideck/state/tabs_provider.dart';
import 'package:ocideck/widgets/app_shell.dart';
import 'package:ocideck/widgets/editors/bullets_editor.dart';
import 'package:ocideck/widgets/editors/code_editor.dart';
import 'package:ocideck/widgets/editors/editor_text_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Een cursor die verspringt is geen bewerking.
///
/// Een [TextEditingController] wekt zijn luisteraars ook wanneer alleen de
/// selectie wijzigt. De dia-editors lazen élke melding als een bewerking, dus
/// één klik in een tekstveld schreef een ongewijzigde dia terug: de presentatie
/// werd 'gewijzigd', er kwam een lege stap in ongedaan-maken bij, en de
/// niet-opgeslagen-stip kwam meteen ná het opslaan weer op.
Widget _testApp(Widget child) {
  return MaterialApp(
    localizationsDelegates: const [
      AppLocalizations.delegate,
      GlobalMaterialLocalizations.delegate,
      FlutterQuillLocalizations.delegate,
    ],
    supportedLocales: AppLocalizations.supportedLocales,
    home: Scaffold(body: child),
  );
}

void main() {
  setUp(() {
    AppLocalizations.setActiveLanguageCode('nl');
    SharedPreferences.setMockInitialValues({'app_consent_accepted': true});
  });

  // De klacht zoals de gebruiker hem meldt: opslaan, en de stip staat er meteen
  // weer. Deze toets legt het vast op de plek waar hij zichtbaar was — het hele
  // scherm, met een schoon deck — en niet alleen in de losse editor.
  testWidgets('een klik in de editor maakt een schoon deck niet vuil', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1600, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(const ProviderScope(child: OciDeckApp()));
    await tester.pumpAndSettle();

    final container = ProviderScope.containerOf(
      tester.element(find.byType(AppShell)),
    );
    final deckNotifier = container.read(tabsProvider).current!.deckNotifier;
    deckNotifier.loadDeck(
      Deck(
        title: 'Proef',
        slides: [
          Slide.create(
            SlideType.bullets,
          ).copyWith(title: 'Eerste dia', bullets: ['Eerste punt']),
        ],
      ),
      filePath: '/tmp/proef.md',
    );
    await tester.pumpAndSettle();
    expect(deckNotifier.currentState.isDirty, isFalse);

    await tester.tap(find.widgetWithText(TextField, 'Eerste punt'));
    await tester.pumpAndSettle();

    expect(
      deckNotifier.currentState.isDirty,
      isFalse,
      reason: 'de cursor in een veld zetten is geen wijziging',
    );
  });

  testWidgets('klikken in een opsommingsveld werkt de dia niet bij', (
    tester,
  ) async {
    final slide = Slide.create(
      SlideType.bullets,
    ).copyWith(title: 'Titel', bullets: ['Eerste punt']);
    var updates = 0;

    await tester.pumpScoped(
      _testApp(BulletsEditor(slide: slide, onUpdate: (_) => updates++)),
    );
    await tester.pumpAndSettle();
    updates = 0; // de opbouw zelf telt niet mee

    await tester.tap(find.widgetWithText(TextField, 'Eerste punt'));
    await tester.pumpAndSettle();

    expect(updates, 0, reason: 'de cursor verzetten is geen bewerking');
  });

  testWidgets('klikken in het titelveld werkt de dia niet bij', (tester) async {
    final slide = Slide.create(
      SlideType.bullets,
    ).copyWith(title: 'Titel', bullets: ['Eerste punt']);
    var updates = 0;

    await tester.pumpScoped(
      _testApp(BulletsEditor(slide: slide, onUpdate: (_) => updates++)),
    );
    await tester.pumpAndSettle();
    updates = 0;

    await tester.tap(find.widgetWithText(TextField, 'Titel'));
    await tester.pumpAndSettle();

    expect(updates, 0, reason: 'de cursor verzetten is geen bewerking');
  });

  testWidgets('klikken in het codeveld werkt de dia niet bij', (tester) async {
    // De code-editor hangt zijn luisteraar als losse closure op, niet als
    // benoemde methode — een vorm die bij het filteren makkelijk overgeslagen
    // wordt, en dus een eigen toets verdient.
    final slide = Slide.create(
      SlideType.code,
    ).copyWith(title: 'Titel', customMarkdown: 'print(1);');
    var updates = 0;

    await tester.pumpScoped(
      _testApp(CodeEditor(slide: slide, onUpdate: (_) => updates++)),
    );
    await tester.pumpAndSettle();
    updates = 0;

    await tester.tap(find.widgetWithText(TextField, 'print(1);'));
    await tester.pumpAndSettle();

    expect(updates, 0, reason: 'de cursor verzetten is geen bewerking');
  });

  group('EditorTextController', () {
    test('meldt tekstwijzigingen, geen cursorwissels', () {
      final controller = EditorTextController(text: 'begin');
      addTearDown(controller.dispose);
      var textChanges = 0;
      var allChanges = 0;
      controller.addTextListener(() => textChanges++);
      controller.addListener(() => allChanges++);

      controller.selection = const TextSelection.collapsed(offset: 2);
      expect(textChanges, 0, reason: 'alleen de cursor verschoof');
      expect(allChanges, 1, reason: 'het tekstveld hoort dit wél te horen');

      controller.text = 'einde';
      expect(textChanges, 1);
      expect(allChanges, 2);
    });

    test('een afgemelde luisteraar hoort niets meer', () {
      final controller = EditorTextController(text: '');
      addTearDown(controller.dispose);
      var changes = 0;
      void onChanged() => changes++;
      controller.addTextListener(onChanged);
      controller.text = 'een';
      controller.removeTextListener(onChanged);
      controller.text = 'twee';

      expect(changes, 1);
    });
  });

  testWidgets('typen werkt de dia wél bij', (tester) async {
    final slide = Slide.create(
      SlideType.bullets,
    ).copyWith(title: 'Titel', bullets: ['Eerste punt']);
    var updates = 0;
    Slide? last;

    await tester.pumpScoped(
      _testApp(
        BulletsEditor(
          slide: slide,
          onUpdate: (s) {
            updates++;
            last = s;
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    updates = 0;

    await tester.enterText(
      find.widgetWithText(TextField, 'Eerste punt'),
      'Tweede punt',
    );
    await tester.pumpAndSettle();

    expect(updates, greaterThan(0));
    expect(last?.bullets, ['Tweede punt']);
  });
}

/// De editors lezen de editorstate; een Riverpod-consumer zonder scope gooit.
extension on WidgetTester {
  Future<void> pumpScoped(Widget child) =>
      pumpWidget(ProviderScope(child: child));
}
