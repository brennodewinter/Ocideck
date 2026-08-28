// Tests for the callout codec — parser, lossless writer, nested merge (§2.5).
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/models/image_callout.dart';
import 'package:ocideck/services/callout_codec.dart';

void main() {
  group('callout codec — parser', () {
    test('absent block returns empty result', () {
      final result = parseCalloutBlock(['marp: true', 'theme: default']);
      expect(result.present, isFalse);
      expect(result.blocks, isEmpty);
    });

    test('parses a single anchor with one point callout', () {
      final result = parseCalloutBlock([
        'marp: true',
        'ocideck_callouts:',
        '  slide-1:',
        '    A: point 0.402 0.251 | the controller board',
        'theme: default',
      ]);
      expect(result.present, isTrue);
      expect(result.blocks, hasLength(1));
      final blk = result.blocks.single;
      expect(blk.anchor, 'slide-1');
      expect(blk.typed, isNotNull);
      expect(blk.typed!.callouts, hasLength(1));
      final c = blk.typed!.callouts.single;
      expect(c.reference, 'A');
      expect(c.targets.single, isA<CalloutPoint>());
      expect((c.targets.single as CalloutPoint).x, closeTo(0.402, 1e-9));
      expect((c.targets.single as CalloutPoint).y, closeTo(0.251, 1e-9));
      expect(c.description, 'the controller board');
    });

    test('parses a region callout', () {
      final result = parseCalloutBlock([
        'ocideck_callouts:',
        '  s1:',
        '    B: region 0.500 0.200 0.180 0.220 | the print head',
      ]);
      final c = result.blocks.single.typed!.callouts.single;
      expect(c.reference, 'B');
      expect(c.targets.single, isA<CalloutRegion>());
      final r = c.targets.single as CalloutRegion;
      expect(r.x, closeTo(0.5, 1e-9));
      expect(r.w, closeTo(0.18, 1e-9));
    });

    test('parses multiple targets separated by semicolons', () {
      final result = parseCalloutBlock([
        'ocideck_callouts:',
        '  s1:',
        '    A: point 0.4 0.2; point 0.7 0.3 | two spots',
      ]);
      final c = result.blocks.single.typed!.callouts.single;
      expect(c.targets, hasLength(2));
      expect(c.targets.every((t) => t is CalloutPoint), isTrue);
    });

    test('parses mode and reveal directives', () {
      final result = parseCalloutBlock([
        'ocideck_callouts:',
        '  s1:',
        '    mode: region',
        '    reveal: steps',
        '    A: point 0.4 0.2 | desc',
      ]);
      final data = result.blocks.single.typed!;
      expect(data.presentation, CalloutPresentation.region);
      expect(data.reveal, BulletRevealMode.steps);
    });

    test('entry without description', () {
      final result = parseCalloutBlock([
        'ocideck_callouts:',
        '  s1:',
        '    A: point 0.4 0.2',
      ]);
      expect(result.blocks.single.typed!.callouts.single.description, '');
    });

    test(
      'malformed geometry is preserved in raw lines, typed is null for that target',
      () {
        final result = parseCalloutBlock([
          'ocideck_callouts:',
          '  s1:',
          '    A: point 0.4 | missing y',
        ]);
        // The entry line is preserved, but the callout has no valid targets.
        final blk = result.blocks.single;
        expect(blk.rawLines, contains('    A: point 0.4 | missing y'));
        // _parseCalloutEntry returns null when no targets parse.
        expect(blk.typed!.callouts, isEmpty);
      },
    );

    test('unknown geometry token is preserved, not parsed', () {
      final result = parseCalloutBlock([
        'ocideck_callouts:',
        '  s1:',
        '    A: circle 0.5 0.5 0.1 | future token',
      ]);
      final blk = result.blocks.single;
      expect(
        blk.rawLines,
        contains('    A: circle 0.5 0.5 0.1 | future token'),
      );
      expect(blk.typed!.callouts, isEmpty);
    });

    test('comment lines are preserved in raw lines', () {
      final result = parseCalloutBlock([
        'ocideck_callouts:',
        '  s1:',
        '    # this is a comment',
        '    A: point 0.4 0.2 | desc',
      ]);
      final blk = result.blocks.single;
      expect(
        blk.rawLines.any((l) => l.contains('# this is a comment')),
        isTrue,
      );
    });

    test('multiple anchor blocks', () {
      final result = parseCalloutBlock([
        'ocideck_callouts:',
        '  slide-1:',
        '    A: point 0.4 0.2 | first',
        '  slide-2:',
        '    B: region 0.5 0.2 0.1 0.1 | second',
      ]);
      expect(result.blocks, hasLength(2));
      expect(result.blocks[0].anchor, 'slide-1');
      expect(result.blocks[1].anchor, 'slide-2');
    });
  });

  group('callout codec — lossless writer (§2.5 nested merge)', () {
    test('null when no slide has callouts', () {
      final out = serializeCalloutBlock(
        slidesWithCallouts: const [],
        original: null,
      );
      expect(out, isNull);
    });

    test('canonical output for a new block', () {
      final out = serializeCalloutBlock(
        slidesWithCallouts: [
          (
            anchor: 's1',
            callouts: [
              const ImageCallout(
                reference: 'A',
                targets: [CalloutPoint(0.402, 0.251)],
                description: 'the controller board',
              ),
            ],
            presentation: CalloutPresentation.pin,
            reveal: BulletRevealMode.all,
          ),
        ],
        original: null,
      );
      expect(out, isNotNull);
      expect(out!.first, 'ocideck_callouts:');
      expect(out[1], '  s1:');
      // mode and reveal are default, so not emitted.
      expect(out.any((l) => l.contains('mode:')), isFalse);
      expect(out.any((l) => l.contains('reveal:')), isFalse);
      expect(out[2], contains('A: point 0.402 0.251'));
      expect(out[2], contains('| the controller board'));
    });

    test('emits mode and reveal when non-default', () {
      final out = serializeCalloutBlock(
        slidesWithCallouts: [
          (
            anchor: 's1',
            callouts: [
              const ImageCallout(
                reference: 'A',
                targets: [CalloutPoint(0.4, 0.2)],
              ),
            ],
            presentation: CalloutPresentation.region,
            reveal: BulletRevealMode.steps,
          ),
        ],
        original: null,
      );
      expect(out!.any((l) => l.trimLeft() == 'mode: region'), isTrue);
      expect(out.any((l) => l.trimLeft() == 'reveal: steps'), isTrue);
    });

    test('idempotent: writing twice produces the same output', () {
      final slidesWithCallouts = [
        (
          anchor: 's1',
          callouts: [
            const ImageCallout(
              reference: 'A',
              targets: [CalloutPoint(0.402, 0.251)],
              description: 'desc',
            ),
          ],
          presentation: CalloutPresentation.pin,
          reveal: BulletRevealMode.all,
        ),
      ];
      final first = serializeCalloutBlock(
        slidesWithCallouts: slidesWithCallouts,
        original: null,
      )!;
      // Parse the first output and use it as the "original" for the second pass.
      final parsed = parseCalloutBlock(first);
      final second = serializeCalloutBlock(
        slidesWithCallouts: slidesWithCallouts,
        original: parsed,
      )!;
      expect(second, first);
    });

    test('new-reader edit: only the edited entry differs', () {
      // A block with an unknown child, a comment, a quoted description, a
      // malformed known entry, and a future token. Edit one entry. Only that
      // entry should differ.
      final originalLines = [
        'ocideck_callouts:',
        '  s1:',
        '    A: point 0.402 0.251 | the controller board',
        '    B: point 0.6 0.4 | "quoted desc"',
        '    # a comment',
        '    C: point 0.4 | malformed',
        '    D: circle 0.5 0.5 0.1 | future token',
      ];
      final original = parseCalloutBlock(originalLines);

      // Edit only entry A — move it slightly.
      final out = serializeCalloutBlock(
        slidesWithCallouts: [
          (
            anchor: 's1',
            callouts: [
              const ImageCallout(
                reference: 'A',
                targets: [CalloutPoint(0.5, 0.3)],
                description: 'the controller board',
              ),
              // B is kept as typed (matches original after quote stripping).
              const ImageCallout(
                reference: 'B',
                targets: [CalloutPoint(0.6, 0.4)],
                description: 'quoted desc',
              ),
            ],
            presentation: CalloutPresentation.pin,
            reveal: BulletRevealMode.all,
          ),
        ],
        original: original,
      )!;

      // A was edited → canonical line with new coords.
      expect(out.any((l) => l.contains('A: point 0.500 0.300')), isTrue);
      // B was not edited → raw line preserved verbatim (with original quoting).
      expect(
        out.any((l) => l.contains('B: point 0.6 0.4 | "quoted desc"')),
        isTrue,
      );
      // Comment preserved.
      expect(out.any((l) => l.contains('# a comment')), isTrue);
      // Malformed entry C preserved verbatim (not in typed model, kept as raw).
      expect(out.any((l) => l.contains('C: point 0.4 | malformed')), isTrue);
      // Future token D preserved verbatim.
      expect(
        out.any((l) => l.contains('D: circle 0.5 0.5 0.1 | future token')),
        isTrue,
      );
    });

    test('orphan anchor block preserved when not in typed model', () {
      final originalLines = [
        'ocideck_callouts:',
        '  s1:',
        '    A: point 0.4 0.2 | desc',
        '  orphan-slide:',
        '    B: point 0.6 0.4 | orphan',
      ];
      final original = parseCalloutBlock(originalLines);

      // Only s1 is in the typed model; orphan-slide should be preserved.
      final out = serializeCalloutBlock(
        slidesWithCallouts: [
          (
            anchor: 's1',
            callouts: [
              const ImageCallout(
                reference: 'A',
                targets: [CalloutPoint(0.4, 0.2)],
                description: 'desc',
              ),
            ],
            presentation: CalloutPresentation.pin,
            reveal: BulletRevealMode.all,
          ),
        ],
        original: original,
      )!;

      // The orphan anchor block is preserved verbatim.
      expect(out.any((l) => l.trimLeft() == 'orphan-slide:'), isTrue);
      expect(out.any((l) => l.contains('B: point 0.6 0.4 | orphan')), isTrue);
    });
  });

  group('callout codec — YAML scalars', () {
    test('description with special YAML chars is parsed as-is', () {
      final result = parseCalloutBlock([
        'ocideck_callouts:',
        '  s1:',
        r'    A: point 0.4 0.2 | the: board #1',
      ]);
      // The description is everything after ' | ', parsed as a plain scalar.
      expect(
        result.blocks.single.typed!.callouts.single.description,
        contains('the: board #1'),
      );
    });

    test('description with semicolons is kept whole', () {
      final result = parseCalloutBlock([
        'ocideck_callouts:',
        '  s1:',
        '    A: point 0.4 0.2 | a; b; c',
      ]);
      // The pipe splits geometry from description; semicolons in the description
      // are not geometry separators.
      expect(
        result.blocks.single.typed!.callouts.single.description,
        'a; b; c',
      );
    });
  });

  group('callout codec — §8 limits', () {
    test('26 references (A–Z) parse', () {
      final lines = [
        'ocideck_callouts:',
        '  s1:',
        for (var i = 0; i < 26; i++)
          '    ${String.fromCharCode(65 + i)}: point 0.${i.toString().padLeft(3, '0')} 0.100 | ref $i',
      ];
      final result = parseCalloutBlock(lines);
      expect(result.blocks.single.typed!.callouts, hasLength(26));
    });

    test('8 targets per reference parse', () {
      final geos = List.generate(
        8,
        (i) => 'point 0.${i.toString().padLeft(3, '0')} 0.5',
      ).join('; ');
      final result = parseCalloutBlock([
        'ocideck_callouts:',
        '  s1:',
        '    A: $geos | eight targets',
      ]);
      expect(result.blocks.single.typed!.callouts.single.targets, hasLength(8));
    });

    test('region at minimum size (0.02) is valid', () {
      const target = CalloutRegion(0.5, 0.5, 0.02, 0.02);
      expect(target.isValid, isTrue);
    });

    test('region with w > 1 is invalid', () {
      const target = CalloutRegion(0.0, 0.0, 1.5, 0.1);
      expect(target.isValid, isFalse);
    });

    test('point at exactly 0 and 1 is valid', () {
      expect(const CalloutPoint(0, 0).isValid, isTrue);
      expect(const CalloutPoint(1, 1).isValid, isTrue);
    });

    test('point outside [0,1] is invalid', () {
      expect(const CalloutPoint(1.5, 0.5).isValid, isFalse);
      expect(const CalloutPoint(-0.1, 0.5).isValid, isFalse);
    });
  });
}
