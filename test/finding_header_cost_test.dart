import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/models/finding_spec.dart';
import 'package:ocideck/models/settings.dart';
import 'package:ocideck/models/slide.dart';
import 'package:ocideck/services/finding_pagination.dart';
import 'package:ocideck/widgets/slides/slide_preview.dart';

/// Grounds the pagination's header-card cost model against the LIVE render.
///
/// `_headerCardCost` predicts, without a render context, how tall a finding's
/// header card is — the pagination budgets page 1's first section against it.
/// It used to be a single constant (18.5 line-units ≈ 80% of a slide), but the
/// real card measures ~44% for a common finding and ~98% for a fat one. That
/// over-reservation produced a header-only, mostly-empty page 1 (worse with a
/// logo reserve, #1198), while under-reserving a fat header so its first section
/// overflowed. The model is now content-derived; this test renders each variant
/// and fails if the model drifts away from what the card actually measures — the
/// guard that keeps an eyeballed estimate from silently rotting again.
void main() {
  const vector =
      'CVSS:4.0/AV:N/AC:L/AT:N/PR:N/UI:N/VC:H/VI:H/VA:L/SC:N/SI:N/SA:N';
  const shortHeading = 'F-01 · Kort';
  const longHeading =
      'F-12 · Onbeveiligde directe objectreferentie in de exportmodule van het '
      'klantportaal maakt cross-tenant datalekken mogelijk';

  // A representative spread of the header content that changes the card height:
  // heading length, scope, the CVSS score card and identity badge rows.
  final cases = <String, FindingSpec>{
    'minimal': const FindingSpec(heading: shortHeading, description: 'x'),
    'long heading': const FindingSpec(heading: longHeading, description: 'x'),
    'scope only': const FindingSpec(
      heading: shortHeading,
      scopeObject: 'https://a/b',
      description: 'x',
    ),
    'cvss only': const FindingSpec(
      heading: shortHeading,
      cvssVector: vector,
      description: 'x',
    ),
    'one badge': const FindingSpec(
      heading: shortHeading,
      cweId: 89,
      description: 'x',
    ),
    'many badges': const FindingSpec(
      heading: shortHeading,
      cweId: 639,
      masweId: 'MASWE-0042',
      testId: 'MASTG-TEST-0231',
      cveIds: ['CVE-2024-12345', 'CVE-2024-67890'],
      retest: RetestStatus.notResolved,
      description: 'x',
    ),
    'typical finding': const FindingSpec(
      heading: 'F-03 · SQL-injectie in het loginformulier',
      scopeObject: 'https://app.voorbeeld/login',
      cvssVector: vector,
      cweId: 89,
      description: 'x',
    ),
    'fat header': const FindingSpec(
      heading: longHeading,
      scopeObject: 'https://app.voorbeeld/api/v2/export?tenant=…',
      cvssVector:
          'CVSS:4.0/AV:N/AC:L/AT:N/PR:L/UI:N/VC:H/VI:H/VA:H/SC:H/SI:H/SA:H',
      cweId: 639,
      masweId: 'MASWE-0042',
      testId: 'MASTG-TEST-0231',
      cveIds: ['CVE-2024-12345', 'CVE-2024-67890'],
      retest: RetestStatus.notResolved,
      description: 'x',
    ),
  };

  Future<double> measuredUnits(WidgetTester tester, FindingSpec spec) async {
    final slide = Slide.create(SlideType.finding).copyWith(
      customMarkdown: spec.toMarkdown(),
      findingRole: FindingRole.header,
    );
    await tester.binding.setSurfaceSize(const Size(960, 540));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));
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
    final canvasH = tester.getSize(find.byType(AspectRatio).first).height;
    final cardH = tester
        .getSize(find.byKey(const ValueKey('finding-header-card')))
        .height;
    return _linesPerSlide * cardH / canvasH;
  }

  for (final entry in cases.entries) {
    testWidgets('header cost model brackets the live card — ${entry.key}', (
      tester,
    ) async {
      final measured = await measuredUnits(tester, entry.value);
      final model = debugHeaderCardCost(entry.value);

      // Never UNDER-reserve: a model shorter than the real card lets a first
      // section share page 1 that then overflows into the header. A hair of
      // slack (0.6u) absorbs sub-pixel rounding.
      expect(
        model,
        greaterThanOrEqualTo(measured - 0.6),
        reason:
            '${entry.key}: model $model under-reserves vs measured $measured',
      );
      // Never grossly OVER-reserve: that is the header-only sparse page #1198
      // was about. Keep the model within ~3.5u of the real card.
      expect(
        model,
        lessThanOrEqualTo(measured + 3.5),
        reason:
            '${entry.key}: model $model over-reserves vs measured $measured',
      );
    });
  }
}

// Kept in step with `_linesPerSlide` in finding_pagination.dart; a slide is this
// many body-line-units tall at the reference width.
const double _linesPerSlide = 23.0;
