// Part of the slide_preview library — see ../slide_preview.dart.
// Split out for navigability; all imports live in the main library file.
part of '../slide_preview.dart';

/// Preview for a `scopeMatrix` slide (PENTEST_MIAUW §2.2 / §4.4): the title with
/// a derived tested/total coverage bar, then the scope objects as a matrix of
/// object × type × (derived) standard × coverage status. Content comes from
/// [ScopeMatrixSpec.fromSlide]; colours are the deterministic [AppTheme] scope
/// tokens so it renders identically in an export isolate.
class _ScopeMatrixPreview extends StatelessWidget {
  final Slide slide;
  final double w;
  final String font;
  final ThemeProfile profile;

  const _ScopeMatrixPreview({
    required this.slide,
    required this.w,
    required this.font,
    required this.profile,
  });

  static Color _statusColor(ScopeStatus status) => switch (status) {
    ScopeStatus.tested => AppTheme.scopeTested,
    ScopeStatus.deviation => AppTheme.scopeDeviation,
    ScopeStatus.unreachable => AppTheme.scopeUnreachable,
    ScopeStatus.notTested => AppTheme.scopeNotTested,
  };

  @override
  Widget build(BuildContext context) {
    final pad = w * 0.07; // vertical margin
    final hPad = w * 0.045; // narrower side margin — use the width (feedback)
    final safe = slide.showLogo ? _logoSafeInsets(w, profile) : EdgeInsets.zero;
    final spec = ScopeMatrixSpec.fromSlide(slide.title, slide.tableRows);
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
                hPad,
                pad + safe.top,
                hPad,
                _logoAwareBottomPadding(pad, safe.bottom),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (spec.title.isNotEmpty)
                    Text(
                      spec.title,
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
                  _coverage(context, spec, accent),
                  SizedBox(height: w * 0.03),
                  _headerRow(context),
                  Divider(height: w * 0.02, color: AppTheme.slate300),
                  for (final row in spec.rows) _dataRow(context, row),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _coverage(BuildContext context, ScopeMatrixSpec spec, Color accent) {
    final fraction = spec.total == 0 ? 0.0 : spec.testedCount / spec.total;
    return Row(
      children: [
        SizedBox(
          width: w * 0.62,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(w * 0.006),
            child: LinearProgressIndicator(
              value: fraction,
              minHeight: w * 0.014,
              backgroundColor: AppTheme.scopeNotTested.withValues(alpha: 0.2),
              valueColor: AlwaysStoppedAnimation(accent),
            ),
          ),
        ),
        SizedBox(width: w * 0.02),
        Text(
          '${spec.testedCount}/${spec.total} ${context.l10n.d('gedekt')}',
          style: _applyFont(
            font,
            TextStyle(fontSize: w * 0.022, color: AppTheme.slate600),
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
        color: AppTheme.slate500,
      ),
    );
    return Padding(
      padding: EdgeInsets.symmetric(vertical: w * 0.008),
      child: Row(
        children: [
          Expanded(flex: 5, child: Text(l10n.d('Object'), style: style())),
          Expanded(flex: 2, child: Text(l10n.d('Type'), style: style())),
          Expanded(flex: 2, child: Text(l10n.d('Standaard'), style: style())),
          Expanded(flex: 3, child: Text(l10n.d('Status'), style: style())),
        ],
      ),
    );
  }

  Widget _dataRow(BuildContext context, ScopeRow row) {
    final l10n = context.l10n;
    TextStyle style() => _applyFont(
      font,
      TextStyle(fontSize: w * 0.022, color: AppTheme.slate700),
    );
    return Padding(
      padding: EdgeInsets.symmetric(vertical: w * 0.008),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(flex: 5, child: Text(row.object, style: style())),
          Expanded(
            flex: 2,
            child: Text(l10n.d(row.type.dutchLabel), style: style()),
          ),
          Expanded(
            flex: 2,
            child: Text(
              row.standard.isEmpty ? '—' : row.standard,
              style: style(),
            ),
          ),
          Expanded(flex: 3, child: _statusChip(context, row.status)),
        ],
      ),
    );
  }

  Widget _statusChip(BuildContext context, ScopeStatus status) {
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
