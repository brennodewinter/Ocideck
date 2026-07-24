import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/services/import/importers/keynote/iwa/iwa_archive.dart';
import 'package:ocideck/services/import/importers/keynote/iwa/iwa_document.dart';
import 'package:ocideck/services/import/importers/keynote/iwa/proto_wire.dart';
import 'package:ocideck/services/import/importers/keynote/iwa/slide_reconstructor.dart';
import 'package:ocideck/services/import/models/body_block.dart';

List<int> _varint(int v) {
  final out = <int>[];
  while (v >= 0x80) {
    out.add((v & 0x7f) | 0x80);
    v >>= 7;
  }
  out.add(v);
  return out;
}

int _key(int field, int wireType) => (field << 3) | wireType;

List<int> _varintField(int field, int value) => [
  ..._varint(_key(field, 0)),
  ..._varint(value),
];

List<int> _stringField(int field, String text) {
  final data = utf8.encode(text);
  return [..._varint(_key(field, 2)), ..._varint(data.length), ...data];
}

/// A payload for a ShapeInfoArchive: super (field 1, empty submessage) +
/// containedStorage reference (field 2, an index into object_references).
List<int> _shapeInfoPayload(int storageRefIndex) => [
  ..._varint(_key(1, 2)), ..._varint(0), // empty ShapeArchive super
  ..._varintField(2, storageRefIndex),
];

/// A payload for a StorageArchive with the given text fragments (repeated
/// string field 3).
List<int> _storagePayload(List<String> texts) => [
  for (final t in texts) ..._stringField(3, t),
];

/// A payload for a SlideArchive: title ref (5), body ref (6), drawables (7).
List<int> _slidePayload({
  required int titleRefIndex,
  required int bodyRefIndex,
  List<int> drawableRefIndices = const [],
}) {
  final out = <int>[
    ..._varintField(5, titleRefIndex),
    ..._varintField(6, bodyRefIndex),
  ];
  for (final d in drawableRefIndices) {
    out.addAll(_varintField(7, d));
  }
  return out;
}

/// A NoteArchive payload: `containedStorage` (field 1, Reference).
List<int> _notePayload(int storageRefIndex) => _varintField(1, storageRefIndex);

/// A payload for a SlideNodeArchive: `children` (field 1, repeated Reference)
/// and/or `slide` (field 2, single Reference). Each value is an index into the
/// node's object_references.
List<int> _slideNodePayload({
  int? slideRefIndex,
  List<int> childrenRefIndices = const [],
}) {
  final out = <int>[];
  for (final c in childrenRefIndices) {
    out.addAll(_varintField(1, c));
  }
  if (slideRefIndex != null) out.addAll(_varintField(2, slideRefIndex));
  return out;
}

/// Build one IWA record with [objectRefs] as MessageInfo.object_references.
List<int> _record(int id, int type, List<int> payload, List<int> objectRefs) {
  final packed = <int>[];
  for (final r in objectRefs) {
    packed.addAll(_varint(r));
  }
  final messageInfo = [
    ..._varintField(1, type),
    ..._varintField(3, payload.length),
    _key(5, 2),
    ..._varint(packed.length),
    ...packed,
  ];
  final archiveInfo = [
    ..._varintField(1, id),
    _key(2, 2),
    ..._varint(messageInfo.length),
    ...messageInfo,
  ];
  return [..._varint(archiveInfo.length), ...archiveInfo, ...payload];
}

void main() {
  final wire = ProtoWire();

  /// Builds a 2-slide IWA stream:
  ///   slide 1: title="Plan", body bullets "A","B"
  ///   slide 2: title="Demo", body "C"
  /// Object ids: 10/11 = slide1 title/body shapes, 12/13 = their storages,
  ///             20/21/22 = slide2 shape + storage, 1/2 = slide archives.
  List<int> twoSlideStream() {
    return [
      // Slide 1 (id=1): titleRef->10, bodyRef->11, no extra drawables.
      _record(1, 1, _slidePayload(titleRefIndex: 0, bodyRefIndex: 1), [10, 11]),
      // Shape 10 -> storage 12 ("Plan").
      _record(10, 2, _shapeInfoPayload(0), [12]),
      // Storage 12.
      _record(12, 3, _storagePayload(['Plan']), const []),
      // Shape 11 -> storage 13 ("A\nB").
      _record(11, 2, _shapeInfoPayload(0), [13]),
      // Storage 13.
      _record(13, 3, _storagePayload(['A\nB']), const []),
      // Slide 2 (id=2): titleRef->20, bodyRef->21.
      _record(2, 1, _slidePayload(titleRefIndex: 0, bodyRefIndex: 1), [20, 21]),
      // Shape 20 -> storage 22 ("Demo").
      _record(20, 2, _shapeInfoPayload(0), [22]),
      _record(22, 3, _storagePayload(['Demo']), const []),
      // Shape 21 -> storage 23 ("C").
      _record(21, 2, _shapeInfoPayload(0), [23]),
      _record(23, 3, _storagePayload(['C']), const []),
    ].expand((e) => e).toList();
  }

  test('reconstructs slides with title and body bullets in order', () {
    final objects = IwaArchive(wire).parse(twoSlideStream());
    final doc = IwaDocument(objects);
    final slides = SlideReconstructor(doc).reconstruct();

    expect(slides, hasLength(2));
    expect(slides[0].title, 'Plan');
    expect(slides[1].title, 'Demo');

    final slide1Bullets = slides[0].bodyBlocks
        .where((b) => b.kind == BodyBlockKind.bullet)
        .map((b) => b.text)
        .toList();
    expect(slide1Bullets, ['A', 'B']);
    expect(slides[1].bodyBlocks.single.text, 'C');
  });

  test('skips objects that are not text-bearing slides', () {
    // A storage with no slide parent and a random object with field 7 refs
    // that resolve to nothing should not produce slides.
    final stream = [
      _record(50, 3, _storagePayload(['loose']), const []),
      _record(51, 1, _varintField(7, 0), [99]), // ref to missing object
    ].expand((e) => e).toList();
    final objects = IwaArchive(wire).parse(stream);
    final slides = SlideReconstructor(IwaDocument(objects)).reconstruct();
    expect(slides, isEmpty);
  });

  test('recovers slide order from the SlideNode tree, not parse order', () {
    // Build a SlideNode tree: root -> [nodeA, nodeB]; nodeA -> slideX ("First"),
    // nodeB -> slideY ("Second"). Insert slideY BEFORE slideX in the stream so
    // parse order would be [Second, First]; the tree must yield [First, Second].
    //
    // Shapes/storages: 11/12 = "First" title/body, 21/22 = "Second" title/body.
    final stream = [
      // slideY (id 2) first in stream — parse order would put it first.
      _record(2, 1, _slidePayload(titleRefIndex: 0, bodyRefIndex: 1), [21, 22]),
      _record(21, 2, _shapeInfoPayload(0), [23]),
      _record(23, 3, _storagePayload(['Second']), const []),
      _record(22, 2, _shapeInfoPayload(0), [24]),
      _record(24, 3, _storagePayload(<String>[]), const []),
      // slideX (id 1) second in stream.
      _record(1, 1, _slidePayload(titleRefIndex: 0, bodyRefIndex: 1), [11, 12]),
      _record(11, 2, _shapeInfoPayload(0), [13]),
      _record(13, 3, _storagePayload(['First']), const []),
      _record(12, 2, _shapeInfoPayload(0), [14]),
      _record(14, 3, _storagePayload(<String>[]), const []),
      // SlideNode tree: root -> [nodeA, nodeB]; nodeA -> slideX, nodeB -> slideY.
      _record(100, 4, _slideNodePayload(childrenRefIndices: [0, 1]), [
        101,
        102,
      ]),
      _record(101, 5, _slideNodePayload(slideRefIndex: 0), [1]),
      _record(102, 5, _slideNodePayload(slideRefIndex: 0), [2]),
    ].expand((e) => e).toList();

    final objects = IwaArchive(wire).parse(stream);
    final slides = SlideReconstructor(IwaDocument(objects)).reconstruct();

    expect(slides, hasLength(2));
    expect(slides[0].title, 'First');
    expect(slides[1].title, 'Second');
    // Indices follow the tree (source) order, not parse order.
    expect(slides[0].index, lessThan(slides[1].index));
  });

  test(
    'salvages speaker notes via SlideArchive.note -> NoteArchive -> storage',
    () {
      // Slide 1 carries a note ref (field 27) -> note (id 30) -> storage (id 31).
      final stream = [
        _record(
          1,
          1,
          [
            ..._slidePayload(titleRefIndex: 0, bodyRefIndex: 1),
            ..._varintField(27, 2), // note ref -> object_references[2] -> 30
          ],
          [10, 11, 30],
        ),
        _record(10, 2, _shapeInfoPayload(0), [12]),
        _record(12, 3, _storagePayload(['Plan']), const []),
        _record(11, 2, _shapeInfoPayload(0), [13]),
        _record(13, 3, _storagePayload(<String>[]), const []),
        _record(30, 6, _notePayload(0), [31]),
        _record(31, 3, _storagePayload(['Remember to introduce']), const []),
      ].expand((e) => e).toList();

      final objects = IwaArchive(wire).parse(stream);
      final slides = SlideReconstructor(IwaDocument(objects)).reconstruct();

      expect(slides, hasLength(1));
      expect(slides.single.title, 'Plan');
      expect(slides.single.notes, 'Remember to introduce');
    },
  );
}
