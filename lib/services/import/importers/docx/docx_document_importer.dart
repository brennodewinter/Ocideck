// DOCX (WordprocessingML / OOXML) → Markdown converter.
//
// Leest een `.docx` en zet de doorlopende tekstinhoud om in GFM-Markdown.
// Headless: geen Flutter, geen IO — draait op bytes, dus ook op web.
//
// Parseert `word/document.xml` (de body), `word/styles.xml` (kop-stijlnamen)
// en `word/_rels/document.xml.rels` (hyperlink-relaties). `word/numbering.xml`
// wordt gelezen om onderscheid te maken tussen geordende en ongeordende lijsten.
//
// Best-effort: koppen, lijsten, tabellen, vet/cursief/doorgestreept en links
// gaan mee; wat geen Markdown-tegenhanger heeft (voetnoten, tekstkaders,
// positie-geplaatste objecten) valt stil. De uitvoer is gewone Markdown.

import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:xml/xml.dart';

import '../../utils/archive_utils.dart';
import '../../utils/import_budget.dart';
import '../../utils/xml_utils.dart';

/// Zet de bytes van een `.docx` om in Markdown.
///
/// Gooit [ImportBudgetException] bij overschrijding van het budget,
/// [FormatException] bij een beschadigd archief, en [Exception] bij een
/// onleesbaar onderdeel.
String convertDocxToMarkdown(
  List<int> bytes, {
  ImportBudget budget = ImportBudget.standard,
}) {
  final archive = safeDecodeZip(bytes, budget: budget);
  final ctx = _DocxContext(archive, budget: budget);

  final doc = ctx.readXml('word/document.xml');
  if (doc == null) {
    throw FormatException('word/document.xml ontbreekt — geen geldig .docx');
  }

  final body = _findLocal(doc, 'body');
  if (body == null) {
    throw FormatException('Geen <w:body> gevonden — geen geldig .docx');
  }

  final buf = StringBuffer();
  for (final child in body.children.whereType<XmlElement>()) {
    _emitBlock(ctx, child, buf, indent: '');
  }
  return _trimTrailingBlank(buf.toString());
}

XmlElement? _findLocal(XmlNode root, String local) {
  for (final node in root.descendants.whereType<XmlElement>()) {
    if (node.name.local == local) return node;
  }
  return null;
}

void _emitBlock(
  _DocxContext ctx,
  XmlElement el,
  StringBuffer buf, {
  required String indent,
}) {
  switch (el.name.local) {
    case 'p':
      _emitParagraph(ctx, el, buf, indent: indent);
    case 'tbl':
      _emitTable(ctx, el, buf);
      buf.writeln();
    case 'sdt':
      // Structured document tag: loop door de inhoud.
      for (final child in el.descendants.whereType<XmlElement>()) {
        if (child.name.local == 'p') {
          _emitParagraph(ctx, child, buf, indent: indent);
        }
      }
    default:
      break;
  }
}

void _emitParagraph(
  _DocxContext ctx,
  XmlElement p,
  StringBuffer buf, {
  required String indent,
}) {
  final pPr = _child(p, 'pPr');
  final styleVal = pPr != null ? _val(_child(pPr, 'pStyle')) : null;
  final headingLevel = ctx.headingLevel(styleVal);

  // Lijstitem?
  final numPr = pPr != null ? _child(pPr, 'numPr') : null;
  final isList = numPr != null;
  final numId = numPr != null ? _val(_child(numPr, 'numId')) : null;
  final ordered = numId != null && ctx.isNumbered(numId);
  final ilvl = numPr != null
      ? int.tryParse(_val(_child(numPr, 'ilvl')) ?? '') ?? 0
      : 0;

  final text = _inlineText(ctx, p);

  if (headingLevel > 0) {
    final hashes = '#' * headingLevel;
    buf.writeln('$hashes $text');
    buf.writeln();
    return;
  }

  if (isList) {
    final pad = '$indent${'  ' * ilvl}';
    final marker = ordered ? '1. ' : '- ';
    if (text.isNotEmpty) {
      buf.writeln('$pad$marker$text');
    }
    return;
  }

  if (text.isEmpty) {
    buf.writeln();
    return;
  }
  buf.writeln('$indent$text');
  buf.writeln();
}

void _emitTable(_DocxContext ctx, XmlElement tbl, StringBuffer buf) {
  final rows = <List<String>>[];
  for (final tr in _children(tbl, 'tr')) {
    final cells = <String>[];
    for (final tc in _children(tr, 'tc')) {
      cells.add(_cellText(ctx, tc));
    }
    if (cells.isNotEmpty) rows.add(cells);
  }
  if (rows.isEmpty) return;

  final header = rows.first;
  final body = rows.length > 1 ? rows.sublist(1) : const <List<String>>[];
  buf.writeln('| ${header.join(' | ')} |');
  buf.writeln('| ${header.map((_) => '---').join(' | ')} |');
  for (final row in body) {
    buf.writeln('| ${row.join(' | ')} |');
  }
}

String _cellText(_DocxContext ctx, XmlElement tc) {
  final parts = <String>[];
  for (final p in _descendants(tc, 'p')) {
    final t = _inlineText(ctx, p).trim();
    if (t.isNotEmpty) parts.add(t);
  }
  return parts.join(' <br> ');
}

/// Verzamelt de inline tekst van een element, met vet/cursief/links.
String _inlineText(_DocxContext ctx, XmlElement el) {
  final buf = StringBuffer();
  for (final child in el.children) {
    if (child is XmlElement) {
      _walkInline(ctx, child, buf, bold: false, italic: false, strike: false);
    }
  }
  return buf.toString().trim();
}

void _walkInline(
  _DocxContext ctx,
  XmlElement el,
  StringBuffer buf, {
  required bool bold,
  required bool italic,
  required bool strike,
}) {
  switch (el.name.local) {
    case 'r':
      final rPr = _child(el, 'rPr');
      final b = bold || (rPr != null && _child(rPr, 'b') != null);
      final i = italic || (rPr != null && _child(rPr, 'i') != null);
      final s = strike || (rPr != null && _child(rPr, 'strike') != null);
      final prefix = StringBuffer();
      if (b && !bold) prefix.write('**');
      if (i && !italic) prefix.write('_');
      if (s && !strike) prefix.write('~~');
      buf.write(prefix);
      for (final child in el.children) {
        if (child is XmlText) {
          buf.write(_escapeMarkdown(child.value));
        } else if (child is XmlElement) {
          _walkRunChild(ctx, child, buf, bold: b, italic: i, strike: s);
        }
      }
      final suffix = StringBuffer();
      if (s && !strike) suffix.write('~~');
      if (i && !italic) suffix.write('_');
      if (b && !bold) suffix.write('**');
      buf.write(suffix);
    case 'hyperlink':
      final rid = _attr(el, 'id');
      final anchor = _attr(el, 'anchor');
      final text = _inlineText(ctx, el);
      final url = rid != null
          ? ctx.relationship(rid)
          : (anchor != null ? '#$anchor' : null);
      if (url != null && url.isNotEmpty && text.isNotEmpty) {
        buf.write('[$text]($url)');
      } else {
        buf.write(text);
      }
    case 't':
      buf.write(_escapeText(el.innerText));
    case 'tab':
      buf.write(' ');
    case 'br':
      buf.write('\n');
    case 'cr':
      buf.write('\n');
    default:
      for (final child in el.children.whereType<XmlElement>()) {
        _walkInline(
          ctx,
          child,
          buf,
          bold: bold,
          italic: italic,
          strike: strike,
        );
      }
  }
}

void _walkRunChild(
  _DocxContext ctx,
  XmlElement el,
  StringBuffer buf, {
  required bool bold,
  required bool italic,
  required bool strike,
}) {
  switch (el.name.local) {
    case 't':
      buf.write(_escapeText(el.innerText));
    case 'tab':
      buf.write(' ');
    case 'br':
      buf.write('\n');
    case 'cr':
      buf.write('\n');
    default:
      _walkInline(ctx, el, buf, bold: bold, italic: italic, strike: strike);
  }
}

String _escapeText(String s) => s
    .replaceAll('\\', '\\\\')
    .replaceAll('*', '\\*')
    .replaceAll('_', '\\_')
    .replaceAll('[', '\\[')
    .replaceAll(']', '\\]')
    .replaceAll('`', '\\`')
    .replaceAll('#', '\\#')
    .replaceAll('|', '\\|');

String _escapeMarkdown(String s) => _escapeText(s);

String _trimTrailingBlank(String s) {
  var out = s.trimRight();
  if (out.isNotEmpty) out += '\n';
  return out;
}

// --- Namespace-agnostic XML helpers (local-name based) ----------------------

XmlElement? _child(XmlElement parent, String local) {
  for (final node in parent.children.whereType<XmlElement>()) {
    if (node.name.local == local) return node;
  }
  return null;
}

Iterable<XmlElement> _children(XmlElement parent, String local) =>
    parent.children.whereType<XmlElement>().where((e) => e.name.local == local);

Iterable<XmlElement> _descendants(XmlNode root, String local) => root
    .descendants
    .whereType<XmlElement>()
    .where((e) => e.name.local == local);

String? _val(XmlElement? el) {
  if (el == null) return null;
  for (final a in el.attributes) {
    if (a.name.local == 'val') return a.value;
  }
  return null;
}

String? _attr(XmlElement el, String local) {
  for (final a in el.attributes) {
    if (a.name.local == local) return a.value;
  }
  return null;
}

// --- Context: styles, relationships, numbering -------------------------------

class _DocxContext {
  _DocxContext(this.archive, {this.budget = ImportBudget.standard});

  final Archive archive;
  final ImportBudget budget;
  final _parsed = <String, XmlDocument?>{};
  Map<String, int>?
  _headingStyles; // style-id → heading level (0 = not heading)
  Map<String, String>? _relationships; // r:id → target URL
  Map<String, bool>? _numbering; // numId → isOrdered

  String? readPart(String path) {
    final bytes = readPartBytes(path);
    return bytes == null ? null : utf8.decode(bytes);
  }

  List<int>? readPartBytes(String path) {
    for (final f in archive) {
      if (f.name == path) return f.content as List<int>;
    }
    return null;
  }

  XmlDocument? readXml(String path) {
    return _parsed.putIfAbsent(path, () {
      final src = readPart(path);
      if (src == null) return null;
      return parseXmlSafe(src, budget: budget);
    });
  }

  /// Geeft het kopniveau (1–6) voor een stijl-ID, of 0 als het geen kop is.
  int headingLevel(String? styleId) {
    if (styleId == null) return 0;
    _headingStyles ??= _loadHeadingStyles();
    return _headingStyles![styleId] ?? 0;
  }

  /// Geeft de doel-URL voor een relatie-ID, of null.
  String? relationship(String rid) {
    _relationships ??= _loadRelationships();
    return _relationships![rid];
  }

  /// Geeft true als een numId een geordende lijst is.
  bool isNumbered(String? numId) {
    if (numId == null) return false;
    _numbering ??= _loadNumbering();
    return _numbering![numId] ?? false;
  }

  Map<String, int> _loadHeadingStyles() {
    final result = <String, int>{};
    final doc = readXml('word/styles.xml');
    if (doc == null) return result;
    for (final style in _descendants(doc, 'style')) {
      final id = _attr(style, 'styleId');
      if (id == null) continue;
      final name = _val(_child(style, 'name')) ?? '';
      // Standaard OOXML: styleId="Heading1", name="heading 1".
      // Maar gelokaliseerde installaties gebruiken andere styleId's,
      // terwijl de name altijd "heading N" is (OOXML-standaard).
      final level = _headingLevelFromName(name) ?? _headingLevelFromId(id) ?? 0;
      if (level > 0) result[id] = level;
    }
    return result;
  }

  int? _headingLevelFromName(String name) {
    final m = RegExp(r'heading\s+(\d)', caseSensitive: false).firstMatch(name);
    if (m != null) return int.tryParse(m.group(1)!);
    return null;
  }

  int? _headingLevelFromId(String id) {
    final m = RegExp(r'heading(\d)', caseSensitive: false).firstMatch(id);
    if (m != null) return int.tryParse(m.group(1)!);
    if (id.toLowerCase() == 'title') return 1;
    return null;
  }

  Map<String, String> _loadRelationships() {
    final result = <String, String>{};
    final doc = readXml('word/_rels/document.xml.rels');
    if (doc == null) return result;
    for (final rel in _descendants(doc, 'Relationship')) {
      final id = _attr(rel, 'Id');
      final target = _attr(rel, 'Target');
      if (id != null && target != null) result[id] = target;
    }
    return result;
  }

  Map<String, bool> _loadNumbering() {
    final result = <String, bool>{};
    final doc = readXml('word/numbering.xml');
    if (doc == null) return result;
    // numId → abstractNumId
    final numToAbstract = <String, String>{};
    for (final num in _descendants(doc, 'num')) {
      final numId = _attr(num, 'numId');
      final abstractId = _val(_child(num, 'abstractNumId'));
      if (numId != null && abstractId != null) {
        numToAbstract[numId] = abstractId;
      }
    }
    // abstractNumId → isOrdered (op basis van het eerste lvl's numFmt)
    final abstractToOrdered = <String, bool>{};
    for (final abs in _descendants(doc, 'abstractNum')) {
      final absId = _attr(abs, 'abstractNumId');
      if (absId == null) continue;
      final firstLvl = _child(abs, 'lvl');
      if (firstLvl == null) continue;
      final fmt = _val(_child(firstLvl, 'numFmt')) ?? '';
      abstractToOrdered[absId] =
          fmt == 'decimal' ||
          fmt == 'decimalEnclosedParen' ||
          fmt == 'decimalZero';
    }
    for (final entry in numToAbstract.entries) {
      result[entry.key] = abstractToOrdered[entry.value] ?? false;
    }
    return result;
  }
}
