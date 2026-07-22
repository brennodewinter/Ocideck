@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/models/local_cve_status.dart';
import 'package:ocideck/services/cve/cve_bulk_ingest.dart';
import 'package:ocideck/services/cve/local_cve_database_io.dart';

/// De desktop-helft van de lokale CVE-database: de schil om de index heen
/// ([IoLocalCveDatabase]) en de netwerkuitgang die het bulkarchief ophaalt
/// ([GithubBulkTransport]).
///
/// De index zelf staat in `local_cve_index_test`, de ingest-keten in
/// `cve_bulk_ingest_test`. Hier gaat het om wat dit bestand toevoegt: dat de
/// schil bouwt, zoekt, telt en wist op dezelfde wortel, en dat de transport de
/// SSRF-poort hóudt — hij volgt redirects met de hand juist omdat
/// `HttpClient` ze zou volgen langs de poort heen.
void main() {
  late Directory tmp;

  setUp(() => tmp = Directory.systemTemp.createTempSync('ocideck-cve-io-'));
  tearDown(() {
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  Map<String, dynamic> cveJson(String id, String title, String description) => {
    'dataType': 'CVE_RECORD',
    'dataVersion': '5.1',
    'cveMetadata': {
      'cveId': id,
      'state': 'PUBLISHED',
      'datePublished': '2021-12-10T00:00:00.000Z',
    },
    'containers': {
      'cna': {
        'title': title,
        'descriptions': [
          {'lang': 'en', 'value': description},
        ],
      },
    },
  };

  /// De echte vorm van de bron: een zip die één `cves.zip` bevat.
  List<int> nestedArchive() {
    final inner = Archive();
    void add(String path, Map<String, dynamic> json) =>
        inner.add(ArchiveFile.bytes(path, utf8.encode(jsonEncode(json))));
    add(
      'cves/2021/44xxx/CVE-2021-44228.json',
      cveJson(
        'CVE-2021-44228',
        'Log4Shell',
        'Remote code execution in Apache Log4j2.',
      ),
    );
    add(
      'cves/2014/0xxx/CVE-2014-0160.json',
      cveJson('CVE-2014-0160', 'Heartbleed', 'Information leak in OpenSSL.'),
    );
    return ZipEncoder().encode(
      Archive()..add(ArchiveFile.bytes('cves.zip', ZipEncoder().encode(inner))),
    );
  }

  IoLocalCveDatabase database() => IoLocalCveDatabase(
    root: Directory('${tmp.path}/cve'),
    transport: _FakeTransport(nestedArchive()),
  );

  test('op desktop meldt de database zich als aanwezig', () {
    expect(localCveSupported, isTrue);
    expect(database().supported, isTrue);
  });

  test('zonder gebouwde index zijn er geen cijfers en geen treffers', () async {
    final db = database();
    expect(await db.stats(), isNull);
    expect(await db.search('log4j'), isEmpty);
  });

  test('bouwen vult de index, zoeken vindt hem terug, wissen ruimt op', () async {
    final db = database();

    final voortgang = <CveIngestProgress>[];
    final stats = await db.build(
      onProgress: voortgang.add,
      isCancelled: () => false,
    );

    expect(stats.records, 2);
    expect(
      voortgang,
      isNotEmpty,
      reason:
          'zonder voortgang staat de gebruiker minutenlang naar niets te '
          'kijken',
    );

    // De cijfers komen uit dezelfde wortel als waar gebouwd is — een schil die
    // een andere map leest, meldt "geen database" op iets dat er wél staat.
    expect((await db.stats())!.records, 2);

    final treffers = await db.search('log4j');
    expect(treffers.map((r) => r.id), contains('CVE-2021-44228'));
    expect(treffers.first.title, isNotEmpty);

    // Zoeken is begrensd: een limiet die niet doorkomt, laat een brede term de
    // hele database in het geheugen trekken.
    expect(await db.search('e', limit: 1), hasLength(1));

    await db.delete();
    expect(await db.stats(), isNull);
    expect(await db.search('log4j'), isEmpty);
  });

  group('de netwerkuitgang houdt de poort dicht', () {
    const transport = GithubBulkTransport();

    Future<CveIngestException> weigering(Future<void> Function() body) async {
      try {
        await body();
        fail('dit had geweigerd moeten worden');
      } on CveIngestException catch (e) {
        return e;
      }
    }

    test('alles wat geen https is wordt geweigerd zonder socket', () async {
      for (final uri in const [
        'http://github.com/x',
        'file:///etc/passwd',
        'ftp://github.com/x',
      ]) {
        final e = await weigering(() => transport.getJson(Uri.parse(uri)));
        expect(e.failure, CveIngestFailure.networkFailed, reason: uri);
        expect(e.detail, 'alleen https', reason: uri);
      }
    });

    test(
      'een adres dat de poort weigert komt niet voorbij de naamopzoeking',
      () async {
        // 127.0.0.1 en het metadata-adres van een cloudinstantie zijn precies
        // waar een omleiding je heen zou willen sturen.
        for (final host in const ['127.0.0.1', '169.254.169.254', '[::1]']) {
          final e = await weigering(
            () => transport.getJson(Uri.parse('https://$host/x')),
          );
          expect(e.detail, startsWith('host geweigerd'), reason: host);
        }
      },
    );

    test('ook het downloadpad gaat door dezelfde poort', () async {
      final doel = File('${tmp.path}/uit/archief.zip');
      final e = await weigering(
        () => transport.download(
          Uri.parse('http://github.com/archief.zip'),
          doel,
          onProgress: (_, _) {},
          isCancelled: () => false,
        ),
      );
      expect(e.detail, 'alleen https');
      expect(
        doel.existsSync(),
        isFalse,
        reason: 'een geweigerde download hoort geen bestand achter te laten',
      );
    });
  });
}

/// Levert de release-metadata en het archief zonder ook maar iets te bellen.
class _FakeTransport implements CveBulkTransport {
  _FakeTransport(this.archive);

  final List<int> archive;

  @override
  Future<String> getJson(Uri url) async => jsonEncode({
    'tag_name': 'cve_2026',
    'assets': [
      {
        'name': '2026-07-14_all_CVEs_at_midnight.zip.zip',
        'browser_download_url': 'https://example.invalid/all.zip.zip',
        'size': archive.length,
      },
    ],
  });

  @override
  Future<void> download(
    Uri url,
    File destination, {
    required void Function(int received, int total) onProgress,
    required bool Function() isCancelled,
  }) async {
    destination.parent.createSync(recursive: true);
    destination.writeAsBytesSync(archive);
    onProgress(archive.length, archive.length);
  }
}
