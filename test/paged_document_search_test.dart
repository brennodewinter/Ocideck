import 'package:material_ui/material_ui.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/models/page_size.dart';
import 'package:ocideck/services/document_footnote_setup.dart';
import 'package:ocideck/utils/text_search.dart';
import 'package:ocideck/widgets/reader/document_markdown_view.dart';
import 'package:ocideck/widgets/reader/document_search_overlay.dart';
import 'package:ocideck/widgets/reader/paged_document_view.dart';

void main() {
  testWidgets(
    'gegenereerde voetnootcijfers verschuiven hoofdteksttreffer niet',
    (tester) async {
      Rect? rect;
      const source =
          'Een noot[^a].\n\nWaarde 1 in de hoofdtekst.\n\n[^a]: toelichting';
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: DocumentSearchOverlay(
              query: '1',
              activeIndex: 0,
              onActiveRect: (value) => rect = value,
              child: const DocumentMarkdownView(source),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final paragraph = tester.renderObject<RenderParagraph>(
        find.byWidgetPredicate(
          (w) => w is RichText && w.text.toPlainText().contains('Waarde 1'),
        ),
      );
      final root = tester.renderObject(
        find.byType(DocumentSearchOverlay, skipOffstage: false),
      );
      final origin = paragraph.localToGlobal(Offset.zero, ancestor: root);
      final text = paragraph.text.toPlainText();
      final box = paragraph
          .getBoxesForSelection(
            TextSelection(
              baseOffset: text.indexOf('1'),
              extentOffset: text.indexOf('1') + 1,
            ),
          )
          .single
          .toRect()
          .shift(origin);
      expect(rect, box);
    },
  );

  for (final placement in FootnotePlacement.values) {
    testWidgets(
      'meerregelige gebruikte noot blijft bereikbaar naast orphan bij $placement',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(1100, 350));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        const source =
            'Begin.\n\n---\n\nEen noot[^a].\n\n[^orphan]: belangrijke passage\n\n[^a]: belangrijke\n    passage';
        final projected = VisibleMarkdownText(
          source,
          includeUnreferencedFootnotes: false,
        );
        expect(projected.matches('belangrijke passage'), hasLength(1));
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: PagedDocumentView(
                markdown: source,
                pageSize: PageSizeSpec.a4,
                margins: const PageMargins(),
                footnotePlacement: placement,
                searchQuery: 'belangrijke passage',
                searchMatchIndex: 0,
                searchRevealSignal: 1,
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(_visibleSearchHighlights(tester), isNotEmpty);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets('nootinhoud krijgt exacte markering en reveal bij $placement', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(1100, 650));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      // Definitievolgorde verschilt van referentievolgorde; beide noten en de
      // hoofdtekst bevatten dezelfde query, zodat alleen een exacte rang klopt.
      const source =
          'kat in de hoofdtekst.\n\n---\n\nLatere noot[^b] en daarna[^a].\n\n[^a]: kat alfa\n\n[^b]: kat beta';
      Widget surface(int index) => MaterialApp(
        home: Scaffold(
          body: PagedDocumentView(
            markdown: source,
            pageSize: PageSizeSpec.a4,
            margins: const PageMargins(),
            footnotePlacement: placement,
            searchQuery: 'kat',
            searchMatchIndex: index,
            searchRevealSignal: index + 1,
          ),
        ),
      );
      await tester.pumpWidget(surface(1));
      await tester.pumpAndSettle();
      final match = findVisibleMarkdownMatches(source, 'kat')[1];
      expect(
        source.substring(match.start, match.end + 5),
        contains('kat alfa'),
      );
      final overlays = tester
          .widgetList<DocumentSearchOverlay>(
            find.byType(DocumentSearchOverlay, skipOffstage: false),
          )
          .toList();
      final measures = overlays
          .where((w) => w.measure && w.query.isNotEmpty)
          .toList();
      expect(measures, hasLength(placement == FootnotePlacement.page ? 2 : 1));
      final activePaint = overlays.where(
        (w) => !w.measure && (w.geometry?.boxes.isNotEmpty ?? false),
      );
      expect(activePaint, isNotEmpty);
      final visible = _visibleSearchHighlights(tester);
      expect(
        visible,
        isNotEmpty,
        reason: 'de geselecteerde noot staat echt in beeld',
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(surface(2));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
    'paginakopieën hergebruiken één meting en dezelfde body bij querywissel',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1100, 160));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final source = List.generate(
        25,
        (i) => 'Pagina $i met kat.',
      ).join('\n\n---\n\n');
      Widget surface(String query, int signal, {int index = 0}) => MaterialApp(
        home: Scaffold(
          body: PagedDocumentView(
            markdown: source,
            pageSize: PageSizeSpec.a4,
            margins: const PageMargins(),
            searchQuery: query,
            searchMatchIndex: index,
            searchRevealSignal: signal,
          ),
        ),
      );
      await tester.pumpWidget(surface('kat', 1));
      await tester.pumpAndSettle();
      final first = tester
          .widgetList<DocumentSearchOverlay>(
            find.byType(DocumentSearchOverlay, skipOffstage: false),
          )
          .toList();
      expect(first.where((w) => w.measure), hasLength(1));
      final bodies = first
          .where((w) => !w.measure)
          .map((w) => w.child)
          .toList();
      expect(bodies, hasLength(25));
      expect(bodies.every((w) => identical(w, bodies.first)), isTrue);
      await tester.pumpWidget(surface('Pagina', 2));
      await tester.pumpAndSettle();
      final later = tester.widgetList<DocumentSearchOverlay>(
        find.byType(DocumentSearchOverlay, skipOffstage: false),
      );
      expect(later.where((w) => w.measure), hasLength(1));
      expect(
        later
            .where((w) => !w.measure)
            .every((w) => identical(w.child, bodies.first)),
        isTrue,
      );
      await tester.pumpWidget(surface('Pagina', 3, index: 24));
      await tester.pumpAndSettle();
      expect(
        _visibleSearchHighlights(tester),
        isNotEmpty,
        reason:
            'een nieuwe laatste treffer komt ook met gecachete pagina’s binnen de echte clips in beeld',
      );
      final scroll = tester.state<ScrollableState>(
        find
            .byType(Scrollable)
            .evaluate()
            .where(
              (e) =>
                  (e.widget as Scrollable).axisDirection == AxisDirection.down,
            )
            .map((e) => find.byWidget(e.widget))
            .first,
      );
      scroll.position.jumpTo(0);
      await tester.pumpAndSettle();
      expect(_visibleSearchHighlights(tester), isEmpty);
      await tester.pumpWidget(surface('Pagina', 4, index: 24));
      await tester.pumpAndSettle();
      expect(
        _visibleSearchHighlights(tester),
        isNotEmpty,
        reason: 'dezelfde treffer kan na wegscrollen opnieuw worden aangewezen',
      );
      scroll.position.jumpTo(0);
      await tester.pumpAndSettle();
      await tester.pumpWidget(surface('kat', 4, index: 24));
      await tester.pumpAndSettle();
      expect(
        scroll.position.pixels,
        0,
        reason:
            'alleen de query wijzigen herhaalt een oude revealopdracht niet',
      );
      expect(tester.takeException(), isNull);
    },
  );
}

Iterable<Element> _visibleSearchHighlights(WidgetTester tester) {
  return find.byKey(const Key('document-search-highlight')).evaluate().where((
    e,
  ) {
    final render = e.renderObject;
    if (render is! RenderBox || !render.hasSize) return false;
    final rect = render.localToGlobal(Offset.zero) & render.size;
    var insideClips = true;
    e.visitAncestorElements((ancestor) {
      if (ancestor.widget is ClipRect) {
        final box = ancestor.renderObject;
        if (box is RenderBox && box.hasSize) {
          final clip = box.localToGlobal(Offset.zero) & box.size;
          insideClips = insideClips && clip.contains(rect.center);
        }
      }
      return true;
    });
    return insideClips &&
        rect.center.dx > 0 &&
        rect.center.dx < tester.getSize(find.byType(Scaffold)).width &&
        rect.center.dy > 0 &&
        rect.center.dy < tester.getSize(find.byType(Scaffold)).height;
  });
}
