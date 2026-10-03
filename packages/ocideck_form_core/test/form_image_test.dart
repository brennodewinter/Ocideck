import 'dart:math';
import 'dart:typed_data';

import 'package:ocideck_form_core/ocideck_form_core.dart';
import 'package:test/test.dart';

import 'support/image_fixtures.dart';

/// The EXIF `cleanImage` writes back: the orientation and nothing else.
List<int> orientationOnly(int o) => [
  ...text('MM'),
  ...u16(42),
  ...u32(8),
  ...u16(1),
  ...u16(0x0112),
  ...u16(3),
  ...u32(1),
  ...u16(o),
  0,
  0,
  ...u32(0),
];

void main() {
  group('sniffImageKind — from the bytes, never from a name', () {
    test('recognises the four kinds', () {
      expect(sniffImageKind(jpeg()), FormImageKind.jpeg);
      expect(sniffImageKind(png()), FormImageKind.png);
      expect(sniffImageKind(webp()), FormImageKind.webp);
      expect(sniffImageKind(heic()), FormImageKind.heic);
    });

    test('every brand of the HEIC family is HEIC; AVIF is not', () {
      for (final brand in [
        'heic',
        'heix',
        'hevc',
        'hevx',
        'heim',
        'heis',
        'hevm',
        'hevs',
        'mif1',
        'msf1',
      ]) {
        expect(
          sniffImageKind(heic(brand: brand)),
          FormImageKind.heic,
          reason: brand,
        );
      }
      expect(sniffImageKind(heic(brand: 'avif')), isNull);
      expect(sniffImageKind(heic(brand: 'mp42')), isNull);
    });

    test('text, a script, an empty file and a too-short head are none', () {
      expect(sniffImageKind(bytes(text('<svg xmlns="..."></svg>'))), isNull);
      expect(sniffImageKind(bytes(text('GIF89a......'))), isNull);
      expect(sniffImageKind(Uint8List(0)), isNull);
      expect(sniffImageKind(bytes([0xFF, 0xD8])), isNull);
      expect(sniffImageKind(bytes([0x89, 0x50, 0x4E, 0x47])), isNull);
      expect(sniffImageKind(bytes(text('RIFF....WAVE'))), isNull);
    });

    test('the extension of a kind is the one a package names it with', () {
      expect(FormImageKind.values.map((k) => k.extension), [
        'jpg',
        'png',
        'webp',
        'heic',
      ]);
    });
  });

  group('JPEG', () {
    test('a clean file comes back byte for byte', () {
      final clean = jpegClean();
      final report = cleanImage(clean)!;
      expect(report.bytes, clean);
      expect(report.removed.any, isFalse);
      expect(report.kind, FormImageKind.jpeg);
      expect(report.width, 640);
      expect(report.height, 480);
      expect(report.orientation, isNull);
    });

    test(
      'EXIF, XMP, comment, maker notes and Photoshop block go; the picture stays',
      () {
        final dirty = jpeg(
          exif: tiff(orientation: 1, gps: true),
          xmp: true,
          comment: true,
          photoshop: true,
          makerNote: true,
        );
        final report = cleanImage(dirty)!;
        expect(report.bytes, jpegClean(), reason: 'only the metadata is gone');
        expect(report.removed.exif, isTrue);
        expect(report.removed.gps, isTrue);
        expect(report.removed.xmp, isTrue);
        expect(report.removed.text, isTrue);
        expect(report.removed.other, isTrue);
      },
    );

    test('an EXIF without a GPS block reports no GPS', () {
      final report = cleanImage(jpeg(exif: tiff(orientation: 1)))!;
      expect(report.removed.exif, isTrue);
      expect(report.removed.gps, isFalse);
    });

    test('both byte orders of the EXIF are read', () {
      for (final little in [false, true]) {
        final report = cleanImage(
          jpeg(exif: tiff(orientation: 6, gps: true, little: little)),
        )!;
        expect(report.orientation, 6, reason: 'little=$little');
        expect(report.removed.gps, isTrue, reason: 'little=$little');
      }
    });

    test('the ICC profile, JFIF and Adobe segments are kept', () {
      final report = cleanImage(jpeg(adobe: true, exif: tiff(gps: true)))!;
      expect(report.bytes, jpegClean(adobe: true));
    });

    test('a file without JFIF or ICC loses nothing it never had', () {
      final report = cleanImage(jpeg(jfif: false, icc: false, comment: true))!;
      expect(report.bytes, jpegClean(jfif: false, icc: false));
    });

    test('everything after the end-of-image marker is cut off', () {
      final trailer = text('PK\x03\x04 a zip hidden behind the picture');
      final report = cleanImage(jpeg(trailer: trailer))!;
      expect(report.bytes, jpegClean());
      expect(report.removed.trailerBytes, trailer.length);
      expect(report.removed.any, isTrue);
    });

    test('the orientation stays, as an EXIF that holds nothing else', () {
      for (final o in [2, 3, 4, 5, 6, 7, 8]) {
        final report = cleanImage(jpeg(exif: tiff(orientation: o, gps: true)))!;
        expect(
          report.bytes,
          jpeg(exif: orientationOnly(o)),
          reason:
              'orientation $o: the same picture, the orientation and nothing else',
        );
        expect(report.orientation, o);
        // And it reads back: no GPS, the same orientation.
        final again = cleanImage(report.bytes)!;
        expect(again.orientation, o);
        expect(again.removed.gps, isFalse);
      }
    });

    test('orientation 1 is the default and is not written', () {
      final report = cleanImage(jpeg(exif: tiff(orientation: 1)))!;
      expect(report.bytes, jpegClean());
      expect(report.orientation, 1);
    });

    test('an orientation outside 1–8 is not trusted', () {
      final report = cleanImage(jpeg(exif: tiff(orientation: 9)))!;
      expect(report.orientation, isNull);
      expect(report.bytes, jpegClean());
    });

    test('orientations 5 to 8 swap width and height, 1 to 4 do not', () {
      for (var o = 1; o <= 8; o++) {
        final report = cleanImage(
          jpeg(width: 640, height: 480, exif: tiff(orientation: o)),
        )!;
        final swapped = o >= 5;
        expect(report.displayedWidth, swapped ? 480 : 640, reason: 'o=$o');
        expect(report.displayedHeight, swapped ? 640 : 480, reason: 'o=$o');
      }
    });

    test('the first EXIF decides when there are two', () {
      final report = cleanImage(
        jpeg(exif: tiff(orientation: 6), secondExif: tiff(orientation: 3)),
      )!;
      expect(report.orientation, 6);
    });

    test('the displayed width follows the orientation (§5.5)', () {
      final sideways = cleanImage(
        jpeg(width: 2400, height: 1800, exif: tiff(orientation: 6)),
      )!;
      expect(sideways.width, 2400);
      expect(sideways.displayedWidth, 1800);
      expect(sideways.displayedHeight, 2400);
      final upright = cleanImage(
        jpeg(width: 2400, height: 1800, exif: tiff(orientation: 3)),
      )!;
      expect(upright.displayedWidth, 2400);
      final none = cleanImage(jpeg(width: 2400, height: 1800))!;
      expect(none.displayedWidth, 2400);
    });

    test(
      'is idempotent: cleaning a cleaned file changes nothing and removes nothing',
      () {
        final once = cleanImage(
          jpeg(
            exif: tiff(orientation: 8, gps: true),
            xmp: true,
            trailer: [1, 2, 3],
          ),
        )!;
        final twice = cleanImage(once.bytes)!;
        expect(twice.bytes, once.bytes);
        expect(twice.removed.any, isFalse);
      },
    );

    test(
      'the scan data, with its stuffing and restart marker, is untouched',
      () {
        final report = cleanImage(jpeg(comment: true, trailer: [9, 9]))!;
        final scan = [1, 2, 0xFF, 0x00, 3, 0xFF, 0xD0, 4, 5, 0xFF, 0x00, 6];
        final s = report.bytes.toList();
        var found = false;
        for (var i = 0; i + scan.length <= s.length; i++) {
          if (List.generate(scan.length, (k) => s[i + k]).join(',') ==
              scan.join(',')) {
            found = true;
          }
        }
        expect(found, isTrue);
      },
    );
  });

  group('PNG', () {
    test('a clean file comes back byte for byte', () {
      final clean = png();
      final report = cleanImage(clean)!;
      expect(report.bytes, clean);
      expect(report.removed.any, isFalse);
      expect(report.width, 100);
      expect(report.height, 50);
    });

    test(
      'text, XMP, EXIF, the time and unknown ancillary chunks go; the profile stays',
      () {
        final report = cleanImage(
          png(
            textChunk: true,
            xmp: true,
            exif: tiff(orientation: 1, gps: true),
            time: true,
            unknownAncillary: true,
          ),
        )!;
        expect(
          report.bytes,
          png(),
          reason: 'IHDR, the profile and the data remain',
        );
        expect(report.removed.text, isTrue);
        expect(report.removed.xmp, isTrue);
        expect(report.removed.exif, isTrue);
        expect(report.removed.gps, isTrue);
        expect(report.removed.other, isTrue);
      },
    );

    test('every chunk a picture needs is kept', () {
      final file = png(keepers: true);
      final report = cleanImage(file)!;
      expect(report.bytes, file);
      expect(report.removed.any, isFalse);
    });

    test('everything after IEND is cut off', () {
      final trailer = text('PK a payload');
      final report = cleanImage(png(trailer: trailer))!;
      expect(report.bytes, png());
      expect(report.removed.trailerBytes, trailer.length);
    });

    test('the orientation stays as an eXIf chunk that holds nothing else', () {
      final report = cleanImage(png(exif: tiff(orientation: 6, gps: true)))!;
      expect(report.bytes, png(exif: orientationOnly(6)));
      expect(report.orientation, 6);
      expect(report.displayedWidth, 50);
      final again = cleanImage(report.bytes)!;
      expect(again.orientation, 6);
      expect(again.removed.gps, isFalse);
    });

    test('a wrong checksum is a refusal', () {
      expect(cleanImage(png(badCrc: true)), isNull);
    });

    test('an unknown critical chunk is a refusal; it cannot be dropped', () {
      expect(cleanImage(png(unknownCritical: true)), isNull);
    });

    test(
      'a file that does not start with IHDR, or has no IEND, is a refusal',
      () {
        final good = png().toList();
        // Cut the IEND chunk (12 bytes) off.
        expect(cleanImage(bytes(good.sublist(0, good.length - 12))), isNull);
        // Swap IHDR's type: the first chunk is then not a header.
        final broken = [...good];
        broken.setRange(12, 16, text('IDAT'));
        expect(cleanImage(bytes(broken)), isNull);
      },
    );

    test('is idempotent', () {
      final once = cleanImage(
        png(textChunk: true, exif: tiff(orientation: 3), trailer: [1]),
      )!;
      final twice = cleanImage(once.bytes)!;
      expect(twice.bytes, once.bytes);
      expect(twice.removed.any, isFalse);
    });
  });

  group('WebP', () {
    test('a clean extended file comes back byte for byte', () {
      final clean = webp();
      final report = cleanImage(clean)!;
      expect(report.bytes, clean);
      expect(report.removed.any, isFalse);
      expect(report.width, 300);
      expect(report.height, 200);
    });

    test(
      'EXIF and XMP go, the flags with them, and the size field stays right',
      () {
        final dirty = webp(
          iccp: true,
          exif: tiff(orientation: 1, gps: true),
          xmp: true,
        );
        final report = cleanImage(dirty)!;
        expect(report.bytes, webp(iccp: true));
        expect(report.removed.exif, isTrue);
        expect(report.removed.gps, isTrue);
        expect(report.removed.xmp, isTrue);
        final size = ByteData.sublistView(
          report.bytes,
        ).getUint32(4, Endian.little);
        expect(size, report.bytes.length - 8);
      },
    );

    test(
      'the size comes from the lossless, lossy and extended headers alike',
      () {
        expect(cleanImage(webp(width: 123, height: 77))!.width, 123);
        expect(cleanImage(webp(width: 123, height: 77))!.height, 77);
        final lossy = cleanImage(
          webp(width: 123, height: 77, extended: false, lossy: true),
        )!;
        expect(lossy.width, 123);
        expect(lossy.height, 77);
        final simpleLossless = cleanImage(
          webp(width: 640, height: 480, extended: false),
        )!;
        expect(simpleLossless.width, 640);
        expect(simpleLossless.height, 480);
      },
    );

    test('the scale bits of a lossy header are not part of the size', () {
      final report = cleanImage(
        webp(extended: false, lossy: true, width: 1000, height: 700, scale: 2),
      )!;
      expect(report.width, 1000);
      expect(report.height, 700);
    });

    test('the orientation stays as an EXIF chunk, with its flag', () {
      final report = cleanImage(webp(exif: tiff(orientation: 6, gps: true)))!;
      expect(report.bytes, webp(exif: orientationOnly(6)));
      expect(report.orientation, 6);
      expect(report.displayedWidth, 200);
    });

    test(
      'a simple file that has an orientation gets the extended header it needs',
      () {
        // An EXIF chunk is only allowed in the extended format; a simple file that
        // carries one anyway is rebuilt with a VP8X, so the orientation can stay.
        final simple = webp(
          extended: false,
          lossy: true,
          width: 300,
          height: 700,
          exif: tiff(orientation: 6, gps: true),
        );
        final report = cleanImage(simple)!;
        expect(
          report.bytes,
          webp(lossy: true, width: 300, height: 700, exif: orientationOnly(6)),
        );
        expect(report.removed.gps, isTrue);
      },
    );

    test('a simple file without metadata is returned as it is', () {
      final simple = webp(extended: false, width: 300, height: 200);
      expect(cleanImage(simple)!.bytes, simple);
    });

    test('bytes after the RIFF size are a trailer and are cut off', () {
      final trailer = text('PK zip');
      final report = cleanImage(webp(trailer: trailer))!;
      expect(report.bytes, webp());
      expect(report.removed.trailerBytes, trailer.length);
    });

    test(
      'a size beyond the file, or a chunk beyond the size, is a refusal',
      () {
        final good = webp().toList();
        final big = [...good]..setRange(4, 8, u32le(good.length + 100));
        expect(cleanImage(bytes(big)), isNull);
        expect(cleanImage(bytes(good.sublist(0, good.length - 5))), isNull);
      },
    );

    test('is idempotent', () {
      final once = cleanImage(
        webp(exif: tiff(orientation: 8, gps: true), xmp: true, trailer: [7]),
      )!;
      final twice = cleanImage(once.bytes)!;
      expect(twice.bytes, once.bytes);
      expect(twice.removed.any, isFalse);
    });
  });

  group('the EXIF that a cleaning writes is not "data removed"', () {
    test('an EXIF with only the orientation is kept and not reported', () {
      for (final file in [
        jpeg(exif: orientationOnly(6)),
        png(exif: orientationOnly(6)),
        webp(exif: orientationOnly(6)),
      ]) {
        final report = cleanImage(file)!;
        expect(report.orientation, 6);
        expect(report.removed.any, isFalse, reason: '${report.kind}');
        expect(report.bytes, file, reason: '${report.kind}');
      }
    });

    test('an EXIF with the orientation and anything else is reported', () {
      // The Make tag alone is enough to make it more than an orientation.
      for (final file in [
        jpeg(exif: tiff(orientation: 6)),
        png(exif: tiff(orientation: 6)),
        webp(exif: tiff(orientation: 6)),
      ]) {
        expect(cleanImage(file)!.removed.exif, isTrue);
      }
    });
  });

  group('HEIC — recognised, never opened (D4)', () {
    test('the bytes come back untouched and the report says unverified', () {
      final file = heic();
      final report = cleanImage(file)!;
      expect(report.bytes, file);
      expect(report.kind, FormImageKind.heic);
      expect(report.unverified, isTrue);
      expect(report.width, isNull);
      expect(report.displayedWidth, isNull);
      expect(report.removed.any, isFalse);
    });

    test('the other kinds are verified', () {
      expect(cleanImage(jpeg())!.unverified, isFalse);
    });
  });

  group('a file that is none of them', () {
    test('is null: text, a script, an empty file', () {
      expect(cleanImage(bytes(text('<script>alert(1)</script>'))), isNull);
      expect(cleanImage(Uint8List(0)), isNull);
      expect(
        cleanImage(bytes(text('not an image at all, just words'))),
        isNull,
      );
    });

    test(
      'a JPEG without frame header, without end marker or with a bad length is null',
      () {
        final good = jpeg().toList();
        // No EOI.
        expect(cleanImage(bytes(good.sublist(0, good.length - 2))), isNull);
        // A segment length that runs past the end.
        final longer = [...good]..setRange(2 + 18, 2 + 20, [0xFF, 0xFF]);
        expect(cleanImage(bytes(longer)), isNull);
        // A segment whose length field is smaller than the field itself.
        expect(
          cleanImage(
            bytes([0xFF, 0xD8, 0xFF, 0xE0, 0x00, 0x01, 1, 2, 3, 0xFF, 0xD9]),
          ),
          isNull,
        );
        // Only SOI and EOI.
        expect(cleanImage(bytes([0xFF, 0xD8, 0xFF, 0xD9])), isNull);
        // Junk where a marker belongs.
        expect(
          cleanImage(bytes([0xFF, 0xD8, 0xFF, 0x12, 0x34, 1, 2, 3])),
          isNull,
        );
      },
    );
  });

  group('robustness', () {
    test('never throws, whatever is cut off or flipped', () {
      final random = Random(20261003);
      final samples = [
        jpeg(exif: tiff(orientation: 6, gps: true), xmp: true, trailer: [1, 2]),
        png(textChunk: true, exif: tiff(orientation: 3), trailer: [1]),
        webp(exif: tiff(orientation: 8), xmp: true, trailer: [1]),
        heic(),
      ];
      for (final sample in samples) {
        // Every truncation.
        for (var n = 0; n < sample.length; n++) {
          cleanImage(Uint8List.sublistView(sample, 0, n));
        }
        // Random single-byte changes.
        for (var round = 0; round < 400; round++) {
          final copy = Uint8List.fromList(sample);
          copy[random.nextInt(copy.length)] = random.nextInt(256);
          final report = cleanImage(copy);
          if (report != null) {
            // Whatever comes out must itself be a clean, readable file.
            final again = cleanImage(report.bytes);
            expect(again, isNotNull, reason: 'a cleaned file reads again');
            expect(
              again!.removed.any,
              isFalse,
              reason: 'and has nothing left to remove',
            );
          }
        }
      }
    });
  });

  group('FormImageRemoved', () {
    test('any is true for each kind of thing and for a trailer', () {
      expect(const FormImageRemoved().any, isFalse);
      expect(const FormImageRemoved(gps: true).any, isTrue);
      expect(const FormImageRemoved(exif: true).any, isTrue);
      expect(const FormImageRemoved(xmp: true).any, isTrue);
      expect(const FormImageRemoved(text: true).any, isTrue);
      expect(const FormImageRemoved(other: true).any, isTrue);
      expect(const FormImageRemoved(trailerBytes: 1).any, isTrue);
    });

    test('merge combines the flags and adds the trailers', () {
      final merged = const FormImageRemoved(
        gps: true,
        trailerBytes: 2,
      ).merge(const FormImageRemoved(xmp: true, trailerBytes: 3));
      expect(merged.gps, isTrue);
      expect(merged.xmp, isTrue);
      expect(merged.exif, isFalse);
      expect(merged.trailerBytes, 5);
    });
  });
}
