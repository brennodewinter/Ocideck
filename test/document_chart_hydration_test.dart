// [hydrateDocumentChartData] tegen een echt bestandssysteem: de externe
// grafiek-data moet vóór de OciWacht-scan inline in het ```chart-blok belanden
// (DOCUMENT_MODE.md §11.2 stap 1), en de insluitingsbewaking moet een `../`-
// uitbraak weigeren zonder te crashen.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/services/document_chart_hydration.dart';
import 'package:path/path.dart' as p;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory temp;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('ocideck_dochydrate_');
  });
  tearDown(() async {
    if (await temp.exists()) await temp.delete(recursive: true);
  });

  /// Schrijf `data/x.json` met een uniek herkenbaar getal in de reeksdata.
  Future<void> writeDataFile() async {
    final dataDir = Directory(p.join(temp.path, 'data'));
    await dataDir.create(recursive: true);
    await File(p.join(dataDir.path, 'x.json')).writeAsString(
      '{"x": ["Jan", "Feb"], '
      '"series": [{"name": "Omzet", "data": [4242, 99]}]}',
    );
  }

  const chartBody =
      '```chart\n'
      '{"type": "line", "title": "Omzet", "source": "data/x.json"}\n'
      '```\n';

  test('externe data wordt inline in het chart-blok gevouwen', () async {
    await writeDataFile();
    final out = await hydrateDocumentChartData(
      chartBody,
      projectPath: temp.path,
    );
    // Het unieke getal uit x.json draagt nu in de tekst zelf.
    expect(out.contains('4242'), isTrue);
    expect(out.contains('```chart'), isTrue);
  });

  test('projectPath null laat de body ongewijzigd', () async {
    final out = await hydrateDocumentChartData(chartBody);
    expect(out, equals(chartBody));
  });

  test('een source met ../ wordt geweigerd, blok blijft staan', () async {
    const escaping =
        '```chart\n'
        '{"type": "line", "source": "../secret.json"}\n'
        '```\n';
    final out = await hydrateDocumentChartData(
      escaping,
      projectPath: temp.path,
    );
    expect(out, equals(escaping));
    expect(out.contains('4242'), isFalse);
  });

  test('een ontbrekend databestand laat het blok ongemoeid', () async {
    final out = await hydrateDocumentChartData(
      chartBody,
      projectPath: temp.path,
    );
    expect(out, equals(chartBody));
  });

  test('een blok dat al inline data draagt blijft ongewijzigd', () async {
    await writeDataFile();
    const inline =
        '```chart\n'
        '{"type": "line", "source": "data/x.json", '
        '"x": ["A"], "series": [{"name": "S", "data": [7]}]}\n'
        '```\n';
    final out = await hydrateDocumentChartData(inline, projectPath: temp.path);
    // Niet opnieuw uit het bestand gevouwen: het unieke getal blijft weg.
    expect(out.contains('4242'), isFalse);
    expect(out.contains('7'), isTrue);
  });
}
