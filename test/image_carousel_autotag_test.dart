import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/widgets/dialogs/image_carousel_picker.dart';

/// Dekking voor de auto-tagronde (#2148): elke overgeslagen afbeelding krijgt
/// een getelde reden, en bytes die niet gelezen konden worden bereiken de
/// tag-callback (de AI-grens) helemaal niet.
void main() {
  test(
    'runAutoTag telt per reden en roept de AI niet voor onleesbaren',
    () async {
      var tagCalls = 0;
      final saved = <String, String>{};

      final result = await runAutoTag(
        ['/a.png', '/b.heic', '/c.png', '/d.png', '/e.png'],
        readBytes: (path) async =>
            // /c.png is weg of onleesbaar — geen bytes voor de tagger.
            path == '/c.png' ? null : Uint8List.fromList([path.codeUnitAt(1)]),
        tag: (bytes) async {
          tagCalls++;
          return switch (bytes[0]) {
            0x61 => (tags: 'zon, zee', imageSent: true), // /a.png
            0x62 => (tags: '', imageSent: false), // /b.heic: niet decodeerbaar
            0x64 => (tags: '', imageSent: true), // /d.png: model gaf niets
            _ => throw StateError('server weg'), // /e.png: aanroep faalde
          };
        },
        save: (path, tags) async => saved[path] = tags,
      );

      expect(result.tagged, ['/a.png']);
      expect(saved, {'/a.png': 'zon, zee'});
      expect(result.skippedTotal, 4);
      expect(result.skipped[AutoTagSkip.unreadable], 1);
      expect(result.skipped[AutoTagSkip.notDecodable], 1);
      expect(result.skipped[AutoTagSkip.emptyResponse], 1);
      expect(result.skipped[AutoTagSkip.failed], 1);
      // Vier aanroepen, niet vijf: wie geen bytes had bereikte de AI niet.
      expect(tagCalls, 4);
    },
  );

  test('runAutoTag stopt netjes als de ronde wordt afgebroken', () async {
    final saved = <String, String>{};
    var seen = 0;
    final result = await runAutoTag(
      ['/a.png', '/b.png', '/c.png'],
      readBytes: (path) async => Uint8List.fromList([1]),
      tag: (bytes) async => (tags: 'x', imageSent: true),
      save: (path, tags) async {
        seen++;
        saved[path] = tags;
      },
      isCancelled: () => seen > 0, // na de eerste stopt de ronde
    );

    expect(result.tagged, ['/a.png']);
    expect(saved, hasLength(1));
  });

  test('autoTagSummary noemt aantallen én redenen (#2148)', () {
    final result = AutoTagRunResult()
      ..tagged.addAll(['/a.png'])
      ..skipped[AutoTagSkip.notDecodable] = 2
      ..skipped[AutoTagSkip.failed] = 1;

    final text = autoTagSummary((s) => s, result);

    expect(text, contains('1 afbeeldingen getagd door AI.'));
    expect(text, contains('3 overgeslagen'));
    expect(text, contains('2 niet decodeerbaar'));
    expect(text, contains('1 mislukt'));
  });

  test('autoTagSummary zonder skips is alleen het getagde aantal', () {
    final result = AutoTagRunResult()..tagged.addAll(['/a.png', '/b.png']);
    expect(autoTagSummary((s) => s, result), '2 afbeeldingen getagd door AI.');
  });
}
