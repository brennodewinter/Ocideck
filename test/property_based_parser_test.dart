// Property-based testing voor de invoerparsers van OciDeck.
//
// In plaats van specifieke inputs te testen ("geef deze markdown, verwacht
// deze slides"), genereert deze test random mutaties van geldige bestanden
// en beweert dat elke mutatie óf graceful faalt óf een geldig resultaat
// oplevert — nooit een crash, nooit een hang.
//
// Dit is de structurele investering die de handmatige security-research-
// rondes overbodig maakt: een fuzzer vindt automatisch de gaten die een
// mens niet verzint (#1356).
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/models/settings.dart';
import 'package:ocideck/services/file_service.dart';
import 'package:ocideck/services/image_service.dart';
import 'package:ocideck/services/markdown_service.dart';
import 'package:ocideck/utils/json_depth_guard.dart';

void main() {
  // Een vaste seed maakt de test reproduceerbaar — bij een falende run is
  // de exacte input terug te halen.
  final rng = Random(42);

  FileService makeService() => FileService(
    MarkdownService(),
    ImageService(),
    () => const ThemeProfile(),
  );

  group('property-based: markdown parser', () {
    // Een geldig deck als basis voor mutaties.
    const validDeck =
        '---\nmarp: true\ntheme: default\n---\n\n'
        '# Title\n\n- Bullet 1\n- Bullet 2\n';

    test(
      'elke byte-mutatie van een geldig deck faalt graceful of parseert',
      () {
        for (var i = 0; i < 200; i++) {
          final mutated = _mutate(validDeck, rng);
          expect(
            () => MarkdownService().parseDeck(mutated),
            returnsNormally,
            reason: 'Mutatie #$i: $mutated',
          );
        }
      },
    );

    test('elke truncatie van een geldig deck failt graceful of parseert', () {
      for (var i = 0; i < validDeck.length; i += 7) {
        final truncated = validDeck.substring(0, i);
        expect(
          () => MarkdownService().parseDeck(truncated),
          returnsNormally,
          reason: 'Truncatie op positie $i',
        );
      }
    });
  });

  group('property-based: openDeckFromContent', () {
    const validDeck =
        '---\nmarp: true\ntheme: default\n---\n\n'
        '# Title\n\n- Bullet 1\n- Bullet 2\n';

    test('elke mutatie van een geldig deck faalt graceful of opent', () {
      final service = makeService();
      for (var i = 0; i < 100; i++) {
        final mutated = _mutate(validDeck, rng);
        expect(
          () => service.openDeckFromContent(mutated),
          returnsNormally,
          reason: 'Mutatie #$i: $mutated',
        );
      }
    });
  });

  group('property-based: JSON depth guard', () {
    test('random geneste JSON faalt graceful', () {
      for (var i = 0; i < 100; i++) {
        final depth = rng.nextInt(500);
        final json = '${'[' * depth}1${']' * depth}';
        // jsonDecodeGuarded gooit FormatException boven de dieptelimiet —
        // dat is graceful. Een StackOverflowError is dat niet.
        expect(
          () => jsonDecodeGuarded(json),
          anyOf(returnsNormally, throwsA(isA<FormatException>())),
          reason: 'Diepte $depth',
        );
      }
    });

    test('random JSON met strings die brackets bevatten faalt niet', () {
      for (var i = 0; i < 50; i++) {
        final bracketCount = rng.nextInt(100);
        final value = '${'[' * bracketCount}x${']' * bracketCount}';
        final json = '{"key": "$value"}';
        expect(
          () => jsonDecodeGuarded(json),
          returnsNormally,
          reason: 'Brackets in string: $bracketCount',
        );
      }
    });
  });
}

/// Muteer een string op een willekeurige manier: byte-flip, truncatie,
/// duplicatie, of invoegen van willekeurige bytes.
String _mutate(String input, Random rng) {
  final bytes = Uint8List.fromList(input.codeUnits);
  final mutation = rng.nextInt(4);
  switch (mutation) {
    case 0: // byte-flip
      if (bytes.isEmpty) return input;
      final pos = rng.nextInt(bytes.length);
      bytes[pos] = rng.nextInt(256);
      return String.fromCharCodes(bytes);
    case 1: // truncatie
      if (bytes.isEmpty) return input;
      final cut = rng.nextInt(bytes.length);
      return String.fromCharCodes(bytes.sublist(0, cut));
    case 2: // duplicatie van een segment
      if (bytes.length < 2) return input;
      final start = rng.nextInt(bytes.length - 1);
      final end = start + 1 + rng.nextInt(bytes.length - start);
      final segment = bytes.sublist(start, end);
      final insertAt = rng.nextInt(bytes.length);
      return String.fromCharCodes([
        ...bytes.sublist(0, insertAt),
        ...segment,
        ...bytes.sublist(insertAt),
      ]);
    case 3: // invoegen van willekeurige bytes
      final insertAt = rng.nextInt(bytes.length + 1);
      final count = 1 + rng.nextInt(20);
      final random = Uint8List(count);
      for (var i = 0; i < count; i++) {
        random[i] = rng.nextInt(256);
      }
      return String.fromCharCodes([
        ...bytes.sublist(0, insertAt),
        ...random,
        ...bytes.sublist(insertAt),
      ]);
    default:
      return input;
  }
}
