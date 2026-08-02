import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/models/control_status_spec.dart';

void main() {
  group('ControlStatus tokens', () {
    test('round-trip via token, tolerant of blanks and case', () {
      for (final s in ControlStatus.values) {
        expect(ControlStatus.fromToken(s.token), s);
      }
      expect(ControlStatus.fromToken(''), ControlStatus.notStarted);
      expect(ControlStatus.fromToken('—'), ControlStatus.notStarted);
      expect(ControlStatus.fromToken('IMPLEMENTED'), ControlStatus.implemented);
      expect(ControlStatus.fromToken('rubbish'), ControlStatus.notStarted);
    });

    test('applicability and implemented flags', () {
      expect(ControlStatus.notApplicable.isApplicable, isFalse);
      expect(ControlStatus.implemented.isApplicable, isTrue);
      expect(ControlStatus.implemented.isImplemented, isTrue);
      expect(
        ControlStatus.partial.isImplemented,
        isFalse,
        reason: 'partial telt bewust niet als done',
      );
    });
  });

  group('progress is derived, never stored', () {
    ControlStatusSpec spec(List<ControlStatus> statuses) => ControlStatusSpec(
      rows: [
        for (var i = 0; i < statuses.length; i++)
          ControlStatusRow(id: 'A.$i', status: statuses[i]),
      ],
    );

    test('implemented over applicable, excluding not-applicable', () {
      final s = spec([
        ControlStatus.implemented,
        ControlStatus.implemented,
        ControlStatus.partial,
        ControlStatus.notStarted,
        ControlStatus.notApplicable, // out of scope → out of the denominator
      ]);
      expect(s.total, 5);
      expect(s.applicableCount, 4);
      expect(s.implementedCount, 2);
      expect(s.progressPercent, 50);
    });

    test('all not-applicable → 0%, no divide-by-zero', () {
      final s = spec([
        ControlStatus.notApplicable,
        ControlStatus.notApplicable,
      ]);
      expect(s.applicableCount, 0);
      expect(s.progressPercent, 0);
    });
  });

  group('table round-trip', () {
    test('optional columns and maturity round-trip losslessly', () {
      const original = ControlStatusSpec(
        heading: 'ISO 27001 · Annex A — Organisatorisch (A.5)',
        rows: [
          ControlStatusRow(
            id: 'A.5.1',
            control: 'Policies for information security',
            status: ControlStatus.implemented,
            maturity: 4,
            owner: 'CISO',
            target: '2026-Q4',
            evidence: 'policy-repo#12',
            note: 'jaarlijkse review',
          ),
          ControlStatusRow(id: 'A.5.7', status: ControlStatus.notStarted),
        ],
      );
      final round = ControlStatusSpec.fromSlide(
        original.heading,
        original.toTableRows(),
      );
      expect(round.heading, original.heading);
      expect(round.rows.length, 2);
      final r0 = round.rows.first;
      expect(r0.id, 'A.5.1');
      expect(r0.status, ControlStatus.implemented);
      expect(r0.maturity, 4);
      expect(r0.owner, 'CISO');
      expect(r0.target, '2026-Q4');
      expect(r0.evidence, 'policy-repo#12');
      expect(r0.note, 'jaarlijkse review');
      // An em-dash in an optional cell reads back as empty, never as "—".
      final r1 = round.rows.last;
      expect(r1.owner, '');
      expect(r1.maturity, 0);
    });

    test('a maturity above the max is clamped, non-numeric → 0', () {
      final rows = [
        ControlStatusSpec.header,
        ['A.1', 'x', 'Implemented', '9', '—', '—', '—', ''],
        ['A.2', 'y', 'Implemented', 'n/a', '—', '—', '—', ''],
      ];
      final spec = ControlStatusSpec.fromSlide('', rows);
      expect(spec.rows[0].maturity, controlMaturityMax);
      expect(spec.rows[1].maturity, 0);
    });
  });
}
