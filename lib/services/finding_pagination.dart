/// Render-time pagination for `finding` slides (PENTEST_MIAUW §3.1). A finding is
/// edited as ONE slide, but when its prose is too long for a single slide it is
/// **rendered** across several — so the text stays full-size and full-width
/// instead of shrinking to fit. This is a pure, deck-non-mutating transform: the
/// `.md` on disk is unchanged; only what the preview/presenter/export enumerate
/// changes.
///
/// Page 1 keeps the header card (severity badge, heading, scope) plus the
/// sections that fit; each continuation page repeats the heading with a small
/// "(i/N)" marker, drops the header card, and holds the next sections. A finding
/// that fits one slide is returned unchanged (a single page).
library;

import '../models/finding_spec.dart';
import '../models/settings.dart';
import '../models/slide.dart';
import 'rich_text_layout.dart';
import 'slide_layout_metrics.dart';

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
/// slide is [_linesPerSlide] line-units tall; the header card (severity band,
/// CVSS gauge, wrapping heading, badges, scope) already spends [_headerCardCost]
/// of them — *more than a whole slide* — which is why a paginated finding gets a
/// header-only first page: nothing else fits beside it. A continuation page keeps
/// the heading (its "(i/N)" marker) but drops the meta, costing [_contHeadingCost].
/// A section adds [_sectionHeadingCost] for its `##` heading plus one unit per
/// wrapped body line at [_charsPerLine] characters each.
///
/// The earlier values (22 / 4 / 1.4 / 94) modelled a slide holding ~22 body
/// lines with a 4-line header. The real header is ~4× that, so nearly every
/// multi-section finding overflowed yet the model thought it fit — it never
/// split, and shrank to a third of the width instead. These are calibrated so a
/// genuinely overflowing finding splits into (near-)full-width pages while one
/// that already renders close to full width ([_minSinglePageScale]) stays single.
const double _linesPerSlide = 19.5;
const double _headerCardCost = 21.7;
const double _contHeadingCost = 11.9;
const double _sectionHeadingCost = 3.1;
const double _charsPerLine = 40.0;

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
      _headerCardCost +
      present.fold<double>(0, (a, s) => a + _sectionCost(spec, s));
  if (total <= linesPerSlide / _minSinglePageScale) return [spec];

  // Greedy pack. Page 1 carries the header card, whose cost alone exceeds a
  // slide — so its section budget is negative and it ends up header-only, the
  // sections starting on page 2. Continuation pages carry the (meta-less)
  // heading, so they too reserve room before any section. A section that on its
  // own overflows a page still gets its own page (it renders slightly scaled
  // rather than being dropped), but never shares an already-full page.
  final pages = <List<_Section>>[];
  var current = <_Section>[];
  var isFirstPage = true;
  var budget = linesPerSlide - _headerCardCost;
  for (final s in present) {
    final cost = _sectionCost(spec, s);
    if (cost > budget && (current.isNotEmpty || isFirstPage)) {
      pages.add(current); // page 1 may be empty here → a header-only page
      current = <_Section>[];
      isFirstPage = false;
      budget = linesPerSlide - _contHeadingCost;
    }
    current.add(s);
    budget -= cost;
  }
  pages.add(current);
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

/// The per-page line budget for [slide], reduced when a shown logo reserves
/// vertical space. Without a profile or logo, this is just [_linesPerSlide].
double _linesPerSlideFor(Slide slide, ThemeProfile? profile) {
  if (profile == null || !slide.showLogo) return _linesPerSlide;
  final reserve = logoSafeReserve(kReferenceSlideWidth, profile);
  if (reserve <= 0) return _linesPerSlide;
  final slideH = kReferenceSlideWidth * 9 / 16;
  return _linesPerSlide * (slideH - reserve) / slideH;
}
