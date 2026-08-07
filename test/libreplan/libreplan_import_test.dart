import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/models/libreplan_settings.dart';
import 'package:ocideck/models/slide.dart';
import 'package:ocideck/services/libreplan/libreplan_client.dart';
import 'package:ocideck/services/libreplan/libreplan_import.dart';

class _FakeClient extends LibreplanClient {
  _FakeClient(this._responses)
    : super(
        settings: const LibreplanSettings(
          enabled: true,
          baseUrl: 'https://libreplan.example.org/libreplan/',
          username: 'wsreader',
        ),
        password: 'secret',
        isWeb: false,
      );

  final Map<String, String> _responses;

  @override
  Future<String> fetch(String servicePath) async {
    if (_responses.containsKey(servicePath)) return _responses[servicePath]!;
    final key = servicePath.replaceAll(RegExp(r'/+$'), '');
    if (_responses.containsKey(key)) return _responses[key]!;
    throw LibreplanRequestException('no mock for $servicePath');
  }
}

const _orderXml = '''
<order-list xmlns="http://rest.ws.libreplan.dev">
  <order code="ORDER-1" name="Project X" init-date="2026-09-01">
    <children>
      <order-line code="T1" name="Vooronderzoek" start-date="2026-09-01"
        progress="1.0">
        <hours-groups>
          <hours-group code="HG1" working-hours="40" resource-type="WORKER"/>
        </hours-groups>
      </order-line>
      <order-line code="M1" name="Go/No-Go" milestone="true"
        start-date="2026-09-15"/>
    </children>
  </order>
</order-list>
''';

const _resourceXml = '''
<resource-list xmlns="http://rest.ws.libreplan.dev">
  <machine code="m1" name="3D-printer"/>
  <worker code="w1" first-name="Alice" surname="Smith"/>
</resource-list>
''';

const _workReportXml = '''
<work-report-list xmlns="http://rest.ws.libreplan.dev">
  <work-report code="wr1" resource="w1" work-order="TASK-1" date="2026-09-01">
    <work-report-line-list>
      <work-report-line hours="4" resource="w1" work-order="TASK-1"
        date="2026-09-01" code="l1"/>
    </work-report-line-list>
  </work-report>
</work-report-list>
''';

void main() {
  group('LibreplanImporter.import', () {
    test('produceert slides voor alle geselecteerde types', () async {
      final client = _FakeClient({
        'orderelements/': _orderXml,
        'resources/': _resourceXml,
        'workreports/': _workReportXml,
      });
      final importer = LibreplanImporter(client);

      final result = await importer.import();

      expect(result.slides, hasLength(7));
      expect(result.slides.map((s) => s.type), contains(SlideType.gantt));
      expect(result.slides.map((s) => s.type), contains(SlideType.tree));
      expect(result.slides.map((s) => s.type), contains(SlideType.table));
      expect(result.slides.map((s) => s.type), contains(SlideType.cockpit));
      expect(result.slides.map((s) => s.type), contains(SlideType.timeline));
      expect(result.slides.map((s) => s.type), contains(SlideType.flow));
    });

    test('waarschuwt bij lege projectlijst', () async {
      final client = _FakeClient({
        'orderelements/': '<order-list xmlns="http://rest.ws.libreplan.dev"/>',
      });
      final importer = LibreplanImporter(client);

      final result = await importer.import(
        options: const LibreplanImportOptions(
          resources: false,
          timesheet: false,
          resourceLoad: false,
        ),
      );

      expect(result.slides, isEmpty);
      expect(result.warnings, contains(contains('Geen projecten')));
    });

    test('waarschuwt bij meerdere projecten', () async {
      final multiOrderXml = '''
<order-list xmlns="http://rest.ws.libreplan.dev">
  <order code="A" name="Project A"/>
  <order code="B" name="Project B"/>
</order-list>
''';
      final client = _FakeClient({'orderelements/': multiOrderXml});
      final importer = LibreplanImporter(client);

      final result = await importer.import(
        options: const LibreplanImportOptions(
          resources: false,
          timesheet: false,
          resourceLoad: false,
        ),
      );

      final multiWarning = result.warnings.firstWhere(
        (w) => w.contains('2 projecten'),
      );
      // De waarschuwing mag geen keuzemogelijkheid suggereren die niet
      // bestaat: er is geen projectkeuze-veld, de import neemt altijd het
      // eerste project.
      expect(multiWarning, isNot(contains('projectcode')));
      expect(multiWarning, isNot(contains('Selecteer een specifiek project')));
      // Hij moet wél eerlijk zeggen dat alleen het eerste is geïmporteerd.
      expect(multiWarning, contains('alleen het eerste'));
      expect(multiWarning, contains('Project A'));
      expect(result.slides, isNotEmpty);
    });

    test('faalt niet bij één falende endpoint', () async {
      final client = _FakeClient({'orderelements/': _orderXml});
      final importer = LibreplanImporter(client);

      final result = await importer.import(
        options: const LibreplanImportOptions(
          resourceLoad: false,
          timesheet: false,
        ),
      );

      expect(result.slides, hasLength(5));
      expect(
        result.warnings,
        anyElement(contains('Resources ophalen mislukt')),
      );
    });

    test('lege opties geven een warning', () async {
      final client = _FakeClient({});
      final importer = LibreplanImporter(client);

      final result = await importer.import(
        options: const LibreplanImportOptions(
          gantt: false,
          wbs: false,
          resources: false,
          timesheet: false,
          resourceLoad: false,
          status: false,
          milestones: false,
          criticalPath: false,
        ),
      );

      expect(result.slides, isEmpty);
      expect(result.warnings, contains('Geen slide-types geselecteerd.'));
    });
  });
}
