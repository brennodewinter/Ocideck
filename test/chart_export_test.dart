// Do charts survive the two ways a deck leaves the app — a .ocideck package
// and an HTML export? Both hand the deck to something that cannot resolve a
// `source` against a project folder, so both have to carry the numbers.
import 'dart:convert';
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
    temp = await Directory.systemTemp.createTemp('ocideck_chartexport_');
  });
  tearDown(() async {
    if (await temp.exists()) await temp.delete(recursive: true);
  });

  FileService serviceOf() =>
      FileService(MarkdownService(), ImageService(), ThemeProfile.new);

  Slide inlineChart(List<double> values) =>
      Slide.create(SlideType.chart).copyWith(
        customMarkdown: ChartSpec(
          title: 'Omzet',
          x: const ['Jan', 'Feb'],
          series: [ChartSeries(name: 'Omzet', data: values)],
        ).toBlock(),
      );

  ChartSpec specOf(Deck deck) => ChartSpec.parse(
    deck.slides.firstWhere((s) => s.type == SlideType.chart).customMarkdown,
  );

  group('.ocideck package', () {
    test('an unsaved deck packages its chart inline', () async {
      // No project folder, so no data file can exist: the numbers have to ride
      // in the markdown or the package is broken on arrival.
      final members = await serviceOf().buildPackageMembers(
        Deck(
          title: 'Cijfers',
          slides: [
            inlineChart([120, 138]),
          ],
        ),
      );
      final md = utf8.decode(
        members.entries.firstWhere((e) => e.key.endsWith('.md')).value,
      );
      final spec = ChartSpec.parse(
        MarkdownService().parseDeck(md)!.slides.single.customMarkdown,
      );
      expect(spec.hasInlineData, isTrue);
      expect(spec.series.single.data, [120, 138]);
    });

    test('a saved deck brings its data file along under data/', () async {
      final service = serviceOf();
      final path = p.join(temp.path, 'deck.md');
      final saved = await service.saveDeck(
        Deck(
          title: 'Cijfers',
          slides: [
            inlineChart([120, 138]),
          ],
        ),
        path,
      );

      final members = await service.buildPackageMembers(saved);
      final dataMember = members.keys.firstWhere(
        (k) => k.startsWith('data/'),
        orElse: () => '',
      );
      expect(
        dataMember,
        isNotEmpty,
        reason: 'data file must be in the package',
      );
      expect(utf8.decode(members[dataMember]!), contains('120'));

      // And the reference in the markdown points at the member that is there.
      final md = utf8.decode(
        members.entries.firstWhere((e) => e.key.endsWith('.md')).value,
      );
      expect(md, contains(dataMember));
    });

    test('an edit made since the last save is the one that ships', () async {
      final service = serviceOf();
      final path = p.join(temp.path, 'deck.md');
      final saved = await service.saveDeck(
        Deck(
          title: 'Cijfers',
          slides: [
            inlineChart([120, 138]),
          ],
        ),
        path,
      );

      // The user changes a number and exports without saving first. The file on
      // disk still holds the old numbers; the package must not.
      final edited = specOf(saved).copyWith(
        series: [
          const ChartSeries(name: 'Omzet', data: [999, 138]),
        ],
      );
      final deck = saved.copyWith(
        slides: [
          saved.slides.single.copyWith(customMarkdown: edited.toBlock()),
        ],
      );

      final members = await service.buildPackageMembers(deck);
      final dataMember = members.keys.firstWhere((k) => k.startsWith('data/'));
      expect(
        utf8.decode(members[dataMember]!),
        contains('999'),
        reason: 'the package shipped the stale file from disk',
      );
    });

    test('a package round-trips: export, import, numbers intact', () async {
      final service = serviceOf();
      final path = p.join(temp.path, 'deck.md');
      final saved = await service.saveDeck(
        Deck(
          title: 'Cijfers',
          slides: [
            inlineChart([120, 138]),
          ],
        ),
        path,
      );
      final members = await service.buildPackageMembers(saved);

      // Unpack into a fresh folder, exactly as importing does, and open it.
      final dest = Directory(p.join(temp.path, 'geimporteerd'));
      await dest.create();
      String? mdPath;
      for (final entry in members.entries) {
        final out = File(p.join(dest.path, entry.key));
        await out.parent.create(recursive: true);
        await out.writeAsBytes(entry.value);
        if (entry.key.endsWith('.md')) mdPath = out.path;
      }

      final reopened = await serviceOf().openDeck(mdPath!);
      expect(specOf(reopened!).series.single.data, [120, 138]);
    });
  });

  group('HTML export', () {
    test('the export markdown carries the numbers, not just a path', () {
      // A standalone .html has no folder next to it to resolve `source`
      // against, so the export bundle inlines the data.
      final markdown = MarkdownService().generateDeck(
        Deck(
          title: 'Cijfers',
          slides: [
            Slide.create(SlideType.chart).copyWith(
              customMarkdown: const ChartSpec(
                title: 'Omzet',
                source: 'data/Omzet.json',
                x: ['Jan', 'Feb'],
                series: [
                  ChartSeries(name: 'Omzet', data: [120, 138]),
                ],
              ).toBlock(),
            ),
          ],
        ),
        inlineChartData: true,
        forExport: true,
      );
      final spec = ChartSpec.parse(
        MarkdownService().parseDeck(markdown)!.slides.single.customMarkdown,
      );
      expect(spec.hasInlineData, isTrue);
      expect(spec.series.single.data, [120, 138]);
    });
  });
}
