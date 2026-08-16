// LaTeX-preambles voor de Document- (article) en Deck-export (beamer).
//
// Bevat alleen de preamble — de body komt uit `markdown_to_latex.dart`. Het
// pakketten-set is bewust beperkt tot wat in een standaard TeX Live-distributie
// zit, zodat de gebruiker het `.tex` direct kan compileren met `pdflatex` of
// `xelatex` zonder extra packages te installeren.

import '../export_metadata.dart';
import '../../models/page_size.dart';

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
  PageSizeSpec pageSize = PageSizeSpec.a4,
  PageMargins pageMargins = const PageMargins(),
}) {
  final buf = StringBuffer();
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
  }
  return buf.toString();
}

/// Sluit een article-document af.
const articlePostamble = r'\end{document}';

/// Bouwt de preamble voor een LaTeX `beamer`-presentatie.
///
/// [meta] levert titel, auteur en taal. [theme] is optioneel — een Beamer-
/// themanaam (zoals `metropolis` of `default`). De titelpagina wordt
/// automatisch gegenereerd.
String beamerPreamble(ExportDocumentMetadata meta, {String? theme}) {
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
