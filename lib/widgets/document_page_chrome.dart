import 'package:flutter/material.dart';

import '../models/settings.dart';
import '../theme/app_theme.dart';
import 'theme_profile_logo.dart';

/// Een echte kop- of voettekstband voor documentoppervlakken.
///
/// De inhoud komt uit het stijlprofiel; de Markdown-bron blijft daardoor
/// uitwisselbaar en vrij van OciDeck-specifieke paginaopmaak.
class DocumentChromeBand extends StatelessWidget {
  const DocumentChromeBand({
    super.key,
    required this.profile,
    required this.header,
    this.pageLabel = '1',
    this.projectPath,
    this.compact = false,
  });

  final ThemeProfile profile;
  final bool header;
  final String pageLabel;
  final String? projectPath;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final path = profile.effectiveDocumentLogoPath?.trim() ?? '';
    final logoInBand =
        path.isNotEmpty &&
        profile.documentLogoPosition.startsWith(header ? 'top' : 'bottom');
    final text = header
        ? profile.documentHeaderText.trim()
        : profile.documentFooterText.trim();
    final showPage = !header && profile.documentShowPageNumbers;
    if (!logoInBand && text.isEmpty && !showPage) {
      return const SizedBox.shrink();
    }

    final rightLogo =
        logoInBand && profile.documentLogoPosition.endsWith('right');
    final color = AppTheme.parseHexColor(
      profile.textColor,
    ).withValues(alpha: 0.68);
    final logoWidth = compact
        ? 70.0
        : (profile.logoSize * 0.6).clamp(48.0, 160.0);
    final row = Row(
      children: [
        if (logoInBand && !rightLogo) ...[
          _logo(path, logoWidth, Alignment.centerLeft),
          SizedBox(width: compact ? 10 : 16),
        ],
        Expanded(
          child: Text(
            text,
            key: Key(header ? 'document-header-text' : 'document-footer-text'),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: color,
              fontFamily: profile.fontFamily,
              fontSize: compact ? 9 : 12,
            ),
          ),
        ),
        if (showPage) ...[
          SizedBox(width: compact ? 8 : 12),
          Text(
            pageLabel,
            key: const Key('document-page-number'),
            style: TextStyle(
              color: color,
              fontFamily: profile.fontFamily,
              fontSize: compact ? 9 : 12,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
        if (logoInBand && rightLogo) ...[
          SizedBox(width: compact ? 10 : 16),
          _logo(path, logoWidth, Alignment.centerRight),
        ],
      ],
    );
    final divider = Container(
      key: header ? const Key('document-style-accent-rule') : null,
      height: 1,
      color: AppTheme.parseHexColor(profile.accentColor),
    );
    return Padding(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 0 : 24,
        vertical: compact ? 6 : 10,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: header ? [row, divider] : [divider, row],
      ),
    );
  }

  Widget _logo(String path, double width, Alignment alignment) =>
      ThemeProfileLogo(
        profile: profile,
        logoPath: path,
        projectPath: projectPath,
        width: width,
        height: compact ? 28 : (width * 0.5).clamp(32.0, 72.0),
        alignment: alignment,
      );
}
