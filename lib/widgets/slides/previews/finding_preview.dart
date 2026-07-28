// Part of the slide_preview library — see ../slide_preview.dart.
// Split out for navigability; all imports live in the main library file.
part of '../slide_preview.dart';

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

  const _FindingPreview({
    required this.slide,
    required this.w,
    required this.font,
    required this.profile,
    this.scopeCia = const {},
    this.reportLanguage = '',
  });

  @override
  Widget build(BuildContext context) {
    final pad = w * 0.07; // vertical margin
    // Narrower side margin so MIAUW slides use the width better (feedback):
    // content becomes ~0.91·w instead of 0.86·w, fewer findings spill to a
    // second page.
    final hPad = w * 0.045;
    final spec = FindingSpec.parse(slide.customMarkdown);
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

    return _PreviewScaffold(
      width: w,
      slide: slide,
      profile: profile,
      horizontalPadding: hPad,
      verticalPadding: pad,
      children: [
        if (continuation)
          _continuationHeading(spec)
        else ...[
          _headerCard(context, spec, severityColor, ctxCvss),
          SizedBox(height: w * 0.03),
        ],
        ..._sectionBlocks(context, spec),
      ],
    );
  }

  /// The "(i/N)" page marker that [paginateFinding] appends to a split finding's
  /// heading — the only place it is ever added.
  static final RegExp _pageMarker = RegExp(r'\(\d+/\d+\)\s*$');

  /// Whether this page is a paginated *continuation*: it carries the page marker
  /// but no header meta (that all lives on page 1). Page 1 of a split finding
  /// also carries the marker, but keeps its meta, so it is not matched here.
  bool _isContinuationPage(FindingSpec spec) =>
      _pageMarker.hasMatch(spec.heading) &&
      !_hasBadges(spec) &&
      spec.scopeObject.isEmpty;

  /// A continuation page's heading: the same title (with its "(i/N)" marker), as
  /// a plain line rather than the severity card, so the section below it uses the
  /// full slide width.
  Widget _continuationHeading(FindingSpec spec) {
    return Padding(
      padding: EdgeInsets.only(bottom: w * 0.025),
      child: Text(
        spec.heading,
        style: _applyFont(
          font,
          TextStyle(
            fontSize: w * 0.032,
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
  ) {
    return Container(
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
                  _badges(context, spec, ctxCvss),
                  SizedBox(height: w * 0.02),
                ],
                if (spec.heading.isNotEmpty)
                  Text(
                    spec.heading,
                    style: _applyFont(
                      font,
                      TextStyle(
                        fontSize: w * 0.038,
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
                              fontSize: w * 0.024,
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
          _severityGauge(spec, ctxCvss),
        ],
      ),
    );
  }

  /// A compact cockpit speedometer for the finding's effective CVSS score
  /// (feedback #3): the context score when the scope object is rated, else the
  /// base score. Empty when there is no valid vector. Colours are deterministic
  /// (profile + fixed AppTheme severity colours) so it renders identically in an
  /// export isolate, like the badges.
  Widget _severityGauge(FindingSpec spec, Cvss4? ctxCvss) {
    final cvss = ctxCvss ?? spec.cvss;
    if (cvss == null) return const SizedBox.shrink();
    final meter = CockpitMeterSpec(
      type: CockpitMeterType.speedometer,
      label: 'CVSS',
      unit: '',
      min: 0,
      max: 10,
      greenFrom: 0,
      greenTo: 4,
      redFrom: 7,
      value: cvss.score,
    );
    final textColor = AppTheme.parseHexColor(profile.textColor);
    return Padding(
      padding: EdgeInsets.only(left: w * 0.02),
      child: SizedBox(
        width: w * 0.16,
        height: w * 0.16,
        child: _CockpitInstrument(
          meter: meter,
          progress: 1,
          accent: AppTheme.parseHexColor(profile.accentColor),
          surface: AppTheme.parseHexColor(profile.slideBackgroundColor),
          textColor: textColor,
          mutedColor: textColor.withValues(alpha: 0.62),
          good: AppTheme.success700,
          warning: AppTheme.amber500,
          critical: AppTheme.danger600,
          cold: AppTheme.success700,
          sky: AppTheme.slideRule,
          ground: AppTheme.slideInkSoft,
          font: font,
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

  Widget _badges(BuildContext context, FindingSpec spec, Cvss4? ctxCvss) {
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
          // The CIA-weighted context score leads (it is the "correct" score),
          // with the base score alongside for transparency.
          _filledBadge(badge(l10n.d('Context'), ctxCvss), band(ctxCvss)),
          _filledBadge(badge(l10n.d('Basis'), base), band(base)),
        ] else if (base != null)
          _filledBadge(
            '${base.score.toStringAsFixed(1)} · ${base.severity.label}',
            band(base),
          ),
        if (spec.cweId != null) _outlinedChip('${l10n.d('CWE')}-${spec.cweId}'),
        // MASWE naast CWE, niet in plaats van: een mobiele bevinding hoort in
        // beide talen leesbaar te zijn, en de zwakheid verwijst zelf ook naar
        // een CWE.
        if (spec.masweId.isNotEmpty) _outlinedChip(spec.masweId),
        for (final cve in spec.cveIds) _outlinedChip(cve),
        if (spec.testId.isNotEmpty) _outlinedChip(spec.testId),
        if (spec.retest.isRetested)
          _filledBadge(
            '${l10n.d(spec.retest.dutchLabel)} ${l10n.d('na hertest')}',
            spec.retest.isResolved ? AppTheme.success700 : AppTheme.amber700,
          ),
      ],
    );
  }

  Widget _filledBadge(String text, Color color) {
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
            fontSize: w * 0.024,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }

  Widget _outlinedChip(String text) {
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
            fontSize: w * 0.022,
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
  List<Widget> _sectionBlocks(BuildContext context, FindingSpec spec) {
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
    );
  }
}
