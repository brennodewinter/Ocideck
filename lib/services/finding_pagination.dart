/// Render-time pagination for `finding` slides (PENTEST_MIAUW §3.1). A finding is
/// edited as ONE slide, but when its prose is too long for a single slide it is
/// **rendered** across several — so the text stays full-size and full-width
/// instead of shrinking to fit. This is a pure, deck-non-mutating transform: the
/// `.md` on disk is unchanged; only what the preview/presenter/export enumerate
/// changes.
///
/// Page 1 keeps the header card (severity badge, heading, scope) and fills its
/// remaining room with as many whole sections as stay comfortably readable.
/// Each continuation page repeats the heading with a small "(i/N)" marker,
/// drops the header card, and greedily fills the freed space with the next whole
/// sections. A finding that fits one slide is returned unchanged (a single
/// page).
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

/// The historical header-budget model, in body-line units. It remains as a
/// calibration seam for the live header-card test; pagination now uses
/// [findingHeaderFitScale], the same content measurement as the preview.
///
/// The numbers below are **measured** against the live `_FindingPreview` at
/// `SlidePreviewWidget` — a 16:9 slide, no logo — not eyeballed. The compact CVSS
/// score card leaves enough room for a normal first section below the finding
/// header.
///
/// The previous calibration still described the removed cockpit-style CVSS
/// meter. It reserved more than a page for the header and nearly a page for a
/// continuation heading, producing five sparse pages for content that renders
/// legibly on three. These values are calibrated against that real fixture.
///

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

/// Line-units per wrapped heading line. The identity card uses the compact
/// `kFindingHeaderTypeScale`, so its title is about one body line tall.
const double _headingLineCost = 0.9;

/// Heading characters per line. The CVSS score card (right) narrows the text
/// column, so the heading wraps sooner when a score is shown.
const double _headingCharsPerLine = 33.0;
const double _headingCharsPerLineWithScore = 24.0;

/// The scope row (`my_location` icon + object) when present.
const double _scopeRowCost = 1.7;

/// One row of compact identity badges; about 3.5 fit at this width.
const double _badgeRowCost = 1.75;
const double _badgeChipsPerRow = 3.5;

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
/// pin the historical model against the live `_FindingPreview` (see #1198).
@visibleForTesting
double debugHeaderCardCost(FindingSpec spec) => _headerCardCost(spec);

/// The lowest render scale at which a finding is still left on one slide. A
/// measured finding at or above this multiplier stays single: a modest shrink
/// is not worth spending another slide on. Below it, pagination wins over type
/// that becomes too small at presentation distance.
const double _minSinglePageScale = 0.80;

/// Use the same readability floor while greedily filling paginated pages, so a
/// split never creates an extra continuation that the single-page rule itself
/// considers avoidable.
const double _pagedReadableScale = 0.80;

String _sectionText(FindingSpec spec, _Section s) => switch (s) {
  _Section.description => spec.description,
  _Section.confirmation => spec.confirmation,
  _Section.impact => spec.impact,
  _Section.recommendation => spec.recommendation,
};

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
    // Het kopniveau hoort bij élke pagina, niet alleen de eerste: een
    // vervolgpagina die op `#` terugvalt terwijl de bron `###` zei, verschuift
    // de blokgrens en slokt de rest van het hoofdstuk op. Zelfde les als de
    // vier velden hierboven, en de compiler noemt hem net zo min.
    level: spec.level,
  );
}

/// Split [spec] into the finding pages that render at full size. Returns a
/// single-element list (equal to [spec]) when it already fits one slide.
///
List<FindingSpec> paginateFinding(
  FindingSpec spec, {
  String font = 'Arial',
  double extraVReserve = 0,
}) {
  final present = [
    for (final s in _Section.values)
      if (_sectionText(spec, s).trim().isNotEmpty) s,
  ];
  if (present.isEmpty) return [spec];

  // A finding that renders close enough to full width already: leave it whole
  // rather than trade a small width gain for extra slides.
  if (findingHeaderFitScale(
        spec: spec,
        font: font,
        extraVReserve: extraVReserve,
      ) >=
      _minSinglePageScale) {
    return [spec];
  }

  // Greedily fill page 1 and its continuations using the exact same measured
  // fit as the preview. Sections stay whole and in authored order. A section
  // that cannot reach the floor by itself is still kept intact; splitting
  // authored prose mid-section would be less predictable than one dense page.
  final pages = <List<_Section>>[];
  var current = <_Section>[];
  for (final s in present) {
    final trial = [...current, s];
    final isFirst = pages.isEmpty;
    final candidate = _page(
      spec,
      trial.toSet(),
      isFirst: isFirst,
      pageNumber: isFirst ? 1 : 2,
      pageCount: 2,
    );
    final readable = findingHeaderFitScale(
      spec: candidate,
      font: font,
      continuation: !isFirst,
      extraVReserve: extraVReserve,
    );
    if (readable < _pagedReadableScale && current.isNotEmpty) {
      pages.add(current);
      current = [s];
    } else {
      current = trial;
    }
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
/// When [profile] is given, pagination measures with its font and reserves the
/// shown logo's actual vertical strip, matching the preview.
List<Slide> expandFindingsForRender(
  List<Slide> slides, {
  ThemeProfile? profile,
}) {
  final out = <Slide>[];
  for (final slide in slides) {
    if (slide.type == SlideType.finding &&
        slide.findingRole == FindingRole.header) {
      final metrics = _findingRenderMetrics(slide, profile);
      final pages = paginateFinding(
        FindingSpec.parse(slide.customMarkdown),
        font: metrics.font,
        extraVReserve: metrics.extraVReserve,
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
  final metrics = _findingRenderMetrics(slide, profile);
  return paginateFinding(
    spec,
    font: metrics.font,
    extraVReserve: metrics.extraVReserve,
  ).first;
}

({String font, double extraVReserve}) _findingRenderMetrics(
  Slide slide,
  ThemeProfile? profile,
) {
  final font = profile?.fontFamily ?? 'Arial';
  if (profile == null || !slide.showLogo) {
    return (font: font, extraVReserve: 0);
  }
  final reserve = logoSafeReserve(kReferenceSlideWidth, profile, corner: true);
  return (font: font, extraVReserve: reserve);
}
