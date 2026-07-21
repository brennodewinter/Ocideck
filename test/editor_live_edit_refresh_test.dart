import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/l10n/app_localizations.dart';
import 'package:ocideck/models/slide.dart';
import 'package:ocideck/state/deck_provider.dart';
import 'package:ocideck/theme/app_theme.dart';
import 'package:ocideck/widgets/panels/editor_panel.dart';

// Live bewerken tijdens het presenteren (een tabelcel bijwerken, een checklist
// afvinken) schrijft rechtstreeks naar het deck, buiten de editorvelden om.
// Die velden cachen hun tekst in eigen controllers en lezen pas opnieuw als de
// editor remount — wat aan `DeckState.revision` hangt. Zonder verversing bleef
// de editor daarna de tekst van vóór de presentatie tonen, en schreef de
// eerstvolgende toetsaanslag daarin de live bewerking stil terug.
void main() {
  setUp(() => AppLocalizations.setActiveLanguageCode('nl'));

  testWidgets(
    'a change made outside the editor lands once the fields refresh',
    (tester) async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final notifier = container.read(deckProvider.notifier);
      notifier.newDeck('Test');
      notifier.updateSlide(
        0,
        Slide.create(SlideType.table).copyWith(
          title: 'Cijfers',
          tableRows: [
            ['Rol', 'Waarde'],
            ['Bestuur', 'oud'],
          ],
        ),
      );

      await tester.binding.setSurfaceSize(const Size(1000, 2200));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: AppTheme.light,
            localizationsDelegates: const [
              AppLocalizations.delegate,
              GlobalMaterialLocalizations.delegate,
              FlutterQuillLocalizations.delegate,
            ],
            supportedLocales: AppLocalizations.supportedLocales,
            home: const Scaffold(body: EditorPanel()),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('oud'), findsOneWidget);

      // Zoals de presenter het doet: het deck bijwerken zonder de editorvelden
      // aan te raken.
      final slide = container.read(deckProvider).deck!.slides.first;
      notifier.updateSlide(
        0,
        slide.copyWith(
          tableRows: [
            ['Rol', 'Waarde'],
            ['Bestuur', 'nieuw'],
          ],
        ),
      );
      await tester.pumpAndSettle();

      // Het deck is bij, het veld nog niet — precies de toestand die de stille
      // terugdraai veroorzaakte.
      expect(
        container.read(deckProvider).deck!.slides.first.tableRows[1][1],
        'nieuw',
      );
      expect(find.text('oud'), findsOneWidget);

      notifier.refreshEditorFields();
      await tester.pumpAndSettle();

      expect(find.text('nieuw'), findsOneWidget);
      expect(find.text('oud'), findsNothing);
    },
  );
}
