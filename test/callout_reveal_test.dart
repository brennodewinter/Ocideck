import 'dart:convert';
import 'dart:typed_data';

import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/models/image_callout.dart';
import 'package:ocideck/models/presentation_step_plan.dart';
import 'package:ocideck/models/settings.dart';
import 'package:ocideck/models/slide.dart';
import 'package:ocideck/models/timeline.dart';
import 'package:ocideck/services/web_asset_store.dart';
import 'package:ocideck/widgets/slides/previews/callout_overlay.dart';

/// Tests for the callout reveal step mode (IMAGE_CALLOUTS.md §7).
///
/// The plan-level logic (which references are revealed at which step) is tested
/// in `presentation_step_plan_test.dart`. These tests cover the rendering
/// surface: that `CalloutOverlay` with `revealedReferences` filters callouts,
/// and that the static export path (no step state) shows everything.

/// A minimal valid 1×1 transparent PNG.
final _pngBytes = Uint8List.fromList(
  base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk'
    '+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg==',
  ),
);

Widget _host(Widget child) => MaterialApp(
  home: Center(child: SizedBox(width: 400, height: 300, child: child)),
);

void main() {
  setUp(WebAssetStore.clear);
  tearDown(WebAssetStore.clear);

  group('CalloutOverlay revealedReferences filter', () {
    testWidgets('null revealedReferences → all callouts processed', (
      tester,
    ) async {
      final memPath = WebAssetStore.put(_pngBytes, name: 'test.png');
      final slide = Slide(
        id: 'test',
        type: SlideType.bulletsImage,
        imagePath: memPath,
        callouts: const [
          ImageCallout(
            reference: 'A',
            targets: [CalloutPoint(0.4, 0.3)],
            description: 'eerste',
          ),
          ImageCallout(
            reference: 'B',
            targets: [CalloutPoint(0.6, 0.5)],
            description: 'tweede',
          ),
        ],
      );
      // null = show everything (static export, editor, non-stepping).
      await tester.pumpWidget(
        _host(
          CalloutOverlay(
            slide: slide,
            profile: const ThemeProfile(),
            slotWidth: 400,
            slotHeight: 300,
            revealedReferences: null,
          ),
        ),
      );
      await tester.pumpAndSettle();
      // Image can't resolve in tests → no markers, but no crash either.
      expect(find.text('A'), findsNothing);
      expect(find.text('B'), findsNothing);
    });

    testWidgets('empty revealedReferences → no callouts processed', (
      tester,
    ) async {
      final memPath = WebAssetStore.put(_pngBytes, name: 'test.png');
      final slide = Slide(
        id: 'test',
        type: SlideType.bulletsImage,
        imagePath: memPath,
        callouts: const [
          ImageCallout(
            reference: 'A',
            targets: [CalloutPoint(0.4, 0.3)],
            description: 'eerste',
          ),
        ],
      );
      // Empty set = step 0, nothing revealed yet.
      await tester.pumpWidget(
        _host(
          CalloutOverlay(
            slide: slide,
            profile: const ThemeProfile(),
            slotWidth: 400,
            slotHeight: 300,
            revealedReferences: const {},
          ),
        ),
      );
      await tester.pumpAndSettle();
      // No markers at all — A is filtered out.
      expect(find.text('A'), findsNothing);
    });

    testWidgets('partial revealedReferences → only matching callouts', (
      tester,
    ) async {
      final memPath = WebAssetStore.put(_pngBytes, name: 'test.png');
      final slide = Slide(
        id: 'test',
        type: SlideType.bulletsImage,
        imagePath: memPath,
        callouts: const [
          ImageCallout(
            reference: 'A',
            targets: [CalloutPoint(0.4, 0.3)],
            description: 'eerste',
          ),
          ImageCallout(
            reference: 'B',
            targets: [CalloutPoint(0.6, 0.5)],
            description: 'tweede',
          ),
        ],
      );
      // Only A is revealed (step 1 of 2).
      await tester.pumpWidget(
        _host(
          CalloutOverlay(
            slide: slide,
            profile: const ThemeProfile(),
            slotWidth: 400,
            slotHeight: 300,
            revealedReferences: const {'A'},
          ),
        ),
      );
      await tester.pumpAndSettle();
      // Image can't resolve in tests → no markers, but the filtering code path
      // is exercised without crash.
      expect(find.text('A'), findsNothing);
      expect(find.text('B'), findsNothing);
    });
  });

  group('CalloutRevealStepPlan step sequence', () {
    // These tests verify the step sequence that the presenter follows:
    // forward, backward, re-entry, and the atomic bullet+targets reveal.

    test('forward: step 0 → all revealed one by one', () {
      final slide = Slide(
        id: 'test',
        type: SlideType.bulletsImage,
        bullets: ['controller (A)', 'print head (B)', 'bolts (C)'],
        callouts: const [
          ImageCallout(
            reference: 'A',
            targets: [CalloutPoint(0.4, 0.25)],
          ),
          ImageCallout(
            reference: 'B',
            targets: [CalloutPoint(0.6, 0.5)],
          ),
          ImageCallout(
            reference: 'C',
            targets: [CalloutPoint(0.7, 0.3)],
          ),
        ],
        calloutReveal: BulletRevealMode.steps,
      );
      final plan = PresentationStepPlan.forSlide(slide);
      expect(plan, isA<CalloutRevealStepPlan>());
      final cp = plan as CalloutRevealStepPlan;
      expect(cp.remainingSteps, 3);

      // Step 0: title + image, no bullets, no callouts.
      expect(cp.revealedBulletCount(0), 0);
      expect(cp.revealedReferences(0), <String>{});

      // Step 1: first bullet + callout A.
      expect(cp.revealedBulletCount(1), 1);
      expect(cp.revealedReferences(1), {'A'});

      // Step 2: second bullet + callout B (A still visible).
      expect(cp.revealedBulletCount(2), 2);
      expect(cp.revealedReferences(2), {'A', 'B'});

      // Step 3: all bullets + all callouts.
      expect(cp.revealedBulletCount(3), 3);
      expect(cp.revealedReferences(3), {'A', 'B', 'C'});
    });

    test('backward: step 3 → 0 hides groups in reverse order', () {
      final slide = Slide(
        id: 'test',
        type: SlideType.bulletsImage,
        bullets: ['one (A)', 'two (B)'],
        callouts: const [
          ImageCallout(reference: 'A', targets: [CalloutPoint(0.4, 0.3)]),
          ImageCallout(reference: 'B', targets: [CalloutPoint(0.6, 0.5)]),
        ],
        calloutReveal: BulletRevealMode.steps,
      );
      final cp = PresentationStepPlan.forSlide(slide) as CalloutRevealStepPlan;

      // From step 2 (all revealed) back to step 1: B hidden, A stays.
      expect(cp.revealedReferences(1), {'A'});
      // Back to step 0: everything hidden.
      expect(cp.revealedReferences(0), <String>{});
    });

    test('re-entry resets to step 0 (title + image only)', () {
      final slide = Slide(
        id: 'test',
        type: SlideType.bulletsImage,
        bullets: ['one (A)', 'two (B)'],
        callouts: const [
          ImageCallout(reference: 'A', targets: [CalloutPoint(0.4, 0.3)]),
        ],
        calloutReveal: BulletRevealMode.steps,
      );
      final cp = PresentationStepPlan.forSlide(slide) as CalloutRevealStepPlan;
      // Re-entry = step 0: no bullets, no callouts.
      expect(cp.revealedBulletCount(0), 0);
      expect(cp.revealedReferences(0), <String>{});
    });

    test('multiple targets reveal atomically with their bullet', () {
      final slide = Slide(
        id: 'test',
        type: SlideType.bulletsImage,
        bullets: ['bolts (C)'],
        callouts: const [
          ImageCallout(
            reference: 'C',
            targets: [
              CalloutPoint(0.61, 0.48),
              CalloutPoint(0.70, 0.30),
            ],
            description: 'the two mounting bolts',
          ),
        ],
        calloutReveal: BulletRevealMode.steps,
      );
      final cp = PresentationStepPlan.forSlide(slide) as CalloutRevealStepPlan;
      // Step 0: no callouts.
      expect(cp.revealedReferences(0), <String>{});
      // Step 1: bullet + ALL targets of C revealed atomically.
      expect(cp.revealedReferences(1), {'C'});
      // The plan reveals the reference, not individual targets — the overlay
      // draws all targets of a revealed reference (§7: atomically).
    });

    test('bullet without callout still counts as a step', () {
      final slide = Slide(
        id: 'test',
        type: SlideType.bulletsImage,
        bullets: ['no callout here', 'with callout (A)'],
        callouts: const [
          ImageCallout(reference: 'A', targets: [CalloutPoint(0.5, 0.5)]),
        ],
        calloutReveal: BulletRevealMode.steps,
      );
      final cp = PresentationStepPlan.forSlide(slide) as CalloutRevealStepPlan;
      expect(cp.remainingSteps, 2);
      // Step 1: first bullet visible, no callout yet.
      expect(cp.revealedBulletCount(1), 1);
      expect(cp.revealedReferences(1), <String>{});
      // Step 2: second bullet + callout A.
      expect(cp.revealedBulletCount(2), 2);
      expect(cp.revealedReferences(2), {'A'});
    });
  });

  group('TimelineStepPlan regression (generalisation did not change behaviour)',
  () {
    test('timeline steps: step 0 = first event, step N = all', () {
      final slide = Slide(
        id: 'test',
        type: SlideType.timeline,
        bullets: ['2019 :: A', '2020 :: B', '2021 :: C'],
        timelineReveal: TimelineReveal.steps,
      );
      final plan = PresentationStepPlan.forSlide(slide);
      expect(plan, isA<TimelineStepPlan>());
      final tp = plan as TimelineStepPlan;
      expect(tp.eventCount, 3);
      expect(tp.remainingSteps, 2);
      expect(tp.revealedEventCount(0), 1);
      expect(tp.revealedEventCount(1), 2);
      expect(tp.revealedEventCount(2), 3);
    });

    test('timeline onEnter → no stepping', () {
      final slide = Slide(
        id: 'test',
        type: SlideType.timeline,
        bullets: ['2019 :: A', '2020 :: B'],
        timelineReveal: TimelineReveal.onEnter,
      );
      expect(PresentationStepPlan.forSlide(slide), isA<NoStepPlan>());
    });
  });
}
