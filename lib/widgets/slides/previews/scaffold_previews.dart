// Part of the slide_preview library — see ../slide_preview.dart.
// Split out for navigability; all imports live in the main library file.
part of '../slide_preview.dart';

/// Preview for the Informatieveiligheid scaffold types (P1-S): `finding`,
/// `findingsSummary`, `checklist`, `scopeMatrix`, `signOff`. Renders the
/// free-Markdown body under a small chip that names the type, so the
/// placeholder is identifiable until each type's real preview lands
/// (P1-FIND/CHK/SCOPE/SUM/SIGN). The body comes from [Slide.customMarkdown],
/// the same field the scaffold editor and serialiser use.
class _ScaffoldPreview extends StatelessWidget {
  final Slide slide;
  final double w;
  final String font;
  final ThemeProfile profile;

  const _ScaffoldPreview({
    required this.slide,
    required this.w,
    required this.font,
    required this.profile,
  });

  @override
  Widget build(BuildContext context) {
    final pad = w * 0.07;
    final safe = slide.showLogo ? _logoSafeInsets(w, profile) : EdgeInsets.zero;
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
                  _typeChip(context, accent),
                  SizedBox(height: w * 0.025),
                  ..._markdownBodyBlocks(
                    context,
                    markdown: slide.customMarkdown,
                    w: w,
                    font: font,
                    profile: profile,
                    headingColor: AppTheme.navy,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _typeChip(BuildContext context, Color accent) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: w * 0.022, vertical: w * 0.008),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(w * 0.012),
      ),
      child: Text(
        context.l10n.d(slide.type.label),
        style: _applyFont(
          font,
          TextStyle(
            fontSize: w * 0.022,
            fontWeight: FontWeight.w600,
            color: accent,
          ),
        ),
      ),
    );
  }
}
