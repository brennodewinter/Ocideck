import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/models/local_cve_record.dart';
import 'package:ocideck/services/cve/local_cve_index.dart';

/// Wat "lokaal beschikbaar" mag betekenen.
///
/// De index is honderden megabytes, het metabestand een paar honderd byte. Een
/// opruimtool of een volle schijf haalt de grote weg en laat de kleine staan —
/// en dan meldde de app offline-zoeken terwijl elke opzoeking leeg terugkwam.
/// Omdat het opzoekpad bewust niet terugvalt op de online keten, las dat als
/// "deze CVE is niet van toepassing".
void main() {
  late Directory tmp;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('ocideck_cve_index_');
  });
  tearDown(() => tmp.delete(recursive: true));

  LocalCveIndex indexIn(Directory dir) => LocalCveIndex(dir);

  /// Schrijft een index van één regel en bevestigt hem, zoals de bouw dat doet.
  Future<LocalCveIndex> built() async {
    final index = indexIn(Directory('${tmp.path}/db'));
    final sink = index.openWriter();
    sink.writeln(
      const LocalCveRecord(
        id: 'CVE-2021-44228',
        title: 'Log4Shell',
        description: 'iets met JNDI',
      ).toIndexLine(),
    );
    await sink.close();
    await index.commit(release: 'r1', builtOn: '2026-07-20', records: 1);
    return index;
  }

  test('een bevestigde index is beschikbaar en vindt zijn record', () async {
    final index = await built();

    final stats = await index.stats();
    expect(stats, isNotNull);
    expect(stats!.records, 1);
    expect(stats.bytes, index.indexFile.lengthSync());
    expect((await index.search('CVE-2021-44228')).single.title, 'Log4Shell');
  });

  test('meta zonder index telt niet als beschikbaar', () async {
    final index = await built();
    // De grote weg, de kleine blijft — precies wat een opruimtool doet.
    index.indexFile.deleteSync();

    expect(
      await index.stats(),
      isNull,
      reason: 'zonder index is er niets om offline in te zoeken',
    );
    expect(await index.search('CVE-2021-44228'), isEmpty);
  });

  test('een afgekapte index telt niet als beschikbaar', () async {
    final index = await built();
    // Schijf vol halverwege het wegschrijven: het bestand staat er, maar mist
    // de staart. Zoeken zou dan stil te weinig vinden.
    final half = index.indexFile.readAsBytesSync();
    index.indexFile.writeAsBytesSync(half.sublist(0, half.length ~/ 2));

    expect(await index.stats(), isNull);
  });

  test('een langere index dan beloofd telt evenmin', () async {
    final index = await built();
    index.indexFile.writeAsStringSync(
      '${const LocalCveRecord(id: 'CVE-2000-0001', title: 'x').toIndexLine()}\n',
      mode: FileMode.append,
    );

    expect(await index.stats(), isNull);
  });

  test('onleesbare meta levert geen halve waarheid op', () async {
    final index = await built();
    index.metaFile.writeAsStringSync('{niet: geldig');

    expect(await index.stats(), isNull);
  });
}
