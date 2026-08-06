import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/l10n/app_localizations.dart';
import 'package:ocideck/models/finding_spec.dart';
import 'package:ocideck/models/settings.dart';
import 'package:ocideck/models/slide.dart';
import 'package:ocideck/services/finding_header_metrics.dart';
import 'package:ocideck/services/finding_pagination.dart';
import 'package:ocideck/widgets/slides/slide_preview.dart';

/// The content-aware header auto-fit (#1282). A dense finding header used to
/// render at its fixed #1163 size — far too large, and (once it overflowed) shrunk
/// and parked top-left by the scaffold's `BoxFit.scaleDown`. These tests pin the
/// fix against a REAL render: a dense header now reflows to a bounded size that
/// fits the slide, a sparse one is held at the ceiling, and pagination is intact.
void main() {
  setUp(() => AppLocalizations.setActiveLanguageCode('nl'));

  // A dense F-01 header: full identity meta plus four prose sections — the
  // "renders far too large" case from #1282.
  const denseF01 = FindingSpec(
    heading: 'F-01 · Slim kattenluik met ingebakken sleutel',
    scopeObject: 'https://kattenluik.voorbeeld/api/v1/toegang',
    cvssVector:
        'CVSS:4.0/AV:N/AC:L/AT:N/PR:N/UI:N/VC:H/VI:H/VA:H/SC:N/SI:N/SA:N',
    cweId: 798,
    masweId: 'MASWE-0011',
    testId: 'MASTG-TEST-0231',
    cveIds: ['CVE-2024-12345'],
    description:
        'Het kattenluik bevat een ingebakken (hardcoded) API-sleutel die uit de '
        'firmware te lezen is. Iedereen die de sleutel achterhaalt kan het luik '
        'op afstand ontgrendelen, ongeacht de eigenaar.',
    confirmation:
        '1. Firmware uitgelezen via de debugpoort.\n'
        '2. De sleutel gevonden in het klare tekstsegment.\n'
        '3. Met de sleutel het luik op afstand geopend.',
    impact:
        'Een aanvaller kan elk luik van dit model openen zonder fysieke toegang, '
        'wat de woning van de eigenaar blootstelt aan inbraak.',
    recommendation:
        'Vervang de ingebakken sleutel door een per-apparaat gegenereerde '
        'sleutel in beveiligde opslag, en voorzie in sleutelrotatie.',
  );

  // A sparse header: one line, no meta — nothing to shrink.
  const sparse = FindingSpec(
    heading: 'F-9 · Klein dingetje',
    description: 'Kort.',
  );

  Future<void> pump(WidgetTester tester, FindingSpec spec) async {
    final slide = Slide.create(SlideType.finding).copyWith(
      customMarkdown: spec.toMarkdown(),
      findingRole: FindingRole.header,
    );
    await tester.binding.setSurfaceSize(const Size(960, 540));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 960,
              height: 540,
              child: SlidePreviewWidget(
                slide: slide,
                themeProfile: ThemeProfile.libreKat,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 50));
  }

  // The on-screen type size the finding renders its heading at, as a fraction of
  // the slide width (base heading = w*0.038). This folds in BOTH the type
  // multiplier the preview applies and any residual scaffold scale-down, so it is
  // the size the reader actually sees — the "renders far too large" measure.
  ({double effective, double scaleDown}) rendered(
    WidgetTester tester,
    String headingNeedle,
  ) {
    final ro =
        tester.renderObject(find.byType(FittedBox))
            as RenderObjectWithChildMixin<RenderBox>;
    final own = (ro as RenderBox).size;
    final child = ro.child!.size;
    // scaleDown only shrinks; content laid out at the full width, so the height
    // ratio is the on-screen scale.
    final scaleDown = math.min(1.0, own.height / child.height);
    final heading = tester.widget<Text>(
      find.descendant(
        of: find.byKey(const ValueKey('finding-header-card')),
        matching: find.textContaining(headingNeedle),
      ),
    );
    final applied = heading.style!.fontSize!;
    final base = child.width * 0.038;
    return (effective: applied * scaleDown / base, scaleDown: scaleDown);
  }

  testWidgets('a dense F-01 header reflows to a bounded size that fits (#1282)', (
    tester,
  ) async {
    await pump(tester, denseF01);
    expect(tester.takeException(), isNull);

    final r = rendered(tester, 'F-01');

    // (a) It fits the slide at full width: the scaffold no longer has to shrink
    // and park it top-left (pre-fix this content overflowed and rendered at
    // ~0.68 scale). scaleDown == 1.0 means the page fits as laid out.
    expect(
      r.scaleDown,
      greaterThan(0.99),
      reason: 'content should fit the slide at full width, not be parked',
    );

    // (b) It is no longer oversized: the header reads at roughly half the base
    // size (the reporter's ~50%), an UPPER bound the pre-fix fixed 0.84 render
    // (~0.57 on-screen for this content) violates. This is the guard the fixed
    // scale lacked — not merely the existing "≥ 0.70" readability floor.
    expect(
      r.effective,
      lessThanOrEqualTo(0.55),
      reason: 'dense header should render at ~half size, was ${r.effective}',
    );
    // …and not collapsed to nothing.
    expect(r.effective, greaterThan(0.35));
  });

  testWidgets('a sparse header is held at the ceiling, not enlarged (#1282)', (
    tester,
  ) async {
    await pump(tester, sparse);
    expect(tester.takeException(), isNull);

    final r = rendered(tester, 'F-9');
    // Nothing to shrink: the fit is capped, so the type stays at the #1163
    // baseline (0.84) rather than blowing up to fill the slide.
    expect(r.scaleDown, greaterThan(0.99));
    expect(r.effective, closeTo(kFindingBaseFontScale, 0.02));
  });

  test('the fit engages for a dense header and is capped for a sparse one', () {
    const font = 'Roboto';
    final densePage = firstRenderPageSpec(
      Slide.create(SlideType.finding).copyWith(
        customMarkdown: denseF01.toMarkdown(),
        findingRole: FindingRole.header,
      ),
    );
    final denseFit = findingHeaderFitScale(spec: densePage, font: font);
    final sparseFit = findingHeaderFitScale(spec: sparse, font: font);

    // A dense header is shrunk; a sparse one sits at the ceiling.
    expect(denseFit, lessThan(0.8));
    expect(denseFit, greaterThan(0.0));
    expect(sparseFit, 1.0);
    // The ceiling is honoured whatever is passed.
    expect(
      findingHeaderFitScale(spec: sparse, font: font, maxScale: 0.7),
      lessThanOrEqualTo(0.7),
    );
  });

  test('pagination is preserved: a dense finding still splits (#1282)', () {
    // The fit sizes the type on each page; it does not merge pages. A finding
    // dense enough to span slides keeps splitting (the section-stream integrity
    // of the split is covered by finding_pagination_test.dart).
    expect(paginateFinding(denseF01).length, greaterThan(1));
  });
}
