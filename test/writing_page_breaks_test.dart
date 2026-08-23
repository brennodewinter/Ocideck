import 'package:material_ui/material_ui.dart';
import 'package:flutter/rendering.dart' show BoxParentData;
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/l10n/app_localizations.dart';
import 'package:ocideck/utils/markdown_quill_codec.dart';
import 'package:ocideck/widgets/markdown_editor/markdown_editor_theme.dart';
import 'package:ocideck/widgets/markdown_editor/wysiwyg_notes_field.dart';
import 'package:ocideck/widgets/reader/document_markdown_view.dart'
    show documentKeepWithNextHeight;
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
            ...GlobalMaterialLocalizations.delegates,
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

    // De beeldkeuring vond dit: de lijn liep dwars door de letters van een kop
    // in plaats van in de witruimte ervoor. Oorzaak was het optellen van alleen
    // `size.height`, zonder de ruimte tússen de blokken — dan loopt de som met
    // elk blok verder achter op de werkelijke y.
    testWidgets('de hoogtes tellen de ruimte tussen de blokken mee', (
      tester,
    ) async {
      await pump(tester, 'Een kop\n=======\n\nEen alinea.\n\nNog een.');

      final editor = editorKey.currentState!.renderEditor;
      final heights = writingBlockHeights(editor);
      // De som tot en met het voorlaatste blok hoort exact de bovenkant van het
      // laatste blok te zijn — anders zit er ergens ruimte niet in de telling.
      final tops = <double>[];
      editor.visitChildren((child) {
        final data = (child as RenderBox).parentData;
        if (data is BoxParentData) tops.add(data.offset.dy);
      });
      expect(tops.length, heights.length);
      // De telling begint bij de bovenkant van het eerste blok, niet bij nul:
      // de editor heeft een eigen binnenmarge, en die hoort niet als tekst mee
      // te tellen.
      var sum = writingContentTop(editor);
      expect(sum, tops.first);
      for (var i = 0; i < heights.length - 1; i++) {
        sum += heights[i];
        expect(
          sum,
          closeTo(tops[i + 1], 0.01),
          reason: 'na blok $i loopt de telling uit de pas met de echte plek',
        );
      }
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

    // #2: een kop hoort niet alleen onderaan een vel achter te blijven. De
    // schrijfstand moet daarvoor weten wélk blok een kop is; zonder die kennis
    // valt de streepjeslijn hier anders dan het vel in de Pagina's-stand.
    testWidgets('de koppen in de schrijfstand worden herkend', (tester) async {
      await pump(tester, 'Alinea een.\n\n## Een kop\n\nAlinea twee.');

      final editor = editorKey.currentState!.renderEditor;
      expect(writingHeadingBlocks(editor), {1});
      expect(writingBlockHeights(editor), hasLength(3));
    });

    testWidgets('een kop onderaan schuift de lijn naar boven de kop', (
      tester,
    ) async {
      await pump(tester, 'Alinea een.\n\n## Een kop\n\nAlinea twee.');

      final editor = editorKey.currentState!.renderEditor;
      final heights = writingBlockHeights(editor);
      // Een vel dat precies de eerste alinea plus de kop kan dragen: zonder de
      // regel valt het einde ná de kop, met de regel ervóór.
      final pageHeight = heights[0] + heights[1] + 1;
      expect(
        writingPageBreaks(blockHeights: heights, pageContentHeight: pageHeight),
        [closeTo(heights[0] + heights[1], 0.01)],
      );
      expect(
        writingPageBreaks(
          blockHeights: heights,
          pageContentHeight: pageHeight,
          headingBlocks: writingHeadingBlocks(editor),
          minKeepHeight: documentKeepWithNextHeight(TextScaler.noScaling),
        ),
        [closeTo(heights[0], 0.01)],
      );
    });
  });
}
