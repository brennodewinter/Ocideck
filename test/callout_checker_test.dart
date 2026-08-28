// Tests for the callout checker — §2.6 binding table, invalid geometry,
// duplicates, orphans, missing anchor.
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/models/deck.dart';
import 'package:ocideck/models/image_callout.dart';
import 'package:ocideck/models/slide.dart';
import 'package:ocideck/models/slide_quality.dart';
import 'package:ocideck/services/slide_quality_analyzer.dart';

void main() {
  final analyzer = const SlideQualityAnalyzer();

  Slide calloutSlide({
    required String anchor,
    required List<ImageCallout> callouts,
    List<String> bullets = const [],
  }) => Slide.create(
    SlideType.bullets,
  ).copyWith(anchor: anchor, bullets: bullets, callouts: callouts);

  group('callout checker — §2.6 binding table', () {
    test('one-to-one: bullet ends with (A), one entry A → no finding', () {
      final deck = Deck(
        title: 'test',
        slides: [
          calloutSlide(
            anchor: 's1',
            bullets: ['controller board (A)'],
            callouts: const [
              ImageCallout(
                reference: 'A',
                targets: [CalloutPoint(0.4, 0.2)],
                description: 'the board',
              ),
            ],
          ),
        ],
      );
      final result = analyzer.analyze(deck);
      final calloutIssues = result.issues.where(
        (i) => i.category == SlideQualityCategory.callout,
      );
      expect(calloutIssues, isEmpty);
    });

    test('no entry X exists → ordinary prose, no finding', () {
      // A bullet ends with (A) but there are no callouts at all.
      final deck = Deck(
        title: 'test',
        slides: [
          calloutSlide(
            anchor: 's1',
            bullets: ['some prose (A)'],
            callouts: const [],
          ),
        ],
      );
      final result = analyzer.analyze(deck);
      final calloutIssues = result.issues.where(
        (i) => i.category == SlideQualityCategory.callout,
      );
      expect(calloutIssues, isEmpty);
    });

    test('two bullets end with (X) → duplicate finding', () {
      final deck = Deck(
        title: 'test',
        slides: [
          calloutSlide(
            anchor: 's1',
            bullets: ['first bullet (A)', 'second bullet (A)'],
            callouts: const [
              ImageCallout(reference: 'A', targets: [CalloutPoint(0.4, 0.2)]),
            ],
          ),
        ],
      );
      final result = analyzer.analyze(deck);
      final dupes = result.issues.where(
        (i) => i.kind == SlideQualityIssueKind.calloutDuplicateReference,
      );
      // The checker reports a duplicate for the second occurrence of A.
      expect(dupes, isNotEmpty);
    });

    test('entry X exists, no bullet carries it → orphan finding', () {
      final deck = Deck(
        title: 'test',
        slides: [
          calloutSlide(
            anchor: 's1',
            bullets: ['unrelated text'],
            callouts: const [
              ImageCallout(reference: 'A', targets: [CalloutPoint(0.4, 0.2)]),
            ],
          ),
        ],
      );
      final result = analyzer.analyze(deck);
      final orphans = result.issues.where(
        (i) => i.kind == SlideQualityIssueKind.calloutOrphanReference,
      );
      expect(orphans, isNotEmpty);
    });

    test('bullet has (A), no entry A → orphan finding', () {
      final deck = Deck(
        title: 'test',
        slides: [
          calloutSlide(
            anchor: 's1',
            bullets: ['text with (A)'],
            callouts: const [
              ImageCallout(reference: 'B', targets: [CalloutPoint(0.4, 0.2)]),
            ],
          ),
        ],
      );
      final result = analyzer.analyze(deck);
      final orphans = result.issues.where(
        (i) => i.kind == SlideQualityIssueKind.calloutOrphanReference,
      );
      // (A) in text without an entry → orphan.
      expect(orphans.any((i) => i.args['ref'] == '(A)'), isTrue);
    });
  });

  group('callout checker — invalid geometry', () {
    test('point outside [0,1] → invalid geometry finding', () {
      final deck = Deck(
        title: 'test',
        slides: [
          calloutSlide(
            anchor: 's1',
            bullets: ['text (A)'],
            callouts: const [
              ImageCallout(reference: 'A', targets: [CalloutPoint(1.5, 0.5)]),
            ],
          ),
        ],
      );
      final result = analyzer.analyze(deck);
      expect(
        result.issues.where(
          (i) => i.kind == SlideQualityIssueKind.calloutInvalidGeometry,
        ),
        isNotEmpty,
      );
    });

    test('region with negative width → invalid geometry finding', () {
      final deck = Deck(
        title: 'test',
        slides: [
          calloutSlide(
            anchor: 's1',
            bullets: ['text (A)'],
            callouts: const [
              ImageCallout(
                reference: 'A',
                targets: [CalloutRegion(0.5, 0.5, -0.1, 0.1)],
              ),
            ],
          ),
        ],
      );
      final result = analyzer.analyze(deck);
      expect(
        result.issues.where(
          (i) => i.kind == SlideQualityIssueKind.calloutInvalidGeometry,
        ),
        isNotEmpty,
      );
    });

    test('valid geometry → no invalid finding', () {
      final deck = Deck(
        title: 'test',
        slides: [
          calloutSlide(
            anchor: 's1',
            bullets: ['text (A)'],
            callouts: const [
              ImageCallout(reference: 'A', targets: [CalloutPoint(0.4, 0.2)]),
            ],
          ),
        ],
      );
      final result = analyzer.analyze(deck);
      expect(
        result.issues.where(
          (i) => i.kind == SlideQualityIssueKind.calloutInvalidGeometry,
        ),
        isEmpty,
      );
    });
  });

  group('callout checker — missing anchor', () {
    test('slide with callouts but no anchor → missing anchor finding', () {
      final deck = Deck(
        title: 'test',
        slides: [
          calloutSlide(
            anchor: '',
            bullets: ['text (A)'],
            callouts: const [
              ImageCallout(reference: 'A', targets: [CalloutPoint(0.4, 0.2)]),
            ],
          ),
        ],
      );
      final result = analyzer.analyze(deck);
      expect(
        result.issues.where(
          (i) => i.kind == SlideQualityIssueKind.calloutMissingAnchor,
        ),
        isNotEmpty,
      );
    });

    test('slide with callouts and anchor → no missing anchor finding', () {
      final deck = Deck(
        title: 'test',
        slides: [
          calloutSlide(
            anchor: 's1',
            bullets: ['text (A)'],
            callouts: const [
              ImageCallout(reference: 'A', targets: [CalloutPoint(0.4, 0.2)]),
            ],
          ),
        ],
      );
      final result = analyzer.analyze(deck);
      expect(
        result.issues.where(
          (i) => i.kind == SlideQualityIssueKind.calloutMissingAnchor,
        ),
        isEmpty,
      );
    });
  });

  group('callout checker — duplicate reference', () {
    test('same letter twice in callouts → duplicate finding', () {
      final deck = Deck(
        title: 'test',
        slides: [
          calloutSlide(
            anchor: 's1',
            bullets: ['text (A)'],
            callouts: const [
              ImageCallout(reference: 'A', targets: [CalloutPoint(0.4, 0.2)]),
              ImageCallout(reference: 'A', targets: [CalloutPoint(0.6, 0.3)]),
            ],
          ),
        ],
      );
      final result = analyzer.analyze(deck);
      expect(
        result.issues.where(
          (i) => i.kind == SlideQualityIssueKind.calloutDuplicateReference,
        ),
        isNotEmpty,
      );
    });
  });
}
