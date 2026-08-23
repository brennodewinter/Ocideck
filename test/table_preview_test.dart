import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/models/display_window_spec.dart';
import 'package:ocideck/models/slide.dart';
import 'package:ocideck/services/table_layout_metrics.dart';
import 'package:ocideck/services/text_measurement.dart';
import 'package:ocideck/theme/app_theme.dart';
import 'package:ocideck/widgets/slides/slide_preview.dart';

Widget _host(
  List<List<String>> rows, {
  bool markOverdue = false,
  DisplayWindowSpec? viewLimit,
}) {
  return MaterialApp(
    home: Scaffold(
      body: Center(
        child: SizedBox(
          width: 800,
          height: 450,
          child: SlidePreviewWidget(
            slide: Slide.create(SlideType.table).copyWith(
              tableRows: rows,
              tableMarkOverdue: markOverdue,
              viewLimit: viewLimit,
            ),
          ),
        ),
      ),
    ),
  );
}

List<double> _columnWidths(WidgetTester tester) {
  final table = tester.widget<Table>(find.byType(Table));
  final widths = table.columnWidths!;
  return [
    for (var c = 0; c < widths.length; c++)
      (widths[c]! as FixedColumnWidth).value,
  ];
}

/// Alle tekst die de slide tekent, aaneengeregen.
String _textOf(WidgetTester tester) {
  final out = StringBuffer();
  for (final rich in tester.widgetList<RichText>(find.byType(RichText))) {
    rich.text.visitChildren((span) {
      if (span is TextSpan) out.write(span.text ?? '');
      return true;
    });
  }
  return out.toString();
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

    final widths = _columnWidths(tester);

    // The long "Omschrijving" column (index 1) earns more room than the short
    // ID (0) and OK (2) columns, so it wraps less and the table stays compact
    // instead of being scaled down (which wastes the slide width).
    expect(widths[1], greaterThan(widths[0]));
    expect(widths[1], greaterThan(widths[2]));
    expect(tester.takeException(), isNull);
  });

  // De bevinding: op tekenaantal verdeeld kreeg een korte kolom minder ruimte
  // dan haar eigen kop breed is. De kop brak dan letter voor letter af en viel
  // bij de smalste kolommen buiten de cel, dwars over de tabellijnen heen.
  testWidgets('a short column is never narrower than its own header word', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(<List<String>>[
        const ['#', 'Finding', 'Ernst', 'Systemen', 'Orgs'],
        const ['1', 'SSL/TLS Certificate expired', 'critical', '6', '1'],
        const ['2', 'Unencrypted website traffic', 'high', '31', '1'],
      ]),
    );
    await tester.pump();

    final widths = _columnWidths(tester);
    final cellSize = tester
        .widgetList<RichText>(find.byType(RichText))
        .map((r) => r.text.style?.fontSize ?? 0)
        .reduce((a, b) => a < b ? a : b);
    for (final (c, header) in const [
      'Finding',
      'Ernst',
      'Systemen',
      'Orgs',
    ].indexed) {
      expect(
        widths[c + 1],
        greaterThanOrEqualTo(
          measureTextWordWidth(header, cellSize, bold: true) +
              cellSize * kTableCellHPadFactor * 2,
        ),
        reason: 'kolom "$header" is te smal voor haar eigen kop',
      );
    }
    expect(tester.takeException(), isNull);
  });

  // Het "N van totaal"-bijschrift hoort onder de tabel, niet erin: als rij telde
  // het mee als inhoud van de eerste kolom, die daardoor een kwart slide breed
  // werd voor enkel rangnummers.
  testWidgets('the view-limit caption sits below the table, not inside it', (
    tester,
  ) async {
    final rows = <List<String>>[
      const ['#', 'Omschrijving'],
      for (var i = 1; i <= 12; i++) ['$i', 'Een omschrijving van regel $i'],
    ];

    await tester.pumpWidget(
      _host(rows, viewLimit: const DisplayWindowSpec(limit: 3)),
    );
    await tester.pump();

    final table = tester.widget<Table>(find.byType(Table));
    expect(table.children, hasLength(4)); // kop + drie regels, geen bijschrift
    expect(_textOf(tester), contains('van 12'), reason: 'bijschrift ontbreekt');
    expect(
      _columnWidths(tester)[0],
      lessThan(_columnWidths(tester)[1]),
      reason: 'de rangnummerkolom mag niet meegroeien met het bijschrift',
    );
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
