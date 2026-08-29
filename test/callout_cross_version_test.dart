// Cross-version preservation fixture for callouts (IMAGE_CALLOUTS.md §9 gate).
//
// A file written by a FUTURE version of the format — with a higher
// `ocideck_format`, unknown geometry tokens, unknown entry keys, unknown
// anchor-level directives, and unknown top-level keys in the callout block —
// is opened and saved by the current version. Everything the current version
// doesn't understand must survive byte-for-byte (§2.4, §2.5).
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/models/image_callout.dart';
import 'package:ocideck/services/markdown_service.dart';

void main() {
  final svc = MarkdownService();

  /// A fixture from a future version (ocideck_format: 3) with:
  /// - An unknown geometry token (`circle`)
  /// - An unknown entry key (lowercase `x`)
  /// - An unknown anchor-level directive (`color: red`)
  /// - An unknown top-level key in the callout block (`future_meta: value`)
  /// - A comment, a blank line, and a quoted description
  /// - An orphan anchor block (anchor not in the deck)
  const futureFixture = '''---
marp: true
ocideck_format: 3
theme: default
ocideck_callouts:
  slide-1:
    A: point 0.402 0.251 | the controller board
    B: circle 0.5 0.5 0.1 | future geometry token
    x: point 0.3 0.3 | future lowercase key
    color: red
    # a comment from the future
    C: point 0.6 0.4 | "quoted desc"
  future-slide:
    Z: ellipse 0.1 0.1 0.2 0.2 | orphan from future version
future_meta: value
---

# Test

<!-- ocideck_slide_anchor: slide-1 -->

- controller board (A)
- second item (B)
- third item (C)
''';

  test('future version fixture is parsed without error', () {
    final deck = svc.parseDeck(futureFixture);
    expect(deck, isNotNull);
    expect(deck!.slides, hasLength(1));
    // The current version parses A and C (known geometry), skips B (circle).
    expect(deck.slides.first.callouts, hasLength(2));
    expect(deck.slides.first.callouts[0].reference, 'A');
    expect(deck.slides.first.callouts[1].reference, 'C');
  });

  test('unknown geometry token is preserved byte-for-byte', () {
    final deck = svc.parseDeck(futureFixture)!;
    final out = svc.generateDeck(deck);
    // The circle token must survive verbatim.
    expect(out, contains('B: circle 0.5 0.5 0.1 | future geometry token'));
  });

  test('unknown entry key is preserved byte-for-byte', () {
    final deck = svc.parseDeck(futureFixture)!;
    final out = svc.generateDeck(deck);
    expect(out, contains('x: point 0.3 0.3 | future lowercase key'));
  });

  test('unknown anchor-level directive is preserved', () {
    final deck = svc.parseDeck(futureFixture)!;
    final out = svc.generateDeck(deck);
    expect(out, contains('color: red'));
  });

  test('comment from future version is preserved', () {
    final deck = svc.parseDeck(futureFixture)!;
    final out = svc.generateDeck(deck);
    expect(out, contains('# a comment from the future'));
  });

  test('quoted description is preserved verbatim', () {
    final deck = svc.parseDeck(futureFixture)!;
    final out = svc.generateDeck(deck);
    expect(out, contains('"quoted desc"'));
  });

  test('orphan anchor block from future version is preserved', () {
    final deck = svc.parseDeck(futureFixture)!;
    final out = svc.generateDeck(deck);
    // The future-slide anchor block is not in the deck's slides, but it
    // must be preserved verbatim (§2.4 — orphans are kept, not removed).
    expect(out, contains('future-slide:'));
    expect(
      out,
      contains('Z: ellipse 0.1 0.1 0.2 0.2 | orphan from future version'),
    );
  });

  test('unknown top-level key in callout block is preserved', () {
    final deck = svc.parseDeck(futureFixture)!;
    final out = svc.generateDeck(deck);
    // `future_meta: value` is an unknown front-matter key — not owned by
    // OciDeck, so it stays where it was.
    expect(out, contains('future_meta: value'));
  });

  test('format version is not downgraded', () {
    // §2.5: a reader never downgrades the format version. The file said 3,
    // so the output must still say 3.
    final deck = svc.parseDeck(futureFixture)!;
    final out = svc.generateDeck(deck);
    expect(out, contains('ocideck_format: 3'));
  });

  test('idempotent: saving twice produces the same output', () {
    final deck1 = svc.parseDeck(futureFixture)!;
    final out1 = svc.generateDeck(deck1);
    final deck2 = svc.parseDeck(out1)!;
    final out2 = svc.generateDeck(deck2);
    expect(out2, out1);
  });

  test('editing a known entry does not disturb future-version content', () {
    // Edit entry A (move it slightly). Only A should change; everything
    // from the future version must survive untouched.
    final deck = svc.parseDeck(futureFixture)!;
    final slide = deck.slides.first.copyWith(
      callouts: [
        // Move A from (0.402, 0.251) to (0.5, 0.3).
        ImageCallout(
          reference: 'A',
          targets: const [CalloutPoint(0.5, 0.3)],
          description: 'the controller board',
        ),
        deck.slides.first.callouts[1],
      ],
    );
    final editedDeck = deck.copyWith(slides: [slide]);
    final out = svc.generateDeck(editedDeck);
    // A was edited → canonical line with new coords.
    expect(out, contains('A: point 0.500 0.300'));
    // Everything else from the future version is preserved.
    expect(out, contains('B: circle 0.5 0.5 0.1 | future geometry token'));
    expect(out, contains('x: point 0.3 0.3 | future lowercase key'));
    expect(out, contains('color: red'));
    expect(out, contains('# a comment from the future'));
    expect(out, contains('"quoted desc"'));
    expect(out, contains('future-slide:'));
    expect(
      out,
      contains('Z: ellipse 0.1 0.1 0.2 0.2 | orphan from future version'),
    );
    expect(out, contains('future_meta: value'));
    expect(out, contains('ocideck_format: 3'));
  });
}
