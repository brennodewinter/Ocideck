// Part of the slide_preview library — see ../slide_preview.dart.
// Split out for navigability; all imports live in the main library file.
part of '../slide_preview.dart';

/// Preview for a `checklist` slide (PENTEST_MIAUW §3.2): the standard label with
/// a derived tested/total progress bar, then the tests as a table with
/// tri-state status chips and finding-id links. Content comes from
/// [ChecklistSpec.fromSlide]; the progress is derived, never stored. Colours are
/// the deterministic [AppTheme] checklist tokens so it renders identically in an
/// export isolate.
class _ChecklistPreview extends StatelessWidget {
  final Slide slide;
  final double w;
  final String font;
  final ThemeProfile profile;

  const _ChecklistPreview({
    required this.slide,
    required this.w,
    required this.font,
    required this.profile,
  });

  static Color _statusColor(ChecklistStatus status) => switch (status) {
    ChecklistStatus.tested => AppTheme.checklistTested,
    ChecklistStatus.anomaly => AppTheme.checklistAnomaly,
    ChecklistStatus.notTestable => AppTheme.checklistNotTestable,
    ChecklistStatus.notTested => AppTheme.checklistNotTested,
  };

  @override
  Widget build(BuildContext context) {
    final pad = w * 0.07;
    final safe = slide.showLogo ? _logoSafeInsets(w, profile) : EdgeInsets.zero;
    final spec = ChecklistSpec.fromSlide(slide.title, slide.tableRows);
    final accent = _hexColor(profile.accentColor);

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
                pad,
                pad + safe.top,
                pad,
                _logoAwareBottomPadding(pad, safe.bottom),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (spec.standardLabel.isNotEmpty)
                    Text(
                      spec.standardLabel,
                      style: _applyFont(
                        font,
                        TextStyle(
                          fontSize: w * 0.04,
                          fontWeight: FontWeight.w700,
                          color: AppTheme.navy,
                        ),
                      ),
                    ),
                  // The scope object this checklist covers (feedback #8).
                  if (slide.checklistScope.isNotEmpty) ...[
                    SizedBox(height: w * 0.008),
                    Text(
                      '${context.l10n.d('Scope-object')}: '
                      '${slide.checklistScope}',
                      style: _applyFont(
                        font,
                        TextStyle(
                          fontSize: w * 0.024,
                          color: AppTheme.slate600,
                        ),
                      ),
                    ),
                  ],
                  SizedBox(height: w * 0.02),
                  _progress(context, spec, accent),
                  SizedBox(height: w * 0.03),
                  _table(context, spec),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _progress(BuildContext context, ChecklistSpec spec, Color accent) {
    final fraction = spec.total == 0 ? 0.0 : spec.testedCount / spec.total;
    return Row(
      children: [
        SizedBox(
          width: w * 0.5,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(w * 0.006),
            child: LinearProgressIndicator(
              value: fraction,
              minHeight: w * 0.014,
              backgroundColor: AppTheme.checklistNotTested.withValues(
                alpha: 0.2,
              ),
              valueColor: AlwaysStoppedAnimation(accent),
            ),
          ),
        ),
        SizedBox(width: w * 0.02),
        Text(
          '${spec.testedCount}/${spec.total} ${context.l10n.d('getoetst')}',
          style: _applyFont(
            font,
            TextStyle(fontSize: w * 0.022, color: AppTheme.slate600),
          ),
        ),
      ],
    );
  }

  Widget _table(BuildContext context, ChecklistSpec spec) {
    final l10n = context.l10n;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _headerRow(l10n),
        Divider(height: w * 0.02, color: AppTheme.slate300),
        for (final row in spec.rows) _dataRow(context, row),
      ],
    );
  }

  Widget _headerRow(AppLocalizations l10n) {
    TextStyle style() => _applyFont(
      font,
      TextStyle(
        fontSize: w * 0.02,
        fontWeight: FontWeight.w700,
        color: AppTheme.slate500,
      ),
    );
    return Padding(
      padding: EdgeInsets.symmetric(vertical: w * 0.008),
      child: Row(
        children: [
          Expanded(flex: 3, child: Text('ID', style: style())),
          Expanded(flex: 5, child: Text('Test', style: style())),
          Expanded(flex: 3, child: Text(l10n.d('Status'), style: style())),
          Expanded(flex: 2, child: Text(l10n.d('Bevinding'), style: style())),
        ],
      ),
    );
  }

  Widget _dataRow(BuildContext context, ChecklistRow row) {
    TextStyle style() => _applyFont(
      font,
      TextStyle(fontSize: w * 0.022, color: AppTheme.slate700),
    );
    return Padding(
      padding: EdgeInsets.symmetric(vertical: w * 0.008),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(flex: 3, child: Text(row.id, style: style())),
          Expanded(flex: 5, child: Text(row.test, style: style())),
          Expanded(flex: 3, child: _statusChip(context, row.status)),
          Expanded(
            flex: 2,
            child: Text(
              row.findingId.isEmpty ? '—' : row.findingId,
              style: style().copyWith(
                color: row.findingId.isEmpty
                    ? AppTheme.slate500
                    : _hexColor(profile.accentColor),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _statusChip(BuildContext context, ChecklistStatus status) {
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
