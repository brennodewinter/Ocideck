import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/services/import/core/result.dart';
import 'package:ocideck/services/import/importers/keynote/key_importer.dart';

import 'helpers/key_fixtures.dart' as fx;

void main() {
  test('imports a large Keynote deck with many text slides', () async {
    const slideCount = 50;
    final records = <List<int>>[];
    final childIds = <int>[];
    final slideIds = <int>[];

    var nextId = 100;
    for (var i = 0; i < slideCount; i++) {
      final titleStorageId = nextId++;
      final bodyStorageId = nextId++;
      final titleShapeId = nextId++;
      final bodyShapeId = nextId++;
      final slideId = nextId++;
      final childNodeId = nextId++;

      records.addAll([
        fx.record(titleStorageId, 3, fx.storagePayload(['Slide $i'])),
        fx.record(bodyStorageId, 3, fx.storagePayload(['Bullet $i'])),
        fx.recordWithRefs(titleShapeId, 2, fx.shapeInfoPayload(0), [
          titleStorageId,
        ]),
        fx.recordWithRefs(bodyShapeId, 2, fx.shapeInfoPayload(0), [
          bodyStorageId,
        ]),
        fx.recordWithRefs(
          slideId,
          1,
          fx.slidePayload(titleRefIndex: 0, bodyRefIndex: 1),
          [titleShapeId, bodyShapeId],
        ),
        fx.recordWithRefs(
          childNodeId,
          5,
          fx.slideNodePayload(slideRefIndex: 0),
          [slideId],
        ),
      ]);

      childIds.add(childNodeId);
      slideIds.add(slideId);
    }

    final rootId = nextId++;
    final rootRefs = List<int>.generate(childIds.length, (i) => i);
    records.add(
      fx.recordWithRefs(
        rootId,
        4,
        fx.slideNodePayload(childrenRefIndices: rootRefs),
        childIds,
      ),
    );

    final recordBytes = records.expand((e) => e).toList();
    final bytes = fx.zip({'Index/slide-1.iwa': fx.iwaStream(recordBytes)});

    final result = await KeyImporter().importBytes(bytes, path: 'large.key');
    expect(result.isErr, isFalse);
    final deck = result.okValue!;
    expect(deck.slides, hasLength(slideCount));
    expect(deck.slides.first.title, 'Slide 0');
    expect(deck.slides.last.title, 'Slide ${slideCount - 1}');
    expect(deck.slides[25].bodyBlocks.single.text, 'Bullet 25');
  });
}
