import 'dart:ui' show AppExitResponse, Size;

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/app.dart';
import 'package:ocideck/l10n/app_localizations.dart';
import 'package:ocideck/models/deck.dart';
import 'package:ocideck/models/slide.dart';
import 'package:ocideck/platform/native_window.dart';
import 'package:ocideck/state/tabs_provider.dart';
import 'package:ocideck/widgets/app_shell.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Cmd+Q, Dock-Stop en uitloggen op macOS gaan via
/// `System.requestAppExit`, niet via de willClose-hook van het venster.
/// Zonder een luisteraar in de shell sluit de app meteen: geen vraag over
/// niet-opgeslagen werk, en de opruimstappen in `_destroy` lopen niet (#2678).
void main() {
  setUp(() {
    AppLocalizations.setActiveLanguageCode('nl');
    SharedPreferences.setMockInitialValues({'app_consent_accepted': true});
    debugResetAppExitForTest();
    debugQuitAppSkipsNative = true;
  });

  tearDown(debugResetAppExitForTest);

  Future<ProviderContainer> pumpShell(WidgetTester tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    await tester.binding.setSurfaceSize(const Size(1600, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(const ProviderScope(child: OciDeckApp()));
    await tester.pumpAndSettle();
    return ProviderScope.containerOf(tester.element(find.byType(AppShell)));
  }

  Future<void> onMacos(
    WidgetTester tester,
    Future<void> Function(ProviderContainer container) body,
  ) async {
    final container = await pumpShell(tester);
    try {
      await body(container);
    } finally {
      // De binding controleert deze vlag ná de testcallback en vóór
      // addTearDown. Hij moet dus hier al weg zijn.
      debugDefaultTargetPlatformOverride = null;
    }
  }

  testWidgets(
    'vuil tabblad: een afsluitverzoek annuleert en toont de opslaan-dialoog (#2678)',
    (tester) async {
      await onMacos(tester, (container) async {
        final tab = container.read(tabsProvider).current!;
        tab.deckNotifier.loadDeck(
          Deck(title: 'Concept', slides: [Slide.create(SlideType.title)]),
          isDirty: true,
        );
        await tester.pump();

        final response = await tester.binding.handleRequestAppExit();
        expect(response, AppExitResponse.cancel);

        await tester.pump();
        expect(find.text('Niet-opgeslagen wijzigingen'), findsOneWidget);

        // Een tweede verzoek terwijl de dialoog open staat start geen tweede
        // bewaking: de eerste dialoog blijft de enige.
        final again = await tester.binding.handleRequestAppExit();
        expect(again, AppExitResponse.cancel);
        await tester.pump();
        expect(find.text('Niet-opgeslagen wijzigingen'), findsOneWidget);
      });
    },
  );

  testWidgets(
    'schoon tabblad: een afsluitverzoek annuleert en loopt door naar quitApp (#2678)',
    (tester) async {
      await onMacos(tester, (_) async {
        expect(
          hasAppExitHandler,
          isTrue,
          reason:
              'platform=$defaultTargetPlatform quitApp-aanroepen=$debugQuitAppCalls',
        );

        // Schijf en endOfFrame lopen alleen door als het verzoek zelf
        // buiten de nep-klok start.
        late final AppExitResponse response;
        await tester.runAsync(() async {
          response = await tester.binding.handleRequestAppExit();
          for (var i = 0; i < 200 && debugQuitAppCalls == 0; i++) {
            await tester.pump(const Duration(milliseconds: 20));
            await Future<void>.delayed(const Duration(milliseconds: 20));
          }
        });
        expect(response, AppExitResponse.cancel);
        expect(find.text('Niet-opgeslagen wijzigingen'), findsNothing);

        // Het sluiten van het laatste venster vraagt nog eens om terminate.
        // Die tweede vraag moet door, anders blijft de app na doorgaan open.
        final followUp = await tester.binding.handleRequestAppExit();
        expect(followUp, AppExitResponse.exit);
        expect(debugQuitAppCalls, 1);
      });
    },
  );
}
