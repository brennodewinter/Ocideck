// Headless step plan for presentation reveals (IMAGE_CALLOUTS.md §7).
//
// A headless `PresentationStepPlan`, shared by timelines and bullet callouts
// rather than copying slide-type-specific step state. The presenter holds one
// session-local step index; the plan translates that index into what is
// visible on each surface.
//
// Flutter-free so it can be tested without a widget tree and used by both the
// presenter and the audience window.

import 'image_callout.dart';
import 'slide.dart';
import 'timeline.dart';

/// A trailing `(A)` reference at the end of a bullet (§2.1): one space, one
/// uppercase letter in parentheses. Used to match a callout to its bullet so
/// the reveal can bring them up together.
final RegExp _bulletRefSuffix = RegExp(r'\s\(([A-Z])\)$');

/// Headless description of how a slide reveals its content step-by-step during
/// a presentation (IMAGE_CALLOUTS.md §7).
///
/// The plan is a pure function of [Slide] data — the presenter holds one
/// session-local step index ([PresentationStepPlan.remainingSteps] clicks from
/// the initial state to fully revealed) and the plan translates that index into
/// what is visible on each surface.
sealed class PresentationStepPlan {
  const PresentationStepPlan();

  /// Number of forward clicks needed to fully reveal the slide from its initial
  /// state. 0 = no stepping (the slide shows everything immediately).
  int get remainingSteps;

  /// Whether this plan actually steps.
  bool get hasSteps => remainingSteps > 0;

  /// Build the plan for [slide], or [NoStepPlan] if the slide doesn't step.
  factory PresentationStepPlan.forSlide(Slide slide) {
    // Timeline in step mode: step 0 shows the first event, each click reveals
    // one more (IMAGE_CALLOUTS.md §7, unchanged from pre-generalisation).
    if (slide.type == SlideType.timeline &&
        slide.timelineReveal == TimelineReveal.steps) {
      return TimelineStepPlan(
        eventCount: parseTimelineEvents(slide.bullets).length,
      );
    }
    // bulletsImage with callout reveal: step 0 shows title + image, each click
    // reveals one bullet plus all of its callout targets atomically (§7).
    if (slide.type == SlideType.bulletsImage &&
        slide.calloutReveal == BulletRevealMode.steps &&
        slide.callouts.isNotEmpty) {
      return CalloutRevealStepPlan.forSlide(slide);
    }
    return const NoStepPlan();
  }
}

/// No stepping — the slide shows everything immediately.
class NoStepPlan extends PresentationStepPlan {
  const NoStepPlan();

  @override
  int get remainingSteps => 0;
}

/// Timeline step mode (IMAGE_CALLOUTS.md §7). Step 0 shows the first event so
/// the slide never opens empty; each click reveals one further event.
class TimelineStepPlan extends PresentationStepPlan {
  /// Total number of timeline events on the slide.
  final int eventCount;

  const TimelineStepPlan({required this.eventCount});

  @override
  int get remainingSteps => eventCount > 0 ? eventCount - 1 : 0;

  /// How many events are visible at [step] (step 0 = first event).
  int revealedEventCount(int step) {
    if (eventCount <= 0) return 0;
    return (step + 1).clamp(1, eventCount);
  }

  @override
  bool operator ==(Object other) =>
      other is TimelineStepPlan && other.eventCount == eventCount;

  @override
  int get hashCode => Object.hash('timeline', eventCount);
}

/// Callout reveal step mode (IMAGE_CALLOUTS.md §7). Step 0 shows title and
/// image only; each click reveals one bullet plus all of its callout targets
/// atomically. The reveal order follows bullet order.
class CalloutRevealStepPlan extends PresentationStepPlan {
  /// Non-empty bullet texts in reveal order.
  final List<String> bullets;

  /// The trailing reference letter for each bullet in [bullets], or '' when the
  /// bullet has no callout reference. Used to match callouts to their bullet so
  /// targets reveal together with the bullet.
  final List<String> bulletReferences;

  /// All callout references that exist on the slide (for quick lookup).
  final Set<String> calloutReferences;

  /// Hoeveel targets elke referentie heeft. Nodig om een onthulstap te kunnen
  /// aankondigen met het aantal markeringen dat er werkelijk bij kwam (§12.2):
  /// één verwijzing kan meerdere markeringen tegelijk laten verschijnen.
  final Map<String, int> targetCounts;

  CalloutRevealStepPlan({
    required this.bullets,
    required this.bulletReferences,
    required this.calloutReferences,
    this.targetCounts = const {},
  });

  /// Build the plan from a slide's bullets and callouts.
  factory CalloutRevealStepPlan.forSlide(Slide slide) {
    final bullets = slide.bullets
        .where((b) => b.trimLeft().isNotEmpty)
        .toList();
    final refs = bullets.map(_extractReference).toList();
    final calloutRefs = slide.callouts.map((c) => c.reference).toSet();
    return CalloutRevealStepPlan(
      bullets: bullets,
      bulletReferences: refs,
      calloutReferences: calloutRefs,
      targetCounts: {
        for (final callout in slide.callouts)
          callout.reference: callout.targets.length,
      },
    );
  }

  @override
  int get remainingSteps => bullets.length;

  /// How many bullets are visible at [step] (step 0 = none, title + image only).
  int revealedBulletCount(int step) => step.clamp(0, bullets.length);

  /// The set of callout references whose bullet is among the first [step]
  /// visible bullets. A callout is revealed atomically with its bullet (§7).
  Set<String> revealedReferences(int step) {
    final count = revealedBulletCount(step);
    return bulletReferences
        .take(count)
        .where((r) => r.isNotEmpty && calloutReferences.contains(r))
        .toSet();
  }

  /// Hoeveel markeringen er bij *deze* stap zichtbaar werden — de targets van
  /// de bullet die net verscheen, niet het totaal dat al stond. Een bullet
  /// zonder verwijzing levert 0: dan is er niets bijgekomen om te melden.
  int marksAtStep(int step) {
    final index = step - 1;
    if (index < 0 || index >= bulletReferences.length) return 0;
    final reference = bulletReferences[index];
    if (reference.isEmpty || !calloutReferences.contains(reference)) return 0;
    return targetCounts[reference] ?? 0;
  }

  /// Extract the trailing `(A)` reference from a bullet, or '' if none.
  static String _extractReference(String bullet) {
    final match = _bulletRefSuffix.firstMatch(bullet.trimRight());
    return match?.group(1) ?? '';
  }

  @override
  bool operator ==(Object other) =>
      other is CalloutRevealStepPlan &&
      _listEq(other.bullets, bullets) &&
      _listEq(other.bulletReferences, bulletReferences) &&
      other.calloutReferences.length == calloutReferences.length &&
      other.calloutReferences.containsAll(calloutReferences) &&
      _mapEq(other.targetCounts, targetCounts);

  @override
  int get hashCode => Object.hash(bullets, bulletReferences, calloutReferences);

  static bool _mapEq(Map<String, int> a, Map<String, int> b) {
    if (a.length != b.length) return false;
    for (final entry in a.entries) {
      if (b[entry.key] != entry.value) return false;
    }
    return true;
  }

  static bool _listEq(List<String> a, List<String> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}
