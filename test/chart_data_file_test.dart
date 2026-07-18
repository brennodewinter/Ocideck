// The data file next to a deck, exercised against a real filesystem.
//
// This is the round trip the whole feature rests on: the .md keeps only a
// `source`, the numbers live in data/<naam>.json, and opening puts them back.
// None of it was covered before — _hydrateCharts, _copyChartData and
// _packChartSlide had no test that touched disk at all.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/models/chart.dart';
import 'package:ocideck/models/deck.dart';
import 'package:ocideck/models/settings.dart';
import 'package:ocideck/models/slide.dart';
import 'package:ocideck/services/file_service.dart';
import 'package:ocideck/services/image_service.dart';
import 'package:ocideck/services/markdown_service.dart';
import 'package:path/path.dart' as p;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory temp;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('ocideck_chartdata_');
  });
  tearDown(() async {
    if (await temp.exists()) await temp.delete(recursive: true);
  });

  FileService serviceOf() =>
      FileService(MarkdownService(), ImageService(), ThemeProfile.new);

  String deckPath() => p.join(temp.path, 'deck.md');

  /// A chart slide linking [source], carrying [values] against labels Jan/Feb.
  Slide chartSlide(String source, List<double> values) =>
      Slide.create(SlideType.chart).copyWith(
        customMarkdown: ChartSpec(
          type: ChartType.line,
          title: 'Omzet',
          source: source,
          x: const ['Jan', 'Feb'],
          series: [ChartSeries(name: 'Omzet', data: values)],
        ).toBlock(),
      );

  Deck deckWith(Slide slide) => Deck(title: 'Cijfers', slides: [slide]);

  ChartSpec specOf(Deck deck) => ChartSpec.parse(
    deck.slides.firstWhere((s) => s.type == SlideType.chart).customMarkdown,
  );

  test('save writes the data file and keeps the .md free of numbers', () async {
    final service = serviceOf();
    await service.saveDeck(
      deckWith(chartSlide('data/omzet.json', [120, 138])),
      deckPath(),
    );

    // The numbers are in the data file...
    final dataFile = File(p.join(temp.path, 'data', 'omzet.json'));
    expect(await dataFile.exists(), isTrue);
    final written = await dataFile.readAsString();
    expect(written, contains('120'));
    expect(written, contains('Jan'));

    // ...and not in the markdown, which keeps only the reference.
    final md = await File(deckPath()).readAsString();
    expect(md, contains('data/omzet.json'));
    expect(md, isNot(contains('120')));
  });

  test('reopening puts the numbers back', () async {
    final service = serviceOf();
    await service.saveDeck(
      deckWith(chartSlide('data/omzet.json', [120, 138])),
      deckPath(),
    );

    final reopened = await serviceOf().openDeck(deckPath());
    final spec = specOf(reopened!);
    expect(spec.source, 'data/omzet.json');
    expect(spec.x, ['Jan', 'Feb']);
    expect(spec.series.single.data, [120, 138]);
  });

  test('editing the chart in the app rewrites the data file', () async {
    final service = serviceOf();
    await service.saveDeck(
      deckWith(chartSlide('data/omzet.json', [120, 138])),
      deckPath(),
    );

    // Reopen, edit as the grid editor would, save again.
    final opened = await service.openDeck(deckPath());
    final edited = specOf(opened!).copyWith(
      series: [
        const ChartSeries(name: 'Omzet', data: [999, 138]),
      ],
    );
    await service.saveDeck(
      opened.copyWith(
        slides: [
          opened.slides.single.copyWith(customMarkdown: edited.toBlock()),
        ],
      ),
      deckPath(),
    );

    expect(
      await File(p.join(temp.path, 'data', 'omzet.json')).readAsString(),
      contains('999'),
    );
    expect(
      specOf((await serviceOf().openDeck(deckPath()))!).series.single.data,
      [999, 138],
    );
  });

  test('a file edited outside the app survives a save', () async {
    final service = serviceOf();
    await service.saveDeck(
      deckWith(chartSlide('data/omzet.json', [120, 138])),
      deckPath(),
    );

    final opened = await service.openDeck(deckPath());
    // Someone edits the data file in a spreadsheet while the deck is open. The
    // user does not touch the chart, then saves the deck for another reason.
    final dataFile = File(p.join(temp.path, 'data', 'omzet.json'));
    await dataFile.writeAsString(
      '{"x":["Jan","Feb"],"series":[{"name":"Omzet","data":[7,8]}]}',
    );
    await service.saveDeck(opened!, deckPath());

    // Their edit is still there: an untouched chart never rewrites its file.
    expect(await dataFile.readAsString(), contains('[7,8]'));
    expect(
      specOf((await serviceOf().openDeck(deckPath()))!).series.single.data,
      [7, 8],
    );
  });

  test('a deck that links a .csv keeps getting .csv', () async {
    final service = serviceOf();
    // A deck written before JSON existed.
    await Directory(p.join(temp.path, 'data')).create(recursive: true);
    await File(
      p.join(temp.path, 'data', 'omzet.csv'),
    ).writeAsString(',Omzet\nJan,1\nFeb,2\n');
    await service.saveDeck(
      deckWith(chartSlide('data/omzet.csv', [1, 2])),
      deckPath(),
    );

    final opened = await service.openDeck(deckPath());
    expect(specOf(opened!).series.single.data, [1, 2]);

    final edited = specOf(opened).copyWith(
      series: [
        const ChartSeries(name: 'Omzet', data: [5, 2]),
      ],
    );
    await service.saveDeck(
      opened.copyWith(
        slides: [
          opened.slides.single.copyWith(customMarkdown: edited.toBlock()),
        ],
      ),
      deckPath(),
    );

    // Still CSV, not silently converted — something outside may point at it.
    final csv = await File(
      p.join(temp.path, 'data', 'omzet.csv'),
    ).readAsString();
    expect(csv, contains('Jan,5'));
    expect(File(p.join(temp.path, 'data', 'omzet.json')).existsSync(), isFalse);
  });

  test('a source pointing outside the project is never written', () async {
    final service = serviceOf();
    final outside = File(p.join(temp.path, 'geheim.json'));
    await outside.writeAsString('{"x":["geheim"],"series":[]}');

    final project = Directory(p.join(temp.path, 'project'));
    await project.create();
    await service.saveDeck(
      deckWith(chartSlide('../geheim.json', [1, 2])),
      p.join(project.path, 'deck.md'),
    );

    // Untouched: a deck must not be able to write outside its own folder.
    expect(await outside.readAsString(), '{"x":["geheim"],"series":[]}');
  });

  test(
    'a missing data file leaves the chart empty rather than crashing',
    () async {
      final service = serviceOf();
      await service.saveDeck(
        deckWith(chartSlide('data/omzet.json', [120, 138])),
        deckPath(),
      );
      await File(p.join(temp.path, 'data', 'omzet.json')).delete();

      final reopened = await serviceOf().openDeck(deckPath());
      expect(reopened, isNotNull);
      final spec = specOf(reopened!);
      expect(spec.source, 'data/omzet.json');
      expect(spec.hasInlineData, isFalse);
    },
  );

  test('a missing data file is reported, not swallowed', () async {
    final service = serviceOf();
    await service.saveDeck(
      deckWith(chartSlide('data/omzet.json', [120, 138])),
      deckPath(),
    );
    await File(p.join(temp.path, 'data', 'omzet.json')).delete();

    // An empty chart looks exactly like a chart with no numbers yet, so the
    // difference has to be said out loud.
    final outcome = await serviceOf().openDeckDetailed(deckPath());
    expect(outcome.deck, isNotNull);
    expect(outcome.warnings, ['data/omzet.json']);
  });

  // The conversion users are not supposed to notice: a deck written before
  // data files existed carries its numbers inline, and moves over on its next
  // save without anyone doing anything.
  group('automatic conversion', () {
    Slide inlineChart(String title, List<double> values) =>
        Slide.create(SlideType.chart).copyWith(
          customMarkdown: ChartSpec(
            title: title,
            x: const ['Jan', 'Feb'],
            series: [ChartSeries(name: 'Omzet', data: values)],
          ).toBlock(),
        );

    test('inline data moves to a data file on save', () async {
      await serviceOf().saveDeck(
        deckWith(inlineChart('Omzet 2025', [120, 138])),
        deckPath(),
      );

      final dataFile = File(p.join(temp.path, 'data', 'Omzet_2025.json'));
      expect(await dataFile.exists(), isTrue);
      expect(await dataFile.readAsString(), contains('120'));

      // The markdown is left with the reference and none of the numbers.
      final md = await File(deckPath()).readAsString();
      expect(md, contains('data/Omzet_2025.json'));
      expect(md, isNot(contains('120')));

      // And the user sees no difference: reopening gives the same chart back.
      final spec = specOf((await serviceOf().openDeck(deckPath()))!);
      expect(spec.x, ['Jan', 'Feb']);
      expect(spec.series.single.data, [120, 138]);
    });

    test('an untitled chart still gets a sensible name', () async {
      await serviceOf().saveDeck(deckWith(inlineChart('', [1, 2])), deckPath());
      expect(
        File(p.join(temp.path, 'data', 'grafiek.json')).existsSync(),
        isTrue,
      );
    });

    test('an empty chart gets no file at all', () async {
      await serviceOf().saveDeck(
        deckWith(Slide.create(SlideType.chart)),
        deckPath(),
      );
      final dir = Directory(p.join(temp.path, 'data'));
      expect(dir.listSync().whereType<File>(), isEmpty);
    });

    test('two charts with the same title get separate files', () async {
      await serviceOf().saveDeck(
        Deck(
          title: 'Cijfers',
          slides: [
            inlineChart('Omzet', [1, 2]),
            inlineChart('Omzet', [3, 4]),
          ],
        ),
        deckPath(),
      );

      // Sharing one file would mean the second chart overwrote the first.
      expect(
        File(p.join(temp.path, 'data', 'Omzet.json')).existsSync(),
        isTrue,
      );
      expect(
        File(p.join(temp.path, 'data', 'Omzet-2.json')).existsSync(),
        isTrue,
      );
      final reopened = await serviceOf().openDeck(deckPath());
      final data = reopened!.slides
          .map((s) => ChartSpec.parse(s.customMarkdown).series.single.data)
          .toList();
      expect(data, [
        [1, 2],
        [3, 4],
      ]);
    });

    test('a duplicated chart slide forks onto its own file', () async {
      final service = serviceOf();
      await service.saveDeck(
        deckWith(inlineChart('Omzet', [1, 2])),
        deckPath(),
      );
      final opened = await service.openDeck(deckPath());

      // Duplicating a slide copies its source along; both would otherwise
      // write to the one file and the numbers of one would win.
      final twin = opened!.slides.single;
      final copy = Slide.create(
        SlideType.chart,
      ).copyWith(customMarkdown: twin.customMarkdown);
      await service.saveDeck(opened.copyWith(slides: [twin, copy]), deckPath());

      expect(
        File(p.join(temp.path, 'data', 'Omzet.json')).existsSync(),
        isTrue,
      );
      expect(
        File(p.join(temp.path, 'data', 'Omzet-2.json')).existsSync(),
        isTrue,
      );
    });

    test('the source stays put when the title changes', () async {
      final service = serviceOf();
      await service.saveDeck(
        deckWith(inlineChart('Omzet', [1, 2])),
        deckPath(),
      );
      final opened = await service.openDeck(deckPath());
      final renamed = specOf(opened!).copyWith(title: 'Heel andere titel');
      await service.saveDeck(
        opened.copyWith(
          slides: [
            opened.slides.single.copyWith(customMarkdown: renamed.toBlock()),
          ],
        ),
        deckPath(),
      );

      // Renaming on every title edit would churn the file and its history.
      expect(
        specOf((await serviceOf().openDeck(deckPath()))!).source,
        'data/Omzet.json',
      );
      expect(
        File(p.join(temp.path, 'data', 'Heel_andere_titel.json')).existsSync(),
        isFalse,
      );
    });

    test('deleting the chart cleans up its data file', () async {
      final service = serviceOf();
      await service.saveDeck(
        deckWith(inlineChart('Omzet', [1, 2])),
        deckPath(),
      );
      final opened = await service.openDeck(deckPath());
      await service.saveDeck(
        opened!.copyWith(slides: [Slide.create(SlideType.title)]),
        deckPath(),
      );
      expect(
        File(p.join(temp.path, 'data', 'Omzet.json')).existsSync(),
        isFalse,
      );
    });

    test('cleanup never touches files it did not create', () async {
      final service = serviceOf();
      await Directory(p.join(temp.path, 'data')).create(recursive: true);
      final stranger = File(
        p.join(temp.path, 'data', 'van_iemand_anders.json'),
      );
      await stranger.writeAsString('{"x":["eigen"],"series":[]}');
      final csv = File(p.join(temp.path, 'data', 'handmatig.csv'));
      await csv.writeAsString(',A\nJan,1\n');

      await service.saveDeck(
        deckWith(inlineChart('Omzet', [1, 2])),
        deckPath(),
      );

      // Nothing in data/ that we did not put there is ours to remove.
      expect(await stranger.readAsString(), '{"x":["eigen"],"series":[]}');
      expect(await csv.readAsString(), ',A\nJan,1\n');
    });
  });

  test('a healthy deck reports nothing', () async {
    final service = serviceOf();
    await service.saveDeck(
      deckWith(chartSlide('data/omzet.json', [120, 138])),
      deckPath(),
    );
    expect((await serviceOf().openDeckDetailed(deckPath())).warnings, isEmpty);
  });
}
