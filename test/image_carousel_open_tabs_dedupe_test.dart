import 'dart:convert';
import 'dart:io';

import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:ocideck/l10n/app_localizations.dart';
import 'package:ocideck/models/deck.dart';
import 'package:ocideck/models/slide.dart';
import 'package:ocideck/services/file_service.dart';
import 'package:ocideck/services/slide_image_refs.dart';
import 'package:ocideck/state/deck_provider.dart';
import 'package:ocideck/state/document_provider.dart';
import 'package:ocideck/state/open_tab_image_usage.dart';
import 'package:ocideck/state/tabs_provider.dart';
import 'package:ocideck/widgets/dialogs/image_carousel_picker.dart';
import 'package:ocideck/widgets/document_editor_screen.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

import 'support/pump_until.dart';

final _onePixelPng = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8z8BQDwAEhQGA'
  'hKmMIQAAAABJRU5ErkJggg==',
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    AppLocalizations.setActiveLanguageCode('nl');
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets(
    'deduplicatie vanuit documenteditor werkt alle open tabs en opslag bij',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1400, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final project = Directory.systemTemp.createTempSync(
        'carousel_open_tabs_dedupe_',
      );
      addTearDown(() {
        if (project.existsSync()) project.deleteSync(recursive: true);
      });
      final images = Directory(p.join(project.path, 'images'))..createSync();
      final copy = File(p.join(images.path, 'kopie.png'))
        ..writeAsBytesSync(_onePixelPng);
      final keeper = File(p.join(images.path, 'behouden.png'))
        ..writeAsBytesSync(_onePixelPng);
      final copyRef = 'images/${p.basename(copy.path)}';
      final keeperRef = 'images/${p.basename(keeper.path)}';

      final deckPath = p.join(project.path, 'presentatie.md');
      final documentAPath = p.join(project.path, 'rapport-a.md');
      final documentBPath = p.join(project.path, 'rapport-b.md');
      final deck = Deck(
        title: 'Beeldgebruik',
        projectPath: project.path,
        slides: [
          Slide.create(SlideType.twoImages).copyWith(
            title: 'Beide velden',
            imagePath: copyRef,
            imagePath2: keeperRef,
          ),
          Slide.create(SlideType.freeMarkdown).copyWith(
            title: 'Vrije Markdown',
            customMarkdown: '![$copyRef]($copyRef)\n![$keeperRef]($keeperRef)',
          ),
          Slide.create(SlideType.question).copyWith(
            title: 'Antwoordafbeeldingen',
            customMarkdown: jsonEncode({
              'type': 'imagePair',
              'question': 'Welke afbeelding?',
              'answers': [
                {'text': 'kopie', 'image': copyRef, 'correct': true},
                {'text': 'behouden', 'image': keeperRef, 'correct': false},
              ],
            }),
          ),
          // Eén extra gebruik maakt de keeperkeuze deterministisch; de kopie
          // moet daardoor werkelijk uit alle andere open tabbladen verdwijnen.
          Slide.create(
            SlideType.image,
          ).copyWith(title: 'Keeper', imagePath: keeperRef),
        ],
      );
      File(documentAPath).writeAsStringSync(
        '# Rapport A\n\n![Kopie]($copyRef)\n\n![Keeper]($keeperRef)\n',
      );
      File(documentBPath).writeAsStringSync(
        '# Rapport B\n\n![Kopie]($copyRef)\n\n![Keeper]($keeperRef)\n',
      );

      final container = ProviderContainer();
      final files = container.read(fileServiceProvider);
      File(deckPath).writeAsStringSync(
        container.read(markdownServiceProvider).generateDeck(deck),
      );
      final tabsNotifier = container.read(tabsProvider.notifier);
      await tester.runAsync(() async {
        expect(await tabsNotifier.openFileByPath(deckPath), OpenResult.opened);
        expect(
          await tabsNotifier.openFileByPath(documentAPath),
          OpenResult.opened,
        );
        expect(
          await tabsNotifier.openFileByPath(documentBPath),
          OpenResult.opened,
        );
      });
      final tabsBefore = container.read(tabsProvider).tabs;
      final activeDocument = tabsBefore.last.documentNotifier!;

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: ProviderScope(
            overrides: [documentProvider.overrideWith((ref) => activeDocument)],
            child: MaterialApp(
              localizationsDelegates: const [
                AppLocalizations.delegate,
                ...GlobalMaterialLocalizations.delegates,
                FlutterQuillLocalizations.delegate,
              ],
              supportedLocales: AppLocalizations.supportedLocales,
              builder: (context, child) => MediaQuery(
                // De carrousel heeft bij de standaard testfont op macOS een
                // bekende, losstaande footer-overflow van 10 px. Met een
                // geldige compacte systeemtekstinstelling blijft deze test
                // gericht op de deduplicatieketen, zonder renderfouten te
                // verbergen of uit de exception-queue te verwijderen.
                data: const MediaQueryData(
                  size: Size(1400, 900),
                  textScaler: TextScaler.linear(0.9),
                ),
                child: child!,
              ),
              home: const DocumentEditorScreen(),
            ),
          ),
        ),
      );
      await tester.pump();

      await tester.tap(find.text('Invoegen'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.text('Afbeelding'));
      await pumpUntil(
        tester,
        () => find.byType(ImageCarouselPicker).evaluate().isNotEmpty,
        reason: 'de carrousel kwam niet vanuit de documenteditor op',
      );
      await pumpUntil(
        tester,
        () => find.byType(CircularProgressIndicator).evaluate().isEmpty,
        reason: 'de carrousel bleef afbeeldingen scannen',
      );

      await tester.tap(find.text('Duplicaten opruimen'), warnIfMissed: false);
      await pumpUntil(
        tester,
        () => find
            .widgetWithText(ElevatedButton, 'Opruimen')
            .evaluate()
            .isNotEmpty,
        reason: 'de bevestiging voor deduplicatie verscheen niet',
      );
      await tester.tap(
        find.widgetWithText(ElevatedButton, 'Opruimen'),
        warnIfMissed: false,
      );
      await pumpUntil(
        tester,
        () => !copy.existsSync(),
        reason: 'de byte-identieke kopie werd niet verwijderd',
      );

      final tabsAfter = container.read(tabsProvider).tabs;
      final liveDeck = tabsAfter.first.deckNotifier.currentState.deck!;
      for (final slide in liveDeck.slides) {
        expect(slideImagePaths(slide), isNot(contains(copyRef)));
      }
      for (final tab in tabsAfter.where(
        (tab) => tab.content is DocumentTabContent,
      )) {
        expect(
          tab.documentNotifier!.currentState.document!.body,
          isNot(contains(copyRef)),
        );
      }
      final usages = openTabImageUsages(tabsAfter, keeper.path);
      expect(usages, hasLength(6));
      expect(usages.toSet(), hasLength(usages.length));
      expect(liveDeck.slides.first.imagePath, keeperRef);
      expect(liveDeck.slides.first.imagePath2, keeperRef);
      expect(slideImagePaths(liveDeck.slides[1]), everyElement(keeperRef));
      expect(slideImagePaths(liveDeck.slides[2]), everyElement(keeperRef));

      await tester.runAsync(() async {
        expect(await tabsAfter.first.deckNotifier.save(), isTrue);
        for (final tab in tabsAfter.where(
          (tab) => tab.content is DocumentTabContent,
        )) {
          final state = tab.documentNotifier!.currentState;
          expect(await saveDocument(state.document!, state.filePath!), isTrue);
        }
      });

      final reopenedDeck = await tester.runAsync(
        () => files.openDeck(deckPath),
      );
      expect(reopenedDeck, isNotNull);
      expect(
        reopenedDeck!.slides.expand(slideImagePaths),
        isNot(contains(copyRef)),
      );
      expect(File(documentAPath).readAsStringSync(), isNot(contains(copyRef)));
      expect(File(documentBPath).readAsStringSync(), isNot(contains(copyRef)));
      expect(keeper.existsSync(), isTrue);

      await tester.pumpWidget(const SizedBox.shrink());
      container.dispose();
      await tester.pump();
    },
  );
}
