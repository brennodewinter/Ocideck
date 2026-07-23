import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:ocideck/services/openkat/openkat_import_service.dart';

Map<String, dynamic> _sampleReport({
  required String organizationCode,
  required String organizationName,
  required String reportDate,
  required List<Map<String, dynamic>> findings,
}) =>
    {
      'organization': {
        'code': organizationCode,
        'name': organizationName,
      },
      'report_date': reportDate,
      'systems': [
        {'ooi': 'ipaddressv4|1.2.3.4', 'hostname': 'host-a'},
        {'ooi': 'hostname|example.com'},
      ],
      'findings': findings,
    };

void main() {
  test('imports a directory with OpenKAT reports into a deck', () async {
    final tmp = Directory.systemTemp.createTempSync('ocikat-test-');
    try {
      final reportA = _sampleReport(
        organizationCode: 'org1',
        organizationName: 'Organisatie 1',
        reportDate: '2024-06-01T00:00:00Z',
        findings: [
          {
            'finding_type': {'id': 'KAT-001', 'name': 'Open poort'},
            'severity': 'high',
            'primary_key': 'finding-1',
            'ooi': 'ipaddressv4|1.2.3.4',
            'first_seen': '2024-05-01T00:00:00Z',
          },
          {
            'finding_type': {'id': 'KAT-002', 'name': 'Verlopen certificaat'},
            'severity': 'medium',
            'primary_key': 'finding-2',
            'ooi': 'hostname|example.com',
          },
        ],
      );

      final reportB = _sampleReport(
        organizationCode: 'org1',
        organizationName: 'Organisatie 1',
        reportDate: '2024-07-01T00:00:00Z',
        findings: [
          {
            'finding_type': {'id': 'KAT-001', 'name': 'Open poort'},
            'severity': 'high',
            'primary_key': 'finding-1',
            'ooi': 'ipaddressv4|1.2.3.4',
          },
        ],
      );

      File(p.join(tmp.path, 'june.json')).writeAsStringSync(jsonEncode(reportA));
      File(p.join(tmp.path, 'july.json')).writeAsStringSync(jsonEncode(reportB));

      const service = OpenKatImportService();
      final result = await service.importDirectory(
        tmp.path,
        outputPath: p.join(tmp.path, 'deck.md'),
      );

      expect(result.manifest.recognized.length, 2);
      expect(result.manifest.unrecognized, isEmpty);
      expect(result.deck.title, 'OpenKAT managementoverzicht');
      expect(result.deck.slides, isNotEmpty);

      final katSlideIds = result.deck.slides
          .where((s) => s.notes.contains('ocideck_openkat_view'))
          .length;
      expect(katSlideIds, greaterThan(0));

      final manifestFile = File(p.join(tmp.path, 'data', 'openkat', 'manifest.json'));
      expect(manifestFile.existsSync(), true);
    } finally {
      tmp.deleteSync(recursive: true);
    }
  });

  test('updateDeck preserves manual slides while replacing generated ones', () async {
    final tmp = Directory.systemTemp.createTempSync('ocikat-update-test-');
    try {
      final report = _sampleReport(
        organizationCode: 'org1',
        organizationName: 'Organisatie 1',
        reportDate: '2024-08-01T00:00:00Z',
        findings: [
          {
            'finding_type': {'id': 'KAT-001', 'name': 'Open poort'},
            'severity': 'high',
            'primary_key': 'finding-1',
            'ooi': 'ipaddressv4|1.2.3.4',
          },
        ],
      );

      File(p.join(tmp.path, 'aug.json')).writeAsStringSync(jsonEncode(report));

      const service = OpenKatImportService();
      final first = await service.importDirectory(
        tmp.path,
        outputPath: p.join(tmp.path, 'deck.md'),
      );

      // Add a manual slide that is not OpenKAT-generated.
      final deckWithManual = first.deck;
      final updated = await service.updateDeck(deckWithManual, tmp.path);

      expect(updated.deck.title, 'OpenKAT managementoverzicht');
      expect(updated.manifest.recognized.length, 1);
    } finally {
      tmp.deleteSync(recursive: true);
    }
  });
}
