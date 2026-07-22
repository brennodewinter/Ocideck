@TestOn('vm')
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/models/local_cve_status.dart';
import 'package:ocideck/services/cve/local_cve_database_io.dart';

/// De bulkdownload schreef door zolang de andere kant bleef sturen:
/// `Content-Length` ging alleen naar de voortgangsbalk, niet naar een grens.
/// Een omgeleide of vervangen asset kon zo de schijf volschrijven bij iemand
/// die alleen op "binnenhalen" had gedrukt.
///
/// Getoetst op [GithubBulkTransport.streamCapped] en niet op `download` zelf:
/// die pint de socket vast via NetGuard, en die weigert loopback. Een
/// testserver op deze machine is dus per ontwerp onbereikbaar — de grens staat
/// daarom apart, juist zodat hij hier wél te bereiken is.
void main() {
  late Directory tmp;

  setUp(() => tmp = Directory.systemTemp.createTempSync('ocideck-dl-'));
  tearDown(() => tmp.deleteSync(recursive: true));

  ({IOSink sink, File file}) doel() {
    final file = File('${tmp.path}/uit.bin');
    return (sink: file.openWrite(), file: file);
  }

  Future<void> stream(
    Stream<List<int>> chunks,
    IOSink sink, {
    int total = 0,
    int maxBytes = 100,
  }) => GithubBulkTransport.streamCapped(
    chunks,
    sink,
    total: total,
    maxBytes: maxBytes,
    onProgress: (_, _) {},
    isCancelled: () => false,
  );

  test('een aangekondigde omvang boven de grens wordt meteen geweigerd', () {
    final uit = doel();
    addTearDown(uit.sink.close);
    expect(
      () => stream(const Stream.empty(), uit.sink, total: 1000),
      throwsA(
        isA<CveIngestException>()
            .having(
              (e) => e.failure,
              'failure',
              CveIngestFailure.invalidArchive,
            )
            .having((e) => e.detail, 'detail', contains('kondigt')),
      ),
    );
  });

  test(
    'een stroom die zonder aankondiging doorgroeit wordt afgekapt',
    () async {
      final uit = doel();
      await expectLater(
        stream(
          Stream.fromIterable([List.filled(60, 1), List.filled(60, 2)]),
          uit.sink,
        ),
        throwsA(
          isA<CveIngestException>().having(
            (e) => e.detail,
            'detail',
            contains('tijdens het binnenhalen'),
          ),
        ),
      );
      await uit.sink.close();

      expect(
        uit.file.lengthSync(),
        60,
        reason:
            'de brok die over de grens gaat mag niet meer op schijf landen — '
            'anders is de grens alleen een melding achteraf',
      );
    },
  );

  test('een stroom binnen de grens komt er gewoon door', () async {
    final uit = doel();
    await stream(
      Stream.fromIterable([List.filled(40, 1), List.filled(40, 2)]),
      uit.sink,
      total: 80,
    );
    await uit.sink.close();
    expect(uit.file.lengthSync(), 80);
  });
}
