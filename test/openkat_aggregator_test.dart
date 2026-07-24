import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/models/openkat/openkat_models.dart';
import 'package:ocideck/services/openkat/openkat_aggregator.dart';

OpenKatFinding _finding({
  required String id,
  required String severity,
  String system = 'example.com',
  String type = 'KAT-001',
  DateTime? openedAt,
}) => OpenKatFinding(
  id: id,
  findingTypeId: type,
  findingTypeName: 'Type $type',
  severity: severity,
  systemId: system,
  openedAt: openedAt,
);

OpenKatSnapshot _snapshot({
  required DateTime date,
  required List<OpenKatFinding> findings,
  List<OpenKatSystem> systems = const [],
}) => OpenKatSnapshot(
  reportDate: date,
  sourceFile: 'rapport-${date.toIso8601String()}.json',
  sourceHash: 'hash-${date.toIso8601String()}',
  systems: systems,
  findings: findings,
);

void main() {
  const aggregator = OpenKatAggregator();

  group('de ernstverdeling verklaart het totaal', () {
    test('een niveau buiten de vier banden belandt in overig', () {
      // OpenKAT rapporteert meer niveaus dan critical/high/medium/low — een
      // echte uitdraai meldde 295 findings terwijl de vier banden er samen 218
      // verklaarden. De 77 die daartussen vielen stonden nergens.
      final snapshot = _snapshot(
        date: DateTime.utc(2026, 7, 20),
        findings: [
          _finding(id: 'f1', severity: 'critical'),
          _finding(id: 'f2', severity: 'high'),
          _finding(id: 'f3', severity: 'recommendation'),
          _finding(id: 'f4', severity: 'unknown'),
          _finding(id: 'f5', severity: ''),
        ],
      );

      final agg = aggregator.aggregateSnapshot(snapshot);
      expect(agg.severityCounts[openKatOtherSeverity], 3);
      expect(
        openKatSeverityOrder.fold<int>(
          0,
          (sum, band) => sum + (agg.severityCounts[band] ?? 0),
        ),
        agg.totalFindings,
        reason:
            'de uitsplitsing moet het totaal verklaren, anders klopt de dia niet',
      );
    });

    test('zonder afwijkende niveaus blijft overig nul', () {
      final agg = aggregator.aggregateSnapshot(
        _snapshot(
          date: DateTime.utc(2026, 7, 20),
          findings: [_finding(id: 'f1', severity: 'low')],
        ),
      );
      expect(agg.severityCounts[openKatOtherSeverity], 0);
      expect(agg.hasOtherSeverities, isFalse);
    });

    test('een systeem telt zijn afwijkende niveaus apart', () {
      final stats = aggregator.systemsWithMostFindings(
        _snapshot(
          date: DateTime.utc(2026, 7, 20),
          findings: [
            _finding(id: 'f1', severity: 'high'),
            _finding(id: 'f2', severity: 'recommendation'),
          ],
        ),
      );
      expect(stats.single.high, 1);
      expect(stats.single.other, 1);
      expect(
        stats.single.critical +
            stats.single.high +
            stats.single.medium +
            stats.single.low +
            stats.single.other,
        stats.single.total,
      );
    });
  });

  group('een issue claimt geen ernst die er niet is', () {
    OpenKatOrganization org(List<OpenKatFinding> findings) =>
        OpenKatOrganization(
          code: 'a',
          name: 'A',
          snapshots: [
            _snapshot(date: DateTime.utc(2026, 6, 1), findings: findings),
          ],
        );

    test('een issue met alleen aanbevelingen heet niet low', () {
      // De teller begon op 'low' en een onbekend niveau won het daar nooit van,
      // dus verscheen "Consider enabling RPKI" in de tabel als Low.
      final issues = aggregator.topIssues([
        org([
          _finding(id: 'f1', severity: 'recommendation', type: 'KAT-RPKI'),
          _finding(id: 'f2', severity: 'recommendation', type: 'KAT-RPKI'),
        ]),
      ]);
      expect(issues.single.highestSeverity, openKatOtherSeverity);
    });

    test('de zwaarste finding bepaalt de ernst van het issue', () {
      final issues = aggregator.topIssues([
        org([
          _finding(id: 'f1', severity: 'low', type: 'KAT-X'),
          _finding(id: 'f2', severity: 'critical', type: 'KAT-X'),
          _finding(id: 'f3', severity: 'medium', type: 'KAT-X'),
        ]),
      ]);
      expect(issues.single.highestSeverity, 'critical');
    });

    test('een issue met alleen aanbevelingen sluit de rij', () {
      final issues = aggregator.topIssues([
        org([
          _finding(id: 'f1', severity: 'recommendation', type: 'KAT-RPKI'),
          _finding(id: 'f2', severity: 'low', type: 'KAT-CAA'),
        ]),
      ]);
      expect(issues.map((i) => i.findingTypeId), ['KAT-CAA', 'KAT-RPKI']);
    });
  });

  group('het verloop over de tijd', () {
    OpenKatOrganization org(String code, List<OpenKatSnapshot> snapshots) =>
        OpenKatOrganization(code: code, name: code, snapshots: snapshots);

    test('elke meetdatum levert een punt op', () {
      final history = aggregator.history([
        org('a', [
          _snapshot(
            date: DateTime.utc(2026, 5, 1),
            findings: [_finding(id: 'f1', severity: 'high')],
          ),
          _snapshot(
            date: DateTime.utc(2026, 6, 1),
            findings: [
              _finding(id: 'f1', severity: 'high'),
              _finding(id: 'f2', severity: 'low'),
            ],
          ),
        ]),
      ]);

      expect(history.map((p) => p.date), [
        DateTime.utc(2026, 5, 1),
        DateTime.utc(2026, 6, 1),
      ]);
      expect(history.last.severityCounts['high'], 1);
      expect(history.last.totalFindings, 2);
    });

    test('een organisatie draagt haar laatst bekende meting mee', () {
      // Organisaties meten niet op dezelfde dag. Op 1 juni is de meting van a
      // uit mei nog steeds de stand van zaken; hem daar op nul zetten zou een
      // daling tonen die niemand heeft gemeten.
      final history = aggregator.history([
        org('a', [
          _snapshot(
            date: DateTime.utc(2026, 5, 1),
            findings: [_finding(id: 'a1', severity: 'high')],
          ),
        ]),
        org('b', [
          _snapshot(
            date: DateTime.utc(2026, 6, 1),
            findings: [_finding(id: 'b1', severity: 'high')],
          ),
        ]),
      ]);

      expect(history.map((p) => p.totalFindings), [1, 2]);
    });

    test('een organisatie telt niet mee vóór haar eerste meting', () {
      final history = aggregator.history([
        org('a', [
          _snapshot(
            date: DateTime.utc(2026, 6, 1),
            findings: [_finding(id: 'a1', severity: 'high')],
          ),
        ]),
        org('b', [
          _snapshot(
            date: DateTime.utc(2026, 5, 1),
            findings: [_finding(id: 'b1', severity: 'low')],
          ),
        ]),
      ]);

      expect(history.first.date, DateTime.utc(2026, 5, 1));
      expect(history.first.severityCounts['high'], 0);
      expect(history.last.severityCounts['high'], 1);
    });

    test('één meting geeft geen verloop', () {
      final history = aggregator.history([
        org('a', [
          _snapshot(
            date: DateTime.utc(2026, 6, 1),
            findings: [_finding(id: 'a1', severity: 'high')],
          ),
        ]),
      ]);
      expect(
        history.length,
        1,
        reason: 'wel een punt, maar een grafiek vraagt er twee',
      );
    });
  });

  group('organisaties vergeleken', () {
    OpenKatOrganization org(String code, int nu, int daarvoor) =>
        OpenKatOrganization(
          code: code,
          name: code.toUpperCase(),
          snapshots: [
            _snapshot(
              date: DateTime.utc(2026, 5, 1),
              findings: [
                for (var i = 0; i < daarvoor; i++)
                  _finding(id: '$code-oud-$i', severity: 'medium'),
              ],
            ),
            _snapshot(
              date: DateTime.utc(2026, 6, 1),
              findings: [
                for (var i = 0; i < nu; i++)
                  _finding(id: '$code-nu-$i', severity: 'medium'),
              ],
            ),
          ],
        );

    test('de grootste bewegers staan vooraan', () {
      final vergelijking = aggregator.organizationComparison([
        org('stil', 10, 10),
        org('stijger', 30, 10),
        org('daler', 5, 20),
      ]);

      expect(vergelijking.map((c) => c.name), ['STIJGER', 'DALER', 'STIL']);
      expect(vergelijking.first.findings, 30);
      expect(vergelijking.first.previousFindings, 10);
    });

    test('een organisatie zonder eerdere meting heeft geen vorige waarde', () {
      final vergelijking = aggregator.organizationComparison([
        OpenKatOrganization(
          code: 'nieuw',
          name: 'Nieuw',
          snapshots: [
            _snapshot(
              date: DateTime.utc(2026, 6, 1),
              findings: [_finding(id: 'n1', severity: 'high')],
            ),
          ],
        ),
      ]);

      expect(vergelijking.single.previousFindings, isNull);
    });
  });
}
