import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/services/import/core/result.dart';
import 'package:ocideck/services/import/importers/keynote/key_importer.dart';

import 'helpers/key_fixtures.dart' as fx;

void main() {
  test('returns an error for a file that is not a zip', () async {
    final result = await KeyImporter().importBytes(
      utf8.encode('not a zip'),
      path: 'not_a_key.key',
    );
    expect(result.isErr, isTrue);
    expect(result.errValue?.message, contains('geen zip-archief'));
  });

  test(
    'returns an error for an empty zip with no preview and no IWA',
    () async {
      final bytes = fx.zip({'readme.txt': 'hello'});
      final result = await KeyImporter().importBytes(bytes, path: 'empty.key');
      expect(result.isErr, isTrue);
      expect(result.errValue?.message, contains('voorbeeldafbeelding'));
    },
  );

  test(
    'de foutmelding bij een leeg .key bevat diagnostische info over het archief',
    () async {
      final bytes = fx.zip({
        'readme.txt': 'hello',
        'Metadata/Properties.plist': '<plist/>',
      });
      final result = await KeyImporter().importBytes(bytes, path: 'empty.key');
      expect(result.isErr, isTrue);
      final msg = result.errValue!.message;
      expect(msg, contains('Archief:'));
      expect(msg, contains('2 bestanden'));
      expect(msg, contains('preview: nee'));
      expect(msg, contains('metadata: ja'));
    },
  );

  test('salvages only preview.jpg when no IWA exists', () async {
    const imageBytes = <int>[0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A];
    final bytes = fx.zip({'preview.jpg': imageBytes});
    final result = await KeyImporter().importBytes(
      bytes,
      path: 'preview_only.key',
    );
    expect(result.isErr, isFalse);
    final deck = result.okValue!;
    expect(deck.slides, hasLength(1));
    expect(deck.slides.single.images, hasLength(1));
    expect(deck.slides.single.title, 'Voorbeeld');
    expect(deck.issues, isNotEmpty);
  });

  test(
    'een plist met ongeldige UTF-8 laat de import niet struikelen',
    () async {
      // Metadata/Properties.plist met bytes die geen geldige UTF-8 zijn
      // (0xC0 start een 2-byte sequence, maar de volgende byte is geen
      // continuation byte). Vroeger liet dit de hele import falen met
      // "FormatException: Missing extension byte"; nu slaat readPart null
      // terug en neemt deckMetadataFromPlist de graceful fallback.
      const imageBytes = <int>[0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A];
      final badPlist = <int>[
        0x00,
        0x01,
        0x02,
        0x03,
        0x04,
        0x05,
        0x06,
        0x07,
        0x08,
        0xC0,
        0x41,
      ];
      final bytes = fx.zip({
        'preview.jpg': imageBytes,
        'Metadata/Properties.plist': badPlist,
      });
      final result = await KeyImporter().importBytes(
        bytes,
        path: 'bad_plist.key',
      );
      expect(result.isErr, isFalse);
      final deck = result.okValue!;
      expect(deck.slides, hasLength(1));
      expect(deck.title, '');
      expect(deck.author, '');
    },
  );

  test('falls back to text salvage when IWA is corrupt', () async {
    final iwaBytes = <int>[0x00, 0x01, 0x02, 0x03, 0x04, 0x05];
    final bytes = fx.zip({'Index/slide-1.iwa': iwaBytes});
    final result = await KeyImporter().importBytes(
      bytes,
      path: 'corrupt_iwa.key',
    );
    expect(result.isErr, isTrue);
    expect(result.errValue?.message, contains('voorbeeldafbeelding'));
  });

  test('records an issue when a video data file is missing', () async {
    final packageMetadata = fx.record(
      2,
      100,
      fx.packageMetadataPayload(
        dataInfos: [
          fx.dataInfoPayload(identifier: 50, preferredFileName: 'missing.mp4'),
        ],
      ),
    );
    final movie = fx.record(23, 200, fx.moviePayload(movieDataId: 50));
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
      packageMetadata,
      movie,
      slide,
    ].expand((e) => e).toList();
    final bytes = fx.zip({'Index/slide-1.iwa': fx.iwaStream(recordBytes)});
    final result = await KeyImporter().importBytes(
      bytes,
      path: 'missing_video.key',
    );
    expect(result.isErr, isFalse);
    final deck = result.okValue!;
    expect(deck.slides, hasLength(1));
    expect(deck.slides.single.video, isNotNull);
    expect(deck.slides.single.video!.bytes, isNull);
  });
}
