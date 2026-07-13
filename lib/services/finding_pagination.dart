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
import '../models/slide.dart';

/// A finding section, in the fixed §3.1 order.
enum _Section { description, confirmation, impact, recommendation }

/// Estimated full-size body lines that fit on one 16:9 slide, and the cost (in
/// those line-units) of the header card and a section heading. Deliberately
/// conservative so a page never overflows back into the shrinking regime; tuned
/// against the live finding preview.
const double _linesPerSlide = 11.0;
const double _headerCardCost = 4.5;
const double _sectionHeadingCost = 1.6;
const double _charsPerLine = 62.0;

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
    cveIds: isFirst ? spec.cveIds : const [],
    description: sec(_Section.description, spec.description),
    confirmation: sec(_Section.confirmation, spec.confirmation),
    impact: sec(_Section.impact, spec.impact),
    recommendation: sec(_Section.recommendation, spec.recommendation),
  );
}

/// Split [spec] into the finding pages that render at full size. Returns a
/// single-element list (equal to [spec]) when it already fits one slide.
List<FindingSpec> paginateFinding(FindingSpec spec) {
  final present = [
    for (final s in _Section.values)
      if (_sectionCost(spec, s) > 0) s,
  ];
  if (present.isEmpty) return [spec];

  // Greedy pack: fill each page up to its budget, header card only on page 1.
  final pages = <List<_Section>>[];
  var current = <_Section>[];
  var budget = _linesPerSlide - _headerCardCost;
  for (final s in present) {
    final cost = _sectionCost(spec, s);
    if (current.isNotEmpty && cost > budget) {
      pages.add(current);
      current = <_Section>[];
      budget = _linesPerSlide; // continuation pages have no header card
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
List<Slide> expandFindingsForRender(List<Slide> slides) {
  final out = <Slide>[];
  for (final slide in slides) {
    if (slide.type == SlideType.finding &&
        slide.findingRole == FindingRole.header) {
      final pages = paginateFinding(FindingSpec.parse(slide.customMarkdown));
      if (pages.length <= 1) {
        out.add(slide);
      } else {
        for (final page in pages) {
          out.add(slide.copyWith(customMarkdown: page.toMarkdown()));
        }
      }
    } else {
      out.add(slide);
    }
  }
  return out;
}
