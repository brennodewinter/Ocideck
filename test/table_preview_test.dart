import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/models/slide.dart';
import 'package:ocideck/widgets/slides/slide_preview.dart';

Widget _host(List<List<String>> rows) {
  return MaterialApp(
    home: Scaffold(
      body: Center(
        child: SizedBox(
          width: 800,
          height: 450,
          child: SlidePreviewWidget(
            slide: Slide.create(SlideType.table).copyWith(tableRows: rows),
          ),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('table columns flex proportionally to their content width', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(<List<String>>[
        ['ID', 'Omschrijving', 'OK'],
        ['1', 'Een tamelijk lange omschrijving die veel breedte vraagt', 'Ja'],
        ['2', 'Kort', 'Nee'],
      ]),
    );
    await tester.pump();

    final table = tester.widget<Table>(find.byType(Table));
    final widths = table.columnWidths!;
    double flex(int c) => (widths[c]! as FlexColumnWidth).value;

    // The long "Omschrijving" column (index 1) earns more flex weight than the
    // short ID (0) and OK (2) columns, so it wraps less and the table stays
    // compact instead of being scaled down (which wastes the slide width).
    expect(flex(1), greaterThan(flex(0)));
    expect(flex(1), greaterThan(flex(2)));
    expect(tester.takeException(), isNull);
  });
}
