import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/models/deck.dart';
import 'package:ocideck/models/slide.dart';
import 'package:ocideck/state/deck_provider.dart';
import 'package:ocideck/state/editor_provider.dart';
import 'package:ocideck/state/settings_provider.dart';
import 'package:ocideck/theme/app_theme.dart';
import 'package:ocideck/widgets/panels/slide_list_panel.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// "Kopieer als afbeelding" is an export-equivalent egress: it renders a slide
/// to the system clipboard. It must honour the same classification gate as
/// [ExportService.export]; otherwise a RED deck under an AMBER release ceiling
/// could be exfiltrated as a PNG.
void main() {
  testWidgets(
    'copy-as-image is blocked when the deck exceeds the release ceiling',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final deckNotifier = container.read(deckProvider.notifier);
      deckNotifier.newDeck('Test');
      deckNotifier.addSlide(SlideType.bullets);
      deckNotifier.updateInfo(tlp: TlpLevel.red);
      container.read(editorProvider.notifier).select(0);

      // Release ceiling AMBER < deck RED → must block.
      await container
          .read(settingsProvider.notifier)
          .setMaxReleaseExportTlp('amber');

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: AppTheme.light,
            home: const Scaffold(
              body: SizedBox(width: 320, height: 600, child: SlideListPanel()),
            ),
          ),
        ),
      );
      await tester.pump();

      // Open the first thumbnail's context menu and pick "copy as image".
      await tester.tap(find.byIcon(Icons.more_vert).first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Kopieer als afbeelding'));
      await tester.pump();

      // The gate returns before rasterisation, so the "rendering…" snackbar is
      // never shown; only the block reason appears.
      expect(find.textContaining('vrijgaveniveau'), findsOneWidget);
      expect(find.text('Slide renderen…'), findsNothing);
    },
  );

  testWidgets('copy-as-image weegt ook de markering van de dia zelf', (
    tester,
  ) async {
    // Het dek staat op GREEN, deze ene dia op RED. Op `deck.tlp` alleen keek
    // de poort langs de dia die juist de strengste markering droeg.
    SharedPreferences.setMockInitialValues({});
    final container = ProviderContainer();
    addTearDown(container.dispose);

    final deckNotifier = container.read(deckProvider.notifier);
    deckNotifier.newDeck('Test');
    deckNotifier.addSlide(SlideType.bullets);
    deckNotifier.updateInfo(tlp: TlpLevel.green);
    deckNotifier.updateSlide(
      0,
      container.read(deckProvider).deck!.slides[0].copyWith(tlp: TlpLevel.red),
    );
    container.read(editorProvider.notifier).select(0);

    await container
        .read(settingsProvider.notifier)
        .setMaxReleaseExportTlp('amber');

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: AppTheme.light,
          home: const Scaffold(
            body: SizedBox(width: 320, height: 600, child: SlideListPanel()),
          ),
        ),
      ),
    );
    await tester.pump();

    await tester.tap(find.byIcon(Icons.more_vert).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Kopieer als afbeelding'));
    await tester.pump();

    expect(find.textContaining('vrijgaveniveau'), findsOneWidget);
    expect(find.text('Slide renderen…'), findsNothing);
  });
}
