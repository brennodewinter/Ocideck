import 'dart:math' as math;

import '../models/finding_spec.dart';
import 'markdown_body_blocks.dart' as md_body;
import 'slide_layout_metrics.dart'
    show
        kFitScaleBisectTolerance,
        kReferenceSlideWidth,
        kTextDensityCriticalScale;
import 'text_measurement.dart';

// ── Finding-header auto-fit (#1282) ──────────────────────────────────────────
// A `finding` header's type was a fixed fraction of the slide width times one
// constant ([kFindingBaseFontScale], the #1163 down-scale). Nothing measured the
// content, so a dense pentest header (full identity meta + a prose section) drew
// at its natural size and the only relief was the scaffold's `BoxFit.scaleDown`,
// which shrinks-and-parks the whole block top-left rather than reflowing it. This
// adds a content-aware fit — the same idea bullets already use in
// [bulletsSlideFitScale] — that measures the page's rendered height and returns a
// multiplier so a dense header reflows smaller while a sparse one is held at the
// [maxScale] ceiling (never enlarged past the #1163 look).

/// The fixed finding type down-scale (#1163), shared with `_FindingPreview` in
/// `finding_preview.dart` so the fit here and the render there cannot drift.
const double kFindingBaseFontScale = 0.84;

/// The identity card is supporting context, not the slide's main prose. Keep
/// its title, badges, scope and CVSS typography a third smaller than the body.
const double kFindingHeaderTypeScale = 2 / 3;

/// Fraction of the slide height a finding header page should aim to fill. The
/// remaining eighth keeps the layout calm without reducing realistic text to
/// thumbnail size. The fit never *enlarges* content to reach this (that is
/// [maxScale]'s job); it only shrinks content that would otherwise exceed it.
const double kFindingHeaderTargetFill = 0.875;

/// The finding preview's side padding, mirrored from `_FindingPreview`.
const double _findingHPadFraction = 0.045;

/// The lowest fit a finding is allowed to reach (matches the bullets floor).
const double _findingMinFitScale = kTextDensityCriticalScale;

/// The content-aware type multiplier for a `finding` header page, in
/// `(0, maxScale]`. It measures the page's rendered content — the severity card
/// (or, on a continuation page, the compact repeated heading) plus the prose
/// sections present on *this* page — against the slide's target height and
/// returns the largest multiplier that keeps the content within it. A sparse
/// header measures short and is held at [maxScale]; a dense one reflows down.
///
/// [spec] must be the page as the preview renders it (a
/// `firstRenderPageSpec`/`expandFindingsForRender` result), so a finding that
/// legitimately spans several slides keeps splitting — the fit only sizes the
/// type on the page it is handed, it does not merge pages. [extraVReserve]
/// (a fraction of the reference width) lowers the target the way a shown logo
/// reserves vertical space.
double findingHeaderFitScale({
  required FindingSpec spec,
  required String font,
  bool continuation = false,
  double maxScale = 1.0,
  double extraVReserve = 0,
}) {
  final w = kReferenceSlideWidth;
  final slideHeight = w * 9 / 16;
  final availW = w - w * _findingHPadFraction * 2;
  // Target a fraction of the height the scaffold actually gives the content: the
  // whole slide, less any logo strip the scaffold reserves *outside* the
  // [FittedBox] ([extraVReserve]). Aiming for a fraction — not all — of that keeps
  // a dense header off the edges while using enough of the slide for readable
  // type; because the fraction already leaves margin, the scaffold's own vertical
  // padding fits within it without a separate subtraction (which would
  // double-count the logo).
  final budget = ((slideHeight - extraVReserve) * kFindingHeaderTargetFill)
      .clamp(1.0, slideHeight);

  double measure(double fit) =>
      _findingContentHeight(spec, fit, availW, font, continuation);

  if (measure(maxScale) <= budget) return maxScale;
  var lo = _findingMinFitScale;
  var hi = maxScale;
  if (measure(lo) > budget) return lo;
  for (var i = 0; i < 24 && hi - lo > kFitScaleBisectTolerance; i++) {
    final mid = (lo + hi) / 2;
    if (measure(mid) <= budget) {
      lo = mid;
    } else {
      hi = mid;
    }
  }
  return lo;
}

/// The rendered height of a finding page's content column at fit multiplier
/// [fit] — the severity card (or continuation heading) plus the prose sections,
/// mirroring `_FindingPreview.build`. Fonts carry [kFindingBaseFontScale] × [fit]
/// exactly as the widget draws them; the fixed spacings do not scale, so the
/// column bottoms out on its chrome rather than collapsing to nothing.
double _findingContentHeight(
  FindingSpec spec,
  double fit,
  double availW,
  String font,
  bool continuation,
) {
  final w = kReferenceSlideWidth;
  final m = kFindingBaseFontScale * fit;
  var h = 0.0;
  if (continuation) {
    if (spec.heading.isNotEmpty) {
      h += measureTextHeight(
        spec.heading,
        w * 0.014 * m,
        availW,
        bold: true,
        fontFamily: font,
      );
    }
    h += w * 0.02; // Padding.bottom under the continuation heading.
  } else {
    h += _findingHeaderCardHeight(
      spec,
      m * kFindingHeaderTypeScale,
      availW,
      font,
    );
    h += w * 0.03; // SizedBox between the card and the first section.
  }
  h += _findingSectionsHeight(spec, fit, availW, font);
  return h;
}

/// The severity header card's height at font multiplier [m], mirroring
/// `_headerCard`: a padded [Row] whose height is the taller of its two columns —
/// the identity column (badges, heading, scope) on the left and the fixed CVSS
/// score card on the right.
double _findingHeaderCardHeight(
  FindingSpec spec,
  double m,
  double availW,
  String font,
) {
  final w = kReferenceSlideWidth;
  final cardPad = w * 0.03;
  final innerW = (availW - cardPad * 2).clamp(1.0, availW);
  final hasScore = spec.cvss != null;
  // Score card: Padding(left w*0.02) + Container(width w*0.21).
  final scoreOuterW = hasScore ? w * 0.02 + w * 0.21 : 0.0;
  final leftW = (innerW - scoreOuterW).clamp(1.0, innerW);

  var left = 0.0;
  if (_findingHasBadges(spec)) {
    left += _findingBadgesHeight(spec, m, leftW, font);
    left += w * 0.02;
  }
  if (spec.heading.isNotEmpty) {
    left += measureTextHeight(
      spec.heading,
      w * 0.038 * m,
      leftW,
      bold: true,
      fontFamily: font,
    );
  }
  if (spec.scopeObject.isNotEmpty) {
    left += w * 0.015;
    final iconW = w * 0.024; // fixed icon, not scaled by the type multiplier.
    final scopeTextW = (leftW - iconW - w * 0.01).clamp(1.0, leftW);
    final textH = measureTextHeight(
      spec.scopeObject,
      w * 0.024 * m,
      scopeTextW,
      fontFamily: font,
    );
    left += math.max(iconW, textH);
  }

  final right = hasScore ? _findingScoreCardHeight(m, font) : 0.0;
  return cardPad * 2 + math.max(left, right);
}

/// The right-hand CVSS score card's height at multiplier [m], mirroring
/// `_severityScoreCard`. Most of its spacing (padding, the meter, the gaps) is
/// fixed, so this block sets the card's floor once a score is present.
double _findingScoreCardHeight(double m, String font) {
  final w = kReferenceSlideWidth;
  final cardW = w * 0.21;
  final vPad = w * 0.014 + w * 0.016;
  // The label is a single line, so only its height matters and that is
  // text-independent; a digit (letterless) gives the line height without pinning
  // a piece of interface text into this measurement helper.
  final label = measureTextHeight(
    '0',
    w * 0.018 * m,
    cardW,
    bold: true,
    fontFamily: font,
  );
  final scoreRow = w * 0.052 * m; // score text drawn with height: 1.
  final endpoints = measureTextHeight(
    '10',
    w * 0.014 * m,
    cardW,
    fontFamily: font,
  );
  return vPad +
      label +
      w * 0.006 +
      scoreRow +
      w * 0.012 +
      w * 0.018 /* meter */ +
      w * 0.002 +
      endpoints;
}

/// Length of the fixed `CWE-` prefix a CWE chip carries before its numeric id,
/// and of the ` na hertest` suffix on a retest chip — counted as characters so
/// the width can be estimated from a glyph proxy without pinning interface text
/// into this measurement helper (see [_findingBadgesHeight]).
const int _cweChipPrefixChars = 4; // "CWE-"
const int _retestChipSuffixChars = 11; // " na hertest"

/// The identity badge row's height at multiplier [m], simulating the `_badges`
/// [Wrap]: chips laid left to right, wrapping to a new row when the next chip no
/// longer fits [availW]. Only the chips `_badges` actually draws are counted, in
/// the same order, so the modelled height tracks the render. The chips' dynamic
/// text (ids, labels) is measured directly; the two fixed affixes are estimated
/// from a letterless glyph-width proxy so no interface literal lands in a
/// measurement call.
double _findingBadgesHeight(
  FindingSpec spec,
  double m,
  double availW,
  String font,
) {
  final w = kReferenceSlideWidth;
  final spacing = w * 0.015;
  final runSpacing = w * 0.012;
  final outlinedFs = w * 0.022 * m;
  final filledFs = w * 0.024 * m;
  double owid(String s, double fs) =>
      measureTextWidth(s, fs, bold: true, fontFamily: font);
  // A representative glyph width per font size (a digit — letterless), used to
  // price the fixed affixes by character count.
  final outlinedGlyph = owid('0', outlinedFs);
  final filledGlyph = owid('0', filledFs);

  final chips = <(double, double)>[]; // (width, height) per chip.
  void outlined(double textW) =>
      chips.add((textW + w * 0.018 * 2, outlinedFs * 1.3 + w * 0.006 * 2));

  if (spec.cweId != null) {
    outlined(
      owid('${spec.cweId}', outlinedFs) + _cweChipPrefixChars * outlinedGlyph,
    );
  }
  if (spec.masweId.isNotEmpty) outlined(owid(spec.masweId, outlinedFs));
  for (final cve in spec.cveIds) {
    outlined(owid(cve, outlinedFs));
  }
  if (spec.testId.isNotEmpty) outlined(owid(spec.testId, outlinedFs));
  if (spec.retest.isRetested) {
    final tw =
        owid(spec.retest.dutchLabel, filledFs) +
        _retestChipSuffixChars * filledGlyph;
    chips.add((tw + w * 0.02 * 2, filledFs * 1.3 + w * 0.008 * 2));
  }
  if (chips.isEmpty) return 0;

  var total = 0.0;
  var rowW = 0.0;
  var rowH = 0.0;
  var isRowStart = true;
  for (final (cw, ch) in chips) {
    final add = isRowStart ? cw : spacing + cw;
    if (!isRowStart && rowW + add > availW) {
      total += rowH + runSpacing;
      rowW = cw;
      rowH = ch;
      isRowStart = false;
      continue;
    }
    rowW += add;
    rowH = math.max(rowH, ch);
    isRowStart = false;
  }
  return total + rowH;
}

/// The prose sections' height at fit [fit], measured with the same markdown-body
/// metric the renderer pairs with — body at `w*0.024` and `##` headings at
/// `w*0.03`, both carrying [kFindingBaseFontScale] × [fit] (see `_sectionBlocks`).
double _findingSectionsHeight(
  FindingSpec spec,
  double fit,
  double availW,
  String font,
) {
  final markdown = _findingSectionsMarkdown(spec);
  if (markdown.isEmpty) return 0;
  final w = kReferenceSlideWidth;
  return md_body.markdownBodyHeight(
    markdown: markdown,
    contentW: availW,
    refW: w,
    bodySize: w * 0.024,
    font: font,
    scale: kFindingBaseFontScale * fit,
  );
}

/// The section markdown a finding page renders, in §3.1 order — the same stream
/// `_sectionBlocks` builds, using the stable anchors (heading text is one line
/// either way, so its wrapped height does not depend on the report language).
String _findingSectionsMarkdown(FindingSpec spec) {
  final buf = StringBuffer();
  void add(String heading, String body) {
    if (body.trim().isEmpty) return;
    buf
      ..writeln('## $heading')
      ..writeln()
      ..writeln(body.trim())
      ..writeln();
  }

  add(FindingSpec.sectionDescription, spec.description);
  add(FindingSpec.sectionConfirmation, spec.confirmation);
  add(FindingSpec.sectionImpact, spec.impact);
  add(FindingSpec.sectionRecommendation, spec.recommendation);
  return buf.toString();
}

/// Whether the finding draws its identity badge row (mirrors `_hasBadges`). A
/// MASWE id alone rides alongside another badge, so it does not, by itself, open
/// the row.
bool _findingHasBadges(FindingSpec spec) =>
    spec.cvss != null ||
    spec.cweId != null ||
    spec.cveIds.isNotEmpty ||
    spec.testId.isNotEmpty ||
    spec.retest.isRetested;
