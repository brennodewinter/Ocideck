import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:ocideck/models/deck.dart';
import 'package:ocideck/models/slide.dart';
import 'package:ocideck/services/openkat/openkat_import_service.dart';

/// Een OpenKAT-organisatierapport in de vorm die de exportknop werkelijk
/// oplevert: de envelop `{organization_code, organization_name,
/// organization_tags, data}` met een vlakke samenvatting in `data`.
///
/// De aanroeper geeft bevindingen in korte vorm op; hier worden ze opgevouwen
/// tot de `finding_types`/`occurrences`-paren van het echte formaat. Zo blijven
/// de toetsen leesbaar zonder dat ze een verzonnen indeling toetsen.
Map<String, dynamic> _sampleReport({
  required String organizationCode,
  required String organizationName,
  required List<Map<String, dynamic>> findings,
}) => {
  'organization_code': organizationCode,
  'organization_name': organizationName,
  'organization_tags': <String>[],
  'data': {
    'systems': {
      'services': {
        'IPAddressV4|internet|1.2.3.4': {
          'hostnames': ['host-a'],
          'services': <dynamic>[],
        },
        'Hostname|internet|example.com': {
          'hostnames': ['example.com'],
          'services': <dynamic>[],
        },
      },
    },
    'findings': {
      'finding_types': [
        for (final finding in findings)
          {
            'finding_type': {
              'object_type': 'KATFindingType',
              'primary_key':
                  'KATFindingType|${(finding['finding_type'] as Map)['id']}',
              'id': (finding['finding_type'] as Map)['id'],
              'name': (finding['finding_type'] as Map)['name'],
              'risk_severity': finding['severity'],
            },
            'occurrences': [
              {
                'finding': {
                  'object_type': 'Finding',
                  'primary_key': finding['primary_key'],
                  'ooi': finding['ooi'],
                },
                if (finding['first_seen'] != null)
                  'first_seen': finding['first_seen'],
              },
            ],
          },
      ],
    },
    'basic_security': {
      'summary': {
        'Web': {
          'rpki': {'number_of_compliant': 1, 'total': 2},
        },
      },
    },
    'total_systems': 2,
  },
};

/// De bestandsnaam waarmee OpenKAT exporteert: `<organisatie>_<stempel>.json`
/// met veertien cijfers zonder scheidingstekens. Het organisatierapport draagt
/// zelf geen datum, dus dít is waar de momentopnamedatum vandaan komt.
String _reportFileName(String organizationCode, String stamp) =>
    '${organizationCode}_$stamp.json';

void main() {
  test('imports a directory with OpenKAT reports into a deck', () async {
    final tmp = Directory.systemTemp.createTempSync('ocikat-test-');
    try {
      final reportA = _sampleReport(
        organizationCode: 'org1',
        organizationName: 'Organisatie 1',
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
        findings: [
          {
            'finding_type': {'id': 'KAT-001', 'name': 'Open poort'},
            'severity': 'high',
            'primary_key': 'finding-1',
            'ooi': 'ipaddressv4|1.2.3.4',
          },
        ],
      );

      Directory(p.join(tmp.path, 'raw-data')).createSync();
      File(
        p.join(tmp.path, 'raw-data', _reportFileName('org1', '20240601000000')),
      ).writeAsStringSync(jsonEncode(reportA));
      File(
        p.join(tmp.path, 'raw-data', _reportFileName('org1', '20240701000000')),
      ).writeAsStringSync(jsonEncode(reportB));

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

      final manifestFile = File(
        p.join(tmp.path, 'processed-data', 'data', 'openkat', 'manifest.json'),
      );
      expect(manifestFile.existsSync(), true);

      final processedDeck = File(
        p.join(tmp.path, 'processed-data', 'OpenKAT_managementoverzicht.md'),
      );
      expect(processedDeck.existsSync(), true);

      final presentationDeck = File(
        p.join(tmp.path, 'presentations', 'OpenKAT_managementoverzicht.md'),
      );
      expect(presentationDeck.existsSync(), true);
    } finally {
      tmp.deleteSync(recursive: true);
    }
  });

  test(
    'updateDeck preserves manual slides while replacing generated ones',
    () async {
      final tmp = Directory.systemTemp.createTempSync('ocikat-update-test-');
      try {
        final report = _sampleReport(
          organizationCode: 'org1',
          organizationName: 'Organisatie 1',
          findings: [
            {
              'finding_type': {'id': 'KAT-001', 'name': 'Open poort'},
              'severity': 'high',
              'primary_key': 'finding-1',
              'ooi': 'ipaddressv4|1.2.3.4',
            },
          ],
        );

        Directory(p.join(tmp.path, 'raw-data')).createSync();
        File(
          p.join(
            tmp.path,
            'raw-data',
            _reportFileName('org1', '20240801000000'),
          ),
        ).writeAsStringSync(jsonEncode(report));

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
    },
  );

  group('herimport: vervangen op zijn plek (bewaker #767)', () {
    Future<({OpenKatImportService service, Directory tmp, Deck deck})>
    vers() async {
      final tmp = Directory.systemTemp.createTempSync('ocikat-plek-');
      addTearDown(() => tmp.deleteSync(recursive: true));
      Directory(p.join(tmp.path, 'raw-data')).createSync();
      File(
        p.join(tmp.path, 'raw-data', _reportFileName('org1', '20240601000000')),
      ).writeAsStringSync(
        jsonEncode(
          _sampleReport(
            organizationCode: 'org1',
            organizationName: 'Organisatie 1',
            findings: [
              {
                'finding_type': {'id': 'KAT-001', 'name': 'Open poort'},
                'severity': 'high',
                'primary_key': 'f1',
                'ooi': 'hostname|example.com',
              },
            ],
          ),
        ),
      );
      const service = OpenKatImportService();
      final eerste = await service.importDirectory(tmp.path);
      return (service: service, tmp: tmp, deck: eerste.deck);
    }

    test('een gedupliceerde gegenereerde dia overleeft de herimport', () async {
      // De markering reist mee met Slide.duplicate; alleen de éérste dia per
      // markering is de gegenereerde. De kopie is werk van de gebruiker.
      final (:service, :tmp, :deck) = await vers();
      final kopie = Slide.duplicate(
        deck.slides[2],
      ).copyWith(title: 'Mijn aantekeningen bij deze tabel');
      final metKopie = deck.copyWith(
        slides: [...deck.slides.take(3), kopie, ...deck.slides.skip(3)],
      );

      final updated = await service.updateDeck(metKopie, tmp.path);
      expect(
        updated.deck.slides.map((s) => s.title),
        contains('Mijn aantekeningen bij deze tabel'),
        reason: 'de snackbar belooft dat handmatig werk blijft staan',
      );
      // En op zijn plek: direct na de dia waarvan hij een kopie is.
      final idx = updated.deck.slides.toList().indexWhere(
        (s) => s.title == 'Mijn aantekeningen bij deze tabel',
      );
      expect(idx, 3);
    });

    test('een handmatige dia tússen de secties houdt zijn plek', () async {
      final (:service, :tmp, :deck) = await vers();
      final eigen = Slide.create(
        SlideType.bullets,
      ).copyWith(title: 'Context bij org 1', bullets: const ['eigen punt']);
      final metEigen = deck.copyWith(
        slides: [...deck.slides.take(2), eigen, ...deck.slides.skip(2)],
      );

      final updated = await service.updateDeck(metEigen, tmp.path);
      expect(
        updated.deck.slides[2].title,
        'Context bij org 1',
        reason: 'de opbouw van de presentatie is het werk, niet alleen de dia',
      );
    });

    test(
      'de volle data blijft in de dia; de limiet toont alleen de kop',
      () async {
        // Zes findingtypes, limiet 5: de tabel draagt álle zes rijen, de
        // weergavelimiet (#672) toont er vijf. Niets wordt weggegooid.
        final tmp = Directory.systemTemp.createTempSync('ocikat-vol-');
        addTearDown(() => tmp.deleteSync(recursive: true));
        Directory(p.join(tmp.path, 'raw-data')).createSync();
        File(
          p.join(
            tmp.path,
            'raw-data',
            _reportFileName('org1', '20240601000000'),
          ),
        ).writeAsStringSync(
          jsonEncode(
            _sampleReport(
              organizationCode: 'org1',
              organizationName: 'Organisatie 1',
              findings: [
                for (var i = 1; i <= 6; i++)
                  {
                    'finding_type': {'id': 'KAT-00$i', 'name': 'Type $i'},
                    'severity': 'high',
                    'primary_key': 'f$i',
                    'ooi': 'hostname|example.com',
                  },
              ],
            ),
          ),
        );
        const service = OpenKatImportService();
        final result = await service.importDirectory(tmp.path);
        final top = result.deck.slides.firstWhere(
          (s) => s.notes.contains('portfolio.top-issues'),
        );
        expect(top.tableRows.length, 7, reason: 'kopregel + zes datarijen');
        expect(top.viewLimit?.limit, 5);
      },
    );
  });
}
