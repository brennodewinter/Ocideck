import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/app.dart';
import 'package:ocideck/l10n/app_localizations.dart';
import 'package:ocideck/models/deck.dart';
import 'package:ocideck/models/slide.dart';
import 'package:ocideck/state/procesverbetering_provider.dart';
import 'package:ocideck/state/tabs_provider.dart';
import 'package:ocideck/widgets/app_shell.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets(
    'retiring security prompts preserves improvement discovery and navigation',
    (tester) async {
      AppLocalizations.setActiveLanguageCode('nl');
      SharedPreferences.setMockInitialValues({'app_consent_accepted': true});
      await tester.binding.setSurfaceSize(const Size(1600, 1000));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(const ProviderScope(child: OciDeckApp()));
      await tester.pumpAndSettle();
      final container = ProviderScope.containerOf(
        tester.element(find.byType(AppShell)),
      );
      final tab = container.read(tabsProvider).current!;
      tab.deckNotifier.loadDeck(
        Deck(
          title: 'Verbetering',
          slides: [
            Slide.create(SlideType.title),
            Slide.create(SlideType.matrix),
          ],
        ),
      );
      container.read(improvementModulePromptProvider.notifier).state =
          ImprovementModulePrompt(tabId: tab.id);
      await tester.pumpAndSettle();
      expect(
        find.textContaining(
          'Deze presentatie bevat onderdelen van de Procesverbetering-module.',
        ),
        findsOneWidget,
      );
      await tester.tap(find.text('Naar de slide'));
      await tester.pumpAndSettle();
      expect(tab.editorNotifier.currentState.selectedIndex, 1);
      await tester.tap(find.text('Inschakelen'));
      await tester.pumpAndSettle();
      expect(container.read(procesverbeteringProvider).enabled, isTrue);
      expect(find.byType(MaterialBanner), findsNothing);
    },
  );
}
