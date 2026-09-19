// ODT (OpenDocument Text) → Markdown converter.
//
// Leest een `.odt` (ISO 26300) en zet de doorlopende tekstinhoud om in GFM-
// Markdown. Headless: geen Flutter, geen IO — draait op bytes, dus ook op web.
// Hergebruikt de namespace-agnostische XML-helpers uit de ODP-importeur
// (ODT en ODP delen hetzelfde ODF-XML-model: `text:p`, `text:h`, `text:list`,
// `table:table`).
//
// Best-effort: structuur (koppen, lijsten, tabellen, vet/cursief, links) gaat
// mee; wat geen Markdown-tegenhanger heeft (voetnoten, annotaties, geneste
// frames) valt stil. De uitvoer is gewone Markdown — geen slot, geen nieuwe
// afhankelijkheid.

import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:xml/xml.dart';

import '../../../../utils/content_hash.dart';
import '../../models/source_document_style.dart';
import '../../utils/archive_utils.dart';
import '../../utils/import_budget.dart';
import '../../utils/xml_utils.dart';
import '../odp/odp_context.dart'
    show descendantsLocal, childLocal, childrenLocal, xlinkHref;

part 'odt_document_style.dart';

/// Wat de import van een `.odt` oplevert: de Markdown, de huisstijl van de
/// bron en het aantal beelden in de tekst dat niet mee kon (#2120).
class OdtDocumentImport {
  const OdtDocumentImport({
    required this.markdown,
    required this.style,
    required this.skippedImages,
  });

  final String markdown;
  final SourceDocumentStyle style;
  final int skippedImages;
}

/// Zet de bytes van een `.odt` om in Markdown.
///
/// Gooit [ImportBudgetException] bij overschrijding van het budget,
/// [FormatException] bij een beschadigd archief, en [Exception] bij een
/// onleesbaar onderdeel. De aanroeper vangt deze en vertaalt ze naar
/// gebruikersmeldingen.
String convertOdtToMarkdown(
  List<int> bytes, {
  ImportBudget budget = ImportBudget.standard,
}) => importOdt(bytes, budget: budget).markdown;

/// Leest een `.odt`: de Markdown én de huisstijl van de bron. Dezelfde
/// uitzonderingen als [convertOdtToMarkdown].
OdtDocumentImport importOdt(
  List<int> bytes, {
  ImportBudget budget = ImportBudget.standard,
}) {
  final archive = safeDecodeZip(bytes, budget: budget);
  final ctx = _OdtContext(archive, budget: budget);

  final doc = ctx.readXml('content.xml');
  if (doc == null) {
    throw FormatException('content.xml ontbreekt — geen geldig .odt');
  }

  final text = _findOfficeText(doc);
  if (text == null) {
    throw FormatException('Geen <office:text> gevonden — geen geldig .odt');
  }

  final buf = StringBuffer();
  for (final child in text.children.whereType<XmlElement>()) {
    _emitBlock(ctx, child, buf, indent: '');
  }
  return OdtDocumentImport(
    markdown: _trimTrailingBlank(buf.toString()),
    style: _extractOdtStyle(ctx),
    skippedImages: descendantsLocal(
      text,
      'frame',
    ).where((f) => descendantsLocal(f, 'image').isNotEmpty).length,
  );
}

XmlElement? _findOfficeText(XmlDocument doc) {
  for (final el in descendantsLocal(doc, 'body')) {
    final text = childLocal(el, 'text');
    if (text != null) return text;
  }
  return null;
}

void _emitBlock(
  _OdtContext ctx,
  XmlElement el,
  StringBuffer buf, {
  required String indent,
}) {
  switch (el.name.local) {
    case 'h':
      final level = int.tryParse(_attr(el, 'outline-level') ?? '') ?? 1;
      final hashes = '#' * level.clamp(1, 6);
      buf.writeln('$hashes ${_inlineText(ctx, el)}');
      buf.writeln();
    case 'p':
      final text = _inlineText(ctx, el);
      if (text.isNotEmpty) {
        buf.writeln('$indent$text');
        buf.writeln();
      }
    case 'list':
      _emitList(ctx, el, buf, indent: indent);
    case 'table':
      _emitTable(ctx, el, buf);
      buf.writeln();
    case 'soft-page-break':
      // Pagina-einde: negeer — Markdown kent geen pagina's.
      break;
    case 'section':
      // Een <text:section> is een benoemd bereik; de inhoud loopt door.
      for (final child in el.children.whereType<XmlElement>()) {
        _emitBlock(ctx, child, buf, indent: indent);
      }
    default:
      // Onbekend blok: probeer de tekst eruit te halen, anders negeer.
      final text = _inlineText(ctx, el);
      if (text.isNotEmpty) {
        buf.writeln('$indent$text');
        buf.writeln();
      }
  }
}

void _emitList(
  _OdtContext ctx,
  XmlElement list,
  StringBuffer buf, {
  required String indent,
}) {
  final ordered = _isOrderedList(ctx, list);
  var index = 1;
  for (final item in childrenLocal(list, 'list-item')) {
    final marker = ordered ? '$index. ' : '- ';
    for (final child in item.children.whereType<XmlElement>()) {
      if (child.name.local == 'list') {
        _emitList(ctx, child, buf, indent: '$indent  ');
      } else if (child.name.local == 'p' || child.name.local == 'h') {
        final text = _inlineText(ctx, child);
        if (text.isNotEmpty) {
          buf.writeln('$indent$marker$text');
        }
      } else {
        _emitBlock(ctx, child, buf, indent: '$indent  ');
      }
    }
    if (ordered) index++;
  }
  buf.writeln();
}

bool _isOrderedList(_OdtContext ctx, XmlElement list) {
  final styleName = _attr(list, 'style-name');
  if (styleName == null) return false;
  final name = ctx.listStyleName(styleName);
  // Veelvoorkomende ODF-lijststijlnamen: "L1", "Numbering_20_1", etc.
  // De betrouwbare weg is het <text:list-style> in styles.xml te lezen,
  // maar voor best-effort volstaat de naamconventie.
  return name.toLowerCase().contains('number') ||
      name.toLowerCase().contains('num');
}

void _emitTable(_OdtContext ctx, XmlElement tbl, StringBuffer buf) {
  final rows = <List<String>>[];
  for (final tr in childrenLocal(tbl, 'table-row')) {
    final cells = <String>[];
    for (final tc in childrenLocal(tr, 'table-cell')) {
      final repeat =
          int.tryParse(_attr(tc, 'number-columns-repeated') ?? '') ?? 1;
      final text = _cellText(ctx, tc);
      for (var i = 0; i < repeat; i++) {
        cells.add(text);
      }
    }
    if (cells.isNotEmpty) rows.add(cells);
  }
  if (rows.isEmpty) return;

  // GFM-tabel: eerste rij is de header, tweede rij is de scheidingsrij.
  final header = rows.first;
  final body = rows.length > 1 ? rows.sublist(1) : const <List<String>>[];
  buf.writeln('| ${header.join(' | ')} |');
  buf.writeln('| ${header.map((_) => '---').join(' | ')} |');
  for (final row in body) {
    buf.writeln('| ${row.join(' | ')} |');
  }
}

String _cellText(_OdtContext ctx, XmlElement cell) {
  final parts = <String>[];
  for (final p in descendantsLocal(cell, 'p')) {
    final t = _inlineText(ctx, p).trim();
    if (t.isNotEmpty) parts.add(t);
  }
  return parts.join(' <br> ');
}

/// Verzamelt de inline tekst van een element, met vet/cursief/links.
String _inlineText(_OdtContext ctx, XmlElement el) {
  final buf = StringBuffer();
  _walkInline(ctx, el, buf, bold: false, italic: false);
  return buf.toString().trim();
}

void _walkInline(
  _OdtContext ctx,
  XmlNode node,
  StringBuffer buf, {
  required bool bold,
  required bool italic,
}) {
  for (final child in node.children) {
    if (child is XmlText) {
      buf.write(_escapeMarkdown(child.value));
    } else if (child is XmlElement) {
      switch (child.name.local) {
        case 'tab':
          buf.write(' ');
        case 'line-break':
          buf.write('\n');
        case 's':
          // Witruimte: schrijf één spatie per voorkomen.
          buf.write(' ');
        case 'a':
          final href = xlinkHref(child);
          final text = _inlineText(ctx, child);
          if (href != null && href.isNotEmpty && text.isNotEmpty) {
            buf.write('[$text]($href)');
          } else {
            buf.write(text);
          }
        case 'span':
          final (b, i) = ctx.spanStyle(_attr(child, 'style-name'));
          final prefix = StringBuffer();
          if (b && !bold) prefix.write('**');
          if (i && !italic) prefix.write('_');
          buf.write(prefix);
          _walkInline(ctx, child, buf, bold: bold || b, italic: italic || i);
          final suffix = StringBuffer();
          if (i && !italic) suffix.write('_');
          if (b && !bold) suffix.write('**');
          buf.write(suffix);
        default:
          _walkInline(ctx, child, buf, bold: bold, italic: italic);
      }
    }
  }
}

/// Ontsnapt Markdown-magische tekens in platte tekst zodat de uitvoer niet
/// per ongeluk opmaak of HTML introduceert.
String _escapeMarkdown(String s) => s
    .replaceAll('\\', '\\\\')
    .replaceAll('*', '\\*')
    .replaceAll('_', '\\_')
    .replaceAll('[', '\\[')
    .replaceAll(']', '\\]')
    .replaceAll('`', '\\`')
    .replaceAll('#', '\\#')
    .replaceAll('|', '\\|');

String _trimTrailingBlank(String s) {
  var out = s.trimRight();
  if (out.isNotEmpty) out += '\n';
  return out;
}

String? _attr(XmlElement el, String local) {
  for (final a in el.attributes) {
    if (a.name.local == local) return a.value;
  }
  return null;
}

/// Een getypeerde weergave van een uitgepakt ODT-pakket, met stijllookup.
class _OdtContext {
  _OdtContext(this.archive, {this.budget = ImportBudget.standard});

  final Archive archive;
  final ImportBudget budget;
  final _parsed = <String, XmlDocument?>{};
  Map<String, (bool, bool)>? _spanStyles; // style-name → (bold, italic)
  Map<String, String>? _listStyles; // style-name → list-style name

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

  /// Geeft (bold, italic) voor een `text:span` stijlnaam.
  (bool, bool) spanStyle(String? styleName) {
    if (styleName == null) return (false, false);
    _spanStyles ??= _loadSpanStyles();
    return _spanStyles![styleName] ?? (false, false);
  }

  /// Geeft de lijststijlnaam voor een `text:list` stijlnaam.
  String listStyleName(String styleName) {
    _listStyles ??= _loadListStyles();
    return _listStyles![styleName] ?? styleName;
  }

  Map<String, (bool, bool)> _loadSpanStyles() {
    final result = <String, (bool, bool)>{};
    for (final part in const ['content.xml', 'styles.xml']) {
      final doc = readXml(part);
      if (doc == null) continue;
      for (final style in descendantsLocal(doc, 'style')) {
        final name = _attr(style, 'name');
        if (name == null || result.containsKey(name)) continue;
        final props = childLocal(style, 'text-properties');
        if (props == null) continue;
        final bold = _attr(props, 'font-weight') == 'bold';
        final italic = _attr(props, 'font-style') == 'italic';
        if (bold || italic) result[name] = (bold, italic);
      }
    }
    return result;
  }

  Map<String, String> _loadListStyles() {
    final result = <String, String>{};
    for (final part in const ['content.xml', 'styles.xml']) {
      final doc = readXml(part);
      if (doc == null) continue;
      for (final ls in descendantsLocal(doc, 'list-style')) {
        final name = _attr(ls, 'name');
        if (name != null) result[name] = name;
      }
    }
    return result;
  }
}
