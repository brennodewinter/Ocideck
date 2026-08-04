import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/services/libreplan/libreplan_xml.dart';

void main() {
  group('parseOrderList', () {
    test('parseert een hiërarchisch project met groepen en taken', () {
      const xml = '''
<?xml version="1.0" encoding="UTF-8"?>
<order-list xmlns="http://rest.ws.libreplan.dev">
  <order code="ORDER-1" name="Project X" init-date="2026-09-01">
    <children>
      <order-line-group code="G1" name="Fase 1">
        <children>
          <order-line code="T1" name="Vooronderzoek"
            start-date="2026-09-01" deadline="2026-09-06" progress="1.0">
            <hours-groups>
              <hours-group code="HG1" working-hours="40" resource-type="WORKER"/>
            </hours-groups>
          </order-line>
          <order-line code="T2" name="Ontwerp"
            start-date="2026-09-08" deadline="2026-09-22" progress="0.5">
            <dependencies>
              <dependency origin="T1"/>
            </dependencies>
          </order-line>
        </children>
      </order-line-group>
      <order-line code="M1" name="Milestone: Go/No-Go" milestone="true"/>
    </children>
  </order>
</order-list>
''';

      final orders = parseOrderList(xml);
      expect(orders, hasLength(1));
      final order = orders.single;
      expect(order.code, 'ORDER-1');
      expect(order.name, 'Project X');
      expect(order.initDate, DateTime(2026, 9, 1));
      expect(order.children, hasLength(2));

      // Fase 1 (container)
      final fase1 = order.children[0];
      expect(fase1.name, 'Fase 1');
      expect(fase1.isContainer, isTrue);
      expect(fase1.children, hasLength(2));

      // Vooronderzoek (bladtaak)
      final t1 = fase1.children[0];
      expect(t1.name, 'Vooronderzoek');
      expect(t1.startDate, DateTime(2026, 9, 1));
      expect(t1.deadline, DateTime(2026, 9, 6));
      expect(t1.progress, 1.0);
      expect(t1.workingHours, 40);
      expect(t1.isContainer, isFalse);

      // Ontwerp (met dependency)
      final t2 = fase1.children[1];
      expect(t2.name, 'Ontwerp');
      expect(t2.dependencies, ['T1']);
      expect(t2.progress, 0.5);

      // Milestone
      final milestone = order.children[1];
      expect(milestone.milestone, isTrue);
      expect(milestone.name, 'Milestone: Go/No-Go');
    });

    test('lege XML retourneert lege lijst (fail-closed)', () {
      expect(parseOrderList(''), isEmpty);
      expect(parseOrderList('<not-order-list/>'), isEmpty);
    });

    test('ontbrekende velden worden getolereerd', () {
      const xml = '''
<order-list xmlns="http://rest.ws.libreplan.dev">
  <order code="X" name="X"/>
</order-list>
''';
      final orders = parseOrderList(xml);
      expect(orders, hasLength(1));
      expect(orders.single.initDate, isNull);
      expect(orders.single.children, isEmpty);
    });

    test('datum met tijd-component wordt date-only geparsed', () {
      const xml = '''
<order-list xmlns="http://rest.ws.libreplan.dev">
  <order code="X" name="X" init-date="2026-09-01T00:00:00+02:00"/>
</order-list>
''';
      final orders = parseOrderList(xml);
      expect(orders.single.initDate, DateTime(2026, 9, 1));
    });
  });

  group('parseResourceList', () {
    test('parseert machines en medewerkers', () {
      const xml = '''
<resource-list xmlns="http://rest.ws.libreplan.dev">
  <machine code="m1" name="3D-printer" description="Prusa"/>
  <worker code="w1" first-name="Alice" surname="Smith" nif="1234"/>
</resource-list>
''';
      final resources = parseResourceList(xml);
      expect(resources, hasLength(2));
      expect(resources[0].isMachine, isTrue);
      expect(resources[0].name, '3D-printer');
      expect(resources[0].displayName, '3D-printer');
      expect(resources[1].isMachine, isFalse);
      expect(resources[1].firstName, 'Alice');
      expect(resources[1].surname, 'Smith');
      expect(resources[1].displayName, 'Alice Smith');
    });

    test('medewerker zonder naam gebruikt name als displayName', () {
      const xml = '''
<resource-list xmlns="http://rest.ws.libreplan.dev">
  <worker code="w1" name="bw1" first-name="" surname=""/>
</resource-list>
''';
      final resources = parseResourceList(xml);
      expect(resources.single.displayName, 'bw1');
    });
  });

  group('parseWorkReportList', () {
    test('parseert werkrapporten met regels', () {
      const xml = '''
<work-report-list xmlns="http://rest.ws.libreplan.dev">
  <work-report code="wr1" work-order="PREFIX-001" resource="w1"
    date="2026-09-01" work-report-type="wrt1">
    <work-report-line-list>
      <work-report-line hours="4" work-order="PREFIX-001" resource="w1"
        date="2026-09-01" code="wrl1"/>
      <work-report-line hours="6" work-order="PREFIX-001" resource="w1"
        date="2026-09-01" code="wrl2"/>
    </work-report-line-list>
  </work-report>
</work-report-list>
''';
      final reports = parseWorkReportList(xml);
      expect(reports, hasLength(1));
      final report = reports.single;
      expect(report.code, 'wr1');
      expect(report.resource, 'w1');
      expect(report.workOrder, 'PREFIX-001');
      expect(report.date, DateTime(2026, 9, 1));
      expect(report.lines, hasLength(2));
      expect(report.lines[0].hours, 4.0);
      expect(report.lines[1].hours, 6.0);
    });
  });

  group('parseResourceHoursList', () {
    test('parseert resource-uren per datum', () {
      const xml = '''
<resource-worked-hours-list xmlns="http://rest.ws.libreplan.dev">
  <resource-worked-hours resource="w1" code="rwh1">
    <work-report-line-list>
      <work-report-line hours="4" date="2026-09-01" code="l1"/>
      <work-report-line hours="6" date="2026-09-02" code="l2"/>
    </work-report-line-list>
  </resource-worked-hours>
</resource-worked-hours-list>
''';
      final hours = parseResourceHoursList(xml);
      expect(hours, hasLength(2));
      expect(hours[0].resourceCode, 'w1');
      expect(hours[0].date, DateTime(2026, 9, 1));
      expect(hours[0].hours, 4.0);
      expect(hours[1].date, DateTime(2026, 9, 2));
    });
  });

  group('parseExpenseSheetList', () {
    test('parseert declaraties', () {
      const xml = '''
<expense-sheet-list xmlns="http://rest.ws.libreplan.dev">
  <expense-sheet code="e1" date="2026-09-01" resource="w1" total="42.50"/>
</expense-sheet-list>
''';
      final expenses = parseExpenseSheetList(xml);
      expect(expenses, hasLength(1));
      expect(expenses.single.total, 42.50);
      expect(expenses.single.date, DateTime(2026, 9, 1));
    });
  });

  group('limieten', () {
    test('XML groter dan maxBytes werpt een exceptie', () {
      final huge = '<order-list>${'x' * (libreplanXmlMaxBytes + 1)}</order-list>';
      expect(
        () => parseOrderList(huge),
        throwsA(isA<LibreplanXmlException>()),
      );
    });

    test('pathologisch diepe XML werpt een exceptie', () {
      // Bouw geldige XML dieper dan libreplanXmlMaxDepth, met correct
      // gesloten tags.
      final parts = <String>[];
      parts.add('<order-list xmlns="http://rest.ws.libreplan.dev">');
      parts.add('<order code="X" name="X"><children>');
      for (var i = 0; i <= libreplanXmlMaxDepth; i++) {
        parts.add('<order-line-group code="g$i" name="g$i"><children>');
      }
      for (var i = 0; i <= libreplanXmlMaxDepth; i++) {
        parts.add('</children></order-line-group>');
      }
      parts.add('</children></order></order-list>');
      expect(
        () => parseOrderList(parts.join()),
        throwsA(isA<LibreplanXmlException>()),
      );
    });
  });
}
