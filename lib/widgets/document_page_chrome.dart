import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';

import '../models/deck.dart';
import '../models/page_size.dart';
import '../models/settings.dart';
import '../services/document_chrome_template.dart';
import '../theme/app_theme.dart';
import 'slides/inline_markdown.dart';
import 'theme_profile_logo.dart';

/// De tekstspiegel die een band zonder eigen paginamaat voorstelt: A4
/// staand met de standaard bladmarges — het vel dat de stijlvoorvertoning
/// toont (#2462).
const double kDefaultDocumentContentWidthPt = 170 * kPointsPerMm;

/// Het hoogtebudget van een bandlogo bij de standaard bladmarge en
/// -basishoogte — dezelfde rekensom als de PDF (#2462).
final double _defaultLogoHeightBudgetPt = documentBandLogoHeightBudgetPt(
  25 * kPointsPerMm,
  kDocumentDefaultBodyFontSize,
);

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
    this.contentWidthPt = kDefaultDocumentContentWidthPt,
    this.logoHeightBudgetPt,
  });

  final ThemeProfile profile;
  final bool header;
  final String pageLabel;
  final String? projectPath;
  final bool compact;
  final TlpLevel tlp;
  final Map<String, String> fields;

  /// De breedte van de tekstspiegel die deze band voorstelt, in
  /// typografische punten. Alleen in [compact]-stand schaalt het logo mee:
  /// de band is dan een pagina in het klein en het beeldmerk moet hetzelfde
  /// aandeel van het vel innemen als op papier.
  final double contentWidthPt;

  /// Hoe hoog het logovlak mag worden, in punten — de marge die deze band
  /// voorstelt minus bandopvulling, zoals [documentBandLogoHeightBudgetPt]
  /// die berekent. De paginaweergave geeft de eigenlijke marge mee; `null`
  /// gebruikt de standaardrand uit [_defaultLogoHeightBudgetPt].
  final double? logoHeightBudgetPt;

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
    return LayoutBuilder(
      builder: (context, constraints) => _band(
        context,
        constraints,
        rightLogo,
        color,
        background,
        text,
        showPage,
        showTlp,
      ),
    );
  }

  Widget _band(
    BuildContext context,
    BoxConstraints constraints,
    bool rightLogo,
    Color color,
    Color background,
    String text,
    bool showPage,
    bool showTlp,
  ) {
    final logoInBand =
        (profile.effectiveDocumentLogoPath?.trim() ?? '').isNotEmpty &&
        profile.documentLogoPosition.startsWith(header ? 'top' : 'bottom');
    final path = profile.effectiveDocumentLogoPath?.trim() ?? '';
    // Hoeveel pixels één punt op deze band beslaat: in de compacte
    // voorvertoning is de band een verkleind vel, in de volle band staat
    // elke punt voor `kCssPxPerPoint` pixels — dezelfde fysieke maat als de
    // PDF (#2462).
    final bandWidth = constraints.hasBoundedWidth
        ? constraints.maxWidth
        : contentWidthPt * kCssPxPerPoint;
    final pxPerPt = compact ? bandWidth / contentWidthPt : kCssPxPerPoint;
    // Dezelfde begrenzing als de PDF-band: het logo krijgt de gevraagde
    // papierbreedte, maar nooit meer dan het vaste aandeel van de spiegel —
    // de kop- of voetregel houdt zijn ruimte.
    final logoWidth = math.min(
      profile.documentLogoWidthPt * pxPerPt,
      bandWidth * kDocumentBandLogoWidthShare,
    );
    // In compact hoort de hoogte bij de marge die de band voorstelt; in de
    // volle band geldt de bestaande eigen begrenzing.
    final logoHeight = compact
        ? math.max(
            0.0,
            math.min(
              logoWidth,
              (logoHeightBudgetPt ?? _defaultLogoHeightBudgetPt) * pxPerPt,
            ),
          )
        : (logoWidth * 0.5).clamp(32.0, 240.0);
    final row = Row(
      children: [
        if (logoInBand && !rightLogo) ...[
          _logo(path, logoWidth, logoHeight, Alignment.centerLeft),
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
          _logo(path, logoWidth, logoHeight, Alignment.centerRight),
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

  Widget _logo(String path, double width, double height, Alignment alignment) =>
      ThemeProfileLogo(
        profile: profile,
        logoPath: path,
        projectPath: projectPath,
        width: width,
        height: height,
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
