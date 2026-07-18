import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/models/deck.dart';
import 'package:ocideck/widgets/dialogs/presentation_info_dialog.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

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
