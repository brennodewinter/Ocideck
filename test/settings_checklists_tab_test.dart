import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/state/info_safety_provider.dart';
import 'package:ocideck/l10n/app_localizations.dart';
import 'package:ocideck/widgets/dialogs/settings_dialog.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// End-to-end test for the Checklists settings tab (feedback #9): create a
/// custom template through the modal editor and see it land as a card.
void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    AppLocalizations.setActiveLanguageCode('nl');
  });

  Finder fieldByLabel(String label) => find.byWidgetPredicate(
    (w) => w is TextField && w.decoration?.labelText == label,
  );
  Finder fieldByHint(String hint) => find.byWidgetPredicate(
    (w) => w is TextField && w.decoration?.hintText == hint,
  );

  testWidgets('creating a template through the editor adds a card', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1500, 1100));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () => SettingsDialog.show(context),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    // De module Informatieveiligheid aanzetten: sinds #648 zit dit oppervlak
    // erachter, en met de module uit hoort het er juist níét te staan.
    await ProviderScope.containerOf(
      tester.element(find.text('open')),
      listen: false,
    ).read(infoSafetyProvider.notifier).enable();
    await tester.pumpAndSettle();
    // Go to the Checklists tab (the nav rail scrolls, so bring it into view).
    await tester.ensureVisible(find.byIcon(Icons.checklist_outlined));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.checklist_outlined));
    await tester.pumpAndSettle();
    expect(find.text('Nog geen eigen checklists.'), findsOneWidget);

    // Open the editor and fill in a template with one test.
    await tester.tap(find.text('Nieuw sjabloon'));
    await tester.pumpAndSettle();

    await tester.enterText(fieldByLabel('Naam'), 'Interne netwerktest');
    await tester.pump();
    await tester.enterText(fieldByHint('ID').first, 'NET-01');
    await tester.enterText(fieldByHint('Test').first, 'Poortscan');
    // The template editor's "Opslaan" — scoped to the AlertDialog so it does not
    // collide with the settings dialog's own save button.
    await tester.tap(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.text('Opslaan'),
      ),
    );
    await tester.pumpAndSettle();

    // The card is shown, and the empty-state text is gone.
    expect(find.text('Interne netwerktest'), findsOneWidget);
    expect(find.text('Nog geen eigen checklists.'), findsNothing);
  });
}
