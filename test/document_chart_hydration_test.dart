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

  test('een source-symlink buiten het project wordt geweigerd', () async {
    final outsideDir = await Directory.systemTemp.createTemp(
      'ocideck_dochydrate_outside_',
    );
    final outside = File(p.join(outsideDir.path, 'outside-chart.json'));
    await outside.writeAsString(
      '{"x": ["geheim"], "series": [{"name": "S", "data": [8675309]}]}',
    );
    addTearDown(() async {
      if (await outsideDir.exists()) await outsideDir.delete(recursive: true);
    });
    final dataDir = Directory(p.join(temp.path, 'data'));
    await dataDir.create();
    await Link(p.join(dataDir.path, 'x.json')).create(outside.path);

    final out = await hydrateDocumentChartData(
      chartBody,
      projectPath: temp.path,
    );

    expect(out, equals(chartBody));
    expect(out, isNot(contains('8675309')));
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

  test('een databestand boven 8 MiB wordt geweigerd (#1666)', () async {
    final dataDir = Directory(p.join(temp.path, 'data'));
    await dataDir.create(recursive: true);
    final big = File(p.join(dataDir.path, 'x.json'));
    // Schrijf een bestand groter dan 8 MiB met geldige JSON-structuur.
    final padding = 'x' * (8 * 1024 * 1024 + 1024);
    await big.writeAsString('{"x": ["$padding"], "series": []}');
    final out = await hydrateDocumentChartData(
      chartBody,
      projectPath: temp.path,
    );
    // Het blok blijft staan; de data is niet ingelezen.
    expect(out, equals(chartBody));
  });

  test('CRLF-document behoudt CRLF in de herschreven fence (#1666)', () async {
    await writeDataFile();
    // Zelfde chart-blok maar met CRLF-regelscheiding.
    const crlfBody =
        '```chart\r\n'
        '{"type": "line", "title": "Omzet", "source": "data/x.json"}\r\n'
        '```\r\n';
    final out = await hydrateDocumentChartData(
      crlfBody,
      projectPath: temp.path,
    );
    expect(out.contains('4242'), isTrue);
    // De fence gebruikt CRLF, niet LF.
    expect(out.contains('```chart\r\n'), isTrue);
    expect(out.contains('\r\n```\r\n'), isTrue);
    // Geen kale LF in de herschreven fence.
    expect(out.contains('```chart\n'), isFalse);
  });

  test('chart zonder newline vóór sluithek wordt gehydrateerd (#1668)', () async {
    await writeDataFile();
    // De laatste specregel grenst direct aan het sluithek: geen \n voor ```.
    // Dit is het compacte geval dat het oude patroon miste.
    final compactBody = StringBuffer()
      ..write('```chart\n')
      ..write('{"type": "line", "source": "data/x.json"}')
      ..write('```');
    final out = await hydrateDocumentChartData(
      compactBody.toString(),
      projectPath: temp.path,
    );
    expect(out.contains('4242'), isTrue);
  });
}
