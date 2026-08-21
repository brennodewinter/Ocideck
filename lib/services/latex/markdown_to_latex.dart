// Markdown → LaTeX-kernconverter.
//
// Zet een GFM-Markdown-string om in een LaTeX-fragment (geen preamble, geen
// \documentclass — dat leveren de wrappers in latex_preamble.dart). Deze kern
// is gedeeld tussen de Document-export (article) en de Deck-export (beamer):
// de ene gebruikt hem voor de body, de andere per-frame.
//
// Hergebruikt de `markdown`-package (pubspec: `markdown: ^7.3.1`) als
// AST-parser — hetzelfde patroon als `lib/utils/markdown_quill_codec.dart`.
// Geen nieuwe dependency.
//
// Wiskunde-pass-through: `$...$` (inline) en `$$...$$` (display) zijn native
// LaTeX. De converter beschermt de bron tegen de markdown-parser en laat alleen
// bekende wiskundecommando's ongewijzigd terug; onbekende TeX-primitieven
// worden zichtbare, geëscapete tekst.

import 'package:markdown/markdown.dart' as md;

import '../../models/settings.dart' show TableBorderStyle;
import '../../utils/export_link.dart';
import '../../utils/footnotes.dart';
import '../document_footnote_setup.dart';
import '../document_timeline.dart';
import '../markdown_table_codec.dart';

/// Zet [markdown] (GFM) om in een LaTeX-fragment.
///
/// De uitvoer is platte LaTeX zonder preamble. Bedoeld om in een
/// `\documentclass{article}`- of `beamer`-document ingebed te worden door de
/// wrappers in `latex_preamble.dart`.
///
/// [tableBorderStyle] bepaalt de randvorm van tabellen (feature 5):
/// [TableBorderStyle.lined] → booktabs (`\toprule`/`\midrule`/`\bottomrule`,
/// de standaard), [TableBorderStyle.boxed] → volledig omkaderd
/// (`|l|l|…|` + `\hline`), [TableBorderStyle.none] → geen regels.
/// [footnotePlacement] bepaalt waar de voetnoten landen: onderaan de bladzijde
/// (`\footnote`, wat LaTeX zelf al doet) of achterin als genummerde lijst onder
/// [endnotesTitle]. Die titel komt van de aanroeper omdat deze converter geen
/// vertalingen kent — hij is zuiver tekst-in, tekst-uit.
String markdownToLatex(
  String markdown, {
  bool chapterPageBreak = false,
  TableBorderStyle tableBorderStyle = TableBorderStyle.lined,
  FootnotePlacement footnotePlacement = FootnotePlacement.page,
  String endnotesTitle = 'Noten',
}) {
  if (markdown.trim().isEmpty) return '';
  // Voetnoten vóór de parse eruit halen en door een sentinel vervangen, om
  // dezelfde reden als de inhoudsopgave hieronder: `\footnote{…}` als tekst door
  // de parser sturen levert `\textbackslash{}footnote` op — letterlijk die
  // tekens in het document.
  final notes = documentFootnotes(markdown);
  var source = stripFootnoteDefinitions(markdown);
  final timelines = _protectDocumentTimelines(source);
  source = timelines.source;
  for (final note in notes) {
    source = source.replaceAll(
      '[^${note.label}]',
      _footnoteSentinel(note.number),
    );
  }
  // Feature 4: `<!-- toc -->` → `\tableofcontents` (LaTeX genereert zelf de
  // inhoudsopgave bij compilatie). De marker wordt vóór de parse vervangen,
  // zodat de markdown-package het commentaar niet als tekst stript — maar niet
  // meteen door het commando zelf: dat komt als gewone tekst door de parser en
  // wordt dan geëscaped tot `\textbackslash{}tableofcontents`, dus letterlijk
  // die tekst in het document in plaats van een inhoudsopgave. Er gaat een
  // sentinel zonder escape-gevoelige tekens doorheen, die na de conversie het
  // commando wordt.
  const tocSentinel = 'OCIDECKTABLEOFCONTENTSMARKER';
  final withToc = source.replaceAll(
    RegExp(r'^<!-- toc -->\s*$', multiLine: true),
    tocSentinel,
  );
  final protected = _MathProtector.protect(withToc);
  final document = md.Document(
    encodeHtml: false,
    extensionSet: md.ExtensionSet.gitHubFlavored,
  );
  final nodes = document.parse(protected.text);
  final visitor = _LatexNodeVisitor(
    mathBlocks: protected.blocks,
    chapterPageBreak: chapterPageBreak,
    tableBorderStyle: tableBorderStyle,
  );
  for (final node in nodes) {
    node.accept(visitor);
  }
  var out = visitor.output.toString().replaceAll(
    tocSentinel,
    '\\tableofcontents',
  );
  for (var index = 0; index < timelines.latex.length; index++) {
    out = out.replaceAll('OCIDECKTIMELINE${index}END', timelines.latex[index]);
  }
  for (final note in notes) {
    out = out.replaceAll(
      _footnoteSentinel(note.number),
      footnotePlacement == FootnotePlacement.page
          // LaTeX zet hem zelf onderaan het blad en nummert zelf door; het
          // nummer dat wij berekenden komt op hetzelfde uit.
          ? '\\footnote{${markdownInlineToLatex(note.text)}}'
          : '\\textsuperscript{${note.number}}',
    );
  }
  if (notes.isNotEmpty && footnotePlacement == FootnotePlacement.document) {
    out = '$out\n\n${_endnotesSection(notes, endnotesTitle)}';
  }
  return out.trimRight();
}

({String source, List<String> latex}) _protectDocumentTimelines(String source) {
  final lines = source.replaceAll('\r\n', '\n').split('\n');
  final output = <String>[];
  final rendered = <String>[];
  var index = 0;
  while (index < lines.length) {
    if (lines[index].trim() != documentTimelineMarker ||
        index + 2 >= lines.length ||
        !isMarkdownTableLine(lines[index + 1]) ||
        !isMarkdownTableDelimiterRow(lines[index + 2])) {
      output.add(lines[index++]);
      continue;
    }
    var end = index + 3;
    while (end < lines.length && isMarkdownTableLine(lines[end])) {
      end++;
    }
    final marked = lines.sublist(index, end).join('\n');
    final timeline = analyzeMarkedTimeline(marked).timeline;
    if (timeline == null) {
      output.add(lines[index++]);
      continue;
    }
    final buffer = StringBuffer('\\begin{description}\n');
    for (final event in timeline.events) {
      buffer
        ..write('\\item[\\textbf{')
        ..write(markdownInlineToLatex(event.marker))
        ..write('}] ')
        ..write(markdownInlineToLatex(event.event));
      if ((event.metadata ?? '').isNotEmpty) {
        buffer
          ..write(' \\quad {\\footnotesize\\textsf{')
          ..write(markdownInlineToLatex(timeline.headers[2]))
          ..write(': ')
          ..write(markdownInlineToLatex(event.metadata!))
          ..write('}}');
      }
      buffer.writeln();
    }
    buffer.write('\\end{description}');
    output.add('OCIDECKTIMELINE${rendered.length}END');
    rendered.add(buffer.toString());
    index = end;
  }
  return (source: output.join('\n'), latex: rendered);
}

/// Het merkteken dat een voetnootverwijzing tijdens de conversie vervangt.
/// Alleen letters en cijfers, zodat geen enkele escape-regel eraan komt, en met
/// een sluitwoord zodat noot 1 niet in noot 11 zit.
String _footnoteSentinel(int number) => 'OCIDECKFOOTNOTE${number}END';

/// De noten achterin, als genummerde lijst onder een eigen kop.
///
/// Een gewone `enumerate` volstaat: de noten zijn per constructie 1…n in
/// leesvolgorde (zie [documentFootnotes]), dus wat LaTeX telt is precies wat er
/// als merkteken in de tekst staat. Geen extra pakket in de preamble nodig.
String _endnotesSection(List<Footnote> notes, String title) {
  final buf = StringBuffer()
    ..writeln('\\section*{${_escapeText(title)}}')
    ..writeln('\\begin{enumerate}');
  for (final note in notes) {
    buf.writeln('  \\item ${markdownInlineToLatex(note.text)}');
  }
  buf.write('\\end{enumerate}');
  return buf.toString();
}

/// Zet een inline-fragment [markdown] om in LaTeX (geen blok-elementen).
///
/// Gebruikt door de Beamer-slidebouwer voor titels en bullet-tekst waar een
/// volledige blok-parse ongewenst is.
String markdownInlineToLatex(String markdown) {
  if (markdown.isEmpty) return '';
  final protected = _MathProtector.protect(markdown);
  final document = md.Document(
    encodeHtml: false,
    extensionSet: md.ExtensionSet.gitHubFlavored,
  );
  final nodes = document.parseInline(protected.text);
  final visitor = _LatexNodeVisitor(mathBlocks: protected.blocks);
  for (final node in nodes) {
    node.accept(visitor);
  }
  return visitor.output.toString();
}

class _LatexNodeVisitor implements md.NodeVisitor {
  _LatexNodeVisitor({
    this._mathBlocks = const {},
    this.chapterPageBreak = false,
    this.tableBorderStyle = TableBorderStyle.lined,
  });

  final StringBuffer output = StringBuffer();

  /// Of elk hoofdstuk (H1) op een nieuwe pagina begint (instelling).
  final bool chapterPageBreak;

  /// De randstijl van tabellen (feature 5).
  final TableBorderStyle tableBorderStyle;

  /// Of we al een hoofdstuk zijn tegengekomen — het eerste krijgt geen `\newpage`.
  bool _seenChapter = false;

  /// Placeholder → originele math-inhoud. De parser stript backslashes voor
  /// leestekens (`\,` → `,`), dus we beschermen math vóór de parse en herstellen
  /// hem hier.
  final Map<String, String> _mathBlocks;

  /// Stack van context-vlaggen per open element.
  final List<_Ctx> _stack = [];

  /// Tijdelijke buffer voor de huidige tabel-rij; cellen worden hierin
  /// verzameld en bij het sluiten van de rij naar [output] gespoten.
  final StringBuffer _rowBuf = StringBuffer();

  /// Of we momenteel in een tabel bezig zijn — dan schrijven we naar
  /// [_rowBuf] in plaats van [output].
  bool get _inTable => _stack.any((c) => c == _Ctx.table);

  /// Of we in een code-blok zitten (binnen <pre>) — dan geen tekst-escaping.
  bool get _inCodeBlock => _stack.any((c) => c == _Ctx.codeBlock);

  /// Of we in inline-code zitten — dan geen tekst-escaping.
  bool get _inInlineCode => _stack.any((c) => c == _Ctx.inlineCode);

  bool get _suppressEscape => _inCodeBlock || _inInlineCode;

  /// De buffer waar we nu heen schrijven: [_rowBuf] binnen een tabel-cel,
  /// anders [output].
  StringBuffer get _buf => _inTable ? _rowBuf : output;

  @override
  void visitText(md.Text text) {
    if (_suppressEscape) {
      _buf.write(_restoreMath(text.text, escapeUnsafe: false));
      return;
    }
    _buf.write(_escapeProtectedText(text.text));
  }

  String _escapeProtectedText(String text) =>
      _restoreMath(_escapeText(text), escapeUnsafe: true);

  /// Vervang math-placeholders door gevalideerde native wiskunde. Een formule
  /// met onbekende TeX-primitieven wordt zichtbare, geëscapete tekst.
  String _restoreMath(String s, {required bool escapeUnsafe}) {
    if (_mathBlocks.isEmpty) return s;
    var result = s;
    for (final entry in _mathBlocks.entries) {
      final math = entry.value;
      result = result.replaceAll(
        entry.key,
        !escapeUnsafe || _isSafeMath(math)
            ? math
            : '\\texttt{${_escapePlainText(math)}}',
      );
    }
    return result;
  }

  @override
  bool visitElementBefore(md.Element element) {
    switch (element.tag) {
      // ── Koppen ──
      case 'h1':
        // 'Nieuw hoofdstuk op een nieuwe pagina': elk hoofdstuk (H1) op een vers
        // blad, behalve het eerste (anders een leeg openingsblad).
        if (chapterPageBreak && _seenChapter) output.write('\\newpage\n');
        _seenChapter = true;
        output.write('\\section{');
        _stack.add(_Ctx.heading);
      case 'h2':
        output.write('\\subsection{');
        _stack.add(_Ctx.heading);
      case 'h3':
        output.write('\\subsubsection{');
        _stack.add(_Ctx.heading);
      case 'h4':
        output.write('\\paragraph{');
        _stack.add(_Ctx.heading);
      case 'h5':
        output.write('\\subparagraph{');
        _stack.add(_Ctx.heading);
      case 'h6':
        output.write('\\textbf{');
        _stack.add(_Ctx.heading);

      // ── Alinea's en blokken ──
      case 'p':
        _stack.add(_Ctx.paragraph);
      case 'blockquote':
        output.write('\\begin{quote}\n');
        _stack.add(_Ctx.blockquote);
      case 'hr':
        // Een thematische breuk (`---`) is in een document een pagina-einde
        // (DOCUMENT_MODE.md): een nieuw blad, geen zichtbare lijn.
        output.write('\n\\newpage\n');
        return false;

      // ── Lijsten ──
      case 'ul':
        output.write('\\begin{itemize}\n');
        _stack.add(_Ctx.unorderedList);
      case 'ol':
        output.write('\\begin{enumerate}\n');
        _stack.add(_Ctx.orderedList);
      case 'li':
        _visitListItem(element);
        _stack.add(_Ctx.listItem);
      case 'input':
        return false;

      // ── Code ──
      case 'pre':
        _stack.add(_Ctx.codeBlock);
        return true;
      case 'code':
        return _visitCode(element);

      // ── Inline-opmaak ──
      case 'strong':
      case 'b':
        _buf.write('\\textbf{');
        _stack.add(_Ctx.inline);
      case 'em':
      case 'i':
        _buf.write('\\textit{');
        _stack.add(_Ctx.inline);
      case 'del':
      case 's':
        _buf.write('\\sout{');
        _stack.add(_Ctx.inline);

      // ── Links en afbeeldingen ──
      case 'a':
        final href = safeExportLink(element.attributes['href']);
        if (href == null) {
          _stack.add(_Ctx.passThrough);
        } else {
          _buf.write('\\href{${_escapeUrl(href)}}{');
          _stack.add(_Ctx.link);
        }
      case 'img':
        _visitImage(element);
        return false;

      // ── Regelonderbreking ──
      case 'br':
        _buf.write(
          (_stack.contains(_Ctx.paragraph) || _stack.contains(_Ctx.heading))
              ? ' \\\\\n'
              : '\n',
        );
        return false;

      // ── Tabellen (GFM) ──
      case 'table':
        _beginTable();
        return true;
      case 'thead':
        _inTableHead = true;
        _stack.add(_Ctx.passThrough);
        return true;
      case 'tbody':
        _inTableHead = false;
        _stack.add(_Ctx.passThrough);
        return true;
      case 'tr':
        _beginTableRow(element);
        return true;
      case 'th':
      case 'td':
        _stack.add(_Ctx.tableCell);
        if (_inTableHead) _rowBuf.write('\\textbf{');
        return true;

      default:
        _stack.add(_Ctx.passThrough);
    }
    return true;
  }

  void _visitListItem(md.Element element) {
    // GFM task-list: <li class="task-list-item"> met een <input>-kind.
    final isTask =
        element.attributes['class']?.contains('task-list-item') ?? false;
    output.write(isTask ? r'\item[$\square$] ' : r'\item ');
  }

  bool _visitCode(md.Element element) {
    if (_inCodeBlock) {
      // De <code> binnen <pre>: open het listing-blok met de taal.
      final lang =
          element.attributes['class']?.replaceAll('language-', '') ?? '';
      output.write('\\begin{lstlisting}');
      if (lang.isNotEmpty) output.write('[language=$lang]');
      output.write('\n');
      _stack.add(_Ctx.codeBlockBody);
    } else {
      output.write(r'\texttt{');
      _stack.add(_Ctx.inlineCode);
    }
    return true;
  }

  void _visitImage(md.Element element) {
    final src = element.attributes['src'] ?? '';
    final alt = element.attributes['alt'] ?? '';
    final safePath = _safeImagePath(src);
    if (safePath == null) {
      if (alt.trim().isNotEmpty) _buf.write(_escapeProtectedText(alt));
      return;
    }
    // Relatief pad — LaTeX kent geen data-URI-inlining. ponytail: ceiling
    // is single-file; upgrade path is een zip-bundel met .tex + images.
    _buf.write(
      r'\includegraphics[width=0.8\textwidth]{'
      '${_escapeImagePath(safePath)}}',
    );
    if (alt.trim().isNotEmpty) {
      _buf.write('\\\\\\small{${_escapeProtectedText(alt)}}');
    }
  }

  void _beginTable() {
    _stack.add(_Ctx.table);
    _tableRows.clear();
    _tableColCount = 0;
    _inTableHead = false;
  }

  void _beginTableRow(md.Element element) {
    _rowBuf.clear();
    _stack.add(_Ctx.tableRow);
    if (_tableColCount == 0) {
      _tableColCount = element.children?.where(_isCell).length ?? 0;
    }
  }

  @override
  void visitElementAfter(md.Element element) {
    final ctx = _stack.removeLast();
    switch (element.tag) {
      case 'h1':
      case 'h2':
      case 'h3':
      case 'h4':
      case 'h5':
      case 'h6':
        output.write('}\n\n');

      case 'p':
        if (ctx == _Ctx.paragraph) output.write('\n\n');

      case 'blockquote':
        output.write('\n\\end{quote}\n');

      case 'ul':
        output.write('\\end{itemize}\n');
      case 'ol':
        output.write('\\end{enumerate}\n');
      case 'li':
        output.write('\n');

      case 'pre':
        // Niets — de lstlisting wordt op <code>-niveau geopend/gesloten.
        break;
      case 'code':
        if (ctx == _Ctx.codeBlockBody) {
          output.write('\n\\end{lstlisting}\n');
        } else if (ctx == _Ctx.inlineCode) {
          output.write('}');
        }

      case 'strong':
      case 'b':
      case 'em':
      case 'i':
      case 'del':
      case 's':
      case 'a':
        _buf.write('}');

      case 'table':
        // Spuit de tabel uit met de juiste kolomspecificatie en randstijl.
        final spec = switch (tableBorderStyle) {
          TableBorderStyle.boxed => '|${'l|' * _tableColCount}',
          _ => 'l' * _tableColCount,
        };
        output.write('\\begin{tabular}{$spec}\n');
        if (tableBorderStyle == TableBorderStyle.boxed) {
          output.write('\\hline\n');
        } else if (tableBorderStyle == TableBorderStyle.lined) {
          output.write('\\toprule\n');
        }
        output.write(_tableRows);
        // Bij `boxed` sluit elke rij zelf al met een `\hline` af (zie 'tr'),
        // dus de onderrand staat er dan al — nog een regel geeft een dubbele
        // lijn onder de tabel.
        if (tableBorderStyle == TableBorderStyle.lined) {
          output.write('\\bottomrule\n');
        }
        output.write('\\end{tabular}\n');
      case 'thead':
        // Niets — de header/body-scheiding (\midrule) wordt bij de eerste
        // tbody-rij geplaatst.
        break;
      case 'tbody':
        break;
      case 'tr':
        // Ruim de afsluitende celscheiding op en sluit de rij af. Elke cel
        // schrijft ' & ' áchter zich, dus de rij eindigt op ' & ' — mét spatie.
        // Het oude patroon (' ?&$') ankerde op de `&` als laatste teken en
        // trof daardoor niets: elke rij hield een lege cel over (`A & B &  \\`),
        // en dat is er één te veel voor de kolomspec. Geen scheve tabel maar
        // een compileerfout ("Extra alignment tab") op elke geëxporteerde
        // tabel.
        final cleaned = _rowBuf.toString().replaceFirst(
          RegExp(r'\s*&\s*$'),
          '',
        );
        // De koprij is de rij die binnen `<thead>` sluit — niet "de rij ná de
        // eerste". Op die aanname stond de `\midrule` een rij te laag: onder de
        // eerste gegevensrij in plaats van onder de kop.
        final rule = switch ((tableBorderStyle, _inTableHead)) {
          // `boxed` betekent in CSS: elke cel een rand rondom. In LaTeX geven
          // de `|` in de kolomspec alleen de verticale randen; zonder een
          // `\hline` per rij kreeg de body geen enkele horizontale lijn.
          (TableBorderStyle.boxed, _) => '\\hline\n',
          (TableBorderStyle.lined, true) => '\\midrule\n',
          _ => '',
        };
        _tableRows.write('$cleaned \\\\\n$rule');
      case 'th':
      case 'td':
        if (_inTableHead) {
          _rowBuf.write('}');
        }
        _rowBuf.write(' & ');

      default:
        break;
    }
  }

  // ── Tabel-state ──
  final StringBuffer _tableRows = StringBuffer();
  int _tableColCount = 0;
  bool _inTableHead = false;
}

bool _isCell(md.Node n) => n is md.Element && (n.tag == 'th' || n.tag == 'td');

enum _Ctx {
  passThrough,
  heading,
  paragraph,
  blockquote,
  unorderedList,
  orderedList,
  listItem,
  codeBlock, // <pre>
  codeBlockBody, // <code> binnen <pre>
  inlineCode, // <code> buiten <pre>
  inline,
  link,
  table,
  tableRow,
  tableCell,
}

/// Escape LaTeX-speciale tekens in platte tekst. Native math komt uitsluitend
/// via een vooraf beschermde placeholder terug nadat [_isSafeMath] hem heeft
/// gevalideerd; generieke tekst mag dollartekens nooit zelf uitvoerbaar maken.
String _escapeText(String s) => _escapePlainText(s);

String _escapePlainText(String s) {
  final result = StringBuffer();
  for (final char in s.split('')) {
    result.write(char == r'$' ? r'\$' : _escapeChar(char));
  }
  return result.toString();
}

const _safeMathCommands = <String>{
  'alpha',
  'beta',
  'gamma',
  'delta',
  'epsilon',
  'varepsilon',
  'zeta',
  'eta',
  'theta',
  'vartheta',
  'iota',
  'kappa',
  'lambda',
  'mu',
  'nu',
  'xi',
  'pi',
  'varpi',
  'rho',
  'varrho',
  'sigma',
  'varsigma',
  'tau',
  'upsilon',
  'phi',
  'varphi',
  'chi',
  'psi',
  'omega',
  'Gamma',
  'Delta',
  'Theta',
  'Lambda',
  'Xi',
  'Pi',
  'Sigma',
  'Upsilon',
  'Phi',
  'Psi',
  'Omega',
  'frac',
  'sqrt',
  'sum',
  'prod',
  'int',
  'iint',
  'iiint',
  'oint',
  'lim',
  'log',
  'ln',
  'exp',
  'sin',
  'cos',
  'tan',
  'min',
  'max',
  'sup',
  'inf',
  'det',
  'gcd',
  'left',
  'right',
  'big',
  'Big',
  'bigg',
  'Bigg',
  'overline',
  'underline',
  'vec',
  'hat',
  'bar',
  'dot',
  'ddot',
  'mathbf',
  'mathrm',
  'mathit',
  'mathsf',
  'mathtt',
  'mathcal',
  'mathbb',
  'mathfrak',
  'operatorname',
  'text',
  'pm',
  'mp',
  'times',
  'div',
  'cdot',
  'ast',
  'star',
  'circ',
  'bullet',
  'oplus',
  'otimes',
  'le',
  'leq',
  'ge',
  'geq',
  'ne',
  'neq',
  'approx',
  'sim',
  'simeq',
  'equiv',
  'propto',
  'in',
  'notin',
  'subset',
  'subseteq',
  'supset',
  'supseteq',
  'cup',
  'cap',
  'emptyset',
  'infty',
  'partial',
  'nabla',
  'forall',
  'exists',
  'neg',
  'land',
  'lor',
  'to',
  'rightarrow',
  'leftarrow',
  'leftrightarrow',
  'Rightarrow',
  'Leftarrow',
  'Leftrightarrow',
  'mapsto',
  'ldots',
  'cdots',
  'vdots',
  'ddots',
  'quad',
  'qquad',
  'colon',
};

final _mathCommand = RegExp(r'\\([A-Za-z]+|.)');

bool _isSafeMath(String math) {
  final body = math.startsWith(r'$$')
      ? math.substring(2, math.length - 2)
      : math.substring(1, math.length - 1);
  if (body.contains(RegExp(r'[#$%&]')) || body.contains('^^')) return false;
  for (final match in _mathCommand.allMatches(body)) {
    final command = match.group(1)!;
    if (command.length == 1) {
      if (!r',;:! {}_|'.contains(command)) return false;
    } else if (!_safeMathCommands.contains(command)) {
      return false;
    }
  }
  return true;
}

String _escapeChar(String c) {
  switch (c) {
    case r'\':
      return r'\textbackslash{}';
    case '&':
      return r'\&';
    case '%':
      return r'\%';
    case '#':
      return r'\#';
    case '_':
      return r'\_';
    case '{':
      return r'\{';
    case '}':
      return r'\}';
    case '~':
      return r'\textasciitilde{}';
    case '^':
      return r'\textasciicircum{}';
    default:
      return c;
  }
}

/// Escape een URL voor `\href{...}`. `%` en `#` zijn problematisch in
/// hyperref-argumenten.
String _escapeUrl(String url) {
  if (url.isEmpty) return '';
  return url
      .replaceAll(r'\', r'\textbackslash{}')
      .replaceAll('{', r'\{')
      .replaceAll('}', r'\}')
      .replaceAll('%', r'\%')
      .replaceAll('#', r'\#');
}

/// Normaliseer een afbeeldingspad voor `\includegraphics`. LaTeX gebruikt
/// forward slashes. Data-URI's kunnen niet — ponytail: ceiling, zie
/// header-comment.
String _escapeImagePath(String src) {
  if (src.isEmpty) return '';
  return src.replaceAll(r'\', '/');
}

String? _safeImagePath(String src) {
  final normalized = src.trim().replaceAll(r'\', '/');
  if (normalized.isEmpty ||
      normalized.startsWith('/') ||
      RegExp(r'^[A-Za-z][A-Za-z0-9+.-]*:').hasMatch(normalized) ||
      normalized.split('/').contains('..') ||
      normalized.runes.any((rune) => rune < 0x20 || rune == 0x7f) ||
      RegExp(r'[{}%#$&~^]').hasMatch(normalized)) {
    return null;
  }
  return normalized;
}

/// Beschermt LaTeX-math (`$$...$$` en `$...$`) tegen de markdown-parser, die
/// backslashes voor leestekens stript (`\,` → `,`).
///
/// Vervangt elk math-blok door een unieke placeholder vóór de parse, en geeft
/// de mapping terug zodat de visitor de placeholders kan herstellen. De
/// placeholder bevat geen markdown-speciale tekens, zodat de parser hem
/// ongemoeid laat.
class _MathProtector {
  final String text;
  final Map<String, String> blocks;

  _MathProtector._(this.text, this.blocks);

  static _MathProtector protect(String input) {
    final blocks = <String, String>{};
    var result = input;
    var i = 0;

    // Eerst display-math $$...$$ (langste-match eerst, anders splitst $$ in
    // twee losse $).
    final displayMath = RegExp(r'\$\$(.*?)\$\$', dotAll: true);
    result = result.replaceAllMapped(displayMath, (m) {
      final key = '@@OCIDECKMATH$i@@';
      blocks[key] = m[0]!;
      i++;
      return key;
    });

    // Dan inline-math $...$ — niet-gepaarde $ (zoals valuta) laten we staan.
    final inlineMath = RegExp(r'\$([^\$\n]+?)\$');
    result = result.replaceAllMapped(inlineMath, (m) {
      final key = '@@OCIDECKMATH$i@@';
      blocks[key] = m[0]!;
      i++;
      return key;
    });

    return _MathProtector._(result, blocks);
  }
}
