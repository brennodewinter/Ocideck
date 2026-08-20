/// Zet klembord-HTML om naar Markdown. De HTML zelf wordt nooit gerenderd.
///
/// Webtoepassingen zetten naast platte tekst vaak een HTML-variant op het
/// klembord, en dáár zit de structuur (geneste lijsten, koppen) die in de
/// platte-tekstvariant al is platgeslagen (#1595, #1556). Deze omzetting is
/// de enige plek waar die bytes binnenkomen: ontleden, een begrensde set
/// constructies naar Markdown, de rest weg.
library;

import 'package:html/dom.dart';
import 'package:html/parser.dart' as html_parser;

import 'markdown_paste_cleanup.dart';

/// Een hele pagina op het klembord mag de omzetting niet vastzetten.
const kClipboardHtmlMaxChars = 256 * 1024;

/// Haalt de CF_HTML-envelope en Apple-fragmentmarkeringen van klembord-HTML.
///
/// Windows levert `Version:0.9` + byte-offsets; WebKit zet
/// `<!--StartFragment-->` om het geselecteerde stuk. De offsets zelf zijn
/// onbetrouwbaar (bytes vs. tekens); de fragmentmarkering en de eerste `<`
/// na een CF_HTML-kop zijn dat wel.
String unwrapClipboardHtml(String raw) {
  var s = raw.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
  const startFrag = '<!--StartFragment-->';
  const endFrag = '<!--EndFragment-->';
  final start = s.indexOf(startFrag);
  final end = s.indexOf(endFrag);
  if (start >= 0 && end > start) {
    return s.substring(start + startFrag.length, end);
  }
  if (s.startsWith('Version:')) {
    final lt = s.indexOf('<');
    if (lt >= 0) return s.substring(lt);
  }
  return s;
}

/// Markdown uit klembord-HTML, of `null` als er niets bruikbaars in zit.
///
/// Te groot, leeg na uitpakken, of alleen ruis: `null`, zodat de aanroeper
/// op de platte-tekstvariant terugvalt. Stijl, class, script en onveilige
/// URL's leveren geen uitvoer.
String? htmlClipboardToMarkdown(String raw) {
  if (raw.isEmpty || raw.length > kClipboardHtmlMaxChars) return null;
  final unwrapped = unwrapClipboardHtml(raw);
  if (unwrapped.trim().isEmpty) return null;
  final document = html_parser.parse(unwrapped);
  final root = document.body ?? document.documentElement;
  if (root == null) return null;
  final buf = StringBuffer();
  _convertChildren(root, buf, listDepth: 0);
  final md = sanitizeMarkdownPaste(buf.toString());
  return md.isEmpty ? null : md;
}

const _skipTags = {
  'script',
  'style',
  'head',
  'meta',
  'link',
  'noscript',
  'iframe',
  'object',
  'embed',
  'svg',
  'img',
  'button',
  'input',
  'textarea',
  'select',
};

void _convertChildren(Node parent, StringBuffer buf, {required int listDepth}) {
  for (final node in parent.nodes) {
    _convertNode(node, buf, listDepth: listDepth);
  }
}

void _convertNode(Node node, StringBuffer buf, {required int listDepth}) {
  if (node is Text) {
    _writeText(buf, node.text);
    return;
  }
  if (node is! Element) return;
  final tag = node.localName?.toLowerCase() ?? '';
  if (_skipTags.contains(tag)) {
    if (tag == 'img') _writeText(buf, node.attributes['alt'] ?? '');
    return;
  }
  switch (tag) {
    case 'h1':
    case 'h2':
    case 'h3':
    case 'h4':
    case 'h5':
    case 'h6':
      _convertHeading(node, buf, int.parse(tag.substring(1)));
    case 'p':
    case 'div':
    case 'section':
    case 'article':
    case 'header':
    case 'footer':
    case 'main':
      _convertBlock(node, buf, listDepth: listDepth);
    case 'br':
      buf.write('\n');
    case 'ul':
      _convertList(node, buf, listDepth: listDepth, ordered: false);
    case 'ol':
      _convertList(node, buf, listDepth: listDepth, ordered: true);
    case 'li':
      // Losse `li` buiten een lijst: behandel als één item.
      _convertListItem(
        node,
        buf,
        listDepth: listDepth,
        ordered: false,
        index: 1,
      );
    case 'blockquote':
      _convertBlockquote(node, buf);
    case 'pre':
      _convertPre(node, buf);
    case 'code':
      if (_hasAncestor(node, 'pre')) {
        _writeText(buf, node.text);
      } else {
        _writeInlineCode(buf, node.text);
      }
    case 'strong':
    case 'b':
      _wrapInline(node, buf, '**', listDepth: listDepth);
    case 'em':
    case 'i':
      _wrapInline(node, buf, '*', listDepth: listDepth);
    case 'a':
      _convertAnchor(node, buf, listDepth: listDepth);
    case 'table':
      _convertTable(node, buf);
    case 'hr':
      _ensureBlankLine(buf);
      buf.writeln('---');
      _ensureBlankLine(buf);
    default:
      _convertChildren(node, buf, listDepth: listDepth);
  }
}

void _convertHeading(Element node, StringBuffer buf, int level) {
  _ensureBlankLine(buf);
  buf.write('${'#' * level} ');
  final inner = StringBuffer();
  _convertChildren(node, inner, listDepth: 0);
  buf.writeln(inner.toString().trim());
  _ensureBlankLine(buf);
}

void _convertBlock(Element node, StringBuffer buf, {required int listDepth}) {
  if (listDepth == 0) _ensureBlankLine(buf);
  _convertChildren(node, buf, listDepth: listDepth);
  if (listDepth == 0) {
    buf.write('\n');
    _ensureBlankLine(buf);
  }
}

void _convertList(
  Element node,
  StringBuffer buf, {
  required int listDepth,
  required bool ordered,
}) {
  _ensureLineStart(buf);
  var index = 1;
  for (final child in node.nodes) {
    if (child is! Element) continue;
    if ((child.localName ?? '').toLowerCase() != 'li') {
      _convertNode(child, buf, listDepth: listDepth);
      continue;
    }
    _convertListItem(
      child,
      buf,
      listDepth: listDepth,
      ordered: ordered,
      index: index,
    );
    index++;
  }
  if (listDepth == 0) _ensureBlankLine(buf);
}

void _convertListItem(
  Element node,
  StringBuffer buf, {
  required int listDepth,
  required bool ordered,
  required int index,
}) {
  _ensureLineStart(buf);
  buf.write('${'  ' * listDepth}${ordered ? '$index. ' : '- '}');
  final nested = <Element>[];
  for (final child in node.nodes) {
    if (child is Element) {
      final tag = child.localName?.toLowerCase() ?? '';
      if (tag == 'ul' || tag == 'ol') {
        nested.add(child);
        continue;
      }
    }
    _convertNode(child, buf, listDepth: listDepth);
  }
  _ensureLineStart(buf);
  for (final list in nested) {
    _convertList(
      list,
      buf,
      listDepth: listDepth + 1,
      ordered: (list.localName ?? '').toLowerCase() == 'ol',
    );
  }
}

void _convertBlockquote(Element node, StringBuffer buf) {
  _ensureBlankLine(buf);
  final inner = StringBuffer();
  _convertChildren(node, inner, listDepth: 0);
  for (final line in inner.toString().trim().split('\n')) {
    buf.writeln('> $line');
  }
  _ensureBlankLine(buf);
}

void _convertPre(Element node, StringBuffer buf) {
  _ensureBlankLine(buf);
  var fence = '```';
  final text = node.text.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
  while (text.contains(fence)) {
    fence = '$fence`';
  }
  buf.writeln(fence);
  buf.write(text.trimRight());
  if (!text.endsWith('\n')) buf.write('\n');
  buf.writeln(fence);
  _ensureBlankLine(buf);
}

void _writeInlineCode(StringBuffer buf, String raw) {
  final text = raw.replaceAll('\n', ' ').trim();
  if (text.isEmpty) return;
  var ticks = '`';
  while (text.contains(ticks)) {
    ticks = '$ticks`';
  }
  final pad = text.startsWith('`') || text.endsWith('`') ? ' ' : '';
  buf.write('$ticks$pad$text$pad$ticks');
}

void _wrapInline(
  Element node,
  StringBuffer buf,
  String mark, {
  required int listDepth,
}) {
  final inner = StringBuffer();
  _convertChildren(node, inner, listDepth: listDepth);
  final text = inner.toString();
  if (text.trim().isEmpty) return;
  buf.write('$mark${text.trim()}$mark');
}

void _convertAnchor(Element node, StringBuffer buf, {required int listDepth}) {
  final inner = StringBuffer();
  _convertChildren(node, inner, listDepth: listDepth);
  final text = inner.toString().trim();
  if (text.isEmpty) return;
  final href = (node.attributes['href'] ?? '').trim();
  if (!_safeHref(href)) {
    buf.write(text);
    return;
  }
  buf.write('[$text]($href)');
}

bool _safeHref(String href) {
  if (href.isEmpty) return false;
  final lower = href.toLowerCase();
  if (lower.contains('javascript:') ||
      lower.contains('vbscript:') ||
      lower.contains('data:')) {
    return false;
  }
  return true;
}

void _convertTable(Element node, StringBuffer buf) {
  final rows = <List<String>>[];
  for (final rowEl in node.querySelectorAll('tr')) {
    final cells = <String>[];
    for (final cell in rowEl.nodes) {
      if (cell is! Element) continue;
      final tag = cell.localName?.toLowerCase() ?? '';
      if (tag != 'td' && tag != 'th') continue;
      final inner = StringBuffer();
      _convertChildren(cell, inner, listDepth: 0);
      cells.add(
        inner.toString().trim().replaceAll('\n', ' ').replaceAll('|', r'\|'),
      );
    }
    if (cells.isNotEmpty) rows.add(cells);
  }
  if (rows.isEmpty) return;
  final cols = rows.fold<int>(1, (m, r) => r.length > m ? r.length : m);
  String line(List<String> r) =>
      '| ${List.generate(cols, (c) => c < r.length ? r[c] : '').join(' | ')} |';
  _ensureBlankLine(buf);
  buf.writeln(line(rows.first));
  buf.writeln('| ${List.filled(cols, '---').join(' | ')} |');
  for (final r in rows.skip(1)) {
    buf.writeln(line(r));
  }
  _ensureBlankLine(buf);
}

void _writeText(StringBuffer buf, String raw) {
  if (raw.isEmpty) return;
  var text = raw.replaceAll('\u00A0', ' ');
  text = text.replaceAll(RegExp(r'[ \t\f\v]+'), ' ');
  text = text.replaceAll(RegExp(r'\n+'), ' ');
  if (text.isEmpty) return;
  final atStart = buf.isEmpty || buf.toString().endsWith('\n');
  if (atStart) text = text.replaceFirst(RegExp(r'^ +'), '');
  if (text.isEmpty) return;
  buf.write(text);
}

void _ensureBlankLine(StringBuffer buf) {
  if (buf.isEmpty) return;
  final s = buf.toString();
  if (s.endsWith('\n\n')) return;
  if (s.endsWith('\n')) {
    buf.write('\n');
    return;
  }
  buf.write('\n\n');
}

void _ensureLineStart(StringBuffer buf) {
  if (buf.isEmpty || buf.toString().endsWith('\n')) return;
  buf.write('\n');
}

bool _hasAncestor(Element node, String tag) {
  var parent = node.parent;
  while (parent != null) {
    if ((parent.localName ?? '').toLowerCase() == tag) return true;
    parent = parent.parent;
  }
  return false;
}
