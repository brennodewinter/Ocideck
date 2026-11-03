import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/models/page_size.dart';
import 'package:ocideck/widgets/reader/paged_document_view.dart';

void main() {
  testWidgets(
    'hoogte van zoekbalk hergebruikt 25 vellen, breedte en thema vernieuwen',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1100, 700));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final source = List.generate(
        25,
        (i) => 'Pagina $i met kat.',
      ).join('\n\n---\n\n');
      Widget surface({
        double height = 600,
        Brightness brightness = Brightness.light,
      }) => MaterialApp(
        theme: ThemeData(brightness: brightness),
        home: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            height: height,
            child: PagedDocumentView(
              markdown: source,
              pageSize: PageSizeSpec.a4,
              margins: const PageMargins(),
            ),
          ),
        ),
      );
      await tester.pumpWidget(surface());
      await tester.pumpAndSettle();
      final sheets = find.byKey(const Key('document-sheet'));
      expect(sheets, findsNWidgets(25));
      final first = tester.widgetList(sheets).toList();
      await tester.pumpWidget(surface(height: 488));
      await tester.pumpAndSettle();
      final shorter = tester.widgetList(sheets).toList();
      expect(
        List.generate(25, (i) => identical(first[i], shorter[i])),
        everyElement(isTrue),
        reason:
            'alleen de viewporthoogte verandert; geen vel hoeft opnieuw gebouwd',
      );
      await tester.binding.setSurfaceSize(const Size(700, 700));
      await tester.pumpAndSettle();
      final narrower = tester.widgetList(sheets).toList();
      expect(identical(shorter.first, narrower.first), isFalse);
      await tester.pumpWidget(
        surface(height: 488, brightness: Brightness.dark),
      );
      await tester.pumpAndSettle();
      expect(
        identical(narrower.first, tester.widgetList(sheets).first),
        isFalse,
      );
      expect(tester.takeException(), isNull);
    },
  );
}
