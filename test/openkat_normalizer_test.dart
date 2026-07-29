import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/models/openkat/openkat_models.dart';
import 'package:ocideck/services/openkat/openkat_directory_scanner.dart';
import 'package:ocideck/services/openkat/openkat_json_adapter.dart';
import 'package:ocideck/services/openkat/openkat_normalizer.dart';

class _ExplicitReferencesAdapter extends OpenKatJsonAdapter {
  final Map<String, dynamic> finding;

  const _ExplicitReferencesAdapter(this.finding);

  @override
  String get name => 'test-expliciete-verwijzingen';

  @override
  Set<OpenKatSourceFeature> get sourceFeatures => const {
    OpenKatSourceFeature.stableAssetIdentity,
    OpenKatSourceFeature.reliableCveReferences,
  };

  @override
  bool recognizes(Map<String, dynamic> json) => true;

  @override
  String? organizationCode(Map<String, dynamic> json) => 'alpha';

  @override
  String? organizationName(Map<String, dynamic> json) => 'Alpha';

  @override
  DateTime? reportDate(Map<String, dynamic> json) => DateTime.utc(2026, 7, 20);

  @override
  List<Map<String, dynamic>> systemObjects(Map<String, dynamic> json) => const [
    {'ooi': 'Hostname|internet|example.com', 'hostname': 'example.com'},
  ];

  @override
  List<Map<String, dynamic>> findingObjects(Map<String, dynamic> json) => [
    finding,
  ];

  @override
  Map<String, OpenKatControlScore> controlScores(Map<String, dynamic> json) =>
      const {};
}

OpenKatSnapshot _normalizeFinding(Map<String, dynamic> finding) {
  final adapter = _ExplicitReferencesAdapter(finding);
  final date = DateTime.utc(2026, 7, 20);
  final candidate = OpenKatSnapshotCandidate(
    path: 'alpha.json',
    hash: 'sha256:alpha',
    organizationCode: 'alpha',
    organizationName: 'Alpha',
    reportDate: date,
    schema: adapter.name,
    adapter: adapter,
    json: const {},
  );
  return const OpenKatNormalizer().normalize(
    OpenKatSnapshotGroup(
      organizationCode: 'alpha',
      organizationName: 'Alpha',
      reportDate: date,
      candidate: candidate,
    ),
    olderSnapshots: const [],
  );
}

/// De sleutelgrammatica van OpenKAT: elke primary key is een `|`-gescheiden
/// reeks die begint bij het objecttype en het *netwerk* waarin het object is
/// gevonden, en die voor samengestelde types de sleutels van zijn onderdelen
/// achter elkaar plakt.
///
/// De sleutels hieronder zijn overgenomen uit een echte uitdraai (organisaties
/// Geonovum, test, underdark). Ze staan er als toets omdat het deck dat eruit
/// rolde systemen toonde als `internet|185.73.32.3|tcp|443|https|internet|
/// underdark.nl` — het netwerksegment bleef hangen, samengestelde types werden
/// nooit tot hun host herleid, en bij een `IPPort` werd letterlijk het woord
/// "internet" als systeem gekozen. Eén website telde daardoor als tientallen
/// systemen, waardoor "89 kwetsbare systemen" boven de 45 systemen van het
/// portfolio uitkwam.
void main() {
  group('openKatSystemAnchor', () {
    test('een hostname verliest zijn netwerksegment', () {
      expect(
        openKatSystemAnchor('Hostname|internet|underdark.nl'),
        'underdark.nl',
      );
      expect(
        openKatSystemAnchor('DNSZone|internet|underdark.nl'),
        'underdark.nl',
      );
    });

    test('een IP-adres verliest zijn netwerksegment', () {
      expect(
        openKatSystemAnchor('IPAddressV4|internet|185.73.32.3'),
        '185.73.32.3',
      );
      expect(
        openKatSystemAnchor('IPAddressV6|internet|2a00:1450:400e:80c::200e'),
        '2a00:1450:400e:80c::200e',
      );
    });

    test('een poort en een dienst horen bij hun IP-adres', () {
      // Hier koos de oude code het tweede segment: "internet".
      expect(
        openKatSystemAnchor('IPPort|internet|185.73.32.3|tcp|443'),
        '185.73.32.3',
      );
      expect(
        openKatSystemAnchor('IPService|internet|185.73.32.3|tcp|443|https'),
        '185.73.32.3',
      );
    });

    test('een samengesteld type herleidt tot zijn hostname', () {
      expect(
        openKatSystemAnchor(
          'Website|internet|185.73.32.3|tcp|443|https|internet|underdark.nl',
        ),
        'underdark.nl',
      );
      expect(
        openKatSystemAnchor('HostnameHTTPURL|https|internet|librekat.nl|443|/'),
        'librekat.nl',
      );
    });

    test('alle paden van één website zijn één systeem', () {
      // Dit is waar de tabel "Systemen met de meeste findings" op stukliep: elk
      // pad en elke header stond er als eigen regel.
      const basis =
          'HTTPResource|internet|185.73.32.3|tcp|443|https|internet|'
          'css.underdark.nl|https|internet|css.underdark.nl|443';
      expect(openKatSystemAnchor('$basis|/'), 'css.underdark.nl');
      expect(openKatSystemAnchor('$basis|/stable/'), 'css.underdark.nl');
      expect(
        openKatSystemAnchor('$basis|/.well-known/security.txt'),
        'css.underdark.nl',
      );
    });

    test('een HTTP-header hoort bij de website, niet bij zichzelf', () {
      // De laatste segmenten zijn een pad en een headernaam; geen van beide is
      // een host, en juist die verwarring maakte er een eigen "systeem" van.
      expect(
        openKatSystemAnchor(
          'HTTPHeader|internet|185.73.32.3|tcp|443|https|internet|underdark.nl|'
          'https|internet|underdark.nl|443|/|Strict-Transport-Security',
        ),
        'underdark.nl',
      );
    });

    test('een URL herleidt tot zijn host', () {
      expect(
        openKatSystemAnchor('URL|internet|https://example.com/pad/naar/iets'),
        'example.com',
      );
    });

    test('een bevinding op het netwerk zelf houdt de netwerknaam', () {
      expect(openKatSystemAnchor('Network|internet'), 'internet');
    });

    test('hoofdletters in een hostname vallen samen', () {
      expect(
        openKatSystemAnchor('Hostname|internet|Underdark.NL'),
        'underdark.nl',
      );
    });

    test('een sleutel zonder netwerksegment blijft werken', () {
      // De korte vorm die de bestaande toetsen gebruiken.
      expect(openKatSystemAnchor('hostname|example.com'), 'example.com');
      expect(openKatSystemAnchor('ipaddressv4|1.2.3.4'), '1.2.3.4');
      expect(openKatSystemAnchor('example.com'), 'example.com');
    });

    test('een onbekende sleutel valt terug in plaats van te raden', () {
      expect(openKatSystemAnchor(''), '');
      expect(openKatSystemAnchor('KATFindingType|KAT-NO-CAA'), 'KAT-NO-CAA');
    });

    test('de velden van het object gaan voor op de terugval', () {
      expect(
        openKatSystemAnchor('Onbekend|iets', const {
          'hostname': 'echte-host.nl',
        }),
        'echte-host.nl',
      );
    });
  });

  group('expliciete bronsemantiek', () {
    test('CVE-ID’s komen alleen uit het daarvoor bestemde bronveld', () {
      final snapshot = _normalizeFinding({
        'finding_type': {'id': 'KAT-X', 'name': 'Finding X'},
        'primary_key': 'KATFinding|alpha|1',
        'ooi': 'Hostname|internet|example.com',
        'description': 'Vrije tekst noemt CVE-2099-9999 maar bewijst niets.',
        'cve_ids': [
          'cve-2026-1234',
          'CVE-2026-1234',
          'CVE-2026-76543',
          'geen-cve',
        ],
      });

      expect(snapshot.findings.single.cveIds, [
        'CVE-2026-1234',
        'CVE-2026-76543',
      ]);
      expect(snapshot.findings.single.stableIdentity, isTrue);
      expect(
        snapshot.sourceFeatures,
        contains(OpenKatSourceFeature.reliableCveReferences),
      );
    });

    test('vrije tekst wordt nooit als CVE-koppeling geïnterpreteerd', () {
      final snapshot = _normalizeFinding({
        'finding_type': {'id': 'KAT-X', 'name': 'CVE-2026-1234'},
        'ooi': 'Hostname|internet|example.com',
        'description': 'Zie CVE-2026-5678.',
      });

      expect(snapshot.findings.single.cveIds, isEmpty);
      expect(snapshot.findings.single.stableIdentity, isFalse);
    });
  });
}
