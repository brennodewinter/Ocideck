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
}
