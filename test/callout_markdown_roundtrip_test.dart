// Markdown round-trip test for callouts — parse a deck with an
// `ocideck_callouts` front-matter block, serialise it back, and verify the
// block survives losslessly (§2.5 nested merge).
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/models/image_callout.dart';
import 'package:ocideck/services/markdown_service.dart';

void main() {
  final svc = MarkdownService();

  test('parse and re-serialise a deck with callouts preserves the block', () {
    const markdown = '''---
marp: true
ocideck_format: 1
theme: default
ocideck_callouts:
  slide-1:
    A: point 0.402 0.251 | the controller board
    B: region 0.500 0.200 0.180 0.220 | the print head
---

# Test

<!-- ocideck_slide_anchor: slide-1 -->

- controller board with display (A)
- printing head (B)
''';
    final deck = svc.parseDeck(markdown);
    expect(deck, isNotNull, reason: 'parseDeck returned null');
    expect(deck!.slides, hasLength(1));
    final slide = deck.slides.first;
    expect(slide.callouts, hasLength(2));
    expect(slide.callouts[0].reference, 'A');
    expect(slide.callouts[0].targets.single, isA<CalloutPoint>());
    expect(slide.callouts[1].reference, 'B');
    expect(slide.callouts[1].targets.single, isA<CalloutRegion>());

    // Re-serialise and verify the callout block is present.
    final out = svc.generateDeck(deck);
    expect(out, contains('ocideck_callouts:'));
    expect(out, contains('A: point 0.402 0.251'));
    expect(out, contains('B: region 0.500 0.200 0.180 0.220'));
  });

  test('format version becomes 2 when callouts are present', () {
    const markdown = '''---
marp: true
ocideck_format: 1
theme: default
---

# Test

<!-- ocideck_slide_anchor: s1 -->

- item (A)
''';
    final deck = svc.parseDeck(markdown)!;
    // Add a callout to the first slide.
    final slide = deck.slides.first.copyWith(
      anchor: 's1',
      callouts: const [
        ImageCallout(reference: 'A', targets: [CalloutPoint(0.4, 0.2)]),
      ],
    );
    final deckWithCallout = deck.copyWith(slides: [slide]);
    final out = svc.generateDeck(deckWithCallout);
    expect(out, contains('ocideck_format: 2'));
  });

  test('format version stays 1 when no callouts are present', () {
    const markdown = '''---
marp: true
ocideck_format: 1
theme: default
---

# Test
''';
    final deck = svc.parseDeck(markdown)!;
    final out = svc.generateDeck(deck);
    expect(out, contains('ocideck_format: 1'));
  });

  test(
    'callout block with comments and unknown tokens survives round-trip',
    () {
      const markdown = '''---
marp: true
ocideck_format: 1
theme: default
ocideck_callouts:
  slide-1:
    A: point 0.402 0.251 | the controller board
    # a comment
    B: point 0.6 0.4 | "quoted desc"
    C: point 0.4 | malformed
    D: circle 0.5 0.5 0.1 | future token
---

# Test

<!-- ocideck_slide_anchor: slide-1 -->

- controller board (A)
- second item (B)
''';
      final deck = svc.parseDeck(markdown)!;
      final out = svc.generateDeck(deck);

      // The comment is preserved.
      expect(out, contains('# a comment'));
      // The quoted description is preserved verbatim.
      expect(out, contains('"quoted desc"'));
      // The malformed entry is preserved.
      expect(out, contains('C: point 0.4 | malformed'));
      // The future token is preserved.
      expect(out, contains('D: circle 0.5 0.5 0.1 | future token'));
    },
  );

  test('deck without callouts has no callout block', () {
    const markdown = '''---
marp: true
ocideck_format: 1
theme: default
---

# Test

- item
''';
    final deck = svc.parseDeck(markdown)!;
    final out = svc.generateDeck(deck);
    expect(out, isNot(contains('ocideck_callouts:')));
  });
}
