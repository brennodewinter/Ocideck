import 'package:material_ui/material_ui.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/l10n/app_localizations.dart';
import 'package:ocideck/models/markdown_source_document.dart';
import 'package:ocideck/models/slide.dart';
import 'package:ocideck/state/deck_provider.dart';
import 'package:ocideck/state/editor_provider.dart';
import 'package:ocideck/theme/app_theme.dart';
import 'package:ocideck/widgets/editors/markdown_deck_editor.dart';
import 'package:ocideck/widgets/panels/editor_panel.dart';
import 'package:ocideck/widgets/panels/slide_list_panel.dart';
import 'package:ocideck/widgets/slides/slide_thumbnail.dart';

// De 'Bron'-schakelaar in de editor-kopregel (#1160) is het per-dia
// ontsnappingsluik: één klik brengt je van de gestructureerde editor naar de
// rauwe markdown van díe ene dia. Mechanisch leunt hij op de bestaande
// markdown-modus, dus deze tests lopen via die knop de broneditor in.
void main() {
  setUp(() => AppLocalizations.setActiveLanguageCode('nl'));

  Future<ProviderContainer> pump(
    WidgetTester tester, {
    SlideType initialType = SlideType.bullets,
  }) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final notifier = container.read(deckProvider.notifier);
    notifier.newDeck('Test');
    if (initialType != SlideType.title) {
      notifier.updateSlide(0, Slide.create(initialType));
    }

    await tester.binding.setSurfaceSize(const Size(1000, 2200));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: AppTheme.light,
          localizationsDelegates: const [
            AppLocalizations.delegate,
            ...GlobalMaterialLocalizations.delegates,
            FlutterQuillLocalizations.delegate,
          ],
          supportedLocales: AppLocalizations.supportedLocales,
          home: const Scaffold(
            body: Row(
              children: [
                SizedBox(width: 240, child: SlideListPanel()),
                Expanded(child: EditorPanel()),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return container;
  }

  final sourceButton = find.byTooltip('Bewerk deze dia als markdown-bron');
  final sourceField = find.descendant(
    of: find.byType(MarkdownDeckEditor),
    matching: find.byType(TextField),
  );

  Future<ProviderContainer> pumpThreeSlides(WidgetTester tester) async {
    final container = await pump(tester);
    container.read(deckProvider.notifier).insertSlides([
      Slide.create(SlideType.bullets).copyWith(title: 'Tweede dia'),
      Slide.create(SlideType.bullets).copyWith(title: 'Derde dia'),
    ]);
    await tester.pumpAndSettle();
    return container;
  }

  Finder thumbnail(int index) => find.byWidgetPredicate(
    (widget) => widget is SlideThumbnail && widget.index == index,
  );

  testWidgets('the source toggle sits in the structured editor header', (
    tester,
  ) async {
    await pump(tester);
    expect(sourceButton, findsOneWidget);
    expect(find.text('Bron'), findsOneWidget);
  });

  testWidgets('tapping it enters markdown mode scoped to the active slide', (
    tester,
  ) async {
    final container = await pump(tester);

    // Vooraf: visuele modus, deck-omvang (de standaard).
    expect(container.read(editorProvider).mode, EditorMode.visual);

    await tester.tap(sourceButton);
    await tester.pumpAndSettle();

    final editor = container.read(editorProvider);
    expect(editor.mode, EditorMode.markdown);
    expect(editor.markdownScope, MarkdownScope.slide);
    // Het instappunt vult de buffer met de markdown van déze dia, niet het
    // hele deck: geen front-matter-scheidingsregel bovenaan.
    expect(editor.markdownBuffer, isNot(startsWith('---')));
    // En de buffer opent schoon (buffer == baseline), zodat een schone editor
    // deck-wijzigingen als undo/redo blijft volgen.
    expect(editor.hasMarkdownDraft, isFalse);
  });

  testWidgets('dia-bron kan omschakelen naar de volledige bron (#3113)', (
    tester,
  ) async {
    final container = await pumpThreeSlides(tester);
    await tester.tap(sourceButton);
    await tester.pumpAndSettle();
    expect(container.read(editorProvider).markdownScope, MarkdownScope.slide);
    expect(
      tester.widget<TextField>(sourceField).controller!.text,
      isNot(contains('# Tweede dia')),
    );

    await tester.tap(find.text('Volledige presentatie'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(container.read(editorProvider).markdownScope, MarkdownScope.deck);
    final source = tester.widget<TextField>(sourceField).controller!.text;
    expect(source, startsWith('---'));
    expect(source, contains('# Tweede dia'));
    expect(source, contains('# Derde dia'));
  });

  testWidgets('volledige bron houdt dia 2 geselecteerd (#3116)', (
    tester,
  ) async {
    final container = await pumpThreeSlides(tester);
    await tester.tap(sourceButton);
    await tester.pumpAndSettle();
    await tester.tap(thumbnail(1));
    await tester.pumpAndSettle();
    expect(
      tester.widget<TextField>(sourceField).controller!.text,
      contains('# Tweede dia'),
    );

    await tester.tap(find.text('Volledige presentatie'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    final state = container.read(editorProvider);
    expect(state.markdownScope, MarkdownScope.deck);
    expect(state.selectedIndex, 1);
    final controller = tester.widget<TextField>(sourceField).controller!;
    final second = MarkdownSourceDocument.parse(controller.text).blocks[1];
    expect(controller.selection.extentOffset, second.start);
  });

  const invalidDraft = '# Concept\n\n```dart\nNog bezig.\n';
  const validDraft = '# Concept\n\nDit is een gewone zin.\n';

  for (final toDeck in [false, true]) {
    final destination = toDeck ? 'volledige bron' : 'visuele editor';
    testWidgets('pas toe vóór overgang naar $destination (#3117)', (
      tester,
    ) async {
      final container = await pumpThreeSlides(tester);
      await tester.tap(sourceButton);
      await tester.pumpAndSettle();

      Future<void> applyAndTransition() async {
        await tester.tap(
          find.text(toDeck ? 'Volledige presentatie' : "Terug naar de dia's"),
        );
        await tester.pumpAndSettle();
        await tester.tap(
          toDeck
              ? find.descendant(
                  of: find.byType(SnackBar),
                  matching: find.text('Toepassen'),
                )
              : find.text('Toepassen en terug'),
        );
        await tester.pumpAndSettle();
      }

      await tester.enterText(sourceField, invalidDraft);
      await tester.pumpAndSettle();
      await applyAndTransition();
      expect(find.text('Syntaxproblemen gevonden'), findsOneWidget);
      expect(container.read(editorProvider).markdownScope, MarkdownScope.slide);

      await tester.tap(find.text('Terug naar editor'));
      await tester.pumpAndSettle();
      expect(container.read(editorProvider).mode, EditorMode.markdown);
      expect(
        tester.widget<TextField>(sourceField).controller!.text,
        invalidDraft,
      );

      await tester.enterText(sourceField, '');
      await tester.pumpAndSettle();
      await applyAndTransition();
      await tester.tap(find.text('Toch toepassen'));
      await tester.pumpAndSettle();
      expect(container.read(editorProvider).parseError, isTrue);
      expect(container.read(editorProvider).mode, EditorMode.markdown);
      expect(container.read(editorProvider).markdownScope, MarkdownScope.slide);
      expect(tester.widget<TextField>(sourceField).controller!.text, isEmpty);

      await tester.enterText(sourceField, validDraft);
      await tester.pumpAndSettle();
      await applyAndTransition();
      expect(container.read(deckProvider).deck!.slides.first.title, 'Concept');
      expect(
        container.read(editorProvider).mode,
        toDeck ? EditorMode.markdown : EditorMode.visual,
      );
      if (toDeck) {
        expect(
          container.read(editorProvider).markdownScope,
          MarkdownScope.deck,
        );
        final source = tester.widget<TextField>(sourceField).controller!.text;
        expect(source, contains('# Concept'));
        expect(source, contains('# Tweede dia'));
      }
    });
  }
}
