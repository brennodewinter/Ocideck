import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/models/image_callout.dart';
import 'package:ocideck/models/presentation_step_plan.dart';
import 'package:ocideck/models/slide.dart';
import 'package:ocideck/models/timeline.dart';

/// Minimal test-slide builder: only the fields the plan inspects.
Slide testSlide({
  required SlideType type,
  List<String> bullets = const [],
  TimelineReveal? timelineReveal,
  List<ImageCallout> callouts = const [],
  BulletRevealMode calloutReveal = BulletRevealMode.all,
}) => Slide(
  id: 'test',
  type: type,
  bullets: bullets,
  timelineReveal: timelineReveal ?? TimelineReveal.onEnter,
  callouts: callouts,
  calloutReveal: calloutReveal,
);

void main() {
  group('PresentationStepPlan.forSlide', () {
    test('NoStepPlan for a plain bullets slide', () {
      final slide = testSlide(
        type: SlideType.bullets,
        bullets: ['one', 'two', 'three'],
      );
      final plan = PresentationStepPlan.forSlide(slide);
      expect(plan, isA<NoStepPlan>());
      expect(plan.hasSteps, isFalse);
      expect(plan.remainingSteps, 0);
    });

    test('NoStepPlan for a timeline in onEnter mode', () {
      final slide = testSlide(
        type: SlideType.timeline,
        bullets: ['2019 :: A :: desc', '2020 :: B :: desc'],
        timelineReveal: TimelineReveal.onEnter,
      );
      final plan = PresentationStepPlan.forSlide(slide);
      expect(plan, isA<NoStepPlan>());
    });

    test('TimelineStepPlan for a timeline in steps mode', () {
      final slide = testSlide(
        type: SlideType.timeline,
        bullets: ['2019 :: A', '2020 :: B', '2021 :: C'],
        timelineReveal: TimelineReveal.steps,
      );
      final plan = PresentationStepPlan.forSlide(slide);
      expect(plan, isA<TimelineStepPlan>());
      final tp = plan as TimelineStepPlan;
      expect(tp.eventCount, 3);
      expect(tp.remainingSteps, 2); // 3 events, first shown at step 0
      // Step 0 = first event, step 2 = all three.
      expect(tp.revealedEventCount(0), 1);
      expect(tp.revealedEventCount(1), 2);
      expect(tp.revealedEventCount(2), 3);
      expect(tp.revealedEventCount(99), 3); // clamped
    });

    test('TimelineStepPlan with zero events', () {
      final slide = testSlide(
        type: SlideType.timeline,
        bullets: [],
        timelineReveal: TimelineReveal.steps,
      );
      final plan = PresentationStepPlan.forSlide(slide);
      expect(plan, isA<TimelineStepPlan>());
      expect(plan.remainingSteps, 0);
      expect((plan as TimelineStepPlan).revealedEventCount(0), 0);
    });

    test('NoStepPlan for bulletsImage without callout reveal', () {
      final slide = testSlide(
        type: SlideType.bulletsImage,
        bullets: ['one (A)', 'two (B)'],
        callouts: [
          ImageCallout(reference: 'A', targets: [const CalloutPoint(0.5, 0.5)]),
        ],
        calloutReveal: BulletRevealMode.all,
      );
      final plan = PresentationStepPlan.forSlide(slide);
      expect(plan, isA<NoStepPlan>());
    });

    test('NoStepPlan for bulletsImage with steps but no callouts', () {
      final slide = testSlide(
        type: SlideType.bulletsImage,
        bullets: ['one', 'two'],
        calloutReveal: BulletRevealMode.steps,
        callouts: [],
      );
      final plan = PresentationStepPlan.forSlide(slide);
      expect(plan, isA<NoStepPlan>());
    });

    test('CalloutRevealStepPlan for bulletsImage with steps and callouts', () {
      final slide = testSlide(
        type: SlideType.bulletsImage,
        bullets: ['controller board (A)', 'print head (B)', 'no callout'],
        callouts: [
          ImageCallout(
            reference: 'A',
            targets: [const CalloutPoint(0.4, 0.25)],
          ),
          ImageCallout(reference: 'B', targets: [const CalloutPoint(0.6, 0.5)]),
        ],
        calloutReveal: BulletRevealMode.steps,
      );
      final plan = PresentationStepPlan.forSlide(slide);
      expect(plan, isA<CalloutRevealStepPlan>());
      final cp = plan as CalloutRevealStepPlan;
      expect(cp.bullets.length, 3);
      expect(cp.bulletReferences, ['A', 'B', '']);
      expect(cp.calloutReferences, {'A', 'B'});
      expect(cp.remainingSteps, 3); // 3 bullets to reveal
      // Step 0 = title + image only, no bullets.
      expect(cp.revealedBulletCount(0), 0);
      expect(cp.revealedReferences(0), <String>{});
      // Step 1 = first bullet + its callout targets.
      expect(cp.revealedBulletCount(1), 1);
      expect(cp.revealedReferences(1), {'A'});
      // Step 2 = second bullet + its callout targets.
      expect(cp.revealedBulletCount(2), 2);
      expect(cp.revealedReferences(2), {'A', 'B'});
      // Step 3 = all bullets.
      expect(cp.revealedBulletCount(3), 3);
      expect(cp.revealedReferences(3), {'A', 'B'});
    });

    test('CalloutRevealStepPlan: bullet without callout still steps', () {
      final slide = testSlide(
        type: SlideType.bulletsImage,
        bullets: ['no callout', 'with callout (A)'],
        callouts: [
          ImageCallout(reference: 'A', targets: [const CalloutPoint(0.5, 0.5)]),
        ],
        calloutReveal: BulletRevealMode.steps,
      );
      final plan = PresentationStepPlan.forSlide(slide);
      expect(plan, isA<CalloutRevealStepPlan>());
      final cp = plan as CalloutRevealStepPlan;
      expect(cp.remainingSteps, 2);
      // Step 1: first bullet visible, no callout yet.
      expect(cp.revealedReferences(1), <String>{});
      // Step 2: second bullet + callout A.
      expect(cp.revealedReferences(2), {'A'});
    });

    test('CalloutRevealStepPlan: empty bullets produce no steps', () {
      final slide = testSlide(
        type: SlideType.bulletsImage,
        bullets: [],
        callouts: [
          ImageCallout(reference: 'A', targets: [const CalloutPoint(0.5, 0.5)]),
        ],
        calloutReveal: BulletRevealMode.steps,
      );
      final plan = PresentationStepPlan.forSlide(slide);
      expect(plan, isA<CalloutRevealStepPlan>());
      expect(plan.remainingSteps, 0);
    });
  });

  group('PresentationStepPlan equality', () {
    test('TimelineStepPlan equality', () {
      final a = TimelineStepPlan(eventCount: 3);
      final b = TimelineStepPlan(eventCount: 3);
      final c = TimelineStepPlan(eventCount: 4);
      expect(a == b, isTrue);
      expect(a == c, isFalse);
    });

    test('CalloutRevealStepPlan equality', () {
      final a = CalloutRevealStepPlan(
        bullets: ['one (A)'],
        bulletReferences: ['A'],
        calloutReferences: {'A'},
      );
      final b = CalloutRevealStepPlan(
        bullets: ['one (A)'],
        bulletReferences: ['A'],
        calloutReferences: {'A'},
      );
      expect(a == b, isTrue);
    });
  });
}
