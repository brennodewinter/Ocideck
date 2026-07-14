import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/models/local_cve_status.dart';
import 'package:ocideck/services/cve/cve_bulk_ingest.dart';
import 'package:ocideck/services/cve/local_cve_index.dart';

/// De hele keten — release opzoeken, downloaden, de zip ín de zip uitpakken,
/// indexeren — met een archiefje van een paar kilobyte in plaats van 550 MB.
///
/// De geneste zip is niet een detail maar de kern van de vorm van deze bron:
/// een implementatie die er één zip van maakt, werkt hier wel en in het echt
/// niet.
void main() {
  late Directory tmp;

  setUp(() => tmp = Directory.systemTemp.createTempSync('ocideck-cve-'));
  tearDown(() => tmp.deleteSync(recursive: true));

  Map<String, dynamic> cveJson(
    String id, {
    String title = 'Een lek',
    String description = 'Een beschrijving.',
    String state = 'PUBLISHED',
    Map<String, dynamic>? cna,
    List<Map<String, dynamic>>? adp,
  }) => {
    'dataType': 'CVE_RECORD',
    'dataVersion': '5.1',
    'cveMetadata': {
      'cveId': id,
      'state': state,
      'datePublished': '2021-12-10T00:00:00.000Z',
    },
    'containers': {
      'cna':
          cna ??
          {
            'title': title,
            'descriptions': [
              {'lang': 'en', 'value': description},
            ],
          },
      'adp': ?adp,
    },
  };

  /// Bouwt het echte ding: een zip die één `cves.zip` bevat, met daarin de
  /// losse CVE-JSON's.
  List<int> nestedArchive(Map<String, Map<String, dynamic>> records) {
    final innerArchive = Archive();
    records.forEach((path, json) {
      final bytes = utf8.encode(jsonEncode(json));
      innerArchive.add(ArchiveFile.bytes(path, bytes));
    });
    innerArchive.add(ArchiveFile.bytes('cves/README.md', utf8.encode('hoi')));
    final innerZip = ZipEncoder().encode(innerArchive);

    final outerArchive = Archive()
      ..add(ArchiveFile.bytes('cves.zip', innerZip));
    return ZipEncoder().encode(outerArchive);
  }

  CveBulkIngest makeIngest(List<int> archiveBytes, {String tag = 'cve_2026'}) {
    return CveBulkIngest(
      transport: _FakeTransport(archiveBytes, tag: tag),
      index: LocalCveIndex(Directory('${tmp.path}/db')),
      workDirectory: Directory('${tmp.path}/work'),
      releaseApi: Uri.parse('https://example.invalid/releases/latest'),
    );
  }

  Future<LocalCveStats> run(CveBulkIngest ingest) => ingest.run(
    onProgress: (_) {},
    isCancelled: () => false,
    now: DateTime.utc(2026, 7, 14),
  );

  test('walks the zip-inside-a-zip and indexes every published record', () async {
    final ingest = makeIngest(
      nestedArchive({
        'cves/2021/44xxx/CVE-2021-44228.json': cveJson(
          'CVE-2021-44228',
          title: 'Log4Shell',
          description: 'Remote code execution in Apache Log4j2.',
        ),
        'cves/2014/0xxx/CVE-2014-0160.json': cveJson(
          'CVE-2014-0160',
          title: 'Heartbleed',
          description: 'Information disclosure in OpenSSL.',
        ),
      }),
    );

    final stats = await run(ingest);

    expect(stats.records, 2);
    expect(stats.release, 'cve_2026');
    expect(stats.builtOn, '2026-07-14');
    expect(stats.bytes, greaterThan(0));
    // De twee archieven samen zijn in het echt ruim een gigabyte: ze moeten weg.
    expect(Directory('${tmp.path}/work').listSync(), isEmpty);
  });

  test('finds a CVE offline, by id and by keyword', () async {
    final index = LocalCveIndex(Directory('${tmp.path}/db'));
    await run(
      makeIngest(
        nestedArchive({
          'cves/2021/44xxx/CVE-2021-44228.json': cveJson(
            'CVE-2021-44228',
            title: 'Log4Shell',
            description: 'Remote code execution in Apache Log4j2.',
          ),
          'cves/2014/0xxx/CVE-2014-0160.json': cveJson(
            'CVE-2014-0160',
            title: 'Heartbleed',
            description: 'Information disclosure in OpenSSL.',
          ),
        }),
      ),
    );

    final byId = await index.search('CVE-2021-44228');
    expect(byId.single.title, 'Log4Shell');

    final byKeyword = await index.search('openssl');
    expect(byKeyword.single.id, 'CVE-2014-0160');

    expect(await index.search('iets wat er niet is'), isEmpty);
  });

  test('an exact id ranks above a keyword hit for the same term', () async {
    final index = LocalCveIndex(Directory('${tmp.path}/db'));
    await run(
      makeIngest(
        nestedArchive({
          'cves/2021/44xxx/CVE-2021-44228.json': cveJson('CVE-2021-44228'),
          // Noemt de andere CVE in zijn beschrijving — een keyword-treffer.
          'cves/2021/45xxx/CVE-2021-45046.json': cveJson(
            'CVE-2021-45046',
            description: 'The fix for CVE-2021-44228 was incomplete.',
          ),
        }),
      ),
    );

    final hits = await index.search('cve-2021-44228');
    expect(hits.length, 2);
    expect(hits.first.id, 'CVE-2021-44228', reason: 'exacte id hoort bovenaan');
  });

  test('skips records that are not published', () async {
    final ingest = makeIngest(
      nestedArchive({
        'cves/2021/44xxx/CVE-2021-44228.json': cveJson('CVE-2021-44228'),
        'cves/2030/9xxx/CVE-2030-9999.json': cveJson(
          'CVE-2030-9999',
          state: 'REJECTED',
        ),
      }),
    );

    expect((await run(ingest)).records, 1);
  });

  test('picks up a CVSS score an ADP added, not just the CNA one', () async {
    final index = LocalCveIndex(Directory('${tmp.path}/db'));
    await run(
      makeIngest(
        nestedArchive({
          'cves/2021/44xxx/CVE-2021-44228.json': cveJson(
            'CVE-2021-44228',
            cna: {
              'title': 'Log4Shell',
              'descriptions': [
                {'lang': 'en', 'value': 'RCE.'},
              ],
              // De CNA gaf géén CVSS — dat is voor veel oudere CVE's zo.
            },
            adp: [
              {
                'metrics': [
                  {
                    'cvssV3_1': {
                      'baseScore': 10.0,
                      'vectorString':
                          'CVSS:3.1/AV:N/AC:L/PR:N/UI:N/S:C/C:H/I:H/A:H',
                    },
                  },
                ],
              },
            ],
          ),
        }),
      ),
    );

    final hit = (await index.search('CVE-2021-44228')).single;
    expect(hit.score, 10.0);
    expect(hit.vector, startsWith('CVSS:3.1/'));
  });

  test('a corrupt record does not sink the whole build', () async {
    final inner = Archive()
      ..add(
        ArchiveFile.bytes(
          'cves/2021/44xxx/CVE-2021-44228.json',
          utf8.encode(jsonEncode(cveJson('CVE-2021-44228'))),
        ),
      )
      ..add(
        ArchiveFile.bytes(
          'cves/2021/44xxx/CVE-2021-9999.json',
          utf8.encode('{ dit is geen json'),
        ),
      );
    final outer = Archive()
      ..add(ArchiveFile.bytes('cves.zip', ZipEncoder().encode(inner)));

    expect((await run(makeIngest(ZipEncoder().encode(outer)))).records, 1);
  });

  test(
    'an archive with no CVEs fails loudly instead of writing an empty index',
    () async {
      final inner = Archive()
        ..add(ArchiveFile.bytes('cves/README.md', utf8.encode('leeg')));
      final outer = Archive()
        ..add(ArchiveFile.bytes('cves.zip', ZipEncoder().encode(inner)));

      await expectLater(
        run(makeIngest(ZipEncoder().encode(outer))),
        throwsA(
          isA<CveIngestException>().having(
            (e) => e.failure,
            'failure',
            CveIngestFailure.invalidArchive,
          ),
        ),
      );
    },
  );

  test(
    'a release without the full archive asset is reported, not guessed at',
    () async {
      final ingest = CveBulkIngest(
        transport: _FakeTransport(const [], onlyDelta: true),
        index: LocalCveIndex(Directory('${tmp.path}/db')),
        workDirectory: Directory('${tmp.path}/work'),
        releaseApi: Uri.parse('https://example.invalid/releases/latest'),
      );

      await expectLater(
        run(ingest),
        throwsA(
          isA<CveIngestException>().having(
            (e) => e.failure,
            'failure',
            CveIngestFailure.invalidArchive,
          ),
        ),
      );
    },
  );

  test('cancelling leaves no half-written index behind', () async {
    final index = LocalCveIndex(Directory('${tmp.path}/db'));
    final ingest = makeIngest(
      nestedArchive({
        'cves/2021/44xxx/CVE-2021-44228.json': cveJson('CVE-2021-44228'),
      }),
    );

    await expectLater(
      ingest.run(
        onProgress: (_) {},
        isCancelled: () => true,
        now: DateTime.utc(2026, 7, 14),
      ),
      throwsA(
        isA<CveIngestException>().having(
          (e) => e.failure,
          'failure',
          CveIngestFailure.cancelled,
        ),
      ),
    );

    expect(await index.exists, isFalse);
    expect(File('${index.indexFile.path}.tmp').existsSync(), isFalse);
  });

  test('reports the phases it walks through', () async {
    final seen = <CveIngestPhase>{};
    await makeIngest(
      nestedArchive({
        'cves/2021/44xxx/CVE-2021-44228.json': cveJson('CVE-2021-44228'),
      }),
    ).run(
      onProgress: (p) => seen.add(p.phase),
      isCancelled: () => false,
      now: DateTime.utc(2026, 7, 14),
    );

    expect(seen, contains(CveIngestPhase.discovering));
    expect(seen, contains(CveIngestPhase.downloading));
    expect(seen, contains(CveIngestPhase.extracting));
    expect(seen, contains(CveIngestPhase.indexing));
  });
}

/// Serveert de release-metadata en het archief uit het geheugen.
class _FakeTransport implements CveBulkTransport {
  final List<int> archive;
  final String tag;
  final bool onlyDelta;

  _FakeTransport(this.archive, {this.tag = 'cve_2026', this.onlyDelta = false});

  @override
  Future<String> getJson(Uri url) async => jsonEncode({
    'tag_name': tag,
    'assets': [
      {
        'name': '2026-07-14_delta_CVEs_at_1300Z.zip',
        'browser_download_url': 'https://example.invalid/delta.zip',
        'size': 10,
      },
      if (!onlyDelta)
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
