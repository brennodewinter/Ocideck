// Part of the slide_preview library — see ../slide_preview.dart.
// Split out for navigability; all imports live in the main library file.
part of '../slide_preview.dart';

/// A calm, uniform down-scale for the finding slide's type sizes. Since the
/// width fix (#1147/#1152) a finding renders at full slide width, so its
/// `w`-relative fonts landed at their true — and, for a dense pentest finding,
/// unnecessarily large — size. This factor shrinks every finding font in step
/// (headers, body, CVSS card, chips) so more content fits per page without
/// touching layout or the other slide types. The finding's page budget in
/// [paginateFinding] is calibrated against the same factor (#1163). It is the
/// *fixed* part; a content-aware fit ([findingHeaderFitScale]) multiplies it per
/// page so a dense header reflows smaller instead of rendering oversized (#1282).
const double _findingFontScale = kFindingBaseFontScale;

/// Preview for a `finding` header slide (PENTEST_MIAUW §3.1, §11): a
/// severity-coloured header card — heading, CVSS score/severity badge, CWE/MASWE/CVE
/// chips and the scope object — above the finding's prose sections. All content
/// comes from [FindingSpec.parse] over [Slide.customMarkdown]; the severity band
/// is derived from the CVSS vector, so it is deterministic and flows unchanged
/// through export. Colours come from [FindingSeverityPalette] (a local palette
/// until P1-THEME moves severity tokens into the theme profile).
class _FindingPreview extends StatelessWidget {
  final Slide slide;
  final double w;
  final String font;
  final ThemeProfile profile;
  final Map<String, CiaRating> scopeCia;

  /// The report's language (see [SlidePreviewWidget.reportLanguage]).
  final String reportLanguage;

  /// A fixed type multiplier that bypasses the content-aware auto-fit (#1282).
  /// Null on every production path — a finding is not part of a split run — so
  /// the page normally sizes its own type. A test passes 1.0 to measure the
  /// finding at its natural (#1163) size, e.g. to pin the pagination model in
  /// `finding_header_cost_test.dart`.
  final double? fitScaleOverride;

  const _FindingPreview({
    required this.slide,
    required this.w,
    required this.font,
    required this.profile,
    this.scopeCia = const {},
    this.reportLanguage = '',
    this.fitScaleOverride,
  });

  @override
  Widget build(BuildContext context) {
    final pad = w * 0.07; // vertical margin
    // Narrower side margin so MIAUW slides use the width better (feedback):
    // content becomes ~0.91·w instead of 0.86·w, fewer findings spill to a
    // second page.
    final hPad = w * 0.045;
    // Render the finding's first page, not the raw (possibly overflowing) slide:
    // a too-tall finding would otherwise be scaled down uniformly by the
    // [FittedBox] below — shrinking in width until the header card fills a
    // fraction of the slide. The paged main preview, the presenter and the
    // export already pass single-page slides here (via expandFindingsForRender),
    // so this only changes the single-slide previews that didn't — the thumbnail
    // strip and the in-editor live preview (#1147).
    final spec = firstRenderPageSpec(slide, profile: profile);
    // The context (environmental) score when the scope object is rated; the
    // header card and its primary badge then track the CIA-weighted severity.
    final ctxCvss = findingContextCvss(spec, scopeCia);
    final severityColor = FindingSeverityPalette.of(
      (ctxCvss ?? spec.cvss)?.severity,
      profile: profile,
    );

    // A continuation page (produced by [paginateFinding]) carries the finding's
    // heading with an "(i/N)" marker but none of the meta — no CVSS, no scope,
    // no badges. Rendering the full severity card there would wrap a lone
    // heading in ~0.34·w of chrome, which is exactly what forced the page to
    // shrink; a plain heading lets the section fill the slide width. Page 1 keeps
    // its full card (it still has the meta), so the finding's own look is
    // unchanged — continuation pages simply never existed before pagination
    // started splitting overflowing findings.
    final continuation = _isContinuationPage(spec);

    // Content-aware type multiplier for THIS page (#1282): the fixed #1163
    // down-scale times a fit that reflows a dense header smaller and holds a
    // sparse one at the ceiling. Measured on the paginated page, so a finding
    // that legitimately spans slides still splits — this only sizes the type.
    final reserve = slide.showLogo
        ? logoSafeReserve(kReferenceSlideWidth, profile, corner: true)
        : 0.0;
    final fit =
        fitScaleOverride ??
        findingHeaderFitScale(
          spec: spec,
          font: font,
          continuation: continuation,
          extraVReserve: reserve,
        );
    final m = _findingFontScale * fit;
    final headerM = m * kFindingHeaderTypeScale;

    return _PreviewScaffold(
      width: w,
      slide: slide,
      profile: profile,
      horizontalPadding: hPad,
      verticalPadding: pad,
      children: [
        if (continuation)
          _continuationHeading(spec, m)
        else ...[
          _headerCard(context, spec, severityColor, ctxCvss, headerM),
          SizedBox(height: w * 0.03),
        ],
        ..._sectionBlocks(context, spec, m),
      ],
    );
  }

  /// Whether this page is a paginated *continuation*. The page number (from the
  /// shared [findingPageMarker]) is the authority: page 1 must keep the finding
  /// card even when an author supplied no CVSS, scope or other metadata.
  bool _isContinuationPage(FindingSpec spec) {
    final marker = findingPageMarker.firstMatch(spec.heading);
    return marker != null && int.tryParse(marker.group(1) ?? '') != 1;
  }

  /// A continuation page's heading: the same title (with its "(i/N)" marker), as
  /// a plain line rather than the severity card, so the section below it uses the
  /// full slide width.
  Widget _continuationHeading(FindingSpec spec, double m) {
    return Padding(
      key: const ValueKey('finding-continuation-heading'),
      padding: EdgeInsets.only(bottom: w * 0.02),
      child: Text(
        spec.heading,
        style: _applyFont(
          font,
          TextStyle(
            // About half the size of page 1's heading: a continuation page only
            // needs a compact "which finding, page i/N" reminder — the finding's
            // full identity lives on page 1 — so the previously large repeated
            // title just wasted half the slide on the finding's beginning
            // (#1198 follow-up).
            fontSize: w * 0.014 * m,
            fontWeight: FontWeight.w700,
            color: AppTheme.navy,
          ),
        ),
      ),
    );
  }

  Widget _headerCard(
    BuildContext context,
    FindingSpec spec,
    Color severity,
    Cvss4? ctxCvss,
    double m,
  ) {
    return Container(
      key: const ValueKey('finding-header-card'),
      padding: EdgeInsets.all(w * 0.03),
      decoration: BoxDecoration(
        color: severity.withValues(alpha: 0.06),
        border: Border(
          left: BorderSide(color: severity, width: w * 0.01),
        ),
        borderRadius: BorderRadius.circular(w * 0.012),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (_hasBadges(spec)) ...[
                  _badges(context, spec, ctxCvss, m),
                  SizedBox(height: w * 0.02),
                ],
                if (spec.heading.isNotEmpty)
                  Text(
                    spec.heading,
                    style: _applyFont(
                      font,
                      TextStyle(
                        fontSize: w * 0.038 * m,
                        fontWeight: FontWeight.w700,
                        color: AppTheme.navy,
                      ),
                    ),
                  ),
                if (spec.scopeObject.isNotEmpty) ...[
                  SizedBox(height: w * 0.015),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.my_location,
                        size: w * 0.024,
                        color: AppTheme.slideInkSoft,
                      ),
                      SizedBox(width: w * 0.01),
                      Flexible(
                        child: Text(
                          spec.scopeObject,
                          style: _applyFont(
                            font,
                            TextStyle(
                              fontSize: w * 0.024 * m,
                              color: AppTheme.slideInk,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
          _severityScoreCard(context, spec, ctxCvss, severity, m),
        ],
      ),
    );
  }

  /// De effectieve CVSS-score als leesbare tekst naast een rustige visuele
  /// schaal. De score staat bewust buiten de meter: zo blijft de waarde ook in
  /// de slidestrook leesbaar, terwijl de positie tussen 0 en 10 in één oogopslag
  /// zichtbaar blijft (#1059).
  Widget _severityScoreCard(
    BuildContext context,
    FindingSpec spec,
    Cvss4? ctxCvss,
    Color severity,
    double m,
  ) {
    final cvss = ctxCvss ?? spec.cvss;
    if (cvss == null) return const SizedBox.shrink();
    final textColor = AppTheme.parseHexColor(profile.textColor);
    return Padding(
      padding: EdgeInsets.only(left: w * 0.02),
      child: Container(
        key: const ValueKey('finding-cvss-score-card'),
        width: w * 0.21,
        padding: EdgeInsets.fromLTRB(
          w * 0.018,
          w * 0.014,
          w * 0.018,
          w * 0.016,
        ),
        decoration: BoxDecoration(
          color: severity.withValues(alpha: 0.09),
          border: Border.all(color: severity.withValues(alpha: 0.42)),
          borderRadius: BorderRadius.circular(w * 0.012),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              ctxCvss == null
                  ? context.l10n.d('CVSS')
                  : '${context.l10n.d('Context')} ${context.l10n.d('CVSS')}',
              maxLines: 1,
              style: _applyFont(
                font,
                TextStyle(
                  color: textColor.withValues(alpha: 0.68),
                  fontSize: w * 0.018 * m,
                  fontWeight: FontWeight.w700,
                  letterSpacing: w * 0.0015,
                ),
              ),
            ),
            SizedBox(height: w * 0.006),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  cvss.score.toStringAsFixed(1),
                  style: _applyFont(
                    font,
                    TextStyle(
                      color: textColor,
                      fontSize: w * 0.052 * m,
                      fontWeight: FontWeight.w800,
                      height: 1,
                    ),
                  ),
                ),
                SizedBox(width: w * 0.01),
                Expanded(
                  child: Padding(
                    padding: EdgeInsets.only(bottom: w * 0.004),
                    child: Text(
                      cvss.severity.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: _applyFont(
                        font,
                        TextStyle(
                          color: textColor,
                          fontSize: w * 0.021 * m,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
            SizedBox(height: w * 0.012),
            _cvssMeter(cvss, severity, textColor, context.l10n.d('CVSS')),
            SizedBox(height: w * 0.002),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _meterEndpoint('0', textColor, m),
                _meterEndpoint('10', textColor, m),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _cvssMeter(
    Cvss4 cvss,
    Color severity,
    Color textColor,
    String semanticsLabel,
  ) {
    final position = (cvss.score / 10).clamp(0.0, 1.0);
    final markerSize = w * 0.018;
    return Semantics(
      label: semanticsLabel,
      value: '${cvss.score.toStringAsFixed(1)} / 10 · ${cvss.severity.label}',
      child: ExcludeSemantics(
        child: SizedBox(
          key: const ValueKey('finding-cvss-meter'),
          height: markerSize,
          child: LayoutBuilder(
            builder: (context, constraints) {
              return Stack(
                alignment: Alignment.centerLeft,
                children: [
                  Container(
                    height: w * 0.008,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(w * 0.004),
                      gradient: LinearGradient(
                        colors: [
                          AppTheme.success700.withValues(alpha: 0.72),
                          AppTheme.success700.withValues(alpha: 0.72),
                          AppTheme.amber500.withValues(alpha: 0.78),
                          AppTheme.amber500.withValues(alpha: 0.78),
                          AppTheme.danger600.withValues(alpha: 0.82),
                          AppTheme.danger600.withValues(alpha: 0.82),
                        ],
                        stops: const [0, 0.39, 0.4, 0.69, 0.7, 1],
                      ),
                    ),
                  ),
                  Positioned(
                    left: (constraints.maxWidth * position - markerSize / 2)
                        .clamp(0.0, constraints.maxWidth - markerSize),
                    child: Container(
                      key: const ValueKey('finding-cvss-meter-marker'),
                      width: markerSize,
                      height: markerSize,
                      decoration: BoxDecoration(
                        color: severity,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: textColor.withValues(alpha: 0.95),
                          width: w * 0.0025,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: severity.withValues(alpha: 0.32),
                            blurRadius: w * 0.008,
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _meterEndpoint(String value, Color textColor, double m) {
    return Text(
      value,
      style: _applyFont(
        font,
        TextStyle(
          color: textColor.withValues(alpha: 0.58),
          fontSize: w * 0.014 * m,
          fontWeight: FontWeight.w600,
          height: 1,
        ),
      ),
    );
  }

  bool _hasBadges(FindingSpec spec) =>
      spec.cvss != null ||
      spec.cweId != null ||
      spec.cveIds.isNotEmpty ||
      spec.testId.isNotEmpty ||
      spec.retest.isRetested;

  Widget _badges(
    BuildContext context,
    FindingSpec spec,
    Cvss4? ctxCvss,
    double m,
  ) {
    final base = spec.cvss;
    final l10n = context.l10n;
    String badge(String label, Cvss4 cvss) =>
        '$label ${cvss.score.toStringAsFixed(1)} · ${cvss.severity.label}';
    Color band(Cvss4 cvss) =>
        FindingSeverityPalette.of(cvss.severity, profile: profile);
    return Wrap(
      spacing: w * 0.015,
      runSpacing: w * 0.012,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        if (base != null && ctxCvss != null) ...[
          // De contextscore staat al als primaire scorekaart rechts. Alleen de
          // basisscore blijft hier ter vergelijking staan, zonder verdubbeling.
          _filledBadge(badge(l10n.d('Basis'), base), band(base), m),
        ],
        if (spec.cweId != null)
          _outlinedChip('${l10n.d('CWE')}-${spec.cweId}', m),
        // MASWE naast CWE, niet in plaats van: een mobiele bevinding hoort in
        // beide talen leesbaar te zijn, en de zwakheid verwijst zelf ook naar
        // een CWE.
        if (spec.masweId.isNotEmpty) _outlinedChip(spec.masweId, m),
        for (final cve in spec.cveIds) _outlinedChip(cve, m),
        if (spec.testId.isNotEmpty) _outlinedChip(spec.testId, m),
        if (spec.retest.isRetested)
          _filledBadge(
            '${l10n.d(spec.retest.dutchLabel)} ${l10n.d('na hertest')}',
            spec.retest.isResolved ? AppTheme.success700 : AppTheme.amber700,
            m,
          ),
      ],
    );
  }

  Widget _filledBadge(String text, Color color, double m) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: w * 0.02, vertical: w * 0.008),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(w * 0.008),
      ),
      child: Text(
        text,
        style: _applyFont(
          font,
          TextStyle(
            color: Colors.white,
            fontSize: w * 0.024 * m,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }

  Widget _outlinedChip(String text, double m) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: w * 0.018, vertical: w * 0.006),
      decoration: BoxDecoration(
        border: Border.all(color: AppTheme.slideRule),
        borderRadius: BorderRadius.circular(w * 0.008),
      ),
      child: Text(
        text,
        style: _applyFont(
          font,
          TextStyle(
            fontSize: w * 0.022 * m,
            fontWeight: FontWeight.w600,
            color: AppTheme.slideInkMuted,
          ),
        ),
      ),
    );
  }

  /// The finding's prose sections, in §3.1 order. Only sections with content are
  /// shown, so a half-filled finding stays clean.
  ///
  /// The heading shown is resolved into the **report's** language while the
  /// Markdown keeps its stable English anchor (§12.3) — so a Dutch report reads
  /// "Beschrijving" while the file still says `## Description` and round-trips.
  /// This renders the deliverable: the rasterizer drives PDF/PPTX from these
  /// previews, so an unlocalised heading here reaches the client.
  List<Widget> _sectionBlocks(
    BuildContext context,
    FindingSpec spec,
    double m,
  ) {
    final buf = StringBuffer();
    void add(String anchor, String body) {
      if (body.trim().isEmpty) return;
      final heading = AppLocalizations.sourceFor(
        reportLanguage,
        FindingSpec.sectionSources[anchor] ?? anchor,
      );
      buf.writeln('## $heading');
      buf.writeln();
      buf.writeln(body.trim());
      buf.writeln();
    }

    add(FindingSpec.sectionDescription, spec.description);
    add(FindingSpec.sectionConfirmation, spec.confirmation);
    add(FindingSpec.sectionImpact, spec.impact);
    add(FindingSpec.sectionRecommendation, spec.recommendation);
    if (buf.isEmpty) return const [];
    return _markdownBodyBlocks(
      context,
      markdown: buf.toString(),
      w: w,
      font: font,
      profile: profile,
      headingColor: AppTheme.navy,
      // Shrink the prose and its `##` section headings in step with the header
      // card (#1163) and the per-page content fit (#1282), so a dense finding
      // reflows smaller. Defaults are w*0.024 (body) and w*0.03 (heading2).
      bodyFontSize: w * 0.024 * m,
      heading2Size: w * 0.03 * m,
    );
  }
}
