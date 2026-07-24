// Toetst de twee OpenKAT-exportvormen op de plekken waar ze werkelijk van
// elkaar verschillen. De vorm van de brokken hieronder komt uit echte exports
// (een organisatie-export en een assetrapport-export); de namen en adressen
// zijn vervangen, want andermans scandata hoort niet in deze repo.
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/services/openkat/openkat_export_adapters.dart';
import 'package:ocideck/services/openkat/openkat_json_adapter.dart';

Map<String, dynamic> _organisatierapport() => {
  'organization_code': 'voorbeeld',
  'organization_name': 'Voorbeeld',
  'organization_tags': <String>[],
  'data': {
    'systems': {
      'services': {
        'IPAddressV4|internet|192.0.2.10': {
          'hostnames': ['www.example.org', 'example.org'],
          'services': ['http'],
        },
      },
    },
    'findings': {
      'finding_types': [
        {
          'finding_type': {
            'object_type': 'KATFindingType',
            'primary_key': 'KATFindingType|KAT-NO-DNSSEC',
            'id': 'KAT-NO-DNSSEC',
            'name': 'DNSSEC not enabled',
            'recommendation': 'Enable DNSSEC.',
            'impact': 'DNS requests are not authenticated.',
            'risk_severity': 'medium',
          },
          'occurrences': [
            {
              'finding': {
                'primary_key':
                    'Finding|Hostname|internet|example.org|KAT-NO-DNSSEC',
                'ooi': 'Hostname|internet|example.org',
                'description': 'The provided domain does not have DNSSEC.',
              },
              'first_seen': '2026-07-11 11:50:14+00:00',
            },
            {
              'finding': {
                'primary_key':
                    'Finding|Hostname|internet|www.example.org|KAT-NO-DNSSEC',
                'ooi': 'Hostname|internet|www.example.org',
              },
            },
          ],
        },
      ],
    },
    'basic_security': {
      'summary': {
        'Web': {
          'rpki': {'number_of_compliant': 1, 'total': 2},
          'system_specific': {
            'number_of_compliant': 0,
            'total': 1,
            'checks': {'CSP Present': 0},
          },
        },
        'Mail': {
          'rpki': {'number_of_compliant': 2, 'total': 2},
        },
      },
    },
    'total_systems': 1,
  },
};

Map<String, dynamic> _assetrapporten() => {
  'organization_code': 'voorbeeld',
  'organization_name': 'Voorbeeld',
  'organization_tags': <String>[],
  'data': {
    'systems-report': {
      'Hostname|internet|example.org': {
        'template': 'systems_report/report.html',
        'report_name': 'System Report for example.org',
        'created_at': '20260319200604',
        'data': {
          'input_ooi': 'Hostname|internet|example.org',
          'services': {
            'IPAddressV4|internet|192.0.2.10': {
              'hostnames': ['example.org'],
              'services': ['http'],
            },
          },
        },
      },
    },
    'name-server-report': {
      'Hostname|internet|example.org': {
        'template': 'name_server_report/report.html',
        'created_at': '20260319200604',
        'data': {
          'input_ooi': 'Hostname|internet|example.org',
          // Kale KATFindingType-objecten: het deelrapport noemt het type, de
          // OOI is die van het rapport zelf.
          'finding_types': [
            {
              'object_type': 'KATFindingType',
              'primary_key': 'KATFindingType|KAT-NO-DNSSEC',
              'id': 'KAT-NO-DNSSEC',
              'name': 'DNSSEC not enabled',
              'recommendation': 'Enable DNSSEC.',
              'risk_severity': 'medium',
            },
            {
              'object_type': 'KATFindingType',
              'primary_key': 'KATFindingType|KAT-NO-SECURITY-TXT',
              'id': 'KAT-NO-SECURITY-TXT',
              // In echte exports is `name` hier geregeld null.
              'name': null,
              'risk_severity': 'recommendation',
            },
          ],
        },
      },
    },
    'rpki-report': {
      'Hostname|internet|example.org': {
        'template': 'rpki_report/report.html',
        'created_at': '20260319200604',
        'data': {
          'input_ooi': 'Hostname|internet|example.org',
          'number_of_compliant': 3,
          'number_of_ips': 4,
        },
      },
    },
  },
};

void main() {
  group('herkenning', () {
    test('elke vorm kiest zijn eigen adapter', () {
      final gekozen = <String, String>{};
      for (final bron in {
        'organisatie': _organisatierapport(),
        'assets': _assetrapporten(),
      }.entries) {
        final adapter = openKatAdapters.firstWhere(
          (a) => a.recognizes(bron.value),
        );
        gekozen[bron.key] = adapter.name;
      }
      expect(gekozen['organisatie'], 'openkat-organisatierapport');
      expect(gekozen['assets'], 'openkat-assetrapporten');
    });

    test('wat geen OpenKAT-envelop is wordt door niets herkend', () {
      // Dit is de invoerpoort: de map komt van buiten. Een willekeurig
      // JSON-bestand dat toevallig in de map ligt hoort als "unrecognized" in
      // het manifest te belanden, niet half geïmporteerd te worden.
      for (final vreemd in [
        <String, dynamic>{'organization_code': 'x'}, // envelop zonder data
        <String, dynamic>{'data': <String, dynamic>{}}, // data zonder envelop
        <String, dynamic>{'organization_code': 'x', 'data': 'geen map'},
        <String, dynamic>{},
      ]) {
        expect(
          openKatAdapters.any((a) => a.recognizes(vreemd)),
          isFalse,
          reason: 'herkend als OpenKAT: $vreemd',
        );
      }
    });
  });

  group('organisatierapport', () {
    const adapter = OpenKatAggregateReportAdapter();

    test('organisatie komt uit de envelop', () {
      final json = _organisatierapport();
      expect(adapter.organizationCode(json), 'voorbeeld');
      expect(adapter.organizationName(json), 'Voorbeeld');
    });

    test('systemen dragen hun IP en eerste hostnaam', () {
      final systemen = adapter.systemObjects(_organisatierapport());
      expect(systemen, hasLength(1));
      expect(systemen.first['ooi'], 'IPAddressV4|internet|192.0.2.10');
      expect(systemen.first['ip'], '192.0.2.10');
      expect(systemen.first['hostname'], 'www.example.org');
    });

    test('elke waarneming is een bevinding, niet elk type', () {
      // Eén findingtype met twee waarnemingen levert twee bevindingen op.
      // Zou dit één regel geven, dan telde een probleem op twintig systemen
      // even zwaar als op één.
      final bevindingen = adapter.findingObjects(_organisatierapport());
      expect(bevindingen, hasLength(2));
      expect(
        bevindingen.map((f) => f['ooi']),
        containsAll([
          'Hostname|internet|example.org',
          'Hostname|internet|www.example.org',
        ]),
      );
      expect(bevindingen.first['severity'], 'medium');
      expect(bevindingen.first['recommendation'], 'Enable DNSSEC.');
      expect(bevindingen.first['impact'], isNotNull);
    });

    test('basisbeveiliging houdt de noemer vast', () {
      // Zonder noemer is OpenKatControlScore.ratio null en kan de aggregator
      // geen trend berekenen — dat was precies het gebrek in de eerste opzet.
      final controls = adapter.controlScores(_organisatierapport());
      expect(controls['rpki (Web)']?.compliant, 1);
      expect(controls['rpki (Web)']?.total, 2);
      expect(controls['rpki (Web)']?.ratio, 0.5);
      expect(
        controls['rpki (Mail)']?.ratio,
        1.0,
        reason: 'termen worden niet op één hoop gegooid',
      );
      expect(controls['system_specific (Web)']?.total, 1);
    });
  });

  group('assetrapporten', () {
    const adapter = OpenKatAssetReportsAdapter();

    test('de datum komt uit het stempel in het rapportblok', () {
      expect(
        adapter.reportDate(_assetrapporten()),
        DateTime.utc(2026, 3, 19, 20, 6, 4),
      );
    });

    test('systemen komen uit het systems-report', () {
      final systemen = adapter.systemObjects(_assetrapporten());
      expect(systemen, hasLength(1));
      expect(systemen.first['ip'], '192.0.2.10');
    });

    test(
      'bevindingen komen uit de deelrapporten, niet uit findings-report',
      () {
        // Dit is het verschil dat de vorige adapter miste: de deelrapporten
        // dragen de bevindingen, en findings-report is in echte exports leeg.
        final bevindingen = adapter.findingObjects(_assetrapporten());
        expect(bevindingen, hasLength(2));
        expect(
          bevindingen.map((f) => (f['finding_type'] as Map)['id']),
          containsAll(['KAT-NO-DNSSEC', 'KAT-NO-SECURITY-TXT']),
        );
        expect(
          bevindingen.every((f) => f['ooi'] == 'Hostname|internet|example.org'),
          isTrue,
          reason: 'een kaal type hoort bij de OOI van zijn rapport',
        );
      },
    );

    test('een type zonder naam valt terug op zijn id', () {
      final bevindingen = adapter.findingObjects(_assetrapporten());
      final zonderNaam = bevindingen.firstWhere(
        (f) => (f['finding_type'] as Map)['id'] == 'KAT-NO-SECURITY-TXT',
      );
      expect(
        (zonderNaam['finding_type'] as Map)['name'],
        'KAT-NO-SECURITY-TXT',
      );
    });

    test('rpki telt op over de rapporten, mét noemer', () {
      final controls = adapter.controlScores(_assetrapporten());
      expect(controls['rpki-report']?.compliant, 3);
      expect(controls['rpki-report']?.total, 4);
    });

    test('een deelrapport zonder noemer levert geen score', () {
      // Een score zonder noemer is geen score; name-server-report draagt er
      // geen, dus die hoort niet als control op te duiken.
      final controls = adapter.controlScores(_assetrapporten());
      expect(controls.containsKey('name-server-report'), isFalse);
    });
  });

  group('datums uit bestandsnamen', () {
    test('het stempel van de exportknop wordt gelezen', () {
      expect(
        OpenKatJsonAdapter.dateFromFilename('geonovum_20260319200604.json'),
        DateTime.utc(2026, 3, 19, 20, 6, 4),
      );
    });

    test('de geschreven vorm met streepjes blijft werken', () {
      expect(
        OpenKatJsonAdapter.dateFromFilename('rapport-2026-03-19.json'),
        DateTime.utc(2026, 3, 19),
      );
    });

    test('onzin levert niets op in plaats van een verzonnen datum', () {
      expect(OpenKatJsonAdapter.dateFromFilename('rapport.json'), isNull);
      expect(
        OpenKatJsonAdapter.dateFromFilename('versie-20261399.json'),
        isNull,
        reason: 'maand 13 en dag 99 bestaan niet',
      );
    });
  });
}
