// Tests for callout collaboration — SetSlideField round-trip for callouts,
// calloutPresentation and calloutReveal, plus InsertSlide with callouts.
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/collab/collab_codec.dart';
import 'package:ocideck/collab/collab_deck_diff.dart';
import 'package:ocideck/collab/deck_op.dart';
import 'package:ocideck/models/deck.dart';
import 'package:ocideck/models/image_callout.dart';
import 'package:ocideck/models/slide.dart';

void main() {
  group('callout collaboration — SetSlideField round-trip', () {
    test('callouts encode and decode back to the same value', () {
      final slide = Slide.create(SlideType.bullets).copyWith(
        anchor: 's1',
        callouts: const [
          ImageCallout(
            reference: 'A',
            targets: [CalloutPoint(0.402, 0.251)],
            description: 'the controller board',
          ),
          ImageCallout(
            reference: 'B',
            targets: [CalloutRegion(0.5, 0.2, 0.18, 0.22)],
            description: 'the print head',
          ),
        ],
      );
      final op = SetSlideField(
        version: 1,
        authorId: 'alice',
        slideId: slide.id,
        field: SlideField.callouts,
        value: slide.callouts,
      );
      final json = deckOpToJson(op);
      final decoded = deckOpFromJson(json) as SetSlideField;
      expect(decoded.field, SlideField.callouts);
      expect(decoded.value, isA<List<ImageCallout>>());
      final decodedCallouts = decoded.value as List<ImageCallout>;
      expect(decodedCallouts, hasLength(2));
      expect(decodedCallouts[0].reference, 'A');
      expect(decodedCallouts[0].targets.single, isA<CalloutPoint>());
      expect(decodedCallouts[1].reference, 'B');
      expect(decodedCallouts[1].targets.single, isA<CalloutRegion>());
    });

    test('calloutPresentation encodes and decodes', () {
      final op = SetSlideField(
        version: 1,
        authorId: 'alice',
        slideId: 's1',
        field: SlideField.calloutPresentation,
        value: CalloutPresentation.region,
      );
      final decoded = deckOpFromJson(deckOpToJson(op)) as SetSlideField;
      expect(decoded.value, CalloutPresentation.region);
    });

    test('calloutReveal encodes and decodes', () {
      final op = SetSlideField(
        version: 1,
        authorId: 'alice',
        slideId: 's1',
        field: SlideField.calloutReveal,
        value: BulletRevealMode.steps,
      );
      final decoded = deckOpFromJson(deckOpToJson(op)) as SetSlideField;
      expect(decoded.value, BulletRevealMode.steps);
    });

    test('applyOp sets callouts on the slide', () {
      final slide = Slide.create(SlideType.bullets).copyWith(anchor: 's1');
      final deck = Deck(title: 'test', slides: [slide]);
      final op = SetSlideField(
        version: 1,
        authorId: 'alice',
        slideId: slide.id,
        field: SlideField.callouts,
        value: const [
          ImageCallout(reference: 'A', targets: [CalloutPoint(0.4, 0.2)]),
        ],
      );
      final updated = applyOp(deck, op);
      expect(updated.slides.first.callouts, hasLength(1));
      expect(updated.slides.first.callouts.first.reference, 'A');
    });

    test('InsertSlide carries callouts through the wire', () {
      final slide = Slide.create(SlideType.bullets).copyWith(
        anchor: 's1',
        callouts: const [
          ImageCallout(
            reference: 'A',
            targets: [CalloutPoint(0.4, 0.2)],
            description: 'desc',
          ),
        ],
        calloutPresentation: CalloutPresentation.region,
        calloutReveal: BulletRevealMode.steps,
      );
      final op = InsertSlide(
        version: 1,
        authorId: 'alice',
        index: 0,
        slide: slide,
      );
      final decoded = deckOpFromJson(deckOpToJson(op)) as InsertSlide;
      expect(decoded.slide.callouts, hasLength(1));
      expect(decoded.slide.callouts.first.reference, 'A');
      expect(decoded.slide.calloutPresentation, CalloutPresentation.region);
      expect(decoded.slide.calloutReveal, BulletRevealMode.steps);
    });

    test('diff detects callout changes', () {
      final slide = Slide.create(SlideType.bullets).copyWith(
        anchor: 's1',
        callouts: const [
          ImageCallout(reference: 'A', targets: [CalloutPoint(0.4, 0.2)]),
        ],
      );
      final deckA = Deck(title: 'test', slides: [slide]);
      final deckB = Deck(
        title: 'test',
        slides: [
          slide.copyWith(
            callouts: const [
              ImageCallout(reference: 'A', targets: [CalloutPoint(0.5, 0.3)]),
            ],
          ),
        ],
      );
      final ops = deckDiffToOps(deckA, deckB, authorId: 'alice');
      final calloutOps = ops.whereType<SetSlideField>().where(
        (o) => o.field == SlideField.callouts,
      );
      expect(calloutOps, isNotEmpty);
    });
  });
}
