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
    case SlideType.canvas:
      return _freeMarkdownSlide(slide);
    case SlideType.code:
      return _codeSlide(slide);
    // Tabel-backed types delen één tabular-converter.
    case SlideType.table:
    case SlideType.checklist:
    case SlideType.scorecard:
    case SlideType.scopeMatrix:
    case SlideType.matrix:
    case SlideType.controlStatus:
    case SlideType.findingsSummary:
    case SlideType.discoveries:
    case SlideType.assets:
    case SlideType.gantt:
      return _tableSlide(slide);
    case SlideType.signOff:
      return _signOffSlide(slide);
    case SlideType.menu:
      return _menuSlide(slide);
    case SlideType.video:
      return _videoSlide(slide);
    case SlideType.timeline:
      return _timelineSlide(slide);
    case SlideType.question:
      return _questionSlide(slide);
    case SlideType.finding:
      return _findingSlide(slide);
    case SlideType.chart:
      return _chartSlide(slide);
    case SlideType.cockpit:
      return _cockpitSlide(slide);
    case SlideType.tree:
    case SlideType.flow:
    case SlideType.phaseGate:
      return _treeFlowSlide(slide);
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

// ── Fase 3-6: rijke types ──

String _signOffSlide(Slide slide) {
  // signOff heeft alleen een titel — de attestatie zit op deck-niveau.
  final buf = StringBuffer();
  buf.write('\\begin{center}\n');
  buf.write('{\\Large ${_escapeLatex(slide.title)}}\n');
  buf.write('\\end{center}\n');
  return buf.toString();
}

String _menuSlide(Slide slide) {
  // menu: bullets zijn links `[label](#anchor)`. itemize met hyperlink.
  if (slide.bullets.isEmpty) return '';
  final buf = StringBuffer();
  buf.write('\\begin{itemize}\n');
  for (final b in slide.bullets) {
    buf.write('\\item ${markdownInlineToLatex(b)}\n');
  }
  buf.write('\\end{itemize}\n');
  return buf.toString();
}

String _videoSlide(Slide slide) {
  // ponytail: ceiling — LaTeX kan geen video embedden. Toon het pad als
  // hyperlink-tekst. Upgrade path is een externe player + `\href`.
  final buf = StringBuffer();
  if (slide.videoPath.isNotEmpty) {
    buf.write('\\begin{center}\n');
    buf.write(
      r'\href{'
      '${_escapeUrl(slide.videoPath)}}{${_escapeLatex(slide.videoPath)}}\n',
    );
    buf.write('\\end{center}\n');
  }
  return buf.toString();
}

String _timelineSlide(Slide slide) {
  // timeline: bullets als `marker :: titel :: beschrijving`.
  // ponytail: ceiling — eenvoudige itemize i.p.v. TikZ-tijdlijn. Upgrade
  // path is een TikZ-tijdlijn met nodes op een as.
  if (slide.bullets.isEmpty) return '';
  final buf = StringBuffer();
  buf.write('\\begin{itemize}\n');
  for (final b in slide.bullets) {
    final parts = b.split(' :: ');
    final marker = parts.isNotEmpty ? parts[0] : '';
    final title = parts.length > 1 ? parts[1] : '';
    final desc = parts.length > 2 ? parts[2] : '';
    buf.write('\\item[');
    buf.write(_escapeLatex(marker));
    buf.write('] \\textbf{');
    buf.write(_escapeLatex(title));
    buf.write('}');
    if (desc.trim().isNotEmpty) {
      buf.write(' --- ${_escapeLatex(desc)}');
    }
    buf.write('\n');
  }
  buf.write('\\end{itemize}\n');
  return buf.toString();
}

String _questionSlide(Slide slide) {
  // question: customMarkdown bevat een ```question```-fenced JSON-blok.
  // ponytail: ceiling — toon de vraag als tekst + antwoorden als enumerate.
  // Upgrade path is het parsen van QuestionSpec JSON voor een interactief
  // uiterlijk (juiste/gemerkte antwoorden met symbolen).
  return markdownToLatex(slide.customMarkdown);
}

String _findingSlide(Slide slide) {
  // finding: customMarkdown met `##` secties (Description, Confirmation,
  // Impact, Recommendation). De kernconverter vertaalt deze naar
  // \subsection — voldoende voor een Beamer-frame.
  return markdownToLatex(slide.customMarkdown);
}

String _chartSlide(Slide slide) {
  // chart: customMarkdown bevat een ```chart```-fenced JSON-blok met
  // ChartSpec. ponytail: ceiling — toon de chart-data als lstlisting.
  // Upgrade path is pgfplots (fase 4).
  final buf = StringBuffer();
  buf.write('\\begin{lstlisting}\n');
  buf.write(_extractCode(slide.customMarkdown));
  buf.write('\n\\end{lstlisting}\n');
  return buf.toString();
}

String _cockpitSlide(Slide slide) {
  // cockpit: customMarkdown bevat een ```cockpit```-fenced JSON-blok.
  // ponytail: ceiling — toon de cockpit-data als lstlisting. Upgrade path
  // is een TikZ-dashboard met meters.
  final buf = StringBuffer();
  buf.write('\\begin{lstlisting}\n');
  buf.write(_extractCode(slide.customMarkdown));
  buf.write('\n\\end{lstlisting}\n');
  return buf.toString();
}

String _treeFlowSlide(Slide slide) {
  // tree/flow/phaseGate: bullets met geneste hiërarchie (tabs voor nesting).
  // ponytail: ceiling — itemize met nesting i.p.v. TikZ-boom/flowchart.
  // Upgrade path is TikZ (forest voor tree, positioning voor flow).
  if (slide.bullets.isEmpty) return '';
  return _nestedBulletsToLatex(slide.bullets);
}

/// Bouwt geneste itemize-omgevingen uit bullets met tab-inspringing.
String _nestedBulletsToLatex(List<String> bullets) {
  final buf = StringBuffer();
  buf.write('\\begin{itemize}\n');
  for (final b in bullets) {
    final depth = _indentDepth(b);
    final text = b.trim();
    if (depth == 0) {
      buf.write('\\item ${markdownInlineToLatex(text)}\n');
    } else {
      // Sluit diepere itemize-niveaus af en open nieuwe.
      buf.write('\\begin{itemize}\n');
      buf.write('\\item ${markdownInlineToLatex(text)}\n');
      buf.write('\\end{itemize}\n');
    }
  }
  buf.write('\\end{itemize}\n');
  return buf.toString();
}

int _indentDepth(String line) {
  var depth = 0;
  for (final c in line.runes) {
    if (c == 0x09) {
      depth++;
    } else {
      break;
    }
  }
  return depth;
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

String _escapeUrl(String url) {
  if (url.isEmpty) return '';
  return url.replaceAll('%', r'\%').replaceAll('#', r'\#');
}
