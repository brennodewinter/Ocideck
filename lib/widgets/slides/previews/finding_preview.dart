// Part of the slide_preview library — see ../slide_preview.dart.
// Split out for navigability; all imports live in the main library file.
part of '../slide_preview.dart';

/// Preview for a `finding` header slide (PENTEST_MIAUW §3.1, §11): a
/// severity-coloured header card — heading, CVSS score/severity badge, CWE/CVE
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

  const _FindingPreview({
    required this.slide,
    required this.w,
    required this.font,
    required this.profile,
    this.scopeCia = const {},
  });

  @override
  Widget build(BuildContext context) {
    final pad = w * 0.07; // vertical margin
    // Narrower side margin so MIAUW slides use the width better (feedback):
    // content becomes ~0.91·w instead of 0.86·w, fewer findings spill to a
    // second page.
    final hPad = w * 0.045;
    final safe = slide.showLogo ? _logoSafeInsets(w, profile) : EdgeInsets.zero;
    final spec = FindingSpec.parse(slide.customMarkdown);
    // The context (environmental) score when the scope object is rated; the
    // header card and its primary badge then track the CIA-weighted severity.
    final ctxCvss = findingContextCvss(spec, scopeCia);
    final severityColor = FindingSeverityPalette.of(
      (ctxCvss ?? spec.cvss)?.severity,
      profile: profile,
    );

    return Container(
      color: Colors.white,
      child: SizedBox.expand(
        child: FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: w,
            child: Padding(
              padding: EdgeInsets.fromLTRB(
                hPad,
                pad + safe.top,
                hPad,
                _logoAwareBottomPadding(pad, safe.bottom),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  _headerCard(context, spec, severityColor, ctxCvss),
                  SizedBox(height: w * 0.03),
                  ..._sectionBlocks(context, spec),
                ],
              ),
            ),
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
      width: w,
      padding: EdgeInsets.all(w * 0.03),
      decoration: BoxDecoration(
        color: severity.withValues(alpha: 0.06),
        border: Border(
          left: BorderSide(color: severity, width: w * 0.01),
        ),
        borderRadius: BorderRadius.circular(w * 0.012),
      ),
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
                  color: AppTheme.slate500,
                ),
                SizedBox(width: w * 0.01),
                Flexible(
                  child: Text(
                    spec.scopeObject,
                    style: _applyFont(
                      font,
                      TextStyle(fontSize: w * 0.024, color: AppTheme.slate700),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
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
        if (spec.cweId != null) _outlinedChip('CWE-${spec.cweId}'),
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
        border: Border.all(color: AppTheme.slate300),
        borderRadius: BorderRadius.circular(w * 0.008),
      ),
      child: Text(
        text,
        style: _applyFont(
          font,
          TextStyle(
            fontSize: w * 0.022,
            fontWeight: FontWeight.w600,
            color: AppTheme.slate600,
          ),
        ),
      ),
    );
  }

  /// The finding's prose sections, in §3.1 order. Only sections with content are
  /// shown, so a half-filled finding stays clean; the section headings are the
  /// same stable English anchors the Markdown carries.
  List<Widget> _sectionBlocks(BuildContext context, FindingSpec spec) {
    final buf = StringBuffer();
    void add(String title, String body) {
      if (body.trim().isEmpty) return;
      buf.writeln('## $title');
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
