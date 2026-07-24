import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/services/import/models/source_format.dart';
import 'package:ocideck/services/import/pipeline/format_detector.dart';

void main() {
  List<int> zipWith(Map<String, List<int>> entries) {
    final archive = Archive();
    entries.forEach((name, data) {
      archive.addFile(ArchiveFile(name, data.length, data));
    });
    return ZipEncoder().encode(archive);
  }

  test('detects PPTX by the ppt/presentation.xml marker', () {
    final bytes = zipWith({'ppt/presentation.xml': utf8Bytes('<p/>')});
    expect(detectFormatFromBytes(bytes), SourceFormat.pptx);
  });

  test('detects ODP by the mimetype entry', () {
    final bytes = zipWith({
      'mimetype': utf8Bytes('application/vnd.oasis.opendocument.presentation'),
      'content.xml': utf8Bytes('<office/>'),
    });
    expect(detectFormatFromBytes(bytes), SourceFormat.odp);
  });

  test('detects KEY by an Index/*.iwa entry', () {
    final bytes = zipWith({
      'Index/Document.iwa': [1, 2, 3],
    });
    expect(detectFormatFromBytes(bytes), SourceFormat.key);
  });

  test('detects KEY by META-INF/manifest.json', () {
    final bytes = zipWith({
      'META-INF/manifest.json': utf8Bytes('{"fileMinorVersion":2}'),
    });
    expect(detectFormatFromBytes(bytes), SourceFormat.key);
  });

  test('non-zip bytes are unknown', () {
    expect(
      detectFormatFromBytes([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A]),
      SourceFormat.unknown,
    );
  });

  test('too-short input is unknown', () {
    expect(detectFormatFromBytes([0x50, 0x4B]), SourceFormat.unknown);
  });

  test('a content marker wins over a misleading extension', () {
    // The bytes carry the PPTX marker but the basename claims `.key`; the marker
    // must decide, otherwise the extension shortcut would mislabel a real deck.
    final bytes = zipWith({'ppt/presentation.xml': utf8Bytes('<p/>')});
    expect(
      detectFormatFromBytes(bytes, basename: 'deck.key'),
      SourceFormat.pptx,
    );
  });

  test('a marker-less zip falls back to the extension', () {
    final bytes = zipWith({'random/file.txt': utf8Bytes('hi')});
    expect(
      detectFormatFromBytes(bytes, basename: 'deck.odp'),
      SourceFormat.odp,
    );
    expect(
      detectFormatFromBytes(bytes, basename: 'deck.pptx'),
      SourceFormat.pptx,
    );
    expect(
      detectFormatFromBytes(bytes, basename: 'deck.txt'),
      SourceFormat.unknown,
    );
  });

  group('validateFormatFromBytes reports integrity', () {
    test('a proper PPTX archive is valid with no error', () {
      final bytes = zipWith({'ppt/presentation.xml': utf8Bytes('<p/>')});
      final v = validateFormatFromBytes(bytes);
      expect(v.format, SourceFormat.pptx);
      expect(v.isValid, isTrue);
      expect(v.error, isNull);
    });

    test('too-short input is invalid with an explanation', () {
      final v = validateFormatFromBytes([0x50, 0x4B]);
      expect(v.format, SourceFormat.unknown);
      expect(v.isValid, isFalse);
      expect(v.error, isNotNull);
    });

    test('a non-zip payload keeps the extension but is flagged invalid', () {
      final v = validateFormatFromBytes(
        utf8Bytes('this is plainly not a zip archive'),
        basename: 'deck.pptx',
      );
      expect(v.format, SourceFormat.pptx);
      expect(v.isValid, isFalse);
      expect(v.error, isNotNull);
    });

    test('a marker-less zip with an unknown name is fully unknown', () {
      final bytes = zipWith({'random/file.txt': utf8Bytes('hi')});
      final v = validateFormatFromBytes(bytes);
      expect(v.format, SourceFormat.unknown);
      expect(v.isValid, isFalse);
      expect(v.error, isNotNull);
    });
  });
}

List<int> utf8Bytes(String s) => Uint8List.fromList(utf8.encode(s));
