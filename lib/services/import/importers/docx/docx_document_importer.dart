// DOCX (WordprocessingML / OOXML) → Markdown converter.
//
// Leest een `.docx` en zet de doorlopende tekstinhoud om in GFM-Markdown.
// Headless: geen Flutter, geen IO — draait op bytes, dus ook op web.
//
// Parseert `word/document.xml` (de body), `word/styles.xml` (kop-stijlnamen)
// en `word/_rels/document.xml.rels` (hyperlink- én afbeeldingsrelaties).
// `word/numbering.xml` wordt gelezen om onderscheid te maken tussen geordende
// en ongeordende lijsten.
//
// Best-effort: koppen, lijsten, tabellen, vet/cursief/doorgestreept en links
// gaan mee, en afbeeldingen (`w:drawing`/`v:imagedata` → `word/media/`)
// worden als `![alt](ref)` neergezet met hun bytes in [DocumentConversion].
// Wat geen Markdown-tegenhanger heeft (voetnoten, tekstkaders, groepen,
// objecten) wordt geteld in `notImported` in plaats van stil te vallen
// (#2120). De uitvoer is gewone Markdown.
//
// De huisstijl (letters, kleuren, kop- en voettekst, het beeld op elke
// bladzijde) leest het zusterdeel `docx_document_style.dart` uit hetzelfde
// archief, zodat het bestand maar één keer uitgepakt wordt (#2119).

import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:xml/xml.dart';

import '../../../../utils/content_hash.dart';
import '../../models/source_document_style.dart';
import '../../../../utils/image_signature.dart';
import '../../../../utils/markdown_blocks.dart';
import '../../models/document_conversion.dart';
import '../../utils/archive_utils.dart';
import '../../utils/import_budget.dart';
import '../../utils/safe_extensions.dart';
import '../../utils/xml_utils.dart';

part 'docx_document_style.dart';

/// Zet de bytes van een `.docx` om in Markdown.
///
/// Gooit [ImportBudgetException] bij overschrijding van het budget,
/// [FormatException] bij een beschadigd archief, en [Exception] bij een
/// onleesbaar onderdeel.
String convertDocxToMarkdown(
  List<int> bytes, {
  ImportBudget budget = ImportBudget.standard,
}) => convertDocxDetailed(bytes, budget: budget).markdown;

/// Als [convertDocxToMarkdown], maar levert ook de afbeeldingen en de lijst
/// met niet-overgenomen inhoud — de servicelaag beslist waar de bytes landen
/// en hoe het verlies gemeld wordt.
DocumentConversion convertDocxDetailed(
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
  return DocumentConversion(
    markdown: _trimTrailingBlank(buf.toString()),
    images: ctx.images,
    notImported: ctx.notImported,
    style: _extractDocxStyle(ctx),
  );
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
    case 'drawing':
      _emitDrawing(ctx, el, buf);
    case 'pict':
      _emitPict(ctx, el, buf);
    case 'object':
      // Ingebed OLE-object (Excel-blad, vergelijking): geen afbeelding om
      // mee te nemen, maar wél inhoud die de gebruiker kwijtraakt.
      ctx.notImported.add('object');
    case 'AlternateContent':
      // mc:AlternateContent draagt dezelfde inhoud twee keer: de keuze in
      // de nieuwe notatie (w:drawing) en de terugval in de oude (w:pict).
      // Alleen de keuzes doorlopen — anders telt elke afbeelding dubbel.
      for (final child in el.children.whereType<XmlElement>()) {
        if (child.name.local == 'Choice') {
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

/// Verwerk een `w:drawing`: een rasterafbeelding gaat mee als `![alt](ref)`,
/// de rest wordt geteld als niet-overgenomen zodat niets stil verdwijnt
/// (#2120). Inline én geankerde tekeningen komen hier langs — beide hangen
/// als `w:drawing` in een run.
void _emitDrawing(_DocxContext ctx, XmlElement drawing, StringBuffer buf) {
  // Gegroepeerde vormen (wpg:wgp) vallen als één stuk weg.
  if (_findLocal(drawing, 'wgp') != null) {
    ctx.notImported.add('groep');
    return;
  }
  // Tekstkaders (wps:txbx of het oudere v:textbox met w:txbxContent).
  if (_findLocal(drawing, 'txbxContent') != null) {
    ctx.notImported.add('tekstkader');
    return;
  }
  final blip = _findLocal(drawing, 'blip');
  if (blip == null) {
    // Een tekening zónder blip is een vorm, grafiek of diagram — iets dat
    // we niet kunnen afbeelden maar wél benoemen.
    ctx.notImported.add('object');
    return;
  }
  // `r:embed` wijst naar een deel in het pakket; `r:link` naar een externe
  // bron — beide lossen via dezelfde relatie op, maar alleen de interne
  // levert bytes (imagePartPath weigert doelen buiten word/).
  final rid = _attr(blip, 'embed') ?? _attr(blip, 'link');
  final path = rid == null ? null : ctx.imagePartPath(rid);
  if (path == null || !_emitImage(ctx, path, buf, alt: _drawingAlt(drawing))) {
    ctx.notImported.add('afbeelding');
  }
}

/// Verwerk een `w:pict` (de VML-notatie uit oudere documenten): `v:imagedata`
/// is een afbeelding, `v:textbox` een tekstkader, de rest een vorm.
void _emitPict(_DocxContext ctx, XmlElement pict, StringBuffer buf) {
  if (_findLocal(pict, 'textbox') != null) {
    ctx.notImported.add('tekstkader');
    return;
  }
  final imageData = _findLocal(pict, 'imagedata');
  if (imageData == null) {
    ctx.notImported.add('object');
    return;
  }
  final rid = _attr(imageData, 'id');
  final path = rid == null ? null : ctx.imagePartPath(rid);
  if (path == null || !_emitImage(ctx, path, buf, alt: '')) {
    ctx.notImported.add('afbeelding');
  }
}

/// Leest [path] uit het archief en zet — als de bytes een weergeefbaar
/// rasterbeeld zijn — een `![alt](ref)` in de uitvoer. Geeft terug of er een
/// verwijzing is geplaatst; de aanroeper telt het element anders als
/// niet-overgenomen.
bool _emitImage(
  _DocxContext ctx,
  String path,
  StringBuffer buf, {
  required String alt,
}) {
  final bytes = ctx.readPartBytes(path);
  if (bytes == null) return false;
  final mime = imageMimeFromBytes(bytes);
  // Alleen raster gaat mee: SVG/EMF/WMF kan de documentweergave niet
  // tonen, en ontbrekende of verkeerde bytes zijn sowieso niet overdraagbaar.
  if (mime == null) return false;
  ctx.images.add(
    ImportedDocumentImage(
      ref: path,
      name: normalizeImageFileName(
        path.split('/').last,
        fallbackExtension: extensionForImageMime(mime),
      ),
      bytes: Uint8List.fromList(bytes),
      alt: alt,
    ),
  );
  buf.write('![$alt]($path)');
  return true;
}

/// De alt-tekst van een `w:drawing`: `wp:docPr/@descr`, of anders `/@name`.
/// Gesaneerd zodat de `![…](…)`-syntaxis heel blijft.
String _drawingAlt(XmlElement drawing) {
  final docPr = _findLocal(drawing, 'docPr');
  final raw = docPr == null
      ? ''
      : (_attr(docPr, 'descr') ?? _attr(docPr, 'name') ?? '');
  return markdownImageAlt(raw.replaceAll(RegExp(r'\s+'), ' ').trim());
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
  final _partRelationships = <String, Map<String, String>>{};
  Map<String, bool>? _numbering; // numId → isOrdered

  /// De afbeeldingen die de omzetting plaatste, en wat er niet meekwam —
  /// de importeur verzamelt, [convertDocxDetailed] levert op.
  final List<ImportedDocumentImage> images = [];
  final List<String> notImported = [];

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

  /// Het relatiedoel van [rid] in het `.rels`-bestand van [partPath]
  /// (`word/header2.xml` → `word/_rels/header2.xml.rels`), of null.
  String? relationshipOf(String partPath, String rid) {
    final rels = _partRelationships.putIfAbsent(partPath, () {
      final slash = partPath.lastIndexOf('/');
      final dir = slash < 0 ? '' : partPath.substring(0, slash + 1);
      final name = partPath.substring(slash + 1);
      return _loadRelationshipsFrom('${dir}_rels/$name.rels');
    });
    return rels[rid];
  }

  /// Het archiefpad van het deel dat de hoofdrelaties als [type] aanwijzen
  /// (`theme` → `word/theme/theme1.xml`), of null.
  String? partPathForRelationshipType(String type) {
    final doc = readXml('word/_rels/document.xml.rels');
    if (doc == null) return null;
    for (final rel in _descendants(doc, 'Relationship')) {
      final relType = _attr(rel, 'Type');
      final target = _attr(rel, 'Target');
      if (relType != null && target != null && relType.endsWith('/$type')) {
        return _resolveWordPath(target);
      }
    }
    return null;
  }

  /// Het archiefpad van een afbeeldingsrelatie (`r:embed`/`r:id`), of null
  /// als de relatie niet bestaat of het doel buiten `word/` wijst. Doelen
  /// met `..` of een schema (`http:`, `file:`) worden geweigerd: ze mogen
  /// het documentdeel niet ontsnappen en externe beelden halen we bewust
  /// niet binnen.
  String? imagePartPath(String rid) {
    final target = relationship(rid);
    if (target == null || target.contains(':') || target.contains('..')) {
      return null;
    }
    final path = 'word/${target.replaceFirst(RegExp('^/+'), '')}';
    return path == 'word/' ? null : path;
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

  Map<String, String> _loadRelationships() =>
      _loadRelationshipsFrom('word/_rels/document.xml.rels');

  Map<String, String> _loadRelationshipsFrom(String path) {
    final result = <String, String>{};
    final doc = readXml(path);
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
