import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/models/slide.dart';
import 'package:ocideck/theme/app_theme.dart';
import 'package:ocideck/widgets/slides/slide_preview.dart';

Widget _host(List<List<String>> rows, {bool markOverdue = false}) {
  return MaterialApp(
    home: Scaffold(
      body: Center(
        child: SizedBox(
          width: 800,
          height: 450,
          child: SlidePreviewWidget(
            slide: Slide.create(
              SlideType.table,
            ).copyWith(tableRows: rows, tableMarkOverdue: markOverdue),
          ),
        ),
      ),
    ),
  );
}

/// De kleuren waarin [text] ergens in de opgebouwde tekstspans getekend wordt.
Set<Color?> _coloursOf(WidgetTester tester, String text) {
  final found = <Color?>{};
  for (final rich in tester.widgetList<RichText>(find.byType(RichText))) {
    rich.text.visitChildren((span) {
      if (span is TextSpan && (span.text ?? '').contains(text)) {
        found.add(span.style?.color);
      }
      return true;
    });
  }
  return found;
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

  // Een tabel met historische datums zou anders volledig rood kleuren, en een
  // waarschuwing die overal staat waarschuwt nergens voor. Daarom uit tenzij
  // de auteur hem aanzet.
  testWidgets('an expired date is only marked when the slide opts in', (
    tester,
  ) async {
    final rows = <List<String>>[
      const ['Actie', 'Deadline'],
      const ['Al lang open', '2020-01-01'],
    ];

    await tester.pumpWidget(_host(rows));
    await tester.pump();
    expect(
      _coloursOf(tester, '2020-01-01'),
      isNot(contains(AppTheme.danger700)),
    );

    await tester.pumpWidget(_host(rows, markOverdue: true));
    await tester.pump();
    expect(_coloursOf(tester, '2020-01-01'), contains(AppTheme.danger700));
    expect(tester.takeException(), isNull);
  });

  testWidgets('a future date and a non-date stay unmarked when opted in', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(<List<String>>[
        const ['Actie', 'Deadline', 'Status'],
        const ['Nog even', '2999-01-01', 'open'],
      ], markOverdue: true),
    );
    await tester.pump();
    expect(
      _coloursOf(tester, '2999-01-01'),
      isNot(contains(AppTheme.danger700)),
    );
    expect(_coloursOf(tester, 'open'), isNot(contains(AppTheme.danger700)));
  });
}
