// Collaboration robustness for callouts (IMAGE_CALLOUTS.md §9 acceptance gate).
//
// Two scenarios that the round-trip test doesn't cover:
// 1. Reconnect: a slide with callouts survives a full encode/decode cycle
//    (simulating a client disconnecting and reconnecting with the full deck
//    state).
// 2. Incompatible client: an older client that doesn't know callout fields
//    sends a slide JSON without them. The newer client must not crash and
//    must apply sensible defaults (empty callouts, pin, all).
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/collab/collab_codec.dart';
import 'package:ocideck/collab/collab_deck_diff.dart';
import 'package:ocideck/collab/deck_op.dart';
import 'package:ocideck/models/deck.dart';
import 'package:ocideck/models/image_callout.dart';
import 'package:ocideck/models/slide.dart';

void main() {
  group('callout collaboration robustness — reconnect', () {
    test('slide with callouts survives full encode/decode cycle', () {
      final slide = Slide.create(SlideType.bulletsImage).copyWith(
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
        calloutPresentation: CalloutPresentation.region,
        calloutReveal: BulletRevealMode.steps,
      );
      // Simulate reconnect: encode the slide to JSON, decode it back.
      final json = slideToJson(slide);
      final decoded = slideFromJson(json);
      expect(decoded.callouts, hasLength(2));
      expect(decoded.callouts[0].reference, 'A');
      expect(decoded.callouts[0].targets.single, isA<CalloutPoint>());
      expect(decoded.callouts[1].reference, 'B');
      expect(decoded.callouts[1].targets.single, isA<CalloutRegion>());
      expect(decoded.calloutPresentation, CalloutPresentation.region);
      expect(decoded.calloutReveal, BulletRevealMode.steps);
    });

    test('callout data survives multiple reconnect cycles', () {
      var slide = Slide.create(SlideType.bulletsImage).copyWith(
        anchor: 's1',
        callouts: const [
          ImageCallout(
            reference: 'A',
            targets: [CalloutPoint(0.4, 0.2)],
            description: 'desc',
          ),
        ],
      );
      // Three reconnect cycles.
      for (var i = 0; i < 3; i++) {
        slide = slideFromJson(slideToJson(slide));
      }
      expect(slide.callouts, hasLength(1));
      expect(slide.callouts.first.reference, 'A');
      expect(slide.callouts.first.description, 'desc');
    });

    test('SetSlideField for callouts survives encode/decode', () {
      final slide = Slide.create(SlideType.bulletsImage).copyWith(anchor: 's1');
      final op = SetSlideField(
        version: 1,
        authorId: 'alice',
        slideId: slide.id,
        field: SlideField.callouts,
        value: const [
          ImageCallout(
            reference: 'A',
            targets: [CalloutPoint(0.4, 0.2)],
            description: 'reconnect test',
          ),
        ],
      );
      final json = deckOpToJson(op);
      final decoded = deckOpFromJson(json) as SetSlideField;
      final decodedCallouts = decoded.value as List<ImageCallout>;
      expect(decodedCallouts, hasLength(1));
      expect(decodedCallouts.first.reference, 'A');
      expect(decodedCallouts.first.description, 'reconnect test');
    });
  });

  group('callout collaboration robustness — incompatible client', () {
    test('slide JSON without callout fields defaults to empty/pin/all', () {
      // An older client sends a slide JSON without callout fields. Generate
      // a full JSON from a real slide, then strip the callout fields.
      final slide = Slide.create(
        SlideType.bulletsImage,
      ).copyWith(anchor: 's1', title: 'Old slide');
      final json = slideToJson(slide);
      // Remove callout fields — simulating an older client.
      json.remove('callouts');
      json.remove('calloutPresentation');
      json.remove('calloutReveal');
      final decoded = slideFromJson(json);
      expect(decoded.callouts, isEmpty);
      expect(decoded.calloutPresentation, CalloutPresentation.pin);
      expect(decoded.calloutReveal, BulletRevealMode.all);
    });

    test('older client diff does not emit callout ops', () {
      // An older client has a slide without callouts. A newer client adds
      // callouts. The diff should emit a SetSlideField for callouts.
      final oldSlide = Slide.create(SlideType.bulletsImage).copyWith(
        anchor: 's1',
        // No callouts — old client.
      );
      final newSlide = oldSlide.copyWith(
        callouts: const [
          ImageCallout(reference: 'A', targets: [CalloutPoint(0.4, 0.2)]),
        ],
      );
      final deckA = Deck(title: 't', slides: [oldSlide]);
      final deckB = Deck(title: 't', slides: [newSlide]);
      final ops = deckDiffToOps(deckA, deckB, authorId: 'alice');
      final calloutOps = ops.whereType<SetSlideField>().where(
        (o) => o.field == SlideField.callouts,
      );
      expect(calloutOps, isNotEmpty);
    });

    test('callout field with unknown enum value fails closed', () {
      // A future or incompatible client sends an unknown calloutPresentation
      // value. The codec must not crash — it should fail with a clear error
      // (fail-closed), not silently default.
      final slide = Slide.create(SlideType.bulletsImage).copyWith(
        anchor: 's1',
        callouts: const [
          ImageCallout(reference: 'A', targets: [CalloutPoint(0.4, 0.2)]),
        ],
      );
      final json = slideToJson(slide);
      // Corrupt the calloutPresentation to an unknown value.
      json['calloutPresentation'] = 'hologram';
      expect(
        () => slideFromJson(json),
        throwsA(isA<FormatException>()),
        reason: 'Unknown enum value must fail closed, not silently default.',
      );
    });

    test('callout with unknown target type fails closed', () {
      final slide = Slide.create(SlideType.bulletsImage).copyWith(
        anchor: 's1',
        callouts: const [
          ImageCallout(reference: 'A', targets: [CalloutPoint(0.4, 0.2)]),
        ],
      );
      final json = slideToJson(slide);
      // Corrupt the target type to an unknown value.
      final calloutsList = json['callouts'] as List;
      final firstCallout = calloutsList[0] as Map<String, Object?>;
      final targetsList = firstCallout['targets'] as List;
      (targetsList[0] as Map<String, Object?>)['type'] = 'circle';
      expect(
        () => slideFromJson(json),
        throwsA(isA<FormatException>()),
        reason: 'Unknown target type must fail closed.',
      );
    });

    test('empty callouts list survives reconnect', () {
      final slide = Slide.create(
        SlideType.bulletsImage,
      ).copyWith(anchor: 's1', callouts: const []);
      final decoded = slideFromJson(slideToJson(slide));
      expect(decoded.callouts, isEmpty);
    });
  });
}
