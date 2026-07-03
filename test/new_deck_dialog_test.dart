import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/l10n/app_localizations.dart';
import 'package:ocideck/widgets/dialogs/new_deck_dialog.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Pompt een minimale app, opent de dialoog en geeft de result-future terug.
Future<Future<NewDeckChoice?>> _pumpAndOpen(WidgetTester tester) async {
  late Future<NewDeckChoice?> result;
  await tester.pumpWidget(
    ProviderScope(
      child: MaterialApp(
        localizationsDelegates: const [AppLocalizations.delegate],
        home: Builder(
          builder: (context) => Scaffold(
            body: ElevatedButton(
              onPressed: () => result = NewDeckDialog.show(context),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
  return result;
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('titel + standaardprofiel bij aanmaken', (tester) async {
    final result = await _pumpAndOpen(tester);
    await tester.enterText(find.byType(TextFormField), 'Mijn briefing');
    await tester.tap(find.text('Aanmaken'));
    await tester.pumpAndSettle();
    final choice = await result;
    expect(choice, isNotNull);
    expect(choice!.title, 'Mijn briefing');
    // Standaard = het globaal geselecteerde profiel (LibreKAT op een verse
    // installatie).
    expect(choice.profileName, 'LibreKAT');
  });

  testWidgets('stijlprofiel is in de dialoog te kiezen', (tester) async {
    final result = await _pumpAndOpen(tester);
    expect(find.byType(DropdownButtonFormField<String>), findsOneWidget);
    await tester.enterText(find.byType(TextFormField), 'Titel');
    await tester.tap(find.byType(DropdownButtonFormField<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Standaard').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Aanmaken'));
    await tester.pumpAndSettle();
    final choice = await result;
    expect(choice!.profileName, 'Standaard');
  });

  testWidgets('lege titel valideert en maakt niets aan', (tester) async {
    await _pumpAndOpen(tester);
    await tester.tap(find.text('Aanmaken'));
    await tester.pumpAndSettle();
    expect(find.text('Vul een titel in'), findsOneWidget);
  });
}
