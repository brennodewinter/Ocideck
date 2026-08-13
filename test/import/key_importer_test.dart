import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/services/import/core/result.dart';
import 'package:ocideck/services/import/importers/keynote/key_importer.dart';
import 'package:ocideck/services/import/models/body_block.dart';
import 'package:ocideck/services/import/models/source_chart.dart';
import 'package:ocideck/services/import/models/source_video.dart';

import 'helpers/key_fixtures.dart' as fx;

void main() {
  test(
    'salvages preview.jpg as a single image slide when IWA is unparseable',
    () async {
      final preview = [0xFF, 0xD8, 0xFF, 0xE0, 0x00, 0x10];
      final bytes = fx.zip({
        'preview.jpg': preview,
        'Metadata/Properties.plist': fx.b(fx.xmlPlist),
        'Index/Document.iwa': fx.b('iwa-bytes'),
        'Index/slide-1.iwa': fx.b('iwa-bytes'),
        'Index/slide-2.iwa': fx.b('iwa-bytes'),
      });

      final result = await KeyImporter().importBytes(bytes, path: 'deck.key');
      expect(result.isOk, isTrue);
      final deck = result.okValue!;
      expect(deck.title, 'Q3 Roadmap');
      expect(deck.author, 'Jane Doe');
      expect(deck.slides, hasLength(1));
      expect(deck.slides.single.images, hasLength(1));
      expect(deck.slides.single.images.single.bytes, preview);
      expect(deck.issues, hasLength(1));
      expect(deck.issues.single.isSalvaged, isTrue);
    },
  );

  test(
    'reconstructs real slides when the IWA graph matches the schema',
    () async {
      // A schema-conformant graph: slide -> title/body shapes -> storages.
      final recordBytes = [
        fx.recordWithRefs(
          1,
          1,
          fx.slidePayload(titleRefIndex: 0, bodyRefIndex: 1),
          [10, 11],
        ),
        fx.recordWithRefs(10, 2, fx.shapeInfoPayload(0), [12]),
        fx.record(12, 3, fx.storagePayload(['Plan'])),
        fx.recordWithRefs(11, 2, fx.shapeInfoPayload(0), [13]),
        fx.record(13, 3, fx.storagePayload(['A\nB'])),
      ].expand((e) => e).toList();
      final stream = fx.iwaStream(recordBytes);
      final bytes = fx.zip({'Index/slide-1.iwa': stream});

      final deck = (await KeyImporter().importBytes(
        bytes,
        path: 'schema.key',
      )).okValue!;
      expect(deck.slides, hasLength(1));
      expect(deck.slides.single.title, 'Plan');
      final bullets = deck.slides.single.bodyBlocks
          .where((b) => b.kind == BodyBlockKind.bullet)
          .map((b) => b.text)
          .toList();
      expect(bullets, ['A', 'B']);
      expect(
        deck.issues.single.salvagedAs,
        'tekst, volgorde, notities en herkende tabellen, grafieken en media',
      );
    },
  );

  test(
    'preserves bullet indent levels from Keynote paragraph styles',
    () async {
      // A body StorageArchive whose paragraphs alternate between two
      // ParagraphStyleArchives: style A (listLevel 1 = top) and style B
      // (listLevel 3 = sub). The importer must map these to levels 0 and 1.
      final recordBytes = [
        fx.recordWithRefs(
          1,
          1,
          fx.slidePayload(titleRefIndex: 0, bodyRefIndex: 1),
          [10, 11],
        ),
        fx.recordWithRefs(10, 2, fx.shapeInfoPayload(0), [12]),
        fx.record(12, 3, fx.storagePayload(['Plan'])),
        // Body shape → body storage. The storage's object_references list
        // the two ParagraphStyleArchive objects (indices 0 and 1).
        fx.recordWithRefs(
          11,
          2,
          fx.shapeInfoPayload(0),
          [13], // shape's containedStorage → storage id 13
        ),
        fx.recordWithRefs(
          13,
          3,
          fx.storagePayloadWithLevels(
            'Title\nTop\nSub\nTop2\nSub2',
            [0, 0, 1, 0, 1], // style ref indices: 0=top, 1=sub
          ),
          [14, 15], // object_references: [styleA, styleB]
        ),
        fx.record(14, 2022, fx.paragraphStylePayload(1)), // top level
        fx.record(15, 2022, fx.paragraphStylePayload(3)), // sub level
      ].expand((e) => e).toList();
      final stream = fx.iwaStream(recordBytes);
      final bytes = fx.zip({'Index/slide-1.iwa': stream});

      final deck = (await KeyImporter().importBytes(
        bytes,
        path: 'levels.key',
      )).okValue!;
      expect(deck.slides, hasLength(1));
      expect(deck.slides.single.title, 'Plan');
      final bullets = deck.slides.single.bodyBlocks
          .where((b) => b.kind == BodyBlockKind.bullet)
          .toList();
      expect(bullets, hasLength(5));
      expect(bullets[0].text, 'Title');
      expect(bullets[0].level, 0);
      expect(bullets[1].text, 'Top');
      expect(bullets[1].level, 0);
      expect(bullets[2].text, 'Sub');
      expect(bullets[2].level, 1);
      expect(bullets[3].text, 'Top2');
      expect(bullets[3].level, 0);
      expect(bullets[4].text, 'Sub2');
      expect(bullets[4].level, 1);
    },
  );

  test(
    'salvages text from a real IWA Snappy stream into a bullet slide',
    () async {
      // One IWA object whose payload holds a UTF-8 string "Revenue".
      final stream = fx.iwaStream(fx.record(1, 1, fx.stringPayload('Revenue')));
      final bytes = fx.zip({
        'preview.jpg': [0xFF, 0xD8, 0xFF, 0xE0],
        'Index/slide-1.iwa': stream,
      });

      final deck = (await KeyImporter().importBytes(
        bytes,
        path: 'text.key',
      )).okValue!;
      expect(deck.slides, hasLength(2));
      final textSlide = deck.slides.last;
      expect(textSlide.title, 'Geredde tekst');
      final bullets = textSlide.bodyBlocks
          .where((b) => b.kind == BodyBlockKind.bullet)
          .map((b) => b.text)
          .toList();
      expect(bullets, contains('Revenue'));
    },
  );

  test(
    'produces a text-only deck when there is no preview but IWA text exists',
    () async {
      final stream = fx.iwaStream(
        fx.record(1, 1, fx.stringPayload('Hello World')),
      );
      final bytes = fx.zip({'Index/slide-1.iwa': stream});

      final deck = (await KeyImporter().importBytes(
        bytes,
        path: 'tonly.key',
      )).okValue!;
      expect(deck.slides, hasLength(1));
      expect(deck.slides.single.title, 'Geredde tekst');
    },
  );

  test(
    'fails with a clear message when neither preview nor IWA text is present',
    () async {
      final bytes = fx.zip({'Index/Document.iwa': fx.b('iwa')});

      final result = await KeyImporter().importBytes(bytes, path: 'bare.key');
      expect(result.isErr, isTrue);
      expect(result.errValue!.message, contains('voorbeeldafbeelding'));
    },
  );

  test(
    'falls back to a root preview*.png when preview.jpg is absent',
    () async {
      final bytes = fx.zip({
        'preview-large.png': [0x89, 0x50, 0x4E, 0x47],
      });

      final deck = (await KeyImporter().importBytes(
        bytes,
        path: 'alt.key',
      )).okValue!;
      expect(deck.slides.single.images.single.ext, 'png');
    },
  );

  test('reconstructs a table from a TableInfoArchive drawable', () async {
    // String table object (id 20).
    final stringTable = fx.record(
      20,
      100,
      fx.tableDataListPayload(
        listType: 1,
        entries: [(0, 'Naam'), (1, 'Score'), (2, 'Alice'), (3, '9.5')],
      ),
    );
    // Tile (id 22) with one header row and one data row.
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
    // DataStore embedded in TableModel (id 21).
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
    // TableInfo drawable (id 23) referenced by the slide.
    final tableInfo = fx.recordWithRefs(23, 6000, fx.tableInfoPayload(0), [21]);
    // Slide (id 1) references the table drawable.
    final slide = fx.recordWithRefs(
      1,
      1,
      fx.slidePayload(
        titleRefIndex: 0,
        bodyRefIndex: 0,
        drawableRefIndices: [0],
      ),
      [23],
    );
    final recordBytes = [
      stringTable,
      tile,
      tableModel,
      tableInfo,
      slide,
    ].expand((e) => e).toList();

    final bytes = fx.zip({'Index/slide-1.iwa': fx.iwaStream(recordBytes)});

    final result = await KeyImporter().importBytes(bytes, path: 'table.key');
    if (result.isErr) fail('Import failed: ${result.errValue?.message}');
    final deck = result.okValue!;
    expect(deck.slides, hasLength(1));
    final table = deck.slides.single.table;
    expect(table, isNotNull);
    expect(table!.header, ['Naam', 'Score']);
    expect(table.rows, [
      ['Alice', '9.5'],
    ]);
  });

  test('reconstructs a chart from a ChartDrawableArchive', () async {
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
    final slide = fx.recordWithRefs(
      1,
      1,
      fx.slidePayload(
        titleRefIndex: 0,
        bodyRefIndex: 0,
        drawableRefIndices: [0],
      ),
      [23],
    );
    final recordBytes = [chartDrawable, slide].expand((e) => e).toList();

    final bytes = fx.zip({'Index/slide-1.iwa': fx.iwaStream(recordBytes)});

    final result = await KeyImporter().importBytes(bytes, path: 'chart.key');
    if (result.isErr) fail('Import failed: ${result.errValue?.message}');
    final deck = result.okValue!;
    expect(deck.slides, hasLength(1));
    final chart = deck.slides.single.chart;
    expect(chart, isNotNull);
    expect(chart!.type, SourceChartType.line);
    expect(chart.x, ['A', 'B']);
    expect(chart.series.length, 2);
    expect(chart.series[0].name, 'Q1');
    expect(chart.series[0].data, [10.0, 20.0]);
  });

  test('flattens a group and extracts its chart and text', () async {
    final grid = fx.chartGridPayload(
      rowNames: ['Q1'],
      columnNames: ['A', 'B'],
      gridRows: [
        fx.gridRowPayload([
          fx.gridValuePayload(10.0),
          fx.gridValuePayload(20.0),
        ]),
      ],
    );
    final chartArchive = fx.chartArchivePayload(
      chartType: 1, // columnChartType2D
      chartGrid: grid,
      seriesDirection: 1, // by row
    );
    final chartDrawable = fx.record(
      23,
      6003,
      fx.chartDrawablePayload(chartArchive),
    );
    final bulletShape = fx.recordWithRefs(24, 2, fx.shapeInfoPayload(0), [25]);
    final bulletStorage = fx.record(25, 3, fx.storagePayload(['Bullet']));
    // Group (id 30) contains the chart and the bullet shape.
    final group = fx.recordWithRefs(
      30,
      200,
      fx.groupPayload(childRefIndices: [0, 1]),
      [23, 24],
    );
    // Slide title shape (id 26) -> storage (id 27) "Group".
    final titleShape = fx.recordWithRefs(26, 2, fx.shapeInfoPayload(0), [27]);
    final titleStorage = fx.record(27, 3, fx.storagePayload(['Group']));
    // Empty body placeholder (id 28) -> storage (id 29) [] so it is not
    // mixed up with the title.
    final bodyShape = fx.recordWithRefs(28, 2, fx.shapeInfoPayload(0), [29]);
    final bodyStorage = fx.record(29, 3, fx.storagePayload(<String>[]));
    final slide = fx.recordWithRefs(
      1,
      1,
      fx.slidePayload(
        titleRefIndex: 0,
        bodyRefIndex: 1,
        drawableRefIndices: [2],
      ),
      [26, 28, 30],
    );
    final recordBytes = [
      chartDrawable,
      bulletShape,
      bulletStorage,
      group,
      titleShape,
      titleStorage,
      bodyShape,
      bodyStorage,
      slide,
    ].expand((e) => e).toList();

    final bytes = fx.zip({'Index/slide-1.iwa': fx.iwaStream(recordBytes)});

    final result = await KeyImporter().importBytes(bytes, path: 'group.key');
    if (result.isErr) fail('Import failed: ${result.errValue?.message}');
    final deck = result.okValue!;
    expect(deck.slides, hasLength(1));
    expect(deck.slides.single.title, 'Group');
    expect(deck.slides.single.chart, isNotNull);
    expect(deck.slides.single.bodyBlocks, hasLength(1));
    expect(deck.slides.single.bodyBlocks.single.text, 'Bullet');
    expect(deck.issues.any((i) => i.feature == 'Groepering'), isTrue);
  });

  test('reconstructs a video from a MovieArchive drawable', () async {
    const dataId = 50;
    const fileName = 'clip.mp4';
    const videoBytes = <int>[0x00, 0x00, 0x00, 0x20, 0x66, 0x74, 0x79, 0x70];
    final recordBytes = [
      // PackageMetadata (id 2) maps dataId -> Data/ file name.
      fx.record(
        2,
        100,
        fx.packageMetadataPayload(
          dataInfos: [
            fx.dataInfoPayload(identifier: dataId, preferredFileName: fileName),
          ],
        ),
      ),
      // Movie (id 23) references the dataId.
      fx.record(23, 200, fx.moviePayload(movieDataId: dataId)),
      // Slide (id 1) includes the movie drawable.
      fx.recordWithRefs(
        1,
        1,
        fx.slidePayload(
          titleRefIndex: 0,
          bodyRefIndex: 0,
          drawableRefIndices: [0],
        ),
        [23],
      ),
    ].expand((e) => e).toList();

    final bytes = fx.zip({
      'Index/slide-1.iwa': fx.iwaStream(recordBytes),
      'Data/$fileName': videoBytes,
    });

    final result = await KeyImporter().importBytes(bytes, path: 'video.key');
    if (result.isErr) fail('Import failed: ${result.errValue?.message}');
    final deck = result.okValue!;
    expect(deck.slides, hasLength(1));
    final video = deck.slides.single.video;
    expect(video, isNotNull);
    expect(video!.kind, SourceVideoKind.local);
    expect(video.ref, 'media/$fileName');
    expect(video.bytes, videoBytes);
  });

  test('reconstructs images from IWA drawables via PackageMetadata', () async {
    const dataId = 42;
    const fileName = 'photo.png';
    const imageBytes = <int>[0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A];
    final recordBytes = [
      // PackageMetadata (id 2) maps dataId -> Data/ file name.
      fx.record(
        2,
        100,
        fx.packageMetadataPayload(
          dataInfos: [
            fx.dataInfoPayload(identifier: dataId, preferredFileName: fileName),
          ],
        ),
      ),
      // Image (id 10) references the dataId.
      fx.record(10, 200, fx.imagePayload(dataId)),
      // Slide (id 1) includes the image drawable.
      fx.recordWithRefs(
        1,
        1,
        fx.slidePayload(
          titleRefIndex: 0,
          bodyRefIndex: 0,
          drawableRefIndices: [0],
        ),
        [10],
      ),
    ].expand((e) => e).toList();

    final bytes = fx.zip({
      'Index/slide-1.iwa': fx.iwaStream(recordBytes),
      'Data/$fileName': imageBytes,
    });

    final deck = (await KeyImporter().importBytes(
      bytes,
      path: 'image.key',
    )).okValue!;
    expect(deck.slides, hasLength(1));
    expect(deck.slides.single.images, hasLength(1));
    expect(deck.slides.single.images.single.bytes, imageBytes);
    expect(deck.slides.single.images.single.ext, 'png');
  });

  test(
    'skips Keynote thumbnail (field 12) and imports only the full image',
    () async {
      // Keynote stores both a full-resolution image (field 11) and a small
      // thumbnail preview (field 12) in each ImageArchive. The thumbnail
      // must not be imported as a separate image — it creates duplicates
      // in the image library (#1468).
      const fullDataId = 42;
      const thumbDataId = 43;
      const fullFileName = 'photo.png';
      const thumbFileName = 'photo-small.png';
      const fullBytes = <int>[0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A];
      const thumbBytes = <int>[0x89, 0x50, 0x4E, 0x47, 0x01];
      final recordBytes = [
        fx.record(
          2,
          100,
          fx.packageMetadataPayload(
            dataInfos: [
              fx.dataInfoPayload(
                identifier: fullDataId,
                preferredFileName: fullFileName,
              ),
              fx.dataInfoPayload(
                identifier: thumbDataId,
                preferredFileName: thumbFileName,
              ),
            ],
          ),
        ),
        // Image (id 10) with both full (field 11) and thumbnail (field 12).
        fx.record(10, 200, [
          ...fx.varint(fx.key(1, 2)),
          ...fx.varint(0), // empty DrawableArchive super
          ...fx.bytesField(11, fx.varintField(1, fullDataId)),
          ...fx.bytesField(12, fx.varintField(1, thumbDataId)),
        ]),
        fx.recordWithRefs(
          1,
          1,
          fx.slidePayload(
            titleRefIndex: 0,
            bodyRefIndex: 0,
            drawableRefIndices: [0],
          ),
          [10],
        ),
      ].expand((e) => e).toList();

      final bytes = fx.zip({
        'Index/slide-1.iwa': fx.iwaStream(recordBytes),
        'Data/$fullFileName': fullBytes,
        'Data/$thumbFileName': thumbBytes,
      });

      final deck = (await KeyImporter().importBytes(
        bytes,
        path: 'thumb.key',
      )).okValue!;
      expect(deck.slides, hasLength(1));
      // Only the full image, not the thumbnail.
      expect(deck.slides.single.images, hasLength(1));
      expect(deck.slides.single.images.single.bytes, fullBytes);
    },
  );

  test('skips adjusted-image thumbnail (field 16) and imports only the full '
      'adjusted image (field 15)', () async {
    // Een in Keynote aangepaste afbeelding draagt de volle aangepaste
    // afbeelding op field 15 (`adjustedImageData`) én een kleine thumbnail
    // daarvan op field 16 (`thumbnailAdjustedImageData`). Beide importeren
    // geeft de "normaal + small"-dubbeling die de gebruiker zag (#1468).
    const adjustedDataId = 52;
    const thumbDataId = 53;
    const adjustedFileName = 'photo-adjusted.png';
    const thumbFileName = 'photo-adjusted-small.png';
    const adjustedBytes = <int>[
      0x89,
      0x50,
      0x4E,
      0x47,
      0x0D,
      0x0A,
      0x1A,
      0x0A,
      0x10,
    ];
    const thumbBytes = <int>[0x89, 0x50, 0x4E, 0x47, 0x02];
    final recordBytes = [
      fx.record(
        2,
        100,
        fx.packageMetadataPayload(
          dataInfos: [
            fx.dataInfoPayload(
              identifier: adjustedDataId,
              preferredFileName: adjustedFileName,
            ),
            fx.dataInfoPayload(
              identifier: thumbDataId,
              preferredFileName: thumbFileName,
            ),
          ],
        ),
      ),
      // Image (id 10) with adjusted full (field 15) + its thumbnail (16).
      fx.record(10, 200, [
        ...fx.varint(fx.key(1, 2)),
        ...fx.varint(0), // empty DrawableArchive super
        ...fx.bytesField(15, fx.varintField(1, adjustedDataId)),
        ...fx.bytesField(16, fx.varintField(1, thumbDataId)),
      ]),
      fx.recordWithRefs(
        1,
        1,
        fx.slidePayload(
          titleRefIndex: 0,
          bodyRefIndex: 0,
          drawableRefIndices: [0],
        ),
        [10],
      ),
    ].expand((e) => e).toList();

    final bytes = fx.zip({
      'Index/slide-1.iwa': fx.iwaStream(recordBytes),
      'Data/$adjustedFileName': adjustedBytes,
      'Data/$thumbFileName': thumbBytes,
    });

    final deck = (await KeyImporter().importBytes(
      bytes,
      path: 'adjusted.key',
    )).okValue!;
    expect(deck.slides, hasLength(1));
    // Only the full adjusted image, not its thumbnail.
    expect(deck.slides.single.images, hasLength(1));
    expect(deck.slides.single.images.single.bytes, adjustedBytes);
  });

  test('style reference (field 3) whose id collides with a data id does not '
      'inject a template image (#1478)', () async {
    // Keynote drawables carry a style reference on field 3 that points at
    // a TSD.MediaStyle (type 3016) object. Object-IDs en data-IDs delen
    // een namespace, dus als het style-object id 111 heeft én data-ID 111
    // naar een bestand (image51-111.png) mapt, interpreteerde de fallback
    // path de style-referentie als een DataReference en injecteerde de
    // template-afbeelding op elke slide. Op een slide met 180° IWA-rotatie
    // werd die extra afbeelding meegeroteerd en verscheen op de kop.
    const imageDataId = 42;
    const styleObjId = 111;
    const templateDataId = 111;
    const imageFileName = 'photo.png';
    const templateFileName = 'template.png';
    const imageBytes = <int>[0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A];
    const templateBytes = <int>[0x89, 0x50, 0x4E, 0x47, 0x01];
    final recordBytes = [
      fx.record(
        2,
        100,
        fx.packageMetadataPayload(
          dataInfos: [
            fx.dataInfoPayload(
              identifier: imageDataId,
              preferredFileName: imageFileName,
            ),
            fx.dataInfoPayload(
              identifier: templateDataId,
              preferredFileName: templateFileName,
            ),
          ],
        ),
      ),
      // Style object (id 111, type 3016) — not an image.
      fx.record(styleObjId, 3016, [
        ...fx.varint(fx.key(1, 2)),
        ...fx.varint(0),
      ]),
      // Image (id 10) with field 11 → photo + field 3 → style obj 111.
      fx.record(10, 200, [
        ...fx.varint(fx.key(1, 2)),
        ...fx.varint(0), // empty DrawableArchive super
        ...fx.bytesField(11, fx.varintField(1, imageDataId)),
        ...fx.bytesField(3, fx.varintField(1, styleObjId)),
      ]),
      fx.recordWithRefs(
        1,
        1,
        fx.slidePayload(
          titleRefIndex: 0,
          bodyRefIndex: 0,
          drawableRefIndices: [0],
        ),
        [10],
      ),
    ].expand((e) => e).toList();

    final bytes = fx.zip({
      'Index/slide-1.iwa': fx.iwaStream(recordBytes),
      'Data/$imageFileName': imageBytes,
      'Data/$templateFileName': templateBytes,
    });

    final deck = (await KeyImporter().importBytes(
      bytes,
      path: 'style-collision.key',
    )).okValue!;
    expect(deck.slides, hasLength(1));
    // Only the slide's own image, not the template.
    expect(deck.slides.single.images, hasLength(1));
    expect(deck.slides.single.images.single.bytes, imageBytes);
  });

  test(
    'PackageMetadata components with TSP.Reference submessages give slide order',
    () async {
      // Real Keynote files encode the component's object reference (field 1)
      // as a TSP.Reference submessage, not a raw varint. Three slides with
      // distinct titles, ordered via PackageMetadata components.
      final recordBytes = [
        // PackageMetadata (id 2) with three Slide- components.
        fx.record(
          2,
          100,
          fx.packageMetadataPayload(
            components: [
              (objectId: 10, locator: 'Slide-1'),
              (objectId: 20, locator: 'Slide-2'),
              (objectId: 30, locator: 'Slide-3'),
            ],
          ),
        ),
        // Slide 1 (id 10): title "Alpha".
        fx.recordWithRefs(
          10,
          1,
          fx.slidePayload(titleRefIndex: 0, bodyRefIndex: 1),
          [11, 12],
        ),
        fx.recordWithRefs(11, 2, fx.shapeInfoPayload(0), [13]),
        fx.record(13, 3, fx.storagePayload(['Alpha'])),
        fx.recordWithRefs(12, 2, fx.shapeInfoPayload(0), [14]),
        fx.record(14, 3, fx.storagePayload([''])),
        // Slide 2 (id 20): title "Beta".
        fx.recordWithRefs(
          20,
          1,
          fx.slidePayload(titleRefIndex: 0, bodyRefIndex: 1),
          [21, 22],
        ),
        fx.recordWithRefs(21, 2, fx.shapeInfoPayload(0), [23]),
        fx.record(23, 3, fx.storagePayload(['Beta'])),
        fx.recordWithRefs(22, 2, fx.shapeInfoPayload(0), [24]),
        fx.record(24, 3, fx.storagePayload([''])),
        // Slide 3 (id 30): title "Gamma".
        fx.recordWithRefs(
          30,
          1,
          fx.slidePayload(titleRefIndex: 0, bodyRefIndex: 1),
          [31, 32],
        ),
        fx.recordWithRefs(31, 2, fx.shapeInfoPayload(0), [33]),
        fx.record(33, 3, fx.storagePayload(['Gamma'])),
        fx.recordWithRefs(32, 2, fx.shapeInfoPayload(0), [34]),
        fx.record(34, 3, fx.storagePayload([''])),
      ].expand((e) => e).toList();
      final bytes = fx.zip({'Index/Document.iwa': fx.iwaStream(recordBytes)});

      final deck = (await KeyImporter().importBytes(
        bytes,
        path: 'ordered.key',
      )).okValue!;
      expect(deck.slides, hasLength(3));
      expect(deck.slides[0].title, 'Alpha');
      expect(deck.slides[1].title, 'Beta');
      expect(deck.slides[2].title, 'Gamma');
    },
  );

  test(
    'ShowArchive SlideTree gives the real presentation order, not storage order',
    () async {
      // Real Keynote files store the authoritative slide order in
      // KN.ShowArchive.slideTree (field 3), not in PackageMetadata components
      // (which are storage order). Three slides where the ShowArchive order
      // differs from the PackageMetadata order (#1471).
      final recordBytes = [
        // DocumentArchive (id 1, typeId 1) → field 2 refs ShowArchive (id 2).
        fx.recordWithRefs(1, 1, fx.varintField(2, 0), [2]),
        // ShowArchive (id 2, typeId 2) with field 3 = SlideTreeArchive.
        // object_references = [SlideNode A, SlideNode B, SlideNode C].
        fx.recordWithRefs(
          2,
          2,
          [
            // field 3 = SlideTreeArchive (nested submessage)
            ...fx.bytesField(3, fx.slideTreePayload([0, 1, 2])),
          ],
          [10, 11, 12],
        ),
        // SlideNode A (id 10, typeId 4) → slide 20 ("Alpha").
        fx.recordWithRefs(10, 4, fx.slideNodePayload(slideRefIndex: 0), [20]),
        // SlideNode B (id 11, typeId 4) → slide 21 ("Beta").
        fx.recordWithRefs(11, 4, fx.slideNodePayload(slideRefIndex: 0), [21]),
        // SlideNode C (id 12, typeId 4) → slide 22 ("Gamma").
        fx.recordWithRefs(12, 4, fx.slideNodePayload(slideRefIndex: 0), [22]),
        // Slide 20 (typeId 5): title "Alpha".
        fx.recordWithRefs(
          20,
          5,
          fx.slidePayload(titleRefIndex: 0, bodyRefIndex: 1),
          [23, 24],
        ),
        fx.recordWithRefs(23, 2, fx.shapeInfoPayload(0), [25]),
        fx.record(25, 3, fx.storagePayload(['Alpha'])),
        fx.recordWithRefs(24, 2, fx.shapeInfoPayload(0), [26]),
        fx.record(26, 3, fx.storagePayload([''])),
        // Slide 21 (typeId 5): title "Beta".
        fx.recordWithRefs(
          21,
          5,
          fx.slidePayload(titleRefIndex: 0, bodyRefIndex: 1),
          [27, 28],
        ),
        fx.recordWithRefs(27, 2, fx.shapeInfoPayload(0), [29]),
        fx.record(29, 3, fx.storagePayload(['Beta'])),
        fx.recordWithRefs(28, 2, fx.shapeInfoPayload(0), [30]),
        fx.record(30, 3, fx.storagePayload([''])),
        // Slide 22 (typeId 5): title "Gamma".
        fx.recordWithRefs(
          22,
          5,
          fx.slidePayload(titleRefIndex: 0, bodyRefIndex: 1),
          [31, 32],
        ),
        fx.recordWithRefs(31, 2, fx.shapeInfoPayload(0), [33]),
        fx.record(33, 3, fx.storagePayload(['Gamma'])),
        fx.recordWithRefs(32, 2, fx.shapeInfoPayload(0), [34]),
        fx.record(34, 3, fx.storagePayload([''])),
      ].expand((e) => e).toList();
      final bytes = fx.zip({'Index/Document.iwa': fx.iwaStream(recordBytes)});

      final deck = (await KeyImporter().importBytes(
        bytes,
        path: 'showtree.key',
      )).okValue!;
      expect(deck.slides, hasLength(3));
      expect(deck.slides[0].title, 'Alpha');
      expect(deck.slides[1].title, 'Beta');
      expect(deck.slides[2].title, 'Gamma');
    },
  );
}
