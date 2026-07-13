import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/models/checklist_spec.dart';
import 'package:ocideck/models/deck.dart';
import 'package:ocideck/models/slide.dart';
import 'package:ocideck/services/markdown_service.dart';

ChecklistSpec _sampleSpec() => const ChecklistSpec(
  standardLabel: 'Checklist — OWASP WSTG',
  rows: [
    ChecklistRow(
      id: 'WSTG-ATHN-07',
      test: 'Testing for Weak Password Policy',
      status: ChecklistStatus.anomaly,
      findingId: 'F-03',
    ),
    ChecklistRow(
      id: 'WSTG-CRYP-04',
      test: 'Testing for Weak Encryption',
      status: ChecklistStatus.notTestable,
      note: 'functie afwezig',
    ),
    ChecklistRow(id: 'WSTG-SESS-01', test: 'Testing for Session Management'),
  ],
);

void main() {
  group('ChecklistStatus', () {
    test('token round-trips and tolerates em-dash/empty/case', () {
      expect(ChecklistStatus.fromToken('Anomaly'), ChecklistStatus.anomaly);
      expect(
        ChecklistStatus.fromToken('not testable'),
        ChecklistStatus.notTestable,
      );
      expect(ChecklistStatus.fromToken('—'), ChecklistStatus.notTested);
      expect(ChecklistStatus.fromToken(''), ChecklistStatus.notTested);
      expect(ChecklistStatus.fromToken('rubbish'), ChecklistStatus.notTested);
    });
  });

  group('ChecklistSpec', () {
    test('toTableRows/fromSlide is a fixed point', () {
      final spec = _sampleSpec();
      final rows = spec.toTableRows();
      expect(rows.first, ChecklistSpec.header);
      final back = ChecklistSpec.fromSlide(spec.standardLabel, rows);
      expect(back.rows.length, 3);
      expect(back.rows[0].id, 'WSTG-ATHN-07');
      expect(back.rows[0].status, ChecklistStatus.anomaly);
      expect(back.rows[0].findingId, 'F-03');
      expect(back.rows[1].status, ChecklistStatus.notTestable);
      expect(back.rows[1].note, 'functie afwezig');
      expect(back.rows[2].status, ChecklistStatus.notTested);
      expect(back.rows[2].findingId, ''); // '—' → none
    });

    test('progress counts only tested rows', () {
      final spec = _sampleSpec();
      expect(spec.total, 3);
      expect(
        spec.testedCount,
        2,
      ); // anomaly + notTestable count; notTested does not
    });

    test('does not turn its own header row into a test', () {
      final rows = _sampleSpec().toTableRows();
      final back = ChecklistSpec.fromSlide('t', rows);
      expect(back.rows.any((r) => r.id.toLowerCase() == 'id'), isFalse);
    });
  });

  test('checklist slide round-trips as a Markdown table (P1-CHK)', () {
    final spec = _sampleSpec();
    final slide = Slide.create(
      SlideType.checklist,
    ).copyWith(title: spec.standardLabel, tableRows: spec.toTableRows());
    final service = MarkdownService();
    final md = service.generateDeck(Deck(title: 'Demo', slides: [slide]));
    expect(md, contains('<!-- _class: checklist -->'));
    expect(md, contains('| ID | Test | Status | Finding | Note |'));

    final out = service.parseDeck(md)!.slides.single;
    expect(out.type, SlideType.checklist);
    expect(out.title, 'Checklist — OWASP WSTG');
    final back = ChecklistSpec.fromSlide(out.title, out.tableRows);
    expect(back.rows.length, 3);
    expect(back.rows[0].findingId, 'F-03');
    expect(back.rows[0].status, ChecklistStatus.anomaly);
    expect(back.rows[1].note, 'functie afwezig');
    expect(back.testedCount, 2);
  });

  test('checklist slide round-trips its scope-object link (feedback #8)', () {
    final spec = _sampleSpec();
    final slide = Slide.create(SlideType.checklist).copyWith(
      title: spec.standardLabel,
      tableRows: spec.toTableRows(),
      checklistScope: 'https://app.example/login',
    );
    final service = MarkdownService();
    final md = service.generateDeck(Deck(title: 'Demo', slides: [slide]));
    expect(
      md,
      contains('<!-- ocideck_checklist_scope: https://app.example/login -->'),
    );

    final out = service.parseDeck(md)!.slides.single;
    expect(out.type, SlideType.checklist);
    expect(out.checklistScope, 'https://app.example/login');
    // The marker is stripped from the body, not left as a stray comment/table row.
    final back = ChecklistSpec.fromSlide(out.title, out.tableRows);
    expect(back.rows.length, 3);
  });

  test('the scope marker is written only for checklist slides', () {
    // A non-checklist slide that happens to carry a scope string never emits the
    // marker (guards the `type == checklist` condition in the serializer).
    final slide = Slide.create(
      SlideType.bullets,
    ).copyWith(checklistScope: 'https://app.example/login');
    final md = MarkdownService().generateDeck(
      Deck(title: 'Demo', slides: [slide]),
    );
    expect(md, isNot(contains('ocideck_checklist_scope')));
  });
}
