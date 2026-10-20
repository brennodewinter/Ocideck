import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/models/risk_dossier.dart';
import 'package:ocideck/services/ocideck_marked_table.dart';
import 'package:ocideck/services/risk_dossier_scaffold.dart';

void main() {
  group('riskDossierScaffold', () {
    test('FMEA-scaffold: contractmarker, lege tabel, maatregelenregister', () {
      final md = riskDossierScaffold(RiskMethod.fmea);
      final scan = scanOciMarkedTables(md);
      expect(scan.tables, hasLength(2));

      final risks = scan.tables[0];
      expect(risks.kind, 'risks');
      expect(risks.id, 'risico');
      expect(risks.marker!.attr('method'), 'fmea');
      expect(risks.marker!.attr('scale'), 'sod-1-10');
      expect(risks.next, 1);
      expect(risks.cols, hasLength(16));
      // Lege body — geen voorgeschreven scores (#2492).
      expect(risks.bodyRows, isEmpty);
      expect(risks.headerCells.first, 'ID');

      final measures = scan.tables[1];
      expect(measures.kind, 'measures');
      expect(measures.next, 1);
      expect(measures.cols, contains('status'));
    });

    test('kans × impact gebruikt de eigen kolommen en schaal', () {
      final md = riskDossierScaffold(RiskMethod.likelihoodImpact);
      final risks = scanOciMarkedTables(md).tables.first;
      expect(risks.marker!.attr('method'), 'likelihood-impact');
      expect(risks.marker!.attr('scale'), 'li-1-5');
      expect(
        risks.cols,
        containsAll(['l_b', 'i_b', 'l_n', 'i_n', 'uncertainty']),
      );
      expect(risks.cols, isNot(contains('s_b')));
    });

    test('Bowtie-scaffold schrijft het eigen tabelcontract', () {
      final md = riskDossierScaffold(RiskMethod.bowtie);
      final scan = scanOciMarkedTables(md);
      expect(scan.tables.first.kind, 'bowtie');
      expect(scan.tables.first.cols, containsAll(['path', 'side', 'role']));
    });

    test('context wordt gewone proza vóór de markers, geen metadata', () {
      final md = riskDossierScaffold(
        RiskMethod.fmea,
        context: const RiskDossierContext(
          purpose: 'Veilige inbedrijfname lijn 3',
          assessor: 'J. Jansen',
          date: '2026-10-20',
        ),
      );
      expect(
        md.startsWith(
          'Doel: Veilige inbedrijfname lijn 3\n'
          'Beoordelaar: J. Jansen\n'
          'Datum: 2026-10-20\n\n'
          '<!-- ocideck:risks',
        ),
        isTrue,
      );
    });
  });

  group('importTableAsRiskRegister', () {
    test('mappen, ID-allocatie en vrije kolommen (§7)', () {
      final table = [
        '| Faalwijze | Ernst | Kans | Notitie |',
        '|-----------|-------|------|---------|',
        '| Sensor valt uit | 7 | 4 | zie schema |',
        '| Klep hangt | 9 | 2 | |',
      ];
      final result = importTableAsRiskRegister(
        table,
        RiskMethod.fmea,
        mapping: {0: 'failure', 1: 's_b', 2: 'o_b'},
        startNext: 1,
      );
      expect(result.allocatedIds, 2);
      expect(result.freeColumns, ['Notitie']);

      final t = scanOciMarkedTables(result.markdown).tables.single;
      expect(t.kind, 'risks');
      expect(t.next, 3);
      // 'Notitie' reist als vrije x-0-kolom mee achter de contractkolommen.
      expect(t.cols.last, 'x-0');
      expect(t.cell(0, 'id'), 'R-001');
      expect(t.cell(0, 'failure'), 'Sensor valt uit');
      expect(t.cell(0, 's_b'), '7');
      expect(t.cell(0, 'o_b'), '4');
      // Ongemapt contractveld blijft leeg — niets wordt geraden.
      expect(t.cell(0, 'd_b'), '');
      // Vrije kolom-inhoud behouden.
      expect(t.bodyRows[0].last, 'zie schema');
      // De vrije kolom draagt zijn eigen koptekst.
      expect(t.headerCells.last, 'Notitie');
    });

    test('bestaande ID\'s blijven staan en tellen niet op', () {
      final table = [
        '| Nr | Faalwijze | S |',
        '|----|-----------|---|',
        '| R-042 | Oude regel | 3 |',
        '| | Nieuwe regel | 5 |',
      ];
      final result = importTableAsRiskRegister(
        table,
        RiskMethod.fmea,
        mapping: {0: 'id', 1: 'failure', 2: 's_b'},
        startNext: 7,
      );
      expect(result.allocatedIds, 1);
      final t = scanOciMarkedTables(result.markdown).tables.single;
      expect(t.cell(0, 'id'), 'R-042');
      expect(t.cell(1, 'id'), 'R-007');
      expect(t.next, 8);
    });
  });
}
