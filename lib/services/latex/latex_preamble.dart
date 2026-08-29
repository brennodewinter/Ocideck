// LaTeX-preambles voor de Document- (article) en Deck-export (beamer).
//
// Bevat alleen de preamble — de body komt uit `markdown_to_latex.dart`. Het
// pakketten-set is bewust beperkt tot wat in een standaard TeX Live-distributie
// zit, zodat de gebruiker het `.tex` direct kan compileren met `pdflatex` of
// `xelatex` zonder extra packages te installeren.

import '../export_metadata.dart';
import '../../models/deck.dart';
import '../../models/page_size.dart';
import '../../models/settings.dart';
import '../document_chrome_template.dart';
import 'markdown_to_latex.dart';

/// Bouwt de preamble voor een LaTeX `article`-document.
///
/// [meta] levert titel, auteur, organisatie en taal. De taal wordt via
/// `polyglossia` (voor xelatex/lualatex) of `babel` (voor pdflatex) gezet;
/// we gebruiken `babel` met de BCP47-code als taalnaam, wat in de meeste
/// TeX Live-installaties werkt.
///
/// [pageSize] en [pageMargins] bepalen de papiermaat en marges (feature 3).
/// Standaard A4 portret met de gedeelde [PageMargins]-standaard (25mm boven en
/// onder, 20mm links en rechts) — dezelfde marges als de HTML-export en als de
/// beginwaarde van de instelling. Dat is bewust géén 25mm rondom meer, de
/// vorige vaste LaTeX-waarde: paginamaat en marges horen nu in één model, en
/// twee standaarden die uiteenlopen leveren stil twee verschillende PDF's op.
String articlePreamble(
  ExportDocumentMetadata meta, {
  ThemeProfile? theme,
  Map<String, String> documentFields = const {},
  PageSizeSpec pageSize = PageSizeSpec.a4,
  PageMargins pageMargins = const PageMargins(),
  bool cropMarks = false,
}) {
  final buf = StringBuffer();
  final chrome = _articleChrome(meta, theme, documentFields);
  buf.write('\\documentclass[11pt,${pageSize.latexName}]{article}\n');
  // Encoding en lettertype
  buf.write(
    r'\usepackage[utf8]{inputenc}'
    '\n',
  );
  buf.write(
    r'\usepackage[T1]{fontenc}'
    '\n',
  );
  // Wiskunde
  buf.write(
    r'\usepackage{amsmath,amssymb}'
    '\n',
  );
  // Afbeeldingen
  buf.write(
    r'\usepackage{graphicx}'
    '\n',
  );
  // Tabellen met booktabs
  buf.write(
    r'\usepackage{booktabs}'
    '\n',
  );
  buf.write(
    r'\usepackage{array}'
    '\n',
  );
  buf.write(
    r'\usepackage{longtable}'
    '\n',
  );
  // Code-listings
  buf.write(
    r'\usepackage{listings}'
    '\n',
  );
  buf.write(
    r'\usepackage[table]{xcolor}'
    '\n',
  );
  if (theme != null) _writeArticleColors(buf, theme);
  if (chrome.enabled) {
    buf.write(
      r'\usepackage{fancyhdr}'
      '\n',
    );
  }
  // Hyperlinks
  buf.write(
    r'\usepackage[colorlinks=true,linkcolor=blue,urlcolor=blue]{hyperref}'
    '\n',
  );
  // Doorhaling
  buf.write(
    r'\usepackage[normalem]{ulem}'
    '\n',
  );
  // Taal
  final lang = _babelLanguage(meta.language);
  if (lang != null) {
    buf.write('\\usepackage[$lang]{babel}\n');
  }
  // Pagina-marges (feature 3: instelbaar)
  // Met drukkersafloop is het vel groter dan het snijformaat; dan bepaalt
  // `geometry` de papiermaat in plaats van de papiernaam uit `documentclass`.
  final paper = pageSize.latexPaperWith(pageMargins);
  final geometry = paper == null
      ? pageMargins.latexMargin
      : '$paper,${pageMargins.latexMargin}';
  buf.write('\\usepackage[$geometry]{geometry}\n');
  _writeArticleChrome(buf, meta, chrome);
  // Snijtekens: alleen wanneer erom gevraagd is én er afloop is, want zonder
  // afloop wijzen ze nergens naar. `crop` tekent ze rond het snijformaat op het
  // grotere vel — precies wat een drukker nodig heeft om te weten waar hij
  // snijdt.
  //
  // Dit pakket zit niet in de kaalste TeX-installatie (`scheme-basic`), wél in
  // de gangbare volledige. Daarom staat het alleen in de preamble wanneer de
  // gebruiker de snijtekens zelf aanzet: wie ze niet vraagt krijgt geen extra
  // afhankelijkheid, en wie ze wél vraagt accepteert er één die de interface
  // en de documentatie noemen. Het HTML-pad belooft ze niet — geen browser kent
  // `marks` uit CSS Paged Media.
  if (cropMarks && pageMargins.hasBleed) {
    final (trimW, trimH) = pageSize.dimensions;
    buf.write(
      '\\usepackage[width=${_mm(trimW)}mm,height=${_mm(trimH)}mm,'
      'cam,center]{crop}\n',
    );
  }
  buf.write('\n');
  // Metadata
  if (meta.title.trim().isNotEmpty) {
    buf.write('\\title{${_escapeLatex(meta.title)}}\n');
  }
  final authorParts = <String>[
    if (meta.author.trim().isNotEmpty) _escapeLatex(meta.author),
    if (meta.organization.trim().isNotEmpty) _escapeLatex(meta.organization),
  ];
  if (authorParts.isNotEmpty) {
    buf.write('\\author{${authorParts.join(' \\\\ ')}}\n');
  }
  buf.write(
    r'\date{}'
    '\n',
  );
  buf.write('\n');
  // listings-stijl: monospace, lichtgekleurde achtergrond
  buf.write(
    r'\lstset{basicstyle=\ttfamily\small,'
    r'backgroundcolor=\color{gray!10},'
    r'frame=single,framerule=0pt,'
    r'breaklines=true,showstringspaces=false}'
    '\n',
  );
  buf.write('\n');
  buf.write(
    r'\begin{document}'
    '\n',
  );
  if (meta.title.trim().isNotEmpty) {
    buf.write(
      r'\maketitle'
      '\n',
    );
    // `article` zet de titelpagina zelf op `plain`. Zet daarna de reeds
    // opgebouwde documentchrome terug, anders mist juist pagina één de
    // classificatie en de ingestelde kop- en voettekst.
    if (chrome.enabled) {
      buf.write(
        r'\thispagestyle{fancy}'
        '\n',
      );
    }
  }
  return buf.toString();
}

typedef _ArticleChrome = ({
  String header,
  String footer,
  bool enabled,
  bool pageNumbers,
});

void _writeArticleColors(StringBuffer buf, ThemeProfile theme) {
  buf.write(
    '\\definecolor{ocideckTableText}{HTML}{${_latexHexColor(theme.tableTextColor, '222222')}}\n'
    '\\definecolor{ocideckTableHeaderText}{HTML}{${_latexHexColor(theme.tableHeaderTextColor, 'FFFFFF')}}\n'
    '\\definecolor{ocideckTableHeaderBackground}{HTML}{${_latexHexColor(theme.tableHeaderBackgroundColor, '2E7D64')}}\n'
    '\\definecolor{ocideckTableZebra}{HTML}{${_latexHexColor(theme.tableZebraColor, 'F1F5F9')}}\n'
    '\\definecolor{ocideckTableBorder}{HTML}{${_latexHexColor(theme.tableBorderColor, 'CBD5E1')}}\n'
    '\\definecolor{ocideckTableAccent}{HTML}{${_latexHexColor(theme.accentColor, '2E7D64')}}\n'
    '\\definecolor{ocideckDocumentBandText}{HTML}{${_latexHexColor(theme.effectiveDocumentBandTextColor, '222222')}}\n'
    '\\definecolor{ocideckDocumentBandBackground}{HTML}{${_latexHexColor(theme.effectiveDocumentBandBackgroundColor, 'FFFFFF')}}\n',
  );
}

_ArticleChrome _articleChrome(
  ExportDocumentMetadata meta,
  ThemeProfile? theme,
  Map<String, String> fields,
) {
  final header = _latexDocumentChrome(theme?.documentHeaderText ?? '', fields);
  final footer = _latexDocumentChrome(theme?.documentFooterText ?? '', fields);
  return (
    header: header,
    footer: footer,
    pageNumbers:
        theme?.documentShowPageNumbers == true || meta.tlp != TlpLevel.none,
    enabled:
        header.isNotEmpty ||
        footer.isNotEmpty ||
        theme?.documentShowPageNumbers == true ||
        meta.tlp != TlpLevel.none,
  );
}

void _writeArticleChrome(
  StringBuffer buf,
  ExportDocumentMetadata meta,
  _ArticleChrome chrome,
) {
  if (!chrome.enabled) return;
  buf.write('\\pagestyle{fancy}\n');
  buf.write('\\fancyhf{}\n');
  if (chrome.header.isNotEmpty) {
    buf.write('\\fancyhead[L]{${_latexDocumentBand(chrome.header)}}\n');
  }
  if (chrome.footer.isNotEmpty) {
    buf.write('\\fancyfoot[L]{${_latexDocumentBand(chrome.footer)}}\n');
  }
  if (meta.tlp != TlpLevel.none) {
    final color = (meta.tlp.foreground & 0xFFFFFF)
        .toRadixString(16)
        .padLeft(6, '0')
        .toUpperCase();
    final badge =
        '\\colorbox{black}{\\textcolor[HTML]{$color}{\\texttt{\\textbf{${meta.tlp.label}}}}}';
    buf.write('\\fancyhead[${chrome.header.isEmpty ? 'C' : 'R'}]{$badge}\n');
    buf.write('\\fancyfoot[C]{$badge}\n');
  }
  if (chrome.pageNumbers) buf.write('\\fancyfoot[R]{\\thepage}\n');
}

String _latexDocumentChrome(String template, Map<String, String> fields) {
  final resolved = resolveDocumentChromeTemplate(template.trim(), fields);
  if (resolved.isEmpty) return '';
  return markdownInlineToLatex(resolved);
}

String _latexDocumentBand(String content) =>
    '\\colorbox{ocideckDocumentBandBackground}{'
    '\\textcolor{ocideckDocumentBandText}{$content}}';

/// Sluit een article-document af.
const articlePostamble = r'\end{document}';

/// Bouwt de preamble voor een LaTeX `beamer`-presentatie.
///
/// [meta] levert titel, auteur en taal. [theme] is optioneel — een Beamer-
/// themanaam (zoals `metropolis` of `default`). De titelpagina wordt
/// automatisch gegenereerd.
/// [themeProfile] levert de accentkleur voor de beeldverwijzingen (§5). Zonder
/// die definitie verwijst de TikZ-code naar `ocideckTableAccent` terwijl xcolor
/// hem niet kent, en weigert het hele document te compileren — de export ziet
/// er dan gaaf uit en is onbruikbaar.
String beamerPreamble(
  ExportDocumentMetadata meta, {
  String? theme,
  ThemeProfile? themeProfile,
}) {
  final buf = StringBuffer();
  buf.write(
    r'\documentclass[aspectratio=169]{beamer}'
    '\n',
  );
  // Themakeuze — default is voldoende; metropolis is mooier maar niet altijd
  // geïnstalleerd.
  buf.write('\\usetheme{${theme ?? 'default'}}\n');
  // Wiskunde
  buf.write(
    r'\usepackage{amsmath,amssymb}'
    '\n',
  );
  // Afbeeldingen
  buf.write(
    r'\usepackage{graphicx}'
    '\n',
  );
  // Tabellen
  buf.write(
    r'\usepackage{booktabs}'
    '\n',
  );
  buf.write(
    r'\usepackage{longtable}'
    '\n',
  );
  // Code-listings
  buf.write(
    r'\usepackage{listings}'
    '\n',
  );
  buf.write(
    r'\usepackage{xcolor}'
    '\n',
  );
  // Hyperlinks
  buf.write(
    r'\usepackage{hyperref}'
    '\n',
  );
  // Doorhaling
  buf.write(
    r'\usepackage[normalem]{ulem}'
    '\n',
  );
  // TikZ en pgfplots voor grafieken en diagrammen (fase 4+)
  buf.write(
    r'\usepackage{tikz}'
    '\n',
  );
  buf.write(
    r'\usepackage{pgfplots}'
    '\n',
  );
  // De accentkleur van de beeldverwijzingen. Beamer deelde deze definitie niet
  // met de article-preamble, dus verwees de TikZ-code naar een kleur die
  // nergens bestond.
  buf.write(
    '\\definecolor{ocideckTableAccent}{HTML}'
    '{${_latexHexColor(themeProfile?.accentColor ?? '', '2E7D64')}}\n',
  );
  buf.write(
    r'\pgfplotsset{compat=1.18}'
    '\n',
  );
  // Taal
  final lang = _babelLanguage(meta.language);
  if (lang != null) {
    buf.write('\\usepackage[$lang]{babel}\n');
  }
  buf.write('\n');
  // Metadata
  if (meta.title.trim().isNotEmpty) {
    buf.write('\\title{${_escapeLatex(meta.title)}}\n');
  }
  final authorParts = <String>[
    if (meta.author.trim().isNotEmpty) _escapeLatex(meta.author),
    if (meta.organization.trim().isNotEmpty) _escapeLatex(meta.organization),
  ];
  if (authorParts.isNotEmpty) {
    buf.write('\\author{${authorParts.join(' \\\\ ')}}\n');
  }
  buf.write(
    r'\date{}'
    '\n',
  );
  buf.write('\n');
  // listings-stijl
  buf.write(
    r'\lstset{basicstyle=\ttfamily\small,'
    r'backgroundcolor=\color{gray!10},'
    r'frame=single,framerule=0pt,'
    r'breaklines=true,showstringspaces=false}'
    '\n',
  );
  buf.write('\n');
  buf.write(
    r'\begin{document}'
    '\n',
  );
  if (meta.title.trim().isNotEmpty) {
    buf.write(
      r'\begin{frame}'
      '\n',
    );
    buf.write(
      r'\titlepage'
      '\n',
    );
    buf.write(
      r'\end{frame}'
      '\n\n',
    );
  }
  return buf.toString();
}

/// Sluit een beamer-document af.
const beamerPostamble = r'\end{document}';

/// Mapt een BCP47-taalcode naar een babel-taalnaam, of `null` als de taal
/// niet bekend is. Beperkt tot de talen die OciDeck ondersteunt en die een
/// standaard babel-pakket hebben.
String? _babelLanguage(String bcp47) {
  if (bcp47.isEmpty) return null;
  final code = bcp47.split('-').first.toLowerCase();
  const map = {
    'nl': 'dutch',
    'en': 'english',
    'de': 'german',
    'fr': 'french',
    'es': 'spanish',
    'it': 'italian',
    'pt': 'portuguese',
    'sv': 'swedish',
    'da': 'danish',
    'fi': 'finnish',
    'no': 'norsk',
    'pl': 'polish',
    'cs': 'czech',
    'sk': 'slovak',
    'hu': 'hungarian',
    'ro': 'romanian',
    'bg': 'bulgarian',
    'el': 'greek',
    'tr': 'turkish',
    'et': 'estonian',
    'lv': 'latvian',
    'lt': 'lithuanian',
    'sl': 'slovene',
    'hr': 'croatian',
    'is': 'icelandic',
    'ru': 'russian',
    'uk': 'ukrainian',
  };
  return map[code];
}

/// Escape LaTeX-speciale tekens in metadata-velden (titel, auteur).
String _escapeLatex(String s) {
  return s
      .replaceAll(r'\', r'\textbackslash{}')
      .replaceAll('&', r'\&')
      .replaceAll('%', r'\%')
      .replaceAll('#', r'\#')
      .replaceAll('_', r'\_')
      .replaceAll('{', r'\{')
      .replaceAll('}', r'\}')
      .replaceAll('~', r'\textasciitilde{}')
      .replaceAll('^', r'\textasciicircum{}');
}

/// Millimeters zonder overbodige nullen — `210` in plaats van `210.0`.
String _mm(double mm) =>
    mm == mm.roundToDouble() ? mm.toStringAsFixed(0) : mm.toString();

String _latexHexColor(String value, String fallback) {
  final hex = value.replaceFirst('#', '').toUpperCase();
  return RegExp(r'^[0-9A-F]{6}$').hasMatch(hex) ? hex : fallback;
}
