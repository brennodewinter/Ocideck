import 'dart:typed_data';

import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/l10n/app_localizations.dart';
import 'package:ocideck/services/browser_deck_store.dart';
import 'package:ocideck/state/deck_provider.dart';
import 'package:ocideck/widgets/dialogs/browser_storage_dialog.dart';
import 'package:ocideck/widgets/dialogs/settings/browser_storage_section.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    AppLocalizations.setActiveLanguageCode('nl');
  });

  testWidgets('browser warning refuses without storing or marking clean', (
    tester,
  ) async {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    final notifier = DeckNotifier(
      c.read(markdownServiceProvider),
      c.read(fileServiceProvider),
    )..newDeck('Private');
    addTearDown(notifier.dispose);
    bool? result;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () async => result = await chooseBrowserSave(
                context,
                notifier,
                c.read(fileServiceProvider),
              ),
              child: const Text('save'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('save'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('In browser bewaren'));
    await tester.pumpAndSettle();
    expect(find.textContaining('lokale schijf is veiliger'), findsOneWidget);
    await tester.tap(find.text('Annuleren'));
    await tester.pumpAndSettle();
    expect(result, isNull);
    expect(await BrowserDeckStore().list(), isEmpty);
    expect(notifier.currentState.isDirty, isTrue);
  });

  testWidgets('download remains an explicit alternative without browser copy', (
    tester,
  ) async {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    final notifier = DeckNotifier(
      c.read(markdownServiceProvider),
      c.read(fileServiceProvider),
    )..newDeck('Download');
    addTearDown(notifier.dispose);
    bool? result;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () async => result = await chooseBrowserSave(
                context,
                notifier,
                c.read(fileServiceProvider),
              ),
              child: const Text('save'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('save'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Als bestand downloaden'));
    await tester.pumpAndSettle();
    expect(result, isFalse);
    expect(await BrowserDeckStore().list(), isEmpty);
  });

  testWidgets('stored copies can be inspected and deletion can be cancelled', (
    tester,
  ) async {
    await BrowserDeckStore().save(
      'Keep my presentation',
      Uint8List.fromList([1]),
    );
    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(child: BrowserStorageSection()),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Keep my presentation'), findsOneWidget);
    await tester.tap(find.byTooltip('Verwijderen'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Annuleren'));
    await tester.pumpAndSettle();
    expect(await BrowserDeckStore().list(), hasLength(1));
    await tester.tap(find.byTooltip('Verwijderen'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ElevatedButton, 'Verwijderen'));
    await tester.pumpAndSettle();
    expect(await BrowserDeckStore().list(), isEmpty);
  });

  test('a stale saved snapshot cannot mark newer edits clean', () {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    final notifier = DeckNotifier(
      c.read(markdownServiceProvider),
      c.read(fileServiceProvider),
    )..newDeck('First');
    addTearDown(notifier.dispose);
    final snapshot = notifier.currentState;
    notifier.browserStorageId = 'previous-copy';
    notifier.newDeck('Second');
    expect(notifier.browserStorageId, isNull);
    expect(
      notifier.markBrowserSaved(snapshot.deck!, snapshot.revision),
      isFalse,
    );
    expect(notifier.currentState.isDirty, isTrue);
    final current = notifier.currentState;
    expect(notifier.markBrowserSaved(current.deck!, current.revision), isTrue);
    expect(notifier.currentState.isDirty, isFalse);
  });
}
