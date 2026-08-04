/// Render-time pagination for `finding` slides (PENTEST_MIAUW §3.1). A finding is
/// edited as ONE slide, but when its prose is too long for a single slide it is
/// **rendered** across several — so the text stays full-size and full-width
/// instead of shrinking to fit. This is a pure, deck-non-mutating transform: the
/// `.md` on disk is unchanged; only what the preview/presenter/export enumerate
/// changes.
///
/// Page 1 keeps the header card (severity badge, heading, scope) plus the
/// finding's first section — placed unconditionally, so an overflowing finding
/// never renders a header-only, near-empty first page (#1198). Each continuation
/// page repeats the heading with a small "(i/N)" marker, drops the header card,
/// and holds the next sections. A finding that fits one slide is returned
/// unchanged (a single page).
library;

import 'package:flutter/foundation.dart';

import '../models/finding_spec.dart';
import '../models/settings.dart';
import '../models/slide.dart';
import 'rich_text_layout.dart';
import 'slide_layout_metrics.dart';

/// The "(i/N)" marker [paginateFinding] appends to a split finding's heading
/// (see [_page]). The single place that recognises an already-paginated page:
/// [firstRenderPageSpec] leaves such a page untouched, and the preview reads the
/// page number from it to tell a continuation from page one.
final RegExp findingPageMarker = RegExp(r'\((\d+)/\d+\)\s*$');

/// A finding section, in the fixed §3.1 order.
enum _Section { description, confirmation, impact, recommendation }

/// The page-budget model, in "line units" (one full-size body line of the
/// finding preview). It exists so pagination — a pure, deck-non-mutating
/// transform — can predict how tall a page renders WITHOUT a render context, and
/// split a finding before the [FittedBox] in `_PreviewScaffold` has to scale it
/// down (a too-tall finding scales down *uniformly*, so it also shrinks in width:
/// the whole cause of "the finding only uses a third of the slide").
///
/// The numbers below are **measured** against the live `_FindingPreview` at
/// `SlidePreviewWidget` — a 16:9 slide, no logo — not eyeballed. At that width a
/// slide is [_linesPerSlide] line-units tall. The compact CVSS score card leaves
/// enough room for a normal first section below the finding header. A
/// continuation page keeps the heading (its "(i/N)" marker) but drops the meta,
/// costing [_contHeadingCost].
/// A section adds [_sectionHeadingCost] for its `##` heading plus one unit per
/// wrapped body line at [_charsPerLine] characters each.
///
/// The previous calibration still described the removed cockpit-style CVSS
/// meter. It reserved more than a page for the header and nearly a page for a
/// continuation heading, producing five sparse pages for content that renders
/// legibly on three. These values are calibrated against that real fixture.
///
/// Since #1163 the finding preview draws its type ~0.84× (see
/// [_findingFontScale] in `finding_preview.dart`), so a body line holds more
/// characters and more lines fit per slide — both raised in step below so the
/// smaller type actually buys fewer pages.
const double _linesPerSlide = 23.0;

/// A continuation page's repeated heading ("(i/N)" marker) plus its spacing. It
/// is now a quiet half-size reminder rather than a large title (#1198 follow-up:
/// the big heading wasted half a continuation slide on the finding's title), so
/// this reserve dropped in step and continuation pages carry a little more.
const double _contHeadingCost = 4.5;
const double _sectionHeadingCost = 2.5;

// ── Header-card cost, derived from the finding's identity content ────────────
// The finding header card is NOT a fixed height: it grows with the heading's
// wrapped lines, an optional scope line, the identity badge rows (CWE/MASWE/
// CVE/testId/retest) and — dominating when present — the CVSS score card on the
// right. A single constant (the old 18.5) modelled the header at ~80% of a
// slide, but the live card measures ~44% for a common finding and up to ~98%
// for a fat one (long title + every identity field). That over-reservation left
// a header-only, mostly-empty page 1 for ordinary findings — worse once a logo
// also reserves space (#1198) — while UNDER-reserving for fat headers, whose
// first section then overflowed. So the cost is now computed from the spec, each
// term measured at the reference width against the live `_FindingPreview` and
// pinned by `finding_header_cost_test.dart`.

/// Line-units per wrapped heading line.
const double _headingLineCost = 1.35;

/// Heading characters per line. The CVSS score card (right) narrows the text
/// column, so the heading wraps sooner when a score is shown.
const double _headingCharsPerLine = 22.0;
const double _headingCharsPerLineWithScore = 16.0;

/// The scope row (`my_location` icon + object) when present.
const double _scopeRowCost = 1.7;

/// One row of identity badges; chips wrap ~2.5 to a row at this width.
const double _badgeRowCost = 2.1;
const double _badgeChipsPerRow = 2.5;

/// The CVSS score card: a fixed-height block on the right. The header is as tall
/// as the taller of its two columns, so a score sets a floor on the height.
const double _scoreCardCost = 5.9;

/// The card's own vertical padding, present regardless of content.
const double _headerPadCost = 2.5;

/// Whether the finding renders its identity badge row. Mirrors `_hasBadges` in
/// `finding_preview.dart`: a MASWE id alone does not open the row (it rides
/// alongside another badge), so it must not, alone, add badge height here.
bool _hasIdentityBadges(FindingSpec spec) =>
    spec.cvss != null ||
    spec.cweId != null ||
    spec.cveIds.isNotEmpty ||
    spec.testId.isNotEmpty ||
    spec.retest.isRetested;

/// The number of visible identity chips (see `_badges` in `finding_preview.dart`).
int _badgeChipCount(FindingSpec spec) {
  if (!_hasIdentityBadges(spec)) return 0;
  return (spec.cweId != null ? 1 : 0) +
      (spec.masweId.isNotEmpty ? 1 : 0) +
      spec.cveIds.length +
      (spec.testId.isNotEmpty ? 1 : 0) +
      (spec.retest.isRetested ? 1 : 0);
}

/// The finding header card's height in line-units, from its identity content.
/// Grounded on the live render; see the calibration block above and #1198.
double _headerCardCost(FindingSpec spec) {
  final hasScore = spec.cvss != null;
  final charsPerLine = hasScore
      ? _headingCharsPerLineWithScore
      : _headingCharsPerLine;
  final headingLines = spec.heading.isEmpty
      ? 0
      : (spec.heading.length / charsPerLine).ceil();
  var leftColumn = headingLines * _headingLineCost;
  if (spec.scopeObject.isNotEmpty) leftColumn += _scopeRowCost;
  final chips = _badgeChipCount(spec);
  if (chips > 0) {
    leftColumn += (chips / _badgeChipsPerRow).ceil() * _badgeRowCost;
  }
  final rightColumn = hasScore ? _scoreCardCost : 0.0;
  return _headerPadCost + (leftColumn > rightColumn ? leftColumn : rightColumn);
}

/// The modelled header-card cost in line-units, exposed so a real-render test can
/// pin the model against the live `_FindingPreview` (see #1198). Not for
/// production use — pagination reads [_headerCardCost] directly.
@visibleForTesting
double debugHeaderCardCost(FindingSpec spec) => _headerCardCost(spec);

/// One full-size body line holds this many characters at the reference width.
const double _charsPerLine = 47.0;

/// The lowest render scale at which a finding is still left on one slide. A
/// finding whose content fits [_linesPerSlide] / this ratio stays single: it
/// renders at ≥ this fraction of full width, which reads as (near-)full and is
/// not worth spending extra slides on. Below it a finding shrinks far enough to
/// look broken (F-01 rendered at ~0.3), so it is paginated. Derived from the
/// (possibly logo-reduced) per-page budget rather than a fixed constant, so a
/// logo — which lowers the budget — also lowers the split threshold.
const double _minSinglePageScale = 0.70;

/// Estimated line-cost of a section's body text, honouring hard line breaks.
double _bodyCost(String text) {
  final trimmed = text.trim();
  if (trimmed.isEmpty) return 0;
  var lines = 0.0;
  for (final paragraph in trimmed.split('\n')) {
    lines += (paragraph.length / _charsPerLine).ceilToDouble().clamp(1, 999);
  }
  return lines;
}

double _sectionCost(FindingSpec spec, _Section s) {
  final text = switch (s) {
    _Section.description => spec.description,
    _Section.confirmation => spec.confirmation,
    _Section.impact => spec.impact,
    _Section.recommendation => spec.recommendation,
  };
  if (text.trim().isEmpty) return 0;
  return _sectionHeadingCost + _bodyCost(text);
}

/// A finding restricted to [keep]'s sections (the others blanked). Continuation
/// pages ([isFirst] false) also drop the header meta and mark the heading.
FindingSpec _page(
  FindingSpec spec,
  Set<_Section> keep, {
  required bool isFirst,
  required int pageNumber,
  required int pageCount,
}) {
  String sec(_Section s, String text) => keep.contains(s) ? text : '';
  final marker = pageCount > 1 ? ' ($pageNumber/$pageCount)' : '';
  return FindingSpec(
    heading: spec.heading.isEmpty ? '' : '${spec.heading}$marker',
    scopeObject: isFirst ? spec.scopeObject : '',
    cvssVector: isFirst ? spec.cvssVector : '',
    cweId: isFirst ? spec.cweId : null,
    cweName: isFirst ? spec.cweName : '',
    // Deze vier ontbraken hier volledig — óók op pagina één. Een bevinding die
    // lang genoeg is om te paginëren verloor daarmee zijn MASWE-nummer, zijn
    // testverwijzing en de hertest-uitkomst uit élke weergave. Dat laatste is in
    // een opgeleverd rapport het verschil tussen "opgelost" en niets.
    // Net als de andere identiteitsvelden horen ze bij de eerste pagina: het is
    // de kop van de bevinding, niet iets dat per pagina herhaald hoort te worden.
    masweId: isFirst ? spec.masweId : '',
    retest: isFirst ? spec.retest : RetestStatus.notRetested,
    retestNote: isFirst ? spec.retestNote : '',
    testId: isFirst ? spec.testId : '',
    cveIds: isFirst ? spec.cveIds : const [],
    description: sec(_Section.description, spec.description),
    confirmation: sec(_Section.confirmation, spec.confirmation),
    impact: sec(_Section.impact, spec.impact),
    recommendation: sec(_Section.recommendation, spec.recommendation),
  );
}

/// Split [spec] into the finding pages that render at full size. Returns a
/// single-element list (equal to [spec]) when it already fits one slide.
///
/// [linesPerSlide] is the body-line budget per page; it is reduced by the
/// caller when a logo reserves vertical space (see [expandFindingsForRender]).
List<FindingSpec> paginateFinding(
  FindingSpec spec, {
  double linesPerSlide = _linesPerSlide,
}) {
  final present = [
    for (final s in _Section.values)
      if (_sectionCost(spec, s) > 0) s,
  ];
  if (present.isEmpty) return [spec];

  // A finding that renders close enough to full width already: leave it whole
  // rather than trade a small width gain for extra slides.
  final total =
      _headerCardCost(spec) +
      present.fold<double>(0, (a, s) => a + _sectionCost(spec, s));
  final pageCapacity = linesPerSlide / _minSinglePageScale;
  if (total <= pageCapacity) return [spec];

  // Page 1 carries the header card plus the FIRST section — placed
  // unconditionally, so an overflowing finding never renders a header-only,
  // mostly-empty page 1 (#1198). The header card is a tall fixed block whose
  // height varies with the finding's identity content (see [_headerCardCost]);
  // rather than pack further sections down toward the readability floor beneath
  // it — where a list-heavy section can render smaller than its line-cost
  // predicts — page 1 deliberately stops at the first section, which measures
  // comfortably above the floor even with a logo. The remaining sections greedily
  // fill continuation pages (no header card, only the repeated heading), which
  // may hold several related sections each. A single-section finding cannot be
  // split, so it is returned whole (and scaled) rather than stranding its header.
  final pages = <List<_Section>>[
    [present.first],
  ];
  var current = <_Section>[];
  var budget = pageCapacity - _contHeadingCost;
  for (final s in present.skip(1)) {
    final cost = _sectionCost(spec, s);
    if (cost > budget && current.isNotEmpty) {
      // A section that on its own overflows a page still gets its own page (it
      // renders slightly scaled rather than being dropped), but never shares an
      // already-full page.
      pages.add(current);
      current = <_Section>[];
      budget = pageCapacity - _contHeadingCost;
    }
    current.add(s);
    budget -= cost;
  }
  if (current.isNotEmpty) pages.add(current);
  if (pages.length <= 1) return [spec];

  return [
    for (var i = 0; i < pages.length; i++)
      _page(
        spec,
        pages[i].toSet(),
        isFirst: i == 0,
        pageNumber: i + 1,
        pageCount: pages.length,
      ),
  ];
}

/// Expand a deck's slides for rendering: each overflowing `finding` header slide
/// becomes several page-slides (via [paginateFinding]); every other slide — and
/// a finding that fits one slide — passes through unchanged. Detail/evidence
/// slides of a finding group are not the header and pass through as-is.
///
/// When [profile] is given and a finding slide shows its logo, the per-page
/// line budget is reduced proportionally to the logo's vertical reserve — so a
/// finding that fits without a logo still splits when the logo eats into the
/// available height, instead of overflowing under it.
List<Slide> expandFindingsForRender(
  List<Slide> slides, {
  ThemeProfile? profile,
}) {
  final out = <Slide>[];
  for (final slide in slides) {
    if (slide.type == SlideType.finding &&
        slide.findingRole == FindingRole.header) {
      final linesPerSlide = _linesPerSlideFor(slide, profile);
      final pages = paginateFinding(
        FindingSpec.parse(slide.customMarkdown),
        linesPerSlide: linesPerSlide,
      );
      if (pages.length <= 1) {
        out.add(slide);
      } else {
        for (final page in pages) {
          // Omit the blanked sections: a continuation page holds one section, and
          // the Marp/HTML export renders the Markdown verbatim (unlike the Flutter
          // preview, which skips empty `##` blocks) — leaving them in printed
          // three empty section headings under each page.
          out.add(
            slide.copyWith(
              customMarkdown: page.toMarkdown(omitEmptySections: true),
            ),
          );
        }
      }
    } else {
      out.add(slide);
    }
  }
  return out;
}

/// The [FindingSpec] a **single-slide** preview should render for [slide]: the
/// first render page when the finding overflows one slide, otherwise the finding
/// whole. Thumbnails and the in-editor live preview render exactly one slide and
/// never run [expandFindingsForRender] (that expands a whole deck), so without
/// this an overflowing finding is scaled down *uniformly* by the
/// `_PreviewScaffold` [FittedBox] — which shrinks it in width too, until the
/// header card uses only a fraction of the slide (#1147). Returning page 1 makes
/// those previews match the paged main preview, the presenter and the export, at
/// full width.
///
/// A finding that already fits one slide — including a page-slide produced by
/// [expandFindingsForRender] — is returned unchanged, so this is a no-op on the
/// paths that already paginate.
FindingSpec firstRenderPageSpec(Slide slide, {ThemeProfile? profile}) {
  final spec = FindingSpec.parse(slide.customMarkdown);
  // Already a render page? A page produced by [expandFindingsForRender] (the
  // presenter, the export, the paged main preview) carries the "(i/N)" marker
  // and has no header card on its continuations. Re-paginating it would charge
  // the header-card budget to a page that has none and split it again into a
  // mangled, double-marked page — so leave any already-paginated page verbatim
  // and only split an un-split source finding.
  if (findingPageMarker.hasMatch(spec.heading)) return spec;
  return paginateFinding(
    spec,
    linesPerSlide: _linesPerSlideFor(slide, profile),
  ).first;
}

/// The per-page line budget for [slide], reduced when a shown logo reserves
/// vertical space. Without a profile or logo, this is just [_linesPerSlide].
double _linesPerSlideFor(Slide slide, ThemeProfile? profile) {
  if (profile == null || !slide.showLogo) return _linesPerSlide;
  final reserve = logoSafeReserve(kReferenceSlideWidth, profile);
  if (reserve <= 0) return _linesPerSlide;
  final slideH = kReferenceSlideWidth * 9 / 16;
  return _linesPerSlide * (slideH - reserve) / slideH;
}
