import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/models/slide.dart';
import 'package:ocideck/services/markdown_table_codec.dart';

void main() {
  group('decodeMarkdownTableWithAlignment', () {
    test('reads left/center/right from the GFM separator row', () {
      const lines = [
        '| Naam | Score | Datum |',
        '| :--- | :---: | ---: |',
        '| Jan | 8 | 2024-01-01 |',
      ];
      final result = decodeMarkdownTableWithAlignment(lines);
      expect(result.rows, [
        ['Naam', 'Score', 'Datum'],
        ['Jan', '8', '2024-01-01'],
      ]);
      expect(result.alignments, [
        TableAlign.left,
        TableAlign.center,
        TableAlign.right,
      ]);
    });

    test('a separator without colons yields all-left', () {
      const lines = ['| A | B |', '| --- | --- |', '| 1 | 2 |'];
      final result = decodeMarkdownTableWithAlignment(lines);
      expect(result.alignments, [TableAlign.left, TableAlign.left]);
    });

    test('a bare separator row still drops from rows', () {
      const lines = ['| A | B |', '| --- | --- |', '| 1 | 2 |'];
      final result = decodeMarkdownTableWithAlignment(lines);
      expect(result.rows.length, 2); // header + data, separator gone
    });
  });

  group('markdownTableSeparatorRow', () {
    test('produces :--- / :---: / ---: for left/center/right', () {
      expect(
        markdownTableSeparatorRow(3, [
          TableAlign.left,
          TableAlign.center,
          TableAlign.right,
        ]),
        '| :--- | :---: | ---: |',
      );
    });

    test('defaults to bare --- without alignments', () {
      expect(markdownTableSeparatorRow(2), '| --- | --- |');
    });

    test('pads short alignments with left', () {
      expect(
        markdownTableSeparatorRow(3, [TableAlign.right]),
        '| ---: | --- | --- |',
      );
    });
  });

  // De volledige round-trip: schrijf een tabel met uitlijning, lees hem terug,
  // en de uitlijning staat er nog. Dit is de belofte aan het bestandsformaat —
  // een deck dat opslaat met rechts uitgelijnde cijfers opent zo weer.
  test('alignment round-trips through encode → decode', () {
    final rows = [
      ['Naam', 'Score', 'Datum'],
      ['Jan', '8', '2024-01-01'],
    ];
    final alignments = [TableAlign.left, TableAlign.center, TableAlign.right];
    final separator = markdownTableSeparatorRow(3, alignments);
    final table = [
      '| ${rows[0].join(' | ')} |',
      separator,
      '| ${rows[1].join(' | ')} |',
    ];
    final decoded = decodeMarkdownTableWithAlignment(table);
    expect(decoded.rows, rows);
    expect(decoded.alignments, alignments);
  });
}
