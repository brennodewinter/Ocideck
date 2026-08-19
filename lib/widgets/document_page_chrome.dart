import 'package:flutter/material.dart';

import '../models/deck.dart';
import '../models/settings.dart';
import '../services/document_chrome_template.dart';
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
    this.tlp = TlpLevel.none,
    this.fields = const {},
  });

  final ThemeProfile profile;
  final bool header;
  final String pageLabel;
  final String? projectPath;
  final bool compact;
  final TlpLevel tlp;
  final Map<String, String> fields;

  @override
  Widget build(BuildContext context) {
    final path = profile.effectiveDocumentLogoPath?.trim() ?? '';
    final logoInBand =
        path.isNotEmpty &&
        profile.documentLogoPosition.startsWith(header ? 'top' : 'bottom');
    final template = header
        ? profile.documentHeaderText.trim()
        : profile.documentFooterText.trim();
    final text = resolveDocumentChromeTemplate(template, fields);
    final showPage = !header && profile.documentShowPageNumbers;
    final showTlp = tlp != TlpLevel.none;
    if (!logoInBand && text.isEmpty && !showPage && !showTlp) {
      return const SizedBox.shrink();
    }

    final rightLogo =
        logoInBand && profile.documentLogoPosition.endsWith('right');
    final color = AppTheme.parseHexColor(
      profile.effectiveDocumentBandTextColor,
    );
    final background = AppTheme.parseHexColor(
      profile.effectiveDocumentBandBackgroundColor,
    );
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
        if (showTlp) ...[
          SizedBox(width: compact ? 8 : 12),
          _tlpMarking(header),
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
    return ColoredBox(
      key: Key(header ? 'document-header-band' : 'document-footer-band'),
      color: background,
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: compact ? 0 : 24,
          vertical: compact ? 6 : 10,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: header ? [row, divider] : [divider, row],
        ),
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

  Widget _tlpMarking(bool header) => Semantics(
    label: tlp.label,
    child: Container(
      key: Key(header ? 'document-header-tlp' : 'document-footer-tlp'),
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 5 : 7,
        vertical: compact ? 2 : 3,
      ),
      decoration: BoxDecoration(
        color: Colors.black,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(
          color: Color(tlp.foreground).withValues(alpha: 0.75),
        ),
      ),
      child: Text(
        tlp.label,
        maxLines: 1,
        style: TextStyle(
          color: Color(tlp.foreground),
          fontSize: compact ? 8 : 10,
          fontWeight: FontWeight.w700,
          fontFamily: 'monospace',
          fontFamilyFallback: const ['Menlo', 'Consolas', 'Courier New'],
          letterSpacing: 0.25,
        ),
      ),
    ),
  );
}
