import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/services/table_sort.dart';

void main() {
  const service = TableSortService();

  group('stable raw-row sorting', () {
    test(
      'sorts ascending and descending while equal and unknown rows stay stable',
      () {
        const table = [
          '| Key | Event |',
          '| ---: | :--- |',
          '| 2 | first two |',
          '| ? | first unknown |',
          '| 1 | one |',
          '| 2 | second two |',
          '|  | second unknown |',
        ];

        expect(
          service
              .sort(table, columnIndex: 0, kind: TableSortKind.number)
              .lines
              .skip(2),
          [
            '| 1 | one |',
            '| 2 | first two |',
            '| 2 | second two |',
            '| ? | first unknown |',
            '|  | second unknown |',
          ],
        );
        expect(
          service
              .sort(
                table,
                columnIndex: 0,
                kind: TableSortKind.number,
                direction: TableSortDirection.descending,
              )
              .lines
              .skip(2),
          [
            '| 2 | first two |',
            '| 2 | second two |',
            '| 1 | one |',
            '| ? | first unknown |',
            '|  | second unknown |',
          ],
        );
      },
    );

    test('moves opaque raw lines without normalising any bytes', () {
      const table = [
        '| Key | Detail |',
        '| :--- | ---: |',
        r'| b |  leading \| pipe<br>line  |',
        '| a|trailing space   |',
      ];
      final result = service.sort(table, columnIndex: 0);

      expect(result.lines, [table[0], table[1], table[3], table[2]]);
      expect(result.outcome, TableSortOutcome.applied);
    });
  });

  test('automatic parsing recognises text, numbers, dates and times', () {
    TableParseKind kindFor(List<String> values) => service.analyze([
      '| Key |',
      '| --- |',
      ...values.map((value) => '| $value |'),
    ], columnIndex: 0).resolvedKind;

    expect(kindFor(['b', 'a']), TableParseKind.text);
    expect(kindFor(['10', '2']), TableParseKind.number);
    expect(kindFor(['2025-02-01', '2024-12-31']), TableParseKind.date);
    expect(kindFor(['13:10', '09:30']), TableParseKind.time);
  });

  test('qualified values and ranges sort by their start', () {
    const table = [
      '| Marker |',
      '| --- |',
      '| 14:00–15:00 |',
      '| circa 13:10 |',
      '| 13:10-13:30 |',
      '| ca. 12:00 |',
    ];
    final result = service.sort(
      table,
      columnIndex: 0,
      kind: TableSortKind.time,
    );

    expect(result.lines.skip(2), [
      '| ca. 12:00 |',
      '| circa 13:10 |',
      '| 13:10-13:30 |',
      '| 14:00–15:00 |',
    ]);
  });

  test('date and number ranges use the start value', () {
    const dates = [
      '| Date |',
      '| --- |',
      '| 2024-05-01–2024-06-01 |',
      '| circa 2023 |',
      '| 2022-2025 |',
    ];
    expect(
      service
          .sort(dates, columnIndex: 0, kind: TableSortKind.date)
          .lines
          .skip(2),
      ['| 2022-2025 |', '| circa 2023 |', '| 2024-05-01–2024-06-01 |'],
    );

    const mixedDatePrecision = [
      '| Date |',
      '| --- |',
      '| 2024-05-01 |',
      '| 2023 |',
      '| 2024-01-01 |',
    ];
    expect(
      service
          .sort(mixedDatePrecision, columnIndex: 0, kind: TableSortKind.date)
          .lines
          .skip(2),
      ['| 2023 |', '| 2024-01-01 |', '| 2024-05-01 |'],
    );

    const numbers = ['| Phase |', '| --- |', '| 10–12 |', '| 2 |', '| 3-5 |'];
    expect(
      service
          .sort(numbers, columnIndex: 0, kind: TableSortKind.number)
          .lines
          .skip(2),
      ['| 2 |', '| 3-5 |', '| 10–12 |'],
    );
  });

  test('analysis explains confidence, rows and monotonicity', () {
    const table = [
      '| Time |',
      '| --- |',
      '| 13:10 |',
      '| not recorded |',
      '| 12:00 |',
      '|  |',
    ];
    final analysis = service.analyze(table, columnIndex: 0);

    expect(analysis.resolvedKind, TableParseKind.time);
    expect(
      analysis.suitability,
      TableAnalysisSuitability.suitableWithAttentionPoints,
    );
    expect(analysis.profile.nonEmptyCount, 3);
    expect(analysis.profile.emptyCount, 1);
    expect(analysis.profile.parsedRowIndices, [0, 2]);
    expect(analysis.profile.unparsedRowIndices, [1, 3]);
    expect(analysis.profile.alreadyMonotonic, isFalse);
    expect(analysis.profile.confidence, closeTo(2 / 3, 0.0001));
    expect(analysis.profile.reasons, isNotEmpty);
  });

  test('mixed automatic interpretation fails without changing source', () {
    const table = ['| Key |', '| --- |', '| 12:00 |', '| 4 |'];
    final result = service.sort(table, columnIndex: 0);

    expect(result.outcome, TableSortOutcome.failed);
    expect(result.lines, table);
    expect(result.analysis!.resolvedKind, TableParseKind.mixed);
  });

  test('cancel and malformed input are byte-identical no-ops', () {
    const table = ['| Key |', '| --- |', '| b |', '| a |'];
    final cancelled = service.sort(
      table,
      columnIndex: 0,
      decision: TableSortDecision.cancel,
    );
    expect(cancelled.outcome, TableSortOutcome.cancelled);
    expect(cancelled.lines, table);

    const malformed = ['| Key |', '| not a delimiter |', '| b |'];
    final failed = service.sort(malformed, columnIndex: 0);
    expect(failed.outcome, TableSortOutcome.failed);
    expect(failed.lines, malformed);
  });

  test('source sort preserves positional CRLF and final newline bytes', () {
    const source =
        '| Key | Detail |\r\n'
        '| --- | --- |\n'
        '| b |  two  |\r'
        '| a|one |';
    final result = service.sortSource(source, columnIndex: 0);

    expect(
      result.source,
      '| Key | Detail |\r\n'
      '| --- | --- |\n'
      '| a|one |\r'
      '| b |  two  |',
    );
  });
}
