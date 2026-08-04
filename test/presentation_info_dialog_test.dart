import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/models/deck.dart';
import 'package:ocideck/models/used_tool.dart';
import 'package:ocideck/state/info_safety_provider.dart';
import 'package:ocideck/widgets/dialogs/presentation_info_dialog.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  // De MIAUW-vastleggingsvelden (EIS 4.3.2/4.8.2) horen alleen bij een
  // informatieveiligheidspresentatie. Bij een gewone presentatie zeggen ze
  // niets, dus dan staan ze er niet.
  Finder labelledField(String label) => find.byWidgetPredicate(
    (w) => w is TextField && w.decoration?.labelText == label,
  );

  Future<void> pumpDialog(
    WidgetTester tester, {
    required bool reveal,
    Deck deck = const Deck(title: 'Test'),
  }) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [infoSafetyRevealProvider.overrideWithValue(reveal)],
        child: MaterialApp(
          home: Scaffold(body: PresentationInfoDialog(deck: deck)),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('MIAUW-velden blijven weg als de module uitstaat', (
    tester,
  ) async {
    await pumpDialog(tester, reveal: false);

    expect(labelledField('Gebruikte standaarden'), findsNothing);
    expect(labelledField('Gebruikte hulpmiddelen'), findsNothing);
    // De gewone metadata staat er wél: dit bewijst geen leeg dialoog.
    expect(labelledField('Titel'), findsOneWidget);
  });

  testWidgets('MIAUW-velden verschijnen met de module aan', (tester) async {
    await pumpDialog(tester, reveal: true);

    expect(labelledField('Gebruikte standaarden'), findsOneWidget);
    expect(labelledField('Gebruikte hulpmiddelen'), findsOneWidget);
  });

  // Anders leest een deck dat de gegevens al draagt als dataverlies: de velden
  // zijn dan onvindbaar terwijl de inhoud wel meegaat bij opslaan.
  testWidgets('een deck met ingevulde gegevens toont ze ook zonder module', (
    tester,
  ) async {
    await pumpDialog(
      tester,
      reveal: false,
      deck: const Deck(
        title: 'Test',
        standardsUsed: ['OWASP WSTG@4.2'],
        toolsUsed: [UsedTool(name: 'Burp Suite', version: '2026.4')],
      ),
    );

    expect(labelledField('Gebruikte standaarden'), findsOneWidget);
    expect(labelledField('Gebruikte hulpmiddelen'), findsOneWidget);
  });

  testWidgets('double-clicking date fills in the current date', (tester) async {
    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: PresentationInfoDialog(deck: Deck(title: 'Test')),
          ),
        ),
      ),
    );

    final dateField = find.byWidgetPredicate(
      (widget) =>
          widget is TextField && widget.decoration?.labelText == 'Datum',
    );
    final now = DateTime.now();
    String twoDigits(int value) => value.toString().padLeft(2, '0');
    final expected =
        '${now.year}-${twoDigits(now.month)}-${twoDigits(now.day)}';

    await tester.tap(dateField);
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tap(dateField);
    await tester.pump(const Duration(milliseconds: 100));

    final field = tester.widget<TextField>(dateField);
    expect(field.controller!.text, expected);
  });

  testWidgets('the today button fills in the current date', (tester) async {
    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: PresentationInfoDialog(deck: Deck(title: 'Test')),
          ),
        ),
      ),
    );

    final now = DateTime.now();
    String twoDigits(int value) => value.toString().padLeft(2, '0');
    final expected =
        '${now.year}-${twoDigits(now.month)}-${twoDigits(now.day)}';

    // De knop maakt de dubbelklik-functie zichtbaar (#1210): hij hangt in de
    // suffix van het datumveld en vult dezelfde datum in.
    final todayButton = tester.widget<IconButton>(
      find.byWidgetPredicate(
        (widget) =>
            widget is IconButton &&
            widget.icon is Icon &&
            (widget.icon as Icon).icon == Icons.today,
      ),
    );
    expect(todayButton.tooltip, isNotEmpty);

    // De knop rechtstreeks aanroepen in plaats van te tikken: het datumveld
    // draagt ook een onDoubleTap, en die recognizer houdt de arena open tot de
    // dubbelklik-timer afloopt, waardoor een gesimuleerde enkele tik in de
    // fake-async testomgeving de knopdruk niet betrouwbaar laat winnen. De
    // gesture-route naar dezelfde datum staat al in de dubbelklik-test hierboven.
    todayButton.onPressed!();
    await tester.pump();

    final dateField = find.byWidgetPredicate(
      (widget) =>
          widget is TextField && widget.decoration?.labelText == 'Datum',
    );
    final field = tester.widget<TextField>(dateField);
    expect(field.controller!.text, expected);
  });

  testWidgets('gekozen stijlprofiel komt in het resultaat', (tester) async {
    Future<PresentationInfo?>? result;
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: ElevatedButton(
                onPressed: () => result = PresentationInfoDialog.show(
                  context,
                  const Deck(title: 'Test'),
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    // De settings-provider laadt async; wacht tot de profielen er zijn.
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pumpAndSettle();

    // De dialoog scrollt; de profielkiezer staat onder de vouw zodra er velden
    // bijkomen. Eerst in beeld brengen, zoals een gebruiker ook zou doen —
    // anders opent het dropdown-menu buiten het testvenster.
    await tester.ensureVisible(find.byType(DropdownButton<String>).first);
    await tester.pumpAndSettle();
    await tester.tap(find.byType(DropdownButton<String>).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Standaard').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Opslaan'));
    await tester.pumpAndSettle();

    final info = await result!;
    expect(info, isNotNull);
    expect(info!.styleProfileName, 'Standaard');
  });

  testWidgets('play-only toggle komt in het resultaat', (tester) async {
    Future<PresentationInfo?>? result;
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: ElevatedButton(
                onPressed: () => result = PresentationInfoDialog.show(
                  context,
                  const Deck(title: 'Test'),
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pumpAndSettle();

    // Scroll de schakelaar in beeld en zet 'Alleen afspelen' aan.
    await tester.scrollUntilVisible(
      find.text('Alleen afspelen (vergrendeld)'),
      100,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('Alleen afspelen (vergrendeld)'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Opslaan'));
    await tester.pumpAndSettle();

    final info = await result!;
    expect(info, isNotNull);
    expect(info!.playOnly, isTrue);
  });

  testWidgets(
    "'Alleen afspelen' zet de tijden-overzichtschakelaar buiten werking",
    (tester) async {
      // Een schakelaar die aan lijkt te staan maar niets doet, is erger dan
      // geen schakelaar: bij een vergrendeld deck verschijnt het overzicht
      // hoe dan ook niet.
      await pumpDialog(
        tester,
        reveal: false,
        deck: const Deck(title: 'Test', showRehearsalSummary: true),
      );

      SwitchListTile summarySwitch() => tester.widget<SwitchListTile>(
        find.ancestor(
          of: find.text('Tijden-overzicht tonen na afloop'),
          matching: find.byType(SwitchListTile),
        ),
      );

      expect(summarySwitch().value, isTrue);
      expect(summarySwitch().onChanged, isNotNull);

      await tester.scrollUntilVisible(
        find.text('Alleen afspelen (vergrendeld)'),
        100,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.text('Alleen afspelen (vergrendeld)'));
      await tester.pumpAndSettle();

      expect(summarySwitch().value, isFalse);
      expect(summarySwitch().onChanged, isNull);
      expect(
        find.textContaining('deze schakelaar doet dan niets'),
        findsOneWidget,
      );
    },
  );

  testWidgets('120 min-preset komt in seconden in het resultaat', (
    tester,
  ) async {
    // Een ruim venster zodat de hele dropdown-lijst (incl. de laatste items)
    // in beeld rendert en aantikbaar is.
    tester.view.physicalSize = const Size(1200, 2600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    Future<PresentationInfo?>? result;
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: ElevatedButton(
                onPressed: () => result = PresentationInfoDialog.show(
                  context,
                  const Deck(title: 'Test'),
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pumpAndSettle();

    await tester.tap(find.byType(DropdownButton<int>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('120 min').last);
    await tester.pumpAndSettle();

    await tester.tap(find.text('Opslaan'));
    await tester.pumpAndSettle();

    final info = await result!;
    expect(info, isNotNull);
    expect(info!.presentationTargetSeconds, 7200);
  });

  testWidgets('aangepaste doeltijd komt in seconden in het resultaat', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 2600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    Future<PresentationInfo?>? result;
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: ElevatedButton(
                onPressed: () => result = PresentationInfoDialog.show(
                  context,
                  const Deck(title: 'Test'),
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pumpAndSettle();

    // Kies de custom-optie en vul een eigen tijd in minuten in.
    await tester.tap(find.byType(DropdownButton<int>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Aangepast…').last);
    await tester.pumpAndSettle();

    final customField = find.byWidgetPredicate(
      (widget) =>
          widget is TextField &&
          widget.decoration?.labelText == 'Aangepaste tijd',
    );
    expect(customField, findsOneWidget);
    await tester.enterText(customField, '100');
    await tester.pump();

    await tester.tap(find.text('Opslaan'));
    await tester.pumpAndSettle();

    final info = await result!;
    expect(info, isNotNull);
    expect(info!.presentationTargetSeconds, 100 * 60);
  });
}
