import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/models/page_size.dart';
import 'package:ocideck/widgets/reader/document_markdown_view.dart';
import 'package:ocideck/widgets/reader/paged_document_view.dart';

import 'support/document_navigation_fixture.dart';

Widget _surface(
  String source, {
  String query = '',
  int signal = 0,
  double scale = 1,
}) => MaterialApp(
  home: Scaffold(
    body: PagedDocumentView(
      markdown: source,
      pageSize: PageSizeSpec.a4,
      margins: const PageMargins(),
      searchQuery: query,
      searchMatchIndex: query.isEmpty ? -1 : 0,
      searchRevealSignal: signal,
      scale: scale,
    ),
  ),
);

ScrollableState _vertical(WidgetTester tester) => tester.state<ScrollableState>(
  find
      .byWidgetPredicate(
        (w) => w is Scrollable && w.axisDirection == AxisDirection.down,
      )
      .first,
);

void main() {
  for (final pages in [10, 40, 100]) {
    testWidgets(
      '$pages vellen monteren een begrensde viewport en verre kop blijft bereikbaar',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(1100, 650));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        final source = documentPaginationFixture(pages);
        await tester.pumpWidget(_surface(source));
        await tester.pumpAndSettle();
        int trees() => find
            .byType(DocumentMarkdownView, skipOffstage: false)
            .evaluate()
            .length;
        expect(trees(), lessThanOrEqualTo(5));
        expect(find.byKey(ValueKey('document-page-$pages')), findsNothing);
        final body = tester
            .widgetList<DocumentMarkdownView>(find.byType(DocumentMarkdownView))
            .firstWhere((w) => w.onTapLink != null);
        body.onTapLink!('#hoofdstuk-${pages - 1}');
        await tester.pumpAndSettle();
        expect(find.byKey(ValueKey('document-page-$pages')), findsOneWidget);
        expect(_vertical(tester).position.pixels, greaterThan(1000));
        expect(trees(), lessThanOrEqualTo(5));
        _vertical(tester).position.jumpTo(0);
        await tester.pumpAndSettle();
        expect(find.byKey(const ValueKey('document-page-1')), findsOneWidget);
        expect(find.byKey(ValueKey('document-page-$pages')), findsNothing);
        expect(trees(), lessThanOrEqualTo(5));
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'zoeken monteert een verre doelpagina en kan daarna terug naar begin',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1100, 650));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final source = documentPaginationFixture(100);
      await tester.pumpWidget(_surface(source));
      await tester.pumpAndSettle();
      await tester.pumpWidget(
        _surface(source, query: 'bewijsdoel-99', signal: 1),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('document-page-100')), findsOneWidget);
      expect(find.byKey(const Key('document-search-highlight')), findsWidgets);
      expect(_vertical(tester).position.pixels, greaterThan(1000));
      await tester.pumpWidget(
        _surface(source, query: 'bewijsdoel-0.', signal: 2),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('document-page-1')), findsOneWidget);
      expect(_vertical(tester).position.pixels, lessThan(1000));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'zoom en viewportwijziging houden totale scrollmaat en verre navigatie geldig',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1100, 650));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final source = documentPaginationFixture(40);
      await tester.pumpWidget(_surface(source));
      await tester.pumpAndSettle();
      final oldExtent = _vertical(tester).position.maxScrollExtent;
      await tester.pumpWidget(_surface(source, scale: 1.5));
      await tester.pumpAndSettle();
      expect(
        _vertical(tester).position.maxScrollExtent,
        greaterThan(oldExtent * 1.4),
      );
      await tester.binding.setSurfaceSize(const Size(1100, 900));
      await tester.pumpAndSettle();
      expect(_vertical(tester).position.viewportDimension, closeTo(900, 1));
      final body = tester
          .widgetList<DocumentMarkdownView>(find.byType(DocumentMarkdownView))
          .firstWhere((w) => w.onTapLink != null);
      body.onTapLink!('#hoofdstuk-39');
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('document-page-40')), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
