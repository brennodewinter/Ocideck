import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/models/chart.dart';
import 'package:ocideck/models/deck.dart';
import 'package:ocideck/models/slide.dart';
import 'package:ocideck/services/import/presentation_import_service.dart';
import 'package:ocideck/services/web_asset_store.dart';

import 'helpers/key_fixtures.dart' as fx;

/// End-to-end: a synthetic `.key` (a schema-conformant IWA graph) flows through
/// the real [PresentationImportService] — format detection, the registry, the
/// `KeyImporter`, `SlideReconstructor`, the classifier and `DeckBuilder` — and
/// lands as a real OciDeck [Deck] whose slides reflect the recovered order,
/// body bullets, media and notes.
///
/// The registry is the default one, so these tests also prove that `.key` is
/// actually wired up: an unregistered format fails at the lookup, long before
/// any of this.
///
/// Two things these tests deliberately do *not* pin down. Apple's runtime
/// typeId registry is not available, so `SlideReconstructor` recognises message
/// types by their field shape; on a hand-built graph that can recognise one
/// object too many and yield an extra, near-empty slide. And a source slide
/// with only a title has no matching OciDeck slide type, so it is salvaged as
/// free Markdown. Both are properties of the reconstructor and the classifier,
/// not of the wiring under test here — so these tests assert that the content
/// arrives, in the right order, and leave the slide count alone.
Future<Deck> _import(List<int> bytes, String filename) async {
  final result = await PresentationImportService().importBytes(
    Uint8List.fromList(bytes),
    filename: filename,
  );
  if (!result.isSuccess) {
    fail('Conversion failed: ${result.failure?.message}');
  }
  return result.deck!;
}

/// The free-Markdown note slides the import appends for what it could not map.
Iterable<String> _notes(Deck deck) => deck.slides
    .where((s) => s.type == SlideType.freeMarkdown)
    .map((s) => s.customMarkdown);

void main() {
  setUp(WebAssetStore.clear);
  tearDown(WebAssetStore.clear);

  test(
    'converts a synthetic .key with an image into a real image slide',
    () async {
      const dataId = 100;
      const fileName = 'photo.png';
      const imageBytes = <int>[0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A];
      final recordBytes = [
        // PackageMetadata maps dataId to Data/ file name.
        fx.record(
          2,
          100,
          fx.packageMetadataPayload(
            dataInfos: [
              fx.dataInfoPayload(
                identifier: dataId,
                preferredFileName: fileName,
              ),
            ],
          ),
        ),
        // Title shape (id 20) -> storage (id 21) "Photo".
        fx.recordWithRefs(20, 2, fx.shapeInfoPayload(0), [21]),
        fx.record(21, 3, fx.storagePayload(['Photo'])),
        // Image (id 10) references the dataId.
        fx.record(10, 200, fx.imagePayload(dataId)),
        // Slide (id 1) uses title shape and image drawable.
        fx.recordWithRefs(
          1,
          1,
          fx.slidePayload(
            titleRefIndex: 0,
            bodyRefIndex: 0,
            drawableRefIndices: [1],
          ),
          [20, 10],
        ),
      ].expand((e) => e).toList();

      final stream = fx.iwaStream(recordBytes);
      final bytes = fx.zip({
        'Index/slide-1.iwa': stream,
        'Data/$fileName': imageBytes,
        'Metadata/Properties.plist': fx.b(fx.xmlPlist),
      });
      final deck = await _import(bytes, 'Photo.key');

      // The title comes from the plist, not from the file name.
      expect(deck.title, 'Q3 Roadmap');
      final slide = deck.slides.first;
      expect(slide.title, 'Photo');
      // The picture rides along as a `mem:` asset that materialises on save.
      expect(slide.imagePath, startsWith('mem:'));
      expect(WebAssetStore.bytesFor(slide.imagePath), imageBytes);
    },
  );

  test(
    'converts a synthetic .key with a table into a real table slide',
    () async {
      final stringTable = fx.record(
        20,
        100,
        fx.tableDataListPayload(
          listType: 1,
          entries: [(0, 'Item'), (1, 'Value'), (2, 'A'), (3, '1')],
        ),
      );
      final row0 = fx.tileRowInfoPayload(0, [
        fx.v5Cell(type: 3, stringIndex: 0),
        fx.v5Cell(type: 3, stringIndex: 1),
      ]);
      final row1 = fx.tileRowInfoPayload(1, [
        fx.v5Cell(type: 3, stringIndex: 2),
        fx.v5Cell(type: 3, stringIndex: 3),
      ]);
      final tile = fx.record(
        22,
        6002,
        fx.tilePayload(
          maxColumn: 1,
          maxRow: 1,
          numCells: 4,
          numRows: 2,
          rowInfos: [row0, row1],
        ),
      );
      final dataStore = fx.dataStorePayload(
        tileStorage: fx.tileStoragePayload(tileId: 1, tileRefIndex: 1),
        stringTableRefIndex: 0,
      );
      final tableModel = fx.recordWithRefs(
        21,
        6001,
        fx.tableModelPayload(
          dataStore: dataStore,
          numberOfRows: 2,
          numberOfColumns: 2,
          numberOfHeaderRows: 1,
        ),
        [20, 22],
      );
      final tableInfo = fx.recordWithRefs(23, 6000, fx.tableInfoPayload(0), [
        21,
      ]);
      // Title shape (id 24) -> storage (id 25) "Table".
      final titleShape = fx.recordWithRefs(24, 2, fx.shapeInfoPayload(0), [25]);
      final titleStorage = fx.record(25, 3, fx.storagePayload(['Table']));
      // Slide uses title shape and table drawable.
      final slide = fx.recordWithRefs(
        1,
        1,
        fx.slidePayload(
          titleRefIndex: 0,
          bodyRefIndex: 0,
          drawableRefIndices: [1],
        ),
        [24, 23],
      );
      final recordBytes = [
        stringTable,
        tile,
        tableModel,
        tableInfo,
        titleShape,
        titleStorage,
        slide,
      ].expand((e) => e).toList();

      final stream = fx.iwaStream(recordBytes);
      final bytes = fx.zip({
        'Index/slide-1.iwa': stream,
        'Metadata/Properties.plist': fx.b(fx.xmlPlist),
      });
      final deck = await _import(bytes, 'Table.key');

      // Not `slides.first`: the slide carrying the table is what matters, and
      // the reconstructor emits an extra title-only slide for this synthetic
      // graph (see the note at the top of this file).
      final built = deck.slides.firstWhere((s) => s.type == SlideType.table);
      expect(built.title, 'Table');
      expect(built.tableRows.first, ['Item', 'Value']);
      expect(built.tableRows[1], ['A', '1']);
      // The IWA layout that could not be mapped is reported, not dropped.
      expect(_notes(deck).join(), contains('Niet overgenomen'));
    },
  );

  test(
    'converts a synthetic .key with a chart into a real chart slide',
    () async {
      final grid = fx.chartGridPayload(
        rowNames: ['Q1', 'Q2'],
        columnNames: ['A', 'B'],
        gridRows: [
          fx.gridRowPayload([
            fx.gridValuePayload(10.0),
            fx.gridValuePayload(20.0),
          ]),
          fx.gridRowPayload([
            fx.gridValuePayload(30.0),
            fx.gridValuePayload(40.0),
          ]),
        ],
      );
      final chartArchive = fx.chartArchivePayload(
        chartType: 3, // lineChartType2D
        chartGrid: grid,
        seriesDirection: 1, // by row
      );
      final chartDrawable = fx.record(
        23,
        6003,
        fx.chartDrawablePayload(chartArchive),
      );
      // Title shape (id 24) -> storage (id 25) "Chart".
      final titleShape = fx.recordWithRefs(24, 2, fx.shapeInfoPayload(0), [25]);
      final titleStorage = fx.record(25, 3, fx.storagePayload(['Chart']));
      final slide = fx.recordWithRefs(
        1,
        1,
        fx.slidePayload(
          titleRefIndex: 0,
          bodyRefIndex: 0,
          drawableRefIndices: [1],
        ),
        [24, 23],
      );
      final recordBytes = [
        chartDrawable,
        titleShape,
        titleStorage,
        slide,
      ].expand((e) => e).toList();

      final stream = fx.iwaStream(recordBytes);
      final bytes = fx.zip({
        'Index/slide-1.iwa': stream,
        'Metadata/Properties.plist': fx.b(fx.xmlPlist),
      });
      final deck = await _import(bytes, 'Chart.key');

      final built = deck.slides.first;
      expect(built.title, 'Chart');
      expect(built.type, SlideType.chart);
      final spec = ChartSpec.parse(built.customMarkdown);
      expect(spec.type, ChartType.line);
      // seriesDirection 1 = by row, so the row names become the series.
      expect(spec.x, ['A', 'B']);
      expect(spec.series.first.name, 'Q1');
      expect(spec.series.first.data, [10.0, 20.0]);
      expect(_notes(deck).join(), contains('Niet overgenomen'));
    },
  );

  test(
    'converts a synthetic .key with a video into a real video slide',
    () async {
      const dataId = 50;
      const fileName = 'clip.mp4';
      const videoBytes = <int>[0x00, 0x00, 0x00, 0x20, 0x66, 0x74, 0x79, 0x70];
      final packageMetadata = fx.record(
        2,
        100,
        fx.packageMetadataPayload(
          dataInfos: [
            fx.dataInfoPayload(identifier: dataId, preferredFileName: fileName),
          ],
        ),
      );
      final movie = fx.record(23, 200, fx.moviePayload(movieDataId: dataId));
      // Title shape (id 24) -> storage (id 25) "Video".
      final titleShape = fx.recordWithRefs(24, 2, fx.shapeInfoPayload(0), [25]);
      final titleStorage = fx.record(25, 3, fx.storagePayload(['Video']));
      final slide = fx.recordWithRefs(
        1,
        1,
        fx.slidePayload(
          titleRefIndex: 0,
          bodyRefIndex: 0,
          drawableRefIndices: [1],
        ),
        [24, 23],
      );
      final recordBytes = [
        packageMetadata,
        movie,
        titleShape,
        titleStorage,
        slide,
      ].expand((e) => e).toList();

      final stream = fx.iwaStream(recordBytes);
      final bytes = fx.zip({
        'Index/slide-1.iwa': stream,
        'Data/$fileName': videoBytes,
        'Metadata/Properties.plist': fx.b(fx.xmlPlist),
      });
      final deck = await _import(bytes, 'Video.key');

      final built = deck.slides.first;
      expect(built.title, 'Video');
      expect(built.type, SlideType.video);
      expect(built.videoPath, 'media/$fileName');
      expect(_notes(deck).join(), contains('Niet overgenomen'));
    },
  );

  test('converts a synthetic .key into a real deck end-to-end', () async {
    // SlideNode tree: root -> [nodeA, nodeB]; nodeA -> slideX ("First"),
    // nodeB -> slideY ("Second"). slideX also carries a speaker note.
    // Insert slideY before slideX in the stream so only the tree can give the
    // right order; parse order would reverse them.
    final recordBytes = [
      // slideY (id 2) first in stream.
      fx.recordWithRefs(
        2,
        1,
        fx.slidePayload(titleRefIndex: 0, bodyRefIndex: 1),
        [21, 22],
      ),
      fx.recordWithRefs(21, 2, fx.shapeInfoPayload(0), [23]),
      fx.record(23, 3, fx.storagePayload(['Second'])),
      fx.recordWithRefs(22, 2, fx.shapeInfoPayload(0), [24]),
      fx.record(24, 3, fx.storagePayload(<String>[])),
      // slideX (id 1) second in stream, with a note ref at field 27.
      fx.recordWithRefs(
        1,
        1,
        [
          ...fx.slidePayload(titleRefIndex: 0, bodyRefIndex: 1),
          ...fx.varintField(27, 2), // note -> object_references[2] -> 30
        ],
        [11, 12, 30],
      ),
      fx.recordWithRefs(11, 2, fx.shapeInfoPayload(0), [13]),
      fx.record(13, 3, fx.storagePayload(['First'])),
      fx.recordWithRefs(12, 2, fx.shapeInfoPayload(0), [14]),
      fx.record(14, 3, fx.storagePayload(['Intro point'])),
      // The note: NoteArchive (id 30) -> storage (id 31).
      fx.recordWithRefs(30, 6, fx.notePayload(0), [31]),
      fx.record(31, 3, fx.storagePayload(['Remember to introduce'])),
      // SlideNode tree.
      fx.recordWithRefs(
        100,
        4,
        fx.slideNodePayload(childrenRefIndices: [0, 1]),
        [101, 102],
      ),
      fx.recordWithRefs(101, 5, fx.slideNodePayload(slideRefIndex: 0), [1]),
      fx.recordWithRefs(102, 5, fx.slideNodePayload(slideRefIndex: 0), [2]),
    ].expand((e) => e).toList();
    final stream = fx.iwaStream(recordBytes);
    final bytes = fx.zip({
      'Index/slide-1.iwa': stream,
      'Metadata/Properties.plist': fx.b(fx.xmlPlist),
    });
    final deck = await _import(bytes, 'Roadmap.key');

    // Slide order follows the SlideNode tree, not the stream order:
    // "First" before "Second". A title-only slide has no matching OciDeck
    // type, so "Second" is salvaged as free Markdown rather than dropped —
    // hence the search across all of a slide's text, not just its title.
    int at(String needle) => deck.slides.indexWhere(
      (s) =>
          s.title.contains(needle) ||
          s.bullets.any((b) => b.contains(needle)) ||
          s.customMarkdown.contains(needle),
    );
    expect(at('Second'), isNonNegative);
    expect(at('First'), lessThan(at('Second')));
    // The body bullet of the first slide survives.
    expect(deck.slides.first.bullets, contains('Intro point'));
    // The speaker note rides along on its own slide.
    expect(deck.slides.first.notes, 'Remember to introduce');
    // The deck-wide loss note is appended.
    expect(_notes(deck).join(), contains('Niet overgenomen'));
    // The plist title lands on the deck, not the file-name stem.
    expect(deck.title, 'Q3 Roadmap');
  });
}
