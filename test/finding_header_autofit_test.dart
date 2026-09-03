import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';
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
/// fit against a REAL render: a dense header stays presentation-readable while
/// filling the slide, a sparse one is held at the ceiling, and pagination is
/// intact.
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
  TextStyle richTextStyle(WidgetTester tester, String text) {
    TextStyle? findInSpan(InlineSpan span) {
      if (span is! TextSpan) return null;
      if (span.text == text) return span.style;
      for (final child in span.children ?? const <InlineSpan>[]) {
        final found = findInSpan(child);
        if (found != null) return found;
      }
      return null;
    }

    for (final rich in tester.widgetList<RichText>(find.byType(RichText))) {
      final found = findInSpan(rich.text);
      if (found != null) return found;
    }
    throw TestFailure('No RichText style found for "$text"');
  }

  ({double bodyEffective, double headerToBody, double scaleDown}) rendered(
    WidgetTester tester,
    String headingNeedle,
    String body,
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
    final headingSize = heading.style!.fontSize!;
    final bodySize = richTextStyle(tester, body).fontSize!;
    return (
      bodyEffective: bodySize * scaleDown / (child.width * 0.024),
      headerToBody: headingSize / bodySize,
      scaleDown: scaleDown,
    );
  }

  testWidgets('a dense F-01 header reflows to a bounded size that fits (#1282)', (
    tester,
  ) async {
    await pump(tester, denseF01);
    expect(tester.takeException(), isNull);

    final r = rendered(tester, 'F-01', denseF01.description);

    // (a) It remains effectively full-width: the scaffold may absorb a few
    // percent of font-metric drift, but must not shrink and park the page
    // top-left (pre-fix this content rendered at ~0.68 scale).
    // #1932: finding is een panel-slide — het logo zit in de hoek, de
    // inhoud gebruikt de volle hoogte. De autofit-schaal verschilt daardoor
    // licht van de oude situatie met een logo-strook.
    expect(
      r.scaleDown,
      greaterThan(0.89),
      reason: 'content should stay effectively full-width, not be parked',
    );

    // (b) It stays large enough to read from a presentation screen. The first
    // auto-fit aimed at only 60% of the slide and reduced this realistic page to
    // roughly half-size type, leaving conspicuous whitespace below it.
    expect(
      r.bodyEffective,
      greaterThanOrEqualTo(0.60),
      reason:
          'dense body should remain presentation-readable, was '
          '${r.bodyEffective}',
    );
    expect(
      r.headerToBody,
      lessThanOrEqualTo(1.10),
      reason: 'header should not dominate the body, was ${r.headerToBody}×',
    );
  });

  testWidgets('a sparse header is held at the ceiling, not enlarged (#1282)', (
    tester,
  ) async {
    await pump(tester, sparse);
    expect(tester.takeException(), isNull);

    final r = rendered(tester, 'F-9', sparse.description);
    // Nothing to shrink: the fit is capped, so the type stays at the #1163
    // baseline (0.84) rather than blowing up to fill the slide.
    expect(r.scaleDown, greaterThan(0.99));
    expect(r.bodyEffective, closeTo(kFindingBaseFontScale, 0.02));
  });

  test('the compact header keeps a packed first page comfortably readable', () {
    const font = 'Roboto';
    final densePage = firstRenderPageSpec(
      Slide.create(SlideType.finding).copyWith(
        customMarkdown: denseF01.toMarkdown(),
        findingRole: FindingRole.header,
      ),
    );
    final denseFit = findingHeaderFitScale(spec: densePage, font: font);
    final sparseFit = findingHeaderFitScale(spec: sparse, font: font);

    // Page 1 may now use spare room for a second section, but the paginator
    // keeps its measured type comfortably above the readability floor.
    expect(denseFit, greaterThan(0.85));
    expect(denseFit, lessThanOrEqualTo(1.0));
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
