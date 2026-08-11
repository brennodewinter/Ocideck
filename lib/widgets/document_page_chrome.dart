import 'package:flutter/material.dart';

import '../models/settings.dart';
import '../theme/app_theme.dart';
import 'slides/inline_markdown.dart';
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
    final documentLogoSize = profile.effectiveDocumentLogoSize.toDouble();
    final logoWidth = compact
        ? (documentLogoSize * 0.45).clamp(36.0, 144.0)
        : documentLogoSize;
    final row = Row(
      children: [
        if (logoInBand && !rightLogo) ...[
          _logo(path, logoWidth, Alignment.centerLeft),
          SizedBox(width: compact ? 10 : 16),
        ],
        Expanded(
          child: InlineMarkdownText(
            text,
            key: Key(header ? 'document-header-text' : 'document-footer-text'),
            maxLines: compact ? 3 : 4,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: color,
              fontFamily: profile.fontFamily,
              fontSize: compact ? 9 : 12,
              height: 1.3,
            ),
            linkColor: AppTheme.parseHexColor(profile.accentColor),
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
        height: compact
            ? (width * 0.5).clamp(22.0, 72.0)
            : (width * 0.5).clamp(32.0, 240.0),
        alignment: alignment,
      );
}
