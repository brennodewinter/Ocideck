// Beamer-slide-bouwer: zet elke [Slide] uit een geprojecteerd deck om in één
// of meer LaTeX Beamer-frames.
//
// Fase 2 dekt de eenvoudige types: title, section, bullets, twoBullets,
// bulletsImage, twoImages, image, quote, freeMarkdown, code, table. Elk type
// dat hier geen eigen layout krijgt, valt terug op de kernconverter over
// `slide.customMarkdown` — werkend, maar zonder Beamer-specifieke layout.
// De rijke types (chart, timeline, finding, mermaid, …) krijgen eigen
// converters in fases 3-6.
//
// De bouwer neemt een [AudienceDeck] (via de slides) en nooit de rauwe bron —
// de projectiegrens blijft staan. `tool/check_audience_boundary.dart` herkent
// de aanroep vanuit `ExportService._buildLatex`, die een `ExportBundle` meekrijgt.

import '../../models/deck.dart';
import '../../models/slide.dart';
import 'markdown_to_latex.dart';

/// Bouwt de Beamer-frames voor alle slides in [deck] en geeft de body-tekst
/// terug (zonder preamble/postamble — die leveren de wrappers in
/// `latex_preamble.dart`).
String buildBeamerBody(Deck deck) {
  final buf = StringBuffer();
  for (final slide in deck.slides) {
    if (slide.skipped) continue;
    buf.write(_slideToFrame(slide));
    buf.write('\n');
  }
  return buf.toString();
}

/// Zet één [slide] om in één Beamer-frame (of meerdere bij overlopende
/// content — voorlopig één per slide).
String _slideToFrame(Slide slide) {
  // Sectie-slides leveren hun eigen \section + frame-paar; de wrapper
  // zou dubbel-wikkelen.
  if (slide.type == SlideType.section) {
    return _sectionSlide(slide);
  }
  final frameTitle = _frameTitle(slide);
  final body = _slideBody(slide);
  final titleCmd = frameTitle.isEmpty
      ? ''
      : '\\frametitle{${_escapeLatex(frameTitle)}}\n';
  return '\\begin{frame}\n$titleCmd$body\n\\end{frame}\n';
}

/// De titel die bovenaan het frame staat. Leeg bij types die hun titel in de
/// body verwerken (title, section).
String _frameTitle(Slide slide) {
  switch (slide.type) {
    case SlideType.title:
    case SlideType.section:
      return '';
    default:
      return slide.title;
  }
}

/// Het frame-lichaam per SlideType.
String _slideBody(Slide slide) {
  switch (slide.type) {
    case SlideType.title:
      return _titleSlide(slide);
    case SlideType.section:
      return _sectionSlide(slide);
    case SlideType.bullets:
      return _bulletsSlide(slide);
    case SlideType.twoBullets:
      return _twoBulletsSlide(slide);
    case SlideType.bulletsImage:
      return _bulletsImageSlide(slide);
    case SlideType.twoImages:
      return _twoImagesSlide(slide);
    case SlideType.image:
      return _imageSlide(slide);
    case SlideType.quote:
      return _quoteSlide(slide);
    case SlideType.freeMarkdown:
      return _freeMarkdownSlide(slide);
    case SlideType.code:
      return _codeSlide(slide);
    case SlideType.table:
      return _tableSlide(slide);
    // Types die in fase 2 nog geen eigen Beamer-layout hebben vallen terug
    // op de kernconverter over customMarkdown. ponytail: ceiling is dat de
    // layout niet Beamer-specifiek is; upgrade path is een eigen converter
    // per type in fases 3-6.
    default:
      return _fallbackSlide(slide);
  }
}

// ── Per-type builders ──

String _titleSlide(Slide slide) {
  final buf = StringBuffer();
  buf.write('\\begin{center}\n');
  buf.write('{\\Large ${_escapeLatex(slide.title)}}\n');
  if (slide.subtitle.trim().isNotEmpty) {
    buf.write('\n\\vspace{0.5em}\n');
    buf.write('{\\large ${_escapeLatex(slide.subtitle)}}\n');
  }
  buf.write('\\end{center}\n');
  return buf.toString();
}

String _sectionSlide(Slide slide) {
  // Een sectie-slide in Beamer: \section + een sectionpage-frame. \section
  // hoort buiten een frame, dus _slideToFrame roept deze methode direct aan
  // zonder extra wrapper.
  return '\\section{${_escapeLatex(slide.title)}}\n'
      '\\begin{frame}\n'
      '\\sectionpage\n'
      '\\end{frame}\n';
}

String _bulletsSlide(Slide slide) {
  if (slide.bullets.isEmpty) return '';
  final env = slide.listStyle == ListStyle.numbered ? 'enumerate' : 'itemize';
  final buf = StringBuffer();
  buf.write('\\begin{$env}\n');
  for (final b in slide.bullets) {
    buf.write('\\item ${markdownInlineToLatex(b)}\n');
  }
  buf.write('\\end{$env}\n');
  return buf.toString();
}

String _twoBulletsSlide(Slide slide) {
  final buf = StringBuffer();
  buf.write('\\begin{columns}\n');
  buf.write('\\begin{column}{0.48\\textwidth}\n');
  if (slide.columnTitle1.trim().isNotEmpty) {
    buf.write('\\textbf{${_escapeLatex(slide.columnTitle1)}}\n\n');
  }
  buf.write(_bulletsToLatex(slide.bullets, slide.listStyle));
  buf.write('\\end{column}\n');
  buf.write('\\begin{column}{0.48\\textwidth}\n');
  if (slide.columnTitle2.trim().isNotEmpty) {
    buf.write('\\textbf{${_escapeLatex(slide.columnTitle2)}}\n\n');
  }
  buf.write(_bulletsToLatex(slide.bullets2, slide.listStyle));
  buf.write('\\end{column}\n');
  buf.write('\\end{columns}\n');
  return buf.toString();
}

String _bulletsImageSlide(Slide slide) {
  final buf = StringBuffer();
  buf.write('\\begin{columns}\n');
  buf.write('\\begin{column}{0.55\\textwidth}\n');
  buf.write(_bulletsToLatex(slide.bullets, slide.listStyle));
  buf.write('\\end{column}\n');
  buf.write('\\begin{column}{0.40\\textwidth}\n');
  if (slide.imagePath.isNotEmpty) {
    buf.write(
      r'\includegraphics[width=\textwidth]{'
      '${_escapeImagePath(slide.imagePath)}}\n',
    );
  }
  buf.write('\\end{column}\n');
  buf.write('\\end{columns}\n');
  return buf.toString();
}

String _twoImagesSlide(Slide slide) {
  final buf = StringBuffer();
  buf.write('\\begin{columns}\n');
  for (final (path, caption) in [
    (slide.imagePath, slide.imageCaption),
    (slide.imagePath2, slide.imageCaption2),
  ]) {
    buf.write('\\begin{column}{0.48\\textwidth}\n');
    if (path.isNotEmpty) {
      buf.write(
        r'\includegraphics[width=\textwidth]{'
        '${_escapeImagePath(path)}}\n',
      );
    }
    if (caption.trim().isNotEmpty) {
      buf.write('\\\\\\small{${_escapeLatex(caption)}}\n');
    }
    buf.write('\\end{column}\n');
  }
  buf.write('\\end{columns}\n');
  return buf.toString();
}

String _imageSlide(Slide slide) {
  final buf = StringBuffer();
  if (slide.imagePath.isNotEmpty) {
    buf.write('\\begin{center}\n');
    buf.write(
      r'\includegraphics[width=0.9\textwidth]{'
      '${_escapeImagePath(slide.imagePath)}}\n',
    );
    if (slide.imageCaption.trim().isNotEmpty) {
      buf.write('\\\\\\small{${_escapeLatex(slide.imageCaption)}}\n');
    }
    buf.write('\\end{center}\n');
  }
  return buf.toString();
}

String _quoteSlide(Slide slide) {
  final buf = StringBuffer();
  buf.write('\\begin{quote}\n');
  buf.write('${markdownInlineToLatex(slide.quote)}\n');
  buf.write('\\end{quote}\n');
  if (slide.quoteAuthor.trim().isNotEmpty) {
    buf.write('\\begin{flushright}\n');
    buf.write('--- ${_escapeLatex(slide.quoteAuthor)}\n');
    buf.write('\\end{flushright}\n');
  }
  return buf.toString();
}

String _freeMarkdownSlide(Slide slide) {
  // Vrije Markdown: de hele customMarkdown door de kernconverter.
  return markdownToLatex(slide.customMarkdown);
}

String _codeSlide(Slide slide) {
  final buf = StringBuffer();
  buf.write('\\begin{lstlisting}');
  if (slide.codeLanguage.isNotEmpty) {
    buf.write('[language=${slide.codeLanguage}]');
  }
  buf.write('\n');
  // customMarkdown bevat de ruwe code als fenced block; we halen de code
  // eruit door de markdown-converter te laten runnen, die het als
  // lstlisting emitteert. Maar dat dubbel-wikkelt — dus we extracten de
  // code direct uit customMarkdown.
  buf.write(_extractCode(slide.customMarkdown));
  buf.write('\n\\end{lstlisting}\n');
  return buf.toString();
}

String _tableSlide(Slide slide) {
  if (slide.tableRows.isEmpty) return '';
  final buf = StringBuffer();
  final colCount = slide.tableRows.first.length;
  final spec = 'l' * colCount;
  buf.write('\\begin{tabular}{$spec}\n');
  buf.write('\\toprule\n');
  for (var i = 0; i < slide.tableRows.length; i++) {
    final row = slide.tableRows[i];
    final cells = row.map(_escapeLatex).join(' & ');
    buf.write('$cells \\\\\n');
    if (i == 0) buf.write('\\midrule\n');
  }
  buf.write('\\bottomrule\n');
  buf.write('\\end{tabular}\n');
  return buf.toString();
}

String _fallbackSlide(Slide slide) {
  // Types zonder eigen Beamer-layout: kernconverter over customMarkdown.
  // ponytail: ceiling — geen Beamer-specifieke layout; upgrade path is een
  // eigen converter per type (fases 3-6).
  if (slide.customMarkdown.trim().isEmpty) {
    // Geen content: val terug op titel + bullets als tekst.
    final buf = StringBuffer();
    if (slide.title.trim().isNotEmpty) {
      buf.write('\\textbf{${_escapeLatex(slide.title)}}\n\n');
    }
    buf.write(_bulletsToLatex(slide.bullets, slide.listStyle));
    return buf.toString();
  }
  return markdownToLatex(slide.customMarkdown);
}

// ── Hulpmethoden ──

/// Bouwt een itemize/enumerate-omgeving uit een lijst bullets.
String _bulletsToLatex(List<String> bullets, ListStyle style) {
  if (bullets.isEmpty) return '';
  final env = style == ListStyle.numbered ? 'enumerate' : 'itemize';
  final buf = StringBuffer();
  buf.write('\\begin{$env}\n');
  for (final b in bullets) {
    buf.write('\\item ${markdownInlineToLatex(b)}\n');
  }
  buf.write('\\end{$env}\n');
  return buf.toString();
}

/// Extract de code uit een fenced-code customMarkdown-blok (```lang\ncode```).
String _extractCode(String customMarkdown) {
  final match = RegExp(r'```[^\n]*\n([\s\S]*?)```').firstMatch(customMarkdown);
  return match != null ? match.group(1)! : customMarkdown;
}

/// Escape LaTeX-speciale tekens in platte tekst. Hergebruikt de escape uit
/// latex_preamble.dart via een lokale kopie — de preamble-escape is private
/// daar, en duplicatie van 10 regels is goedkoper dan een nieuwe export.
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

String _escapeImagePath(String src) {
  if (src.isEmpty) return '';
  return src.replaceAll(r'\', '/');
}
