import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/l10n/app_localizations.dart';
import 'package:ocideck/models/slide.dart';
import 'package:ocideck/state/deck_provider.dart';
import 'package:ocideck/state/editor_provider.dart';
import 'package:ocideck/widgets/panels/preview_panel.dart';
import 'package:shared_preferences/shared_preferences.dart';

ProviderContainer _deck() {
  SharedPreferences.setMockInitialValues({});
  final container = ProviderContainer();
  container
      .read(deckProvider.notifier)
      .newDeck(
        'Kwartaalpresentatie',
        slides: [
          Slide.create(SlideType.section).copyWith(title: 'Resultaten'),
          Slide.create(SlideType.bullets).copyWith(title: 'Hoofdpunten'),
        ],
      );
  return container;
}

void main() {
  setUp(() => AppLocalizations.setActiveLanguageCode('nl'));

  testWidgets(
    'een klik selecteert de kaart meteen en een dubbelklik opent (#2684)',
    (tester) async {
      tester.view.physicalSize = const Size(1200, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final container = _deck();
      addTearDown(container.dispose);
      final deck = container.read(deckProvider).deck!;

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            home: Builder(
              builder: (context) => TextButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => FullDeckPreview(
                      deck: deck,
                      themeProfile: deck.themeProfile,
                      editable: true,
                    ),
                  ),
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      final card = find.text('2. Hoofdpunten');
      // De tekst is een anker; de klik valt op de Listener die de kaart dekt.
      await tester.tap(card, warnIfMissed: false);
      await tester.pump(const Duration(milliseconds: 50));

      expect(container.read(editorProvider).selectedIndex, 1);

      await tester.tap(card, warnIfMissed: false);
      await tester.tap(card, warnIfMissed: false);
      await tester.pumpAndSettle();

      expect(find.text('open'), findsOneWidget);
    },
  );
}
