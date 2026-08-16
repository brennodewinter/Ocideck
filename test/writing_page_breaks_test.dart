import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/l10n/app_localizations.dart';
import 'package:ocideck/utils/markdown_quill_codec.dart';
import 'package:ocideck/widgets/markdown_editor/markdown_editor_theme.dart';
import 'package:ocideck/widgets/markdown_editor/wysiwyg_notes_field.dart';
import 'package:ocideck/widgets/reader/writing_page_breaks.dart';

/// Pagina-einden in de schrijfstand: de lijn hoort te vallen waar het vel vol
/// is, gemeten aan de blokken die er echt staan — niet op een vast interval.
void main() {
  group('waar de einden vallen', () {
    test('binnen één pagina valt er niets te tekenen', () {
      expect(
        writingPageBreaks(blockHeights: [30, 30], pageContentHeight: 100),
        isEmpty,
      );
    });

    test('het einde valt op de blokgrens, niet op de paginahoogte', () {
      // 40 + 40 past; het derde blok zou tot 120 lopen. De lijn hoort dus op
      // 80 te staan — bovenaan dat blok — en niet op 100, dwars erdoorheen.
      expect(
        writingPageBreaks(blockHeights: [40, 40, 40], pageContentHeight: 100),
        [80],
      );
    });

    test('een blok hoger dan de pagina levert einden binnen dat blok', () {
      // Onvermijdelijk: iets dat op geen enkele pagina past moet wél gesneden.
      expect(writingPageBreaks(blockHeights: [250], pageContentHeight: 100), [
        100,
        200,
      ]);
    });

    test('zonder blokken of met een onzinnige hoogte gebeurt er niets', () {
      expect(
        writingPageBreaks(blockHeights: const [], pageContentHeight: 100),
        isEmpty,
      );
      expect(
        writingPageBreaks(blockHeights: [50], pageContentHeight: 0),
        isEmpty,
      );
    });

    test('zonder editor is er niets gemeten', () {
      expect(writingBlockHeights(null), isEmpty);
    });
  });

  group('gemeten aan de echte schrijfstand', () {
    late QuillController controller;
    late GlobalKey<EditorState> editorKey;

    Future<void> pump(WidgetTester tester, String markdown) async {
      controller = QuillController(
        document: MarkdownQuillCodec.documentFromMarkdown(markdown),
        selection: const TextSelection.collapsed(offset: 0),
      );
      addTearDown(controller.dispose);
      editorKey = GlobalKey<EditorState>();
      final focus = FocusNode();
      addTearDown(focus.dispose);
      final scroll = ScrollController();
      addTearDown(scroll.dispose);

      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            FlutterQuillLocalizations.delegate,
          ],
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: SizedBox(
              width: 640,
              height: 800,
              child: WysiwygNotesField(
                controller: controller,
                scrollController: scroll,
                focusNode: focus,
                editorKey: editorKey,
                editorTheme: MarkdownEditorTheme.documentSurface(
                  scheme: const ColorScheme.light(),
                ),
                hintText: '',
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('elk blok in de editor levert een gemeten hoogte', (
      tester,
    ) async {
      await pump(tester, 'Een.\n\nTwee.\n\nDrie.');

      final heights = writingBlockHeights(editorKey.currentState?.renderEditor);
      expect(heights, hasLength(3));
      for (final h in heights) {
        expect(
          h,
          greaterThan(0),
          reason: 'een blok zonder hoogte is niet echt',
        );
      }
    });

    testWidgets('uitgezet laat de overlay het schrijfvlak met rust', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: WritingPageBreakOverlay(
              editorKey: GlobalKey<EditorState>(),
              pageContentHeight: 500,
              enabled: false,
              child: const Text('schrijfvlak'),
            ),
          ),
        ),
      );
      expect(find.text('schrijfvlak'), findsOneWidget);
      expect(
        find
            .byType(CustomPaint)
            .evaluate()
            .where((e) => (e.widget as CustomPaint).painter != null),
        isEmpty,
        reason: 'uit is uit — geen schilder in de boom',
      );
    });

    testWidgets('de einden komen uit die gemeten hoogtes', (tester) async {
      await pump(tester, List.generate(12, (i) => 'Alinea $i.').join('\n\n'));

      final heights = writingBlockHeights(editorKey.currentState?.renderEditor);
      // Een paginavlak van vier alinea's hoog: dan horen er einden te vallen,
      // en elk einde hoort samen te vallen met een blokgrens.
      final pageHeight = heights.take(4).fold<double>(0, (a, b) => a + b);
      final breaks = writingPageBreaks(
        blockHeights: heights,
        pageContentHeight: pageHeight,
      );
      expect(breaks, isNotEmpty);

      final boundaries = <double>[];
      var y = 0.0;
      for (final h in heights) {
        y += h;
        boundaries.add(y);
      }
      for (final b in breaks) {
        expect(
          boundaries.any((edge) => (edge - b).abs() < 0.5),
          isTrue,
          reason: 'einde op $b valt niet op een blokgrens ($boundaries)',
        );
      }
    });
  });
}
