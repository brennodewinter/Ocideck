import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/models/slide.dart';
import 'package:ocideck/state/deck_provider.dart';
import 'package:ocideck/state/editor_provider.dart';
import 'package:ocideck/theme/app_theme.dart';
import 'package:ocideck/widgets/panels/slide_list_panel.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Dekking voor `_copySlideAsImage` in `slide_list_panel_clipboard.dart`.
/// De classification-gate is al gedekt door `slide_list_panel_classification_gate_test.dart`;
/// hier wordt de toegestane tak getest — de code loopt door naar de
/// rasterize-aanroep en de "Slide renderen…" snackbar verschijnt.
void main() {
  testWidgets(
    'copy-as-image toont "Slide renderen…" wanneer de classificatie toestaat',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final deckNotifier = container.read(deckProvider.notifier);
      deckNotifier.newDeck('Test');
      deckNotifier.addSlide(SlideType.bullets);
      // TLP clear — geen release ceiling die blokkeert.
      container.read(editorProvider.notifier).select(0);

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

      // De gate laat het door, dus de "rendering…" snackbar verschijnt.
      expect(find.text('Slide renderen…'), findsOneWidget);
    },
  );
}
