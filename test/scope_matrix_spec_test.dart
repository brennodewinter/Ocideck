import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/models/deck.dart';
import 'package:ocideck/models/scope_matrix_spec.dart';
import 'package:ocideck/models/slide.dart';
import 'package:ocideck/services/markdown_service.dart';

ScopeMatrixSpec _sample() => const ScopeMatrixSpec(
  title: 'Scope',
  rows: [
    ScopeRow(
      object: 'https://app.example',
      type: ScopeObjectType.web,
      status: ScopeStatus.tested,
    ),
    ScopeRow(
      object: '10.0.0.0/24',
      type: ScopeObjectType.infra,
      status: ScopeStatus.deviation,
      note: 'one host down',
    ),
    ScopeRow(object: 'firmware.bin', type: ScopeObjectType.firmware),
  ],
);

void main() {
  group('ScopeObjectType', () {
    test('maps each type to its bound standard (§10.7)', () {
      expect(ScopeObjectType.web.standard, 'WSTG');
      expect(ScopeObjectType.infra.standard, 'PTES');
      expect(ScopeObjectType.iot.standard, 'ISTG');
      expect(ScopeObjectType.firmware.standard, 'FSTM');
      expect(ScopeObjectType.api.standard, 'WSTG');
      expect(ScopeObjectType.mobile.standard, 'MASTG');
      expect(ScopeObjectType.other.standard, '');
    });

    test('fromToken is case-insensitive and defaults to other', () {
      expect(ScopeObjectType.fromToken('web'), ScopeObjectType.web);
      expect(ScopeObjectType.fromToken('MASTG?'), ScopeObjectType.other);
    });
  });

  group('ScopeMatrixSpec', () {
    test(
      'toTableRows/fromSlide is a fixed point; standard derived from type',
      () {
        final spec = _sample();
        final rows = spec.toTableRows();
        expect(rows.first, ScopeMatrixSpec.header);
        // The standard column is written from the type.
        expect(rows[1][2], 'WSTG');
        expect(rows[2][2], 'PTES');
        final back = ScopeMatrixSpec.fromSlide(spec.title, rows);
        expect(back.rows.map((r) => r.type), [
          ScopeObjectType.web,
          ScopeObjectType.infra,
          ScopeObjectType.firmware,
        ]);
        expect(back.rows[1].status, ScopeStatus.deviation);
        expect(back.rows[1].note, 'one host down');
        expect(back.rows[2].status, ScopeStatus.notTested);
      },
    );

    test('coverage counts only tested/deviation/unreachable rows', () {
      final spec = _sample();
      expect(spec.total, 3);
      expect(spec.testedCount, 2); // web tested + infra deviation; firmware not
    });
  });

  test('scopeMatrix slide round-trips as a Markdown table (P1-SCOPE)', () {
    final spec = _sample();
    final slide = Slide.create(
      SlideType.scopeMatrix,
    ).copyWith(title: spec.title, tableRows: spec.toTableRows());
    final service = MarkdownService();
    final md = service.generateDeck(Deck(title: 'Demo', slides: [slide]));
    expect(md, contains('<!-- _class: scope-matrix -->'));
    expect(md, contains('| Object | Type | Standard | Status | Note |'));

    final out = service.parseDeck(md)!.slides.single;
    expect(out.type, SlideType.scopeMatrix);
    expect(out.title, 'Scope');
    final back = ScopeMatrixSpec.fromSlide(out.title, out.tableRows);
    expect(back.rows.length, 3);
    expect(back.rows[0].type, ScopeObjectType.web);
    expect(back.rows[0].standard, 'WSTG');
    expect(back.rows[1].note, 'one host down');
  });
}
