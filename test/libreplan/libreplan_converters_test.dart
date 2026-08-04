import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/models/slide.dart';
import 'package:ocideck/services/libreplan/libreplan_converters.dart';
import 'package:ocideck/services/libreplan/libreplan_xml.dart';

LibreplanOrder _sampleOrder() {
  return const LibreplanOrder(
    code: 'ORDER-1',
    name: 'Project X',
    initDate: null,
    children: [
      LibreplanOrderElement(
        code: 'G1',
        name: 'Fase 1',
        children: [
          LibreplanOrderElement(
            code: 'T1',
            name: 'Vooronderzoek',
            startDate: null,
            workingHours: 40,
            progress: 1.0,
            dependencies: [],
          ),
          LibreplanOrderElement(
            code: 'T2',
            name: 'Ontwerp',
            startDate: null,
            workingHours: 80,
            progress: 0.5,
            dependencies: ['T1'],
          ),
        ],
      ),
      LibreplanOrderElement(
        code: 'M1',
        name: 'Go/No-Go',
        milestone: true,
        startDate: null,
      ),
    ],
  );
}

void main() {
  group('libreplanOrderToGantt', () {
    test('produceert een gantt-slide met de juiste kolommen', () {
      final slide = libreplanOrderToGantt(_sampleOrder());
      expect(slide.type, SlideType.gantt);
      expect(slide.title, 'Project X');
      expect(slide.tableRows.first,
          ['Taak', 'Start', 'Duur', 'Voortgang', 'Afhankelijk van']);
    });

    test('containers worden sectiekoppen met sections=true', () {
      final slide = libreplanOrderToGantt(_sampleOrder(), sections: true);
      final sectionRow = slide.tableRows
          .where((r) => r.first.startsWith('## '))
          .toList();
      expect(sectionRow, hasLength(1));
      expect(sectionRow.first.first, '## Fase 1');
    });

    test('milestones worden Milestone:-rijen', () {
      final slide = libreplanOrderToGantt(_sampleOrder());
      final milestoneRow = slide.tableRows
          .where((r) => r.first.startsWith('Milestone: '))
          .toList();
      expect(milestoneRow, hasLength(1));
      expect(milestoneRow.first.first, 'Milestone: Go/No-Go');
      expect(milestoneRow.first[2], '0d');
    });

    test('voortgang wordt omgezet naar done/active/leeg', () {
      final slide = libreplanOrderToGantt(_sampleOrder(), sections: false);
      final t1 = slide.tableRows.firstWhere((r) => r.first == 'Vooronderzoek');
      expect(t1[3], 'done');
      final t2 = slide.tableRows.firstWhere((r) => r.first == 'Ontwerp');
      expect(t2[3], 'active');
    });

    test('uren worden omgezet naar een duur', () {
      final slide = libreplanOrderToGantt(_sampleOrder(), sections: false);
      final t1 = slide.tableRows.firstWhere((r) => r.first == 'Vooronderzoek');
      expect(t1[2], '5d');
    });

    test('afhankelijkheden komen in de vijfde kolom', () {
      final slide = libreplanOrderToGantt(_sampleOrder(), sections: false);
      final t2 = slide.tableRows.firstWhere((r) => r.first == 'Ontwerp');
      expect(t2[4], 'T1');
    });
  });

  group('libreplanOrderToWbs', () {
    test('produceert een tree-slide met hiërarchie', () {
      final slide = libreplanOrderToWbs(_sampleOrder());
      expect(slide.type, SlideType.tree);
      expect(slide.title, 'WBS: Project X');
      expect(slide.bullets, contains('Fase 1'));
      expect(slide.bullets, contains('\tVooronderzoek (40u)'));
      expect(slide.bullets, contains('\tOntwerp (80u)'));
    });

    test('milestones krijgen een ◆-prefix', () {
      final slide = libreplanOrderToWbs(_sampleOrder());
      expect(slide.bullets, contains('◆ Go/No-Go'));
    });
  });

  group('libreplanResourcesToTable', () {
    test('produceert een resourcelijst', () {
      final resources = [
        const LibreplanResource(code: 'm1', name: '3D-printer', isMachine: true),
        const LibreplanResource(
            code: 'w1', name: '', firstName: 'Alice', surname: 'Smith'),
      ];
      final slide = libreplanResourcesToTable(resources);
      expect(slide.type, SlideType.table);
      expect(slide.tableRows.first, ['Code', 'Naam', 'Type']);
      expect(slide.tableRows[1], ['m1', '3D-printer', 'Machine']);
      expect(slide.tableRows[2], ['w1', 'Alice Smith', 'Medewerker']);
    });
  });

  group('libreplanWorkReportsToTable', () {
    test('produceert een timesheet-tabel', () {
      final reports = [
        const LibreplanWorkReport(
          code: 'wr1',
          resource: 'w1',
          workOrder: 'TASK-1',
          lines: [
            LibreplanWorkReportLine(
                code: 'l1', hours: 4, resource: 'w1', workOrder: 'TASK-1'),
            LibreplanWorkReportLine(
                code: 'l2', hours: 6, resource: 'w1', workOrder: 'TASK-2'),
          ],
        ),
      ];
      final slide = libreplanWorkReportsToTable(reports);
      expect(slide.type, SlideType.table);
      expect(slide.tableRows.first, ['Datum', 'Resource', 'Taak', 'Uren']);
      expect(slide.tableRows[1][1], 'w1');
      expect(slide.tableRows[1][2], 'TASK-1');
      expect(slide.tableRows[1][3], '4.0');
    });
  });

  group('libreplanResourceHoursToChart', () {
    test('produceert een chart-slide met series per resource', () {
      final validHours = [
        LibreplanResourceHours(
          resourceCode: 'w1',
          date: DateTime(2026, 9, 1),
          hours: 4,
        ),
        LibreplanResourceHours(
          resourceCode: 'w1',
          date: DateTime(2026, 9, 2),
          hours: 6,
        ),
        LibreplanResourceHours(
          resourceCode: 'w2',
          date: DateTime(2026, 9, 1),
          hours: 8,
        ),
      ];
      final slide = libreplanResourceHoursToChart(validHours);
      expect(slide.type, SlideType.chart);
      expect(slide.customMarkdown, contains('"type":"bar"'));
      expect(slide.customMarkdown,
          contains('"xLabels":["2026-09-01","2026-09-02"]'));
      expect(slide.customMarkdown, contains('"name":"w1"'));
      expect(slide.customMarkdown, contains('"name":"w2"'));
    });

    test('lege urenlijst produceert een lege chart', () {
      final slide = libreplanResourceHoursToChart([]);
      expect(slide.type, SlideType.chart);
      expect(slide.customMarkdown, '{"type":"bar","xLabels":[],"series":[]}');
    });
  });

  group('libreplanOrderToCockpit', () {
    test('produceert een cockpit-slide met voortgangmeter', () {
      final slide = libreplanOrderToCockpit(_sampleOrder());
      expect(slide.type, SlideType.cockpit);
      expect(slide.title, 'Status: Project X');
      expect(slide.customMarkdown, contains('"type":"speedometer"'));
      expect(slide.customMarkdown, contains('"label":"Voortgang"'));
      // T1=1.0, T2=0.5, M1=0.0 (milestone, non-container) → gemiddeld=0.5 → 50%
      expect(slide.customMarkdown, contains('"value":50'));
    });

    test('geplande uren worden samengevat', () {
      final slide = libreplanOrderToCockpit(_sampleOrder());
      expect(slide.customMarkdown, contains('"label":"Geplande uren"'));
      // 40 + 80 = 120
      expect(slide.customMarkdown, contains('"value":120'));
    });
  });

  group('libreplanOrderToTimeline', () {
    test('produceert een timeline met milestones', () {
      final slide = libreplanOrderToTimeline(_sampleOrder());
      expect(slide.type, SlideType.timeline);
      expect(slide.title, 'Milestones: Project X');
      expect(slide.bullets, hasLength(1));
      expect(slide.bullets.first, contains('Go/No-Go'));
    });

    test('milestones worden op datum gesorteerd', () {
      final order = LibreplanOrder(
        code: 'O',
        name: 'Test',
        children: [
          const LibreplanOrderElement(code: 'M2', name: 'Laat', milestone: true),
          LibreplanOrderElement(
            code: 'M1',
            name: 'Vroeg',
            milestone: true,
            startDate: DateTime(2026, 1, 1),
          ),
        ],
      );
      final slide = libreplanOrderToTimeline(order);
      expect(slide.bullets.first, contains('Vroeg'));
    });
  });

  group('libreplanOrderToCriticalPath', () {
    test('produceert een flow-slide met het kritieke pad', () {
      final slide = libreplanOrderToCriticalPath(_sampleOrder());
      expect(slide.type, SlideType.flow);
      expect(slide.title, 'Kritieke pad: Project X');
      expect(slide.bullets, isNotEmpty);
      expect(slide.bullets.any((b) => b.startsWith('Vooronderzoek')), isTrue);
    });
  });
}
