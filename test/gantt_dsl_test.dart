import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/services/improvement/gantt_dsl.dart';

void main() {
  group('ganttTableToMermaid', () {
    test('design-doc §3.2 voorbeeld: tabel → DSL', () {
      final dsl = ganttTableToMermaid(
        rows: [
          ['Vooronderzoek', '2026-09-01', '5d', 'done', ''],
          ['Ontwerp', '2026-09-08', '10d', 'active', 'Vooronderzoek'],
          ['Implementatie', '2026-09-22', '15d', '', 'Ontwerp'],
          ['Milestone: oplevering', '2026-10-13', '0d', '', 'Implementatie'],
        ],
      );
      // De dependency-rijen gebruiken `after <id>` in plaats van de startdatum,
      // omdat een afhankelijkheid de start afleidt (GANTT_SLIDETYPE §2.2 *).
      expect(dsl, contains('dateFormat YYYY-MM-DD'));
      expect(dsl, contains('Vooronderzoek :done, t1, 2026-09-01, 5d'));
      expect(dsl, contains('Ontwerp :active, t2, after t1, 10d'));
      expect(dsl, contains('Implementatie :t3, after t2, 15d'));
      expect(dsl, contains('oplevering :milestone, t4, after t3, 0d'));
    });

    test('een taak zonder status krijgt geen status-token', () {
      final dsl = ganttTableToMermaid(
        rows: [
          ['Testen', '2026-10-06', '7d', '', ''],
        ],
      );
      expect(dsl, contains('Testen :t1, 2026-10-06, 7d'));
      expect(dsl, isNot(contains(':done,')));
      expect(dsl, isNot(contains(':active,')));
    });

    test('crit-status wordt doorgegeven', () {
      final dsl = ganttTableToMermaid(
        rows: [
          ['Kritiek pad', '2026-01-01', '3d', 'crit', ''],
        ],
      );
      expect(dsl, contains('Kritiek pad :crit, t1, 2026-01-01, 3d'));
    });

    test('meerdere afhankelijkheden worden after t1, after t2', () {
      final dsl = ganttTableToMermaid(
        rows: [
          ['A', '2026-01-01', '5d', '', ''],
          ['B', '2026-01-01', '5d', '', ''],
          ['C', '', '3d', '', 'A, B'],
        ],
      );
      expect(dsl, contains('C :t3, after t1, after t2, 3d'));
    });

    test('een losse afhankelijkheid (onbekende naam) wordt gedropt', () {
      final dsl = ganttTableToMermaid(
        rows: [
          ['A', '2026-01-01', '5d', '', 'BestaatNiet'],
        ],
      );
      // Geen after-ref; de startdatum valt terug op de expliciete datum.
      expect(dsl, contains('A :t1, 2026-01-01, 5d'));
      expect(dsl, isNot(contains('after')));
    });

    test('een rij met ongeldige datum en zonder afhankelijkheid valt uit', () {
      final dsl = ganttTableToMermaid(
        rows: [
          ['Zonder start', 'geen-datum', '5d', '', ''],
        ],
      );
      expect(dsl, isNot(contains('Zonder start')));
    });

    test('een rij met ongeldige duur valt uit (geen milestone)', () {
      final dsl = ganttTableToMermaid(
        rows: [
          ['Slechte duur', '2026-01-01', 'vijf', '', ''],
        ],
      );
      expect(dsl, isNot(contains('Slechte duur')));
    });

    test('lege rijen worden overgeslagen', () {
      final dsl = ganttTableToMermaid(
        rows: [
          ['', '', '', '', ''],
          ['A', '2026-01-01', '5d', '', ''],
          ['', '', '', '', ''],
        ],
      );
      expect(dsl, contains('A :t1, 2026-01-01, 5d'));
      // Slechts één taakregel (de header telt niet: geen `:t`-token).
      final taskLines = dsl.split('\n').where((l) => l.contains(' :t')).length;
      expect(taskLines, 1);
    });

    test('scale=month geeft %Y-%m as-formaat', () {
      final dsl = ganttTableToMermaid(
        rows: [
          ['A', '2026-01-01', '5d', '', ''],
        ],
        scale: 'month',
      );
      expect(dsl, contains('axisFormat %Y-%m'));
    });

    test('scale=day geeft %Y-%m-%d as-formaat', () {
      final dsl = ganttTableToMermaid(
        rows: [
          ['A', '2026-01-01', '5d', '', ''],
        ],
        scale: 'day',
      );
      expect(dsl, contains('axisFormat %Y-%m-%d'));
    });

    test('auto: korte spanne (<14d) kiest dag-formaat', () {
      final dsl = ganttTableToMermaid(
        rows: [
          ['A', '2026-01-01', '5d', '', ''],
          ['B', '2026-01-10', '3d', '', ''],
        ],
      );
      expect(dsl, contains('axisFormat %Y-%m-%d'));
    });

    test('auto: lange spanne (>=90d) kiest maand-formaat', () {
      final dsl = ganttTableToMermaid(
        rows: [
          ['A', '2026-01-01', '5d', '', ''],
          ['B', '2026-06-01', '3d', '', ''],
        ],
      );
      expect(dsl, contains('axisFormat %Y-%m'));
    });

    test('sections: een rij met ## wordt een section-kop', () {
      final dsl = ganttTableToMermaid(
        rows: [
          ['## Fase 1', '', '', '', ''],
          ['A', '2026-01-01', '5d', '', ''],
          ['## Fase 2', '', '', '', ''],
          ['B', '2026-01-08', '3d', '', ''],
        ],
        sections: true,
      );
      expect(dsl, contains('section Fase 1'));
      expect(dsl, contains('section Fase 2'));
      expect(dsl, contains('A :t1, 2026-01-01, 5d'));
      expect(dsl, contains('B :t2, 2026-01-08, 3d'));
    });

    test('sections uit: een rij met ## is een gewone taaknaam', () {
      final dsl = ganttTableToMermaid(
        rows: [
          ['## Fase 1', '2026-01-01', '5d', '', ''],
        ],
        sections: false,
      );
      expect(dsl, isNot(contains('section')));
      expect(dsl, contains('## Fase 1 :t1, 2026-01-01, 5d'));
    });

    test('milestone met afhankelijkheid gebruikt after', () {
      final dsl = ganttTableToMermaid(
        rows: [
          ['A', '2026-01-01', '5d', '', ''],
          ['Milestone: einde', '0d', '', '', 'A'],
        ],
      );
      expect(dsl, contains('einde :milestone, t2, after t1, 0d'));
    });

    test('lege tabel geeft geldige gantt-header zonder taken', () {
      final dsl = ganttTableToMermaid(rows: const []);
      expect(dsl, startsWith('gantt\n'));
      expect(dsl, contains('dateFormat YYYY-MM-DD'));
      expect(dsl, contains('axisFormat'));
    });

    test('uur- en week-duraties worden geaccepteerd', () {
      final dsl = ganttTableToMermaid(
        rows: [
          ['Kort', '2026-01-01', '4h', '', ''],
          ['Lang', '2026-01-01', '2w', '', ''],
        ],
      );
      expect(dsl, contains('Kort :t1, 2026-01-01, 4h'));
      expect(dsl, contains('Lang :t2, 2026-01-01, 2w'));
    });
  });

  group('ganttStarterRows', () {
    test('heeft de vijf vaste kolomkoppen', () {
      expect(ganttStarterRows.first, [
        'Taak',
        'Start',
        'Duur',
        'Voortgang',
        'Afhankelijk van',
      ]);
      expect(ganttStarterRows.length, 3); // kop + twee lege rijen
    });
  });
}
