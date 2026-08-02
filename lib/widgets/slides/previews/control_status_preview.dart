// Part of the slide_preview library — see ../slide_preview.dart.
// Split out for navigability; all imports live in the main library file.
part of '../slide_preview.dart';

/// Preview for a `controlStatus` slide (ISO_MANAGEMENTSYSTEEM §3.1 / §4): the
/// section heading with a derived *implemented / applicable* progress bar, then
/// the controls as a table of id × control × status × maturity. Content comes
/// from [ControlStatusSpec.fromSlide]; the progress is derived, never stored.
/// Colours reuse the deterministic [AppTheme] status tokens (already contrast-
/// checked) so it renders identically in an export isolate.
class _ControlStatusPreview extends StatelessWidget {
  final Slide slide;
  final double w;
  final String font;
  final ThemeProfile profile;

  const _ControlStatusPreview({
    required this.slide,
    required this.w,
    required this.font,
    required this.profile,
  });

  static Color _statusColor(ControlStatus status) => switch (status) {
    ControlStatus.implemented => AppTheme.checklistTested, // green
    ControlStatus.partial => AppTheme.checklistNotTestable, // amber
    ControlStatus.planned => AppTheme.navy, // scheduled
    ControlStatus.notStarted => AppTheme.checklistNotTested, // grey
    ControlStatus.notApplicable => AppTheme.slideInkSoft, // out of scope
  };

  @override
  Widget build(BuildContext context) {
    final pad = w * 0.07; // vertical margin
    final hPad = w * 0.045; // narrower side margin
    final spec = ControlStatusSpec.fromSlide(slide.title, slide.tableRows);
    final accent = AppTheme.parseHexColor(profile.accentColor);

    return _PreviewScaffold(
      width: w,
      slide: slide,
      profile: profile,
      horizontalPadding: hPad,
      verticalPadding: pad,
      children: [
        if (spec.heading.isNotEmpty)
          Text(
            spec.heading,
            style: _applyFont(
              font,
              TextStyle(
                fontSize: w * 0.04,
                fontWeight: FontWeight.w700,
                color: AppTheme.navy,
              ),
            ),
          ),
        SizedBox(height: w * 0.02),
        _progress(context, spec, accent),
        SizedBox(height: w * 0.03),
        _headerRow(context),
        Divider(height: w * 0.02, color: AppTheme.slideRule),
        for (final row in spec.rows) _dataRow(context, row),
      ],
    );
  }

  Widget _progress(BuildContext context, ControlStatusSpec spec, Color accent) {
    final fraction =
        spec.applicableCount == 0 ? 0.0 : spec.implementedCount / spec.applicableCount;
    return Row(
      children: [
        SizedBox(
          width: w * 0.58,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(w * 0.006),
            child: LinearProgressIndicator(
              value: fraction,
              minHeight: _progressBarThickness(w),
              backgroundColor: AppTheme.scopeNotTested.withValues(alpha: 0.2),
              valueColor: AlwaysStoppedAnimation(accent),
            ),
          ),
        ),
        SizedBox(width: w * 0.02),
        Text(
          '${spec.progressPercent}% ${context.l10n.d('geïmplementeerd')}',
          style: _applyFont(
            font,
            TextStyle(fontSize: w * 0.022, color: AppTheme.slideInkMuted),
          ),
        ),
      ],
    );
  }

  Widget _headerRow(BuildContext context) {
    final l10n = context.l10n;
    TextStyle style() => _applyFont(
      font,
      TextStyle(
        fontSize: w * 0.02,
        fontWeight: FontWeight.w700,
        color: AppTheme.slideInkSoft,
      ),
    );
    return Padding(
      padding: EdgeInsets.symmetric(vertical: w * 0.008),
      child: Row(
        children: [
          Expanded(flex: 2, child: Text(l10n.d('ID'), style: style())),
          Expanded(flex: 6, child: Text(l10n.d('Beheersmaatregel'), style: style())),
          Expanded(flex: 3, child: Text(l10n.d('Status'), style: style())),
          Expanded(flex: 2, child: Text(l10n.d('Niveau'), style: style())),
        ],
      ),
    );
  }

  Widget _dataRow(BuildContext context, ControlStatusRow row) {
    TextStyle style() => _applyFont(
      font,
      TextStyle(fontSize: w * 0.022, color: AppTheme.slideInk),
    );
    return Padding(
      padding: EdgeInsets.symmetric(vertical: w * 0.008),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(flex: 2, child: Text(row.id, style: style())),
          Expanded(flex: 6, child: Text(row.control, style: style())),
          Expanded(flex: 3, child: _statusChip(context, row.status)),
          Expanded(
            flex: 2,
            child: Text(
              row.maturity == 0 ? '—' : '${row.maturity}/$controlMaturityMax',
              style: style(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _statusChip(BuildContext context, ControlStatus status) {
    final color = _statusColor(status);
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: w * 0.014,
          vertical: w * 0.004,
        ),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(w * 0.006),
        ),
        child: Text(
          context.l10n.d(status.dutchLabel),
          style: _applyFont(
            font,
            TextStyle(
              fontSize: w * 0.019,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ),
      ),
    );
  }
}
