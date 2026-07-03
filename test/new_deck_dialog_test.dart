import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/models/deck_template.dart';
import 'package:ocideck/widgets/dialogs/new_deck_dialog.dart';

/// Pumps a host with an "open" button and opens the dialog. The eventual
/// dialog result lands in [_Harness.choice] once the dialog is popped.
class _Harness {
  NewDeckChoice? choice;

  Future<void> open(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Center(
            child: ElevatedButton(
              onPressed: () async => choice = await NewDeckDialog.show(context),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }
}

void main() {
  testWidgets('shows the template picker with title field', (tester) async {
    await _Harness().open(tester);
    expect(find.text('Sjabloon'), findsOneWidget);
    expect(find.text('Leeg deck'), findsOneWidget);
    expect(find.text('Korte briefing'), findsOneWidget);
    expect(find.byType(TextFormField), findsOneWidget);
  });

  testWidgets('an empty title blocks creation', (tester) async {
    final harness = _Harness();
    await harness.open(tester);
    await tester.tap(find.text('Aanmaken'));
    await tester.pumpAndSettle();
    expect(find.text('Vul een titel in'), findsOneWidget);
    expect(find.text('Sjabloon'), findsOneWidget); // dialog still open
    expect(harness.choice, isNull);
  });

  testWidgets('returns the title and the tapped template', (tester) async {
    final harness = _Harness();
    await harness.open(tester);
    await tester.enterText(find.byType(TextFormField), '  Kick-off Q3  ');
    await tester.tap(find.text('Projectstart / kick-off'));
    await tester.pump();
    await tester.tap(find.text('Aanmaken'));
    await tester.pumpAndSettle();

    expect(harness.choice, isNotNull);
    expect(harness.choice!.title, 'Kick-off Q3');
    expect(harness.choice!.template.id, 'kickoff');
  });

  testWidgets('defaults to the empty deck template', (tester) async {
    final harness = _Harness();
    await harness.open(tester);
    await tester.enterText(find.byType(TextFormField), 'Mijn deck');
    await tester.tap(find.text('Aanmaken'));
    await tester.pumpAndSettle();

    expect(harness.choice!.template.id, deckTemplates.first.id);
  });

  testWidgets('every template is reachable in the scrollable list', (
    tester,
  ) async {
    await _Harness().open(tester);
    for (final template in deckTemplates) {
      await tester.scrollUntilVisible(
        find.text(template.title),
        60,
        scrollable: find.byType(Scrollable).last,
      );
      expect(find.text(template.title), findsOneWidget);
    }
  });
}
