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
  static final RegExp _pageMarker = RegExp(r'\((\d+)/\d+\)\s*$');

  /// Whether this page is a paginated *continuation*. The page number is the
  /// authority: page 1 must keep the finding card even when an author supplied
  /// no CVSS, scope or other metadata.
  bool _isContinuationPage(FindingSpec spec) {
    final marker = _pageMarker.firstMatch(spec.heading);
    return marker != null && int.tryParse(marker.group(1) ?? '') != 1;
  }

  /// A continuation page's heading: the same title (with its "(i/N)" marker), as
  /// a plain line rather than the severity card, so the section below it uses the
  /// full slide width.
  Widget _continuationHeading(FindingSpec spec) {
    return Padding(
      key: const ValueKey('finding-continuation-heading'),
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
          _severityScoreCard(context, spec, ctxCvss, severity),
        ],
      ),
    );
  }

  /// De effectieve CVSS-score als rustige typografische kaart. De oude
  /// cockpitmeter schilderde de waarde in een wijzerplaat en herhaalde daarmee
  /// de scorebadge; gewone widgettekst blijft ook op kleine previews leesbaar en
  /// toegankelijk voor hulptechnologie (#1059).
  Widget _severityScoreCard(
    BuildContext context,
    FindingSpec spec,
    Cvss4? ctxCvss,
    Color severity,
  ) {
    final cvss = ctxCvss ?? spec.cvss;
    if (cvss == null) return const SizedBox.shrink();
    final textColor = AppTheme.parseHexColor(profile.textColor);
    return Padding(
      padding: EdgeInsets.only(left: w * 0.02),
      child: Container(
        key: const ValueKey('finding-cvss-score-card'),
        width: w * 0.15,
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
                  fontSize: w * 0.018,
                  fontWeight: FontWeight.w700,
                  letterSpacing: w * 0.0015,
                ),
              ),
            ),
            SizedBox(height: w * 0.004),
            Text(
              cvss.score.toStringAsFixed(1),
              style: _applyFont(
                font,
                TextStyle(
                  color: textColor,
                  fontSize: w * 0.052,
                  fontWeight: FontWeight.w800,
                  height: 1,
                ),
              ),
            ),
            SizedBox(height: w * 0.008),
            Container(
              width: w * 0.032,
              height: w * 0.005,
              decoration: BoxDecoration(
                color: severity,
                borderRadius: BorderRadius.circular(w * 0.003),
              ),
            ),
            SizedBox(height: w * 0.008),
            Text(
              cvss.severity.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: _applyFont(
                font,
                TextStyle(
                  color: textColor,
                  fontSize: w * 0.021,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
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
          // De contextscore staat al als primaire scorekaart rechts. Alleen de
          // basisscore blijft hier ter vergelijking staan, zonder verdubbeling.
          _filledBadge(badge(l10n.d('Basis'), base), band(base)),
        ],
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
