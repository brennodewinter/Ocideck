// Documentation & compatibility matrix test for callouts (IMAGE_CALLOUTS.md §9).
//
// Verifies that the documentation matches the actual behavior:
// 1. FILE_FORMAT.md mentions ocideck_callouts and version 2.
// 2. USER_GUIDE.md describes the three presentation modes.
// 3. USER_GUIDE.nl.md has a callouts section.
// 4. SOURCE_MAP.md lists the callout source files.
// 5. CHANGELOG.md mentions the callout issues.
// 6. The documented limits in IMAGE_CALLOUTS.md §8 match the code.
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/models/image_callout.dart';

void main() {
  final repoRoot = Directory.current.path;

  group('callout documentation — FILE_FORMAT.md', () {
    final content = File('$repoRoot/docs/FILE_FORMAT.md').readAsStringSync();

    test('mentions ocideck_callouts front-matter key', () {
      expect(content, contains('ocideck_callouts'));
    });

    test('documents version 2 for callouts', () {
      expect(content, contains('Version 2'));
      expect(content, contains('callouts'));
    });
  });

  group('callout documentation — USER_GUIDE.md', () {
    final content = File('$repoRoot/docs/USER_GUIDE.md').readAsStringSync();

    test('has an image callouts section', () {
      expect(content, contains('Image callouts'));
    });

    test('documents three presentation modes', () {
      expect(content, contains('Pins'));
      expect(content, contains('Gebieden'));
      expect(content, contains('Pijlen'));
    });

    test('documents the reference letter system (A–Z)', () {
      expect(content, contains('A–Z'));
      expect(content, contains('(A)'));
    });

    test('documents the reveal mode (Stap-voor-stap)', () {
      expect(content, contains('Stap-voor-stap'));
    });

    test('documents LaTeX/Beamer arrow degradation', () {
      expect(content, contains('degrades arrows'));
    });
  });

  group('callout documentation — USER_GUIDE.nl.md', () {
    final content = File('$repoRoot/docs/USER_GUIDE.nl.md').readAsStringSync();

    test('has an afbeeldingsverwijzingen section', () {
      expect(content, contains('Afbeeldingsverwijzingen'));
    });

    test('documents three presentation modes in Dutch', () {
      expect(content, contains('Pins'));
      expect(content, contains('Gebieden'));
      expect(content, contains('Pijlen'));
    });

    test('documents the reference letter system', () {
      expect(content, contains('A–Z'));
      expect(content, contains('(A)'));
    });

    test('documents Stap-voor-stap reveal mode', () {
      expect(content, contains('Stap-voor-stap'));
    });
  });

  group('callout documentation — SOURCE_MAP.md', () {
    final content = File('$repoRoot/docs/SOURCE_MAP.md').readAsStringSync();

    test('lists image_callout.dart model', () {
      expect(content, contains('image_callout.dart'));
    });

    test('lists callout_codec.dart', () {
      expect(content, contains('callout_codec.dart'));
    });

    test('lists callout_overlay.dart widget', () {
      expect(content, contains('callout_overlay.dart'));
    });

    test('lists callout_editor.dart', () {
      expect(content, contains('callout_editor.dart'));
    });

    test('lists image_viewport_geometry.dart', () {
      expect(content, contains('image_viewport_geometry.dart'));
    });
  });

  group('callout documentation — CHANGELOG.md', () {
    final content = File('$repoRoot/CHANGELOG.md').readAsStringSync();

    test('mentions image callouts', () {
      expect(content, contains('Image callouts'));
    });

    test('references the implementation issues', () {
      expect(content, contains('#1824'));
      expect(content, contains('#1826'));
    });
  });

  group('callout documentation — IMAGE_CALLOUTS.md §8 limits match code', () {
    final content = File(
      '$repoRoot/docs/design/IMAGE_CALLOUTS.md',
    ).readAsStringSync();

    test('documents 26 references', () {
      expect(content, contains('26'));
      expect(content, contains('References per slide'));
    });

    test('documents 8 targets per reference', () {
      expect(content, contains('Targets per reference'));
      expect(content, contains('8'));
    });

    test('documents minimum region 0.02', () {
      expect(content, contains('0.02'));
    });

    test('documents coordinates 0..1 with three decimals', () {
      expect(content, contains('0..1'));
      expect(content, contains('three decimals'));
    });

    test('CalloutPoint isValid matches documented range', () {
      expect(const CalloutPoint(0, 0).isValid, isTrue);
      expect(const CalloutPoint(1, 1).isValid, isTrue);
      expect(const CalloutPoint(1.002, 0.5).isValid, isFalse);
    });

    test('CalloutRegion isValid matches documented range', () {
      // The model's isValid checks geometry range and positivity, not the
      // §8 minimum of 0.02 — that's the checker's job. Verify the model
      // matches the documented coordinate range.
      expect(const CalloutRegion(0.5, 0.5, 0.02, 0.02).isValid, isTrue);
      expect(const CalloutRegion(0.0, 0.0, 1.0, 1.0).isValid, isTrue);
      expect(const CalloutRegion(0.5, 0.5, -0.1, 0.1).isValid, isFalse);
    });
  });
}
