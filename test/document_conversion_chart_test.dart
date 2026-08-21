// Regressietest voor #1639: het conversiepad document → presentatie moet
// grafiekdata inline vouwen (gelijk aan export) én de projectmap meenemen,
// anders staat de grafiekdia leeg in het padloze nieuwe tabblad.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/models/slide.dart';
import 'package:ocideck/services/document_chart_hydration.dart';
import 'package:ocideck/services/document_deck_bridge.dart';
import 'package:path/path.dart' as p;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory temp;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('ocideck_convchart_');
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
      '# Rapport\n\n'
      '```chart\n'
      '{"type": "line", "title": "Omzet", "source": "data/x.json"}\n'
      '```\n';

  test('conversiepad: grafiekdata staat inline in de chart-dia', () async {
    await writeDataFile();
    // Het conversiepad hydrateert vóór documentToDeck, gelijk aan export.
    final hydrated = await hydrateDocumentChartData(
      chartBody,
      projectPath: temp.path,
    );
    final deck = DocumentDeckBridge.documentToDeck(
      hydrated,
      projectPath: temp.path,
      title: 'Rapport',
    );
    final chartSlide = deck.slides.firstWhere((s) => s.type == SlideType.chart);
    // Het unieke getal uit x.json draagt nu in de chart-dia zelf.
    expect(chartSlide.customMarkdown, contains('4242'));
  });

  test('zonder hydratatie staat de grafiekdata NIET in de chart-dia', () async {
    await writeDataFile();
    // Het oude conversiepad sloeg hydratatie over — de chart-dia is leeg.
    final deck = DocumentDeckBridge.documentToDeck(chartBody, title: 'Rapport');
    final chartSlide = deck.slides.firstWhere((s) => s.type == SlideType.chart);
    expect(chartSlide.customMarkdown, isNot(contains('4242')));
    expect(chartSlide.customMarkdown, contains('source'));
  });

  test('conversiepad: projectPath reist mee op het nieuwe deck', () async {
    await writeDataFile();
    final hydrated = await hydrateDocumentChartData(
      chartBody,
      projectPath: temp.path,
    );
    final deck = DocumentDeckBridge.documentToDeck(
      hydrated,
      projectPath: temp.path,
      title: 'Rapport',
    );
    expect(deck.projectPath, temp.path);
  });
}
