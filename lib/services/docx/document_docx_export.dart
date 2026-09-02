// DOCX (WordprocessingML / OOXML) export voor een plat-Markdown-document.
//
// Bouwt een .docx-ZIP uit de geprojecteerde body: bewerkbare Wordprocessing-XML
// met koppen, alinea's, tabellen, lijsten, voetnoten en afbeeldingen.
// Mermaid-diagrammen en wiskunde-formules worden gerasteriseerd naar hoog-DPI
// PNG (zie svg_to_png.dart) en als afbeeldingen ingebed. Headless: geen Flutter,
// geen IO — de aanroeper schrijft de bytes weg.
//
// Hergebruikt de `archive`-package (pubspec: `archive: ^4.0.9`) voor de
// ZIP-verpakking, de `markdown`-package via markdown_to_docx.dart voor de
// conversie, en `flutter_svg`+`dart:ui` voor de rasterisatie. Geen nieuwe
// dependency.
//
// DOCX-structuur:
//   [Content_Types].xml
//   _rels/.rels
//   word/document.xml          (body + sectie-eigenschappen)
//   word/styles.xml            (kop-, alinea- en tekenstijlen)
//   word/numbering.xml         (lijstdefinities)
//   word/footnotes.xml         (voetnoten, indien van toepassing)
//   word/endnotes.xml          (eindnoten, indien document-stand)
//   word/_rels/document.xml.rels
//   word/media/image-N.png     (afbeeldingen + gerasteriseerde mermaid/math)
//   docProps/core.xml          (titel, auteur, taal, TLP, datum)
//   docProps/app.xml           (app-naam)

import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;

import '../document_export_service.dart' show projectedDocumentBody;
import '../document_footnote_setup.dart';
import '../export_bundle.dart';
import '../export_metadata.dart';
import '../marp_html_service.dart' show HtmlImageResolver;
import '../pdf/document_pdf_export.dart'
    show MathSvgResolver, MermaidSvgResolver;
import 'markdown_to_docx.dart';
import 'svg_to_png.dart';

/// Bouwt de DOCX-bytes voor een document-export. Headless: geen IO.
///
/// De inhoud die de deur uit gaat komt uit [projectedDocumentBody] — de
/// geprojecteerde body via de bundel, nooit de rauwe bron. De
/// projectiegrens blijft intact: deze functie neemt een [ExportBundle] en
/// geen `Deck`.
///
/// [embedImage] levert per afbeeldingsbron een `data:`-URI op (dezelfde
/// callback als de HTML-, ePub- en ODT-export). De DOCX-builder parseert de
/// data-URI, haalt de ruwe bytes eruit, en slaat ze op als aparte bestanden
/// in `word/media/`.
///
/// [renderMermaid] en [renderMath] leveren per bron een inline-SVG op (dezelfde
/// callbacks als de PDF-export). De DOCX-builder rasteriseert die naar een
/// hoog-DPI PNG via [svgToPng]. Levert een callback `null` of een lege SVG,
/// dan valt het blok terug op zijn bron in een codeblok — dezelfde afspraak
/// als de PDF-export.
Future<Uint8List> buildDocumentExportDocx(
  ExportBundle bundle, {
  ExportDocumentMetadata? metadata,
  bool chapterPageBreak = false,
  FootnotePlacement footnotePlacement = FootnotePlacement.page,
  String footnotesTitle = 'Noten',
  HtmlImageResolver? embedImage,
  MermaidSvgResolver? renderMermaid,
  MathSvgResolver? renderMath,
  String? sourcePath,
  String outputPath = '',
}) async {
  final body = projectedDocumentBody(bundle);
  final meta = metadata ?? ExportDocumentMetadata.fromDeck(bundle.audience);
  final title = meta.displayTitle('Document');

  // 1. Markdown → WordprocessingML body + nevenproducten.
  final conversion = markdownToDocxBody(
    body,
    chapterPageBreak: chapterPageBreak,
    footnotePlacement: footnotePlacement,
  );

  // 2-4. Rasterisatie, afbeeldingen ophalen, sentinels vervangen.
  final prepared = await _prepareDocxMedia(
    conversion,
    embedImage: embedImage,
    renderMermaid: renderMermaid,
    renderMath: renderMath,
  );

  // 5. XML-onderdelen bouwen.
  final pageSize = _pageSizeTwips(bundle);
  final pageMargins = _pageMarginsTwips(bundle);
  final documentXml = _buildDocumentXml(prepared.body, pageSize, pageMargins);
  final stylesXml = _buildStylesXml();
  final numberingXml = _buildNumberingXml();
  final footnotesXml = conversion.footnotes.isNotEmpty
      ? _buildNotesXml(
          conversion.footnotes,
          footnotePlacement == FootnotePlacement.document
              ? 'endnotes'
              : 'footnotes',
        )
      : null;
  final coreXml = _buildCoreXml(meta, title);
  final appXml = _buildAppXml();
  final contentTypesXml = _buildContentTypesXml(
    hasFootnotes: footnotesXml != null,
    hasEndnotes:
        footnotePlacement == FootnotePlacement.document &&
        conversion.footnotes.isNotEmpty,
  );
  final relsXml = _buildRelsXml();
  final docRelsXml = _buildDocumentRelsXml(
    prepared.relations,
    hasFootnotes:
        conversion.footnotes.isNotEmpty &&
        footnotePlacement != FootnotePlacement.document,
    hasEndnotes:
        conversion.footnotes.isNotEmpty &&
        footnotePlacement == FootnotePlacement.document,
  );

  // 6. ZIP samenstellen.
  final archive = Archive();
  void addText(String name, String content) {
    archive.add(ArchiveFile.bytes(name, utf8.encode(content)));
  }

  addText('[Content_Types].xml', contentTypesXml);
  addText('_rels/.rels', relsXml);
  addText('word/document.xml', documentXml);
  addText('word/styles.xml', stylesXml);
  addText('word/numbering.xml', numberingXml);
  if (footnotesXml != null) {
    final name = footnotePlacement == FootnotePlacement.document
        ? 'word/endnotes.xml'
        : 'word/footnotes.xml';
    addText(name, footnotesXml);
  }
  addText('word/_rels/document.xml.rels', docRelsXml);
  addText('docProps/core.xml', coreXml);
  addText('docProps/app.xml', appXml);

  for (var i = 0; i < prepared.media.length; i++) {
    archive.add(
      ArchiveFile.bytes(
        'word/media/${prepared.media[i].name}',
        prepared.media[i].bytes,
      ),
    );
  }

  return ZipEncoder().encodeBytes(archive);
}

/// Het resultaat van de media-voorbereiding: de body met opgeloste sentinels,
/// de media-bestanden en de relaties.
class _PreparedDocx {
  const _PreparedDocx(this.body, this.media, this.relations);

  final String body;
  final List<_DocxMedia> media;
  final List<_DocxRelation> relations;
}

/// Stappen 2-4: rasteriseer mermaid/math naar PNG, haal afbeeldingen op,
/// vervang alle sentinels in de body door tekeningen en verzamel relaties.
Future<_PreparedDocx> _prepareDocxMedia(
  DocxConversion conversion, {
  HtmlImageResolver? embedImage,
  MermaidSvgResolver? renderMermaid,
  MathSvgResolver? renderMath,
}) async {
  // 2. Mermaid- en wiskundeblokken rasteriseren naar PNG.
  final mermaidPngs = <int, Uint8List>{}; // idx → bytes
  if (renderMermaid != null) {
    for (var i = 0; i < conversion.mermaidSources.length; i++) {
      final svg = await renderMermaid(conversion.mermaidSources[i]);
      if (svg == null || svg.trim().isEmpty) continue;
      final png = await svgToPng(svg);
      if (png != null) mermaidPngs[i] = png;
    }
  }
  final mathPngs = <int, Uint8List>{};
  if (renderMath != null) {
    for (var i = 0; i < conversion.mathSources.length; i++) {
      final svg = await renderMath(conversion.mathSources[i]);
      if (svg == null || svg.trim().isEmpty) continue;
      final png = await svgToPng(svg);
      if (png != null) mathPngs[i] = png;
    }
  }

  // 3. Afbeeldingen ophalen via embedImage.
  final imageBytes = <int, Uint8List>{}; // idx → bytes
  if (embedImage != null) {
    for (var i = 0; i < conversion.imageSources.length; i++) {
      final src = conversion.imageSources[i];
      final dataUri = src.startsWith('data:') ? src : await embedImage(src);
      if (dataUri == null) continue;
      final parsed = _parseDataUri(dataUri);
      if (parsed != null) imageBytes[i] = parsed;
    }
  }

  // 4. Sentinels in de body vervangen door tekeningen + relaties verzamelen.
  final media = <_DocxMedia>[]; // volgorde = rId-volgorde
  final relations = <_DocxRelation>[];
  var docBody = conversion.body;

  // Afbeeldingen.
  docBody = _replaceImageSentinels(
    docBody,
    conversion.imageSources.length,
    (idx) => imageBytes[idx],
    media,
    relations,
    (idx) => _imgAlt(docBody, idx),
  );

  // Mermaid.
  docBody = _replaceGraphicSentinels(
    docBody,
    'OCIDECKMERMAID',
    conversion.mermaidSources.length,
    (idx) => mermaidPngs[idx],
    (idx) => conversion.mermaidSources[idx],
    media,
    relations,
    label: 'mermaid',
  );

  // Wiskunde.
  docBody = _replaceGraphicSentinels(
    docBody,
    'OCIDECKMATH',
    conversion.mathSources.length,
    (idx) => mathPngs[idx],
    (idx) => conversion.mathSources[idx],
    media,
    relations,
    label: 'math',
  );

  // Links.
  docBody = _replaceLinkSentinels(docBody, conversion.linkTargets, relations);

  return _PreparedDocx(docBody, media, relations);
}

/// Eén media-bestand in de ZIP.
class _DocxMedia {
  const _DocxMedia(this.name, this.bytes, this.mediaType);

  final String name;
  final Uint8List bytes;
  final String mediaType;
}

/// Eén relatie in `word/_rels/document.xml.rels`.
class _DocxRelation {
  const _DocxRelation(this.id, this.type, this.target, this.targetMode);

  final String id;
  final String type;
  final String target;
  final String? targetMode;
}

/// Doelbreedte voor een afbeelding op kolombreedte: 15 cm ≈ 5,9 duim.
/// 15 cm × 914400 EMU/duim ÷ 2,54 cm/duim = 5.400.000 EMU.
const int _imageWidthEmu = 5400000;

String _replaceImageSentinels(
  String body,
  int count,
  Uint8List? Function(int) bytesFor,
  List<_DocxMedia> media,
  List<_DocxRelation> relations,
  String Function(int) altFor,
) {
  var out = body;
  for (var idx = 0; idx < count; idx++) {
    final sentinel = RegExp('<OCIDECKIMG w:idx="$idx" w:alt="[^"]*"/>');
    final bytes = bytesFor(idx);
    if (bytes == null) {
      out = out.replaceAll(sentinel, '');
      continue;
    }
    final (w, h) = _imageDimensions(bytes);
    final (cx, cy) = _drawingExtent(w, h);
    final (rId, mediaName, mediaType) = _addMedia(bytes, media, relations);
    final alt = altFor(idx);
    out = out.replaceAll(
      sentinel,
      _drawingXml(rId, mediaName, mediaType, cx, cy, alt),
    );
  }
  return out;
}

/// Vervang mermaid/math-sentinels: is er een PNG, dan wordt het een tekening;
/// anders valt het blok terug op de bron in een codeblok.
String _replaceGraphicSentinels(
  String body,
  String tag,
  int count,
  Uint8List? Function(int idx) pngFor,
  String Function(int idx) sourceFor,
  List<_DocxMedia> media,
  List<_DocxRelation> relations, {
  required String label,
}) {
  var out = body;
  for (var idx = 0; idx < count; idx++) {
    final sentinel = RegExp('<$tag w:idx="$idx"/>');
    final png = pngFor(idx);
    if (png == null) {
      // Terugval op bron in een codeblok — dezelfde afspraak als de PDF.
      final source = _xmlEscape(sourceFor(idx));
      out = out.replaceAll(
        sentinel,
        '<w:p><w:pPr><w:pStyle w:val="PreformattedText"/></w:pPr>'
        '<w:r><w:rPr><w:rStyle w:val="SourceText"/></w:rPr>'
        '<w:t xml:space="preserve">$source</w:t></w:r></w:p>',
      );
      continue;
    }
    final (w, h) = _imageDimensions(png);
    final (cx, cy) = _drawingExtent(w, h);
    final (rId, mediaName, mediaType) = _addMedia(png, media, relations);
    out = out.replaceAll(
      sentinel,
      _drawingXml(rId, mediaName, mediaType, cx, cy, label),
    );
  }
  return out;
}

String _replaceLinkSentinels(
  String body,
  List<String> linkTargets,
  List<_DocxRelation> relations,
) {
  var out = body;
  final linkRegex = RegExp(r'<OCIDECKLINK href="([^"]*)">');
  for (final match in linkRegex.allMatches(out).toList()) {
    final href = match.group(1)!;
    final original = match.group(0)!;
    final rId = 'rId${relations.length + 1}';
    relations.add(
      _DocxRelation(
        rId,
        'http://schemas.openxmlformats.org/officeDocument/2006/relationships/hyperlink',
        href,
        'External',
      ),
    );
    out = out.replaceFirst(original, '<w:hyperlink r:id="$rId" w:history="1">');
  }
  out = out.replaceAll('</OCIDECKLINK>', '</w:hyperlink>');
  return out;
}

/// Voegt bytes toe aan media + relaties en geeft (rId, mediaName, mediaType).
(String, String, String) _addMedia(
  Uint8List bytes,
  List<_DocxMedia> media,
  List<_DocxRelation> relations,
) {
  final mediaType = _sniffMediaType(bytes);
  final ext = _extensionForMediaType(mediaType);
  final n = media.length;
  final mediaName = 'image$n.$ext';
  media.add(_DocxMedia(mediaName, bytes, mediaType));
  final rId = 'rId${relations.length + 1}';
  relations.add(
    _DocxRelation(
      rId,
      'http://schemas.openxmlformats.org/officeDocument/2006/relationships/image',
      'media/$mediaName',
      null,
    ),
  );
  return (rId, mediaName, mediaType);
}

/// De teken-grootte in EMU: doelbreedte met behoud van beeldverhouding.
/// Bij onbekende dimensies een vierkant op doelbreedte.
(int, int) _drawingExtent(int pxW, int pxH) {
  if (pxW <= 0 || pxH <= 0) return (_imageWidthEmu, _imageWidthEmu);
  final cy = (_imageWidthEmu * pxH / pxW).round();
  return (_imageWidthEmu, cy);
}

/// Leest de pixelbreedte en -hoogte uit een PNG- of JPEG-header.
/// `image`-package `decodeImage` decodeert volledig; voor alleen de maat
/// volstaat de IHDR (PNG) of een SOF-marker (JPEG) — lichter en zonder de
/// hele afbeelding in het geheugen te halen.
(int, int) _imageDimensions(Uint8List bytes) {
  // PNG: signature + IHDR.
  if (bytes.length >= 24 &&
      bytes[0] == 0x89 &&
      bytes[1] == 0x50 &&
      bytes[2] == 0x4E &&
      bytes[3] == 0x47) {
    final w =
        (bytes[16] << 24) | (bytes[17] << 16) | (bytes[18] << 8) | bytes[19];
    final h =
        (bytes[20] << 24) | (bytes[21] << 16) | (bytes[22] << 8) | bytes[23];
    return (w, h);
  }
  // JPEG: scan SOF-marker (0xFFC0..0xFFCF, behalve 0xFFC4/0xFFC8/0xFFCC).
  if (bytes.length >= 4 && bytes[0] == 0xFF && bytes[1] == 0xD8) {
    var i = 2;
    while (i + 9 < bytes.length) {
      if (bytes[i] != 0xFF) {
        i++;
        continue;
      }
      final marker = bytes[i + 1];
      if (marker >= 0xC0 &&
          marker <= 0xCF &&
          marker != 0xC4 &&
          marker != 0xC8 &&
          marker != 0xCC) {
        final h = (bytes[i + 5] << 8) | bytes[i + 6];
        final w = (bytes[i + 7] << 8) | bytes[i + 8];
        return (w, h);
      }
      final segLen = (bytes[i + 2] << 8) | bytes[i + 3];
      i += 2 + segLen;
    }
  }
  // GIF: dimensions at offset 6-9.
  if (bytes.length >= 10 &&
      (bytes[0] == 0x47 && bytes[1] == 0x49 && bytes[2] == 0x46)) {
    final w = bytes[6] | (bytes[7] << 8);
    final h = bytes[8] | (bytes[9] << 8);
    return (w, h);
  }
  return (0, 0);
}

String _sniffMediaType(Uint8List bytes) {
  if (bytes.length >= 4 && bytes[0] == 0x89 && bytes[1] == 0x50) {
    return 'image/png';
  }
  if (bytes.length >= 3 && bytes[0] == 0xFF && bytes[1] == 0xD8) {
    return 'image/jpeg';
  }
  if (bytes.length >= 6 && bytes[0] == 0x47 && bytes[1] == 0x49) {
    return 'image/gif';
  }
  // Standaard: PNG (mermaid rasteriseert naar PNG).
  return 'image/png';
}

String _extensionForMediaType(String mediaType) => switch (mediaType) {
  'image/png' => 'png',
  'image/jpeg' => 'jpg',
  'image/gif' => 'gif',
  'image/svg+xml' => 'svg',
  'image/webp' => 'webp',
  _ => 'bin',
};

/// De inline-tekening (een `wp:inline` met een `pic:pic`).
String _drawingXml(
  String rId,
  String mediaName,
  String mediaType,
  int cx,
  int cy,
  String alt,
) {
  final name = alt.isNotEmpty ? _xmlEscape(alt) : mediaName;
  return '<w:r><w:drawing>'
      '<wp:inline distT="0" distB="0" distL="0" distR="0">'
      '<wp:extent cx="$cx" cy="$cy"/>'
      '<wp:effectExtent l="0" t="0" r="0" b="0"/>'
      '<wp:docPr id="0" name="$name"/>'
      '<wp:cNvGraphicFramePr><a:graphicFrameLocks '
      'xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" '
      'noChangeAspect="1"/></wp:cNvGraphicFramePr>'
      '<a:graphic xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main">'
      '<a:graphicData uri="http://schemas.openxmlformats.org/drawingml/2006/picture">'
      '<pic:pic xmlns:pic="http://schemas.openxmlformats.org/drawingml/2006/picture">'
      '<pic:nvPicPr><pic:cNvPr id="0" name="$name"/>'
      '<pic:cNvPicPr/></pic:nvPicPr>'
      '<pic:blipFill>'
      '<a:blip xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships" '
      'r:embed="$rId"/>'
      '<a:stretch><a:fillRect/></a:stretch>'
      '</pic:blipFill>'
      '<pic:spPr><a:xfrm><a:off x="0" y="0"/><a:ext cx="$cx" cy="$cy"/></a:xfrm>'
      '<a:prstGeom prst="rect"><a:avLst/></a:prstGeom></pic:spPr>'
      '</pic:pic></a:graphicData></a:graphic>'
      '</wp:inline></w:drawing></w:r>';
}

/// Haalt het alt-attribuut uit een OCIDECKIMG-sentinel.
String _imgAlt(String body, int idx) {
  final m = RegExp(
    '<OCIDECKIMG w:idx="$idx" w:alt="([^"]*)"/>',
  ).firstMatch(body);
  return m?.group(1) ?? '';
}

Uint8List? _parseDataUri(String uri) {
  final comma = uri.indexOf(',');
  if (comma < 0) return null;
  final header = uri.substring(5, comma);
  final data = uri.substring(comma + 1);
  if (!header.contains('base64')) return null;
  try {
    return Uint8List.fromList(base64Decode(data));
  } on FormatException {
    return null;
  }
}

/// pagina-maat in twips uit de bundel (A4-standaard).
({int w, int h}) _pageSizeTwips(ExportBundle bundle) {
  // De bundel draagt geen paginaopmaak mee aan deze laag; de aanroeper zet
  // de sectie-eigenschappen via de standaard A4. Een toekomstige uitbreiding
  // kan pageSize hier doorgeven.
  const a4Wmm = 210.0, a4Hmm = 297.0;
  return (w: _mmToTwips(a4Wmm), h: _mmToTwips(a4Hmm));
}

({int top, int bottom, int left, int right}) _pageMarginsTwips(
  ExportBundle bundle,
) => (
  top: _mmToTwips(25),
  bottom: _mmToTwips(25),
  left: _mmToTwips(20),
  right: _mmToTwips(20),
);

int _mmToTwips(double mm) => (mm * 1440 / 25.4).round();

String _buildDocumentXml(
  String body,
  ({int w, int h}) pageSize,
  ({int top, int bottom, int left, int right}) margins,
) {
  final sectPr =
      '<w:sectPr>'
      '<w:pgSz w:w="${pageSize.w}" w:h="${pageSize.h}"/>'
      '<w:pgMar w:top="${margins.top}" w:right="${margins.right}" '
      'w:bottom="${margins.bottom}" w:left="${margins.left}" '
      'w:header="720" w:footer="720" w:gutter="0"/>'
      '</w:sectPr>';
  return '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>\n'
      '<w:document '
      'xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main" '
      'xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships" '
      'xmlns:wp="http://schemas.openxmlformats.org/drawingml/2006/wordprocessingDrawing" '
      'xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" '
      'xmlns:pic="http://schemas.openxmlformats.org/drawingml/2006/picture">'
      '<w:body>$body\n$sectPr</w:body></w:document>';
}

String _buildStylesXml() =>
    '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>\n'
    '<w:styles xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">'
    '<w:docDefaults><w:rPrDefault><w:rPr>'
    '<w:rFonts w:ascii="Calibri" w:hAnsi="Calibri" w:cs="Calibri"/>'
    '<w:sz w:val="22"/></w:rPr></w:rPrDefault>'
    '<w:pPrDefault><w:pPr><w:spacing w:after="160" w:line="259" w:lineRule="auto"/></w:pPr></w:pPrDefault>'
    '</w:docDefaults>'
    '${_headingStyle(1, 32, 240)}'
    '${_headingStyle(2, 26, 240)}'
    '${_headingStyle(3, 22, 200)}'
    '${_headingStyle(4, 20, 200)}'
    '${_headingStyle(5, 18, 160)}'
    '${_headingStyle(6, 16, 160)}'
    '<w:style w:type="character" w:styleId="SourceText"><w:rPr>'
    '<w:rFonts w:ascii="Consolas" w:hAnsi="Consolas" w:cs="Consolas"/>'
    '</w:rPr></w:style>'
    '<w:style w:type="paragraph" w:styleId="PreformattedText"><w:pPr>'
    '<w:spacing w:after="0" w:line="240" w:lineRule="auto"/>'
    '</w:pPr><w:rPr><w:rFonts w:ascii="Consolas" w:hAnsi="Consolas" w:cs="Consolas"/>'
    '<w:sz w:val="20"/></w:rPr></w:style>'
    '<w:style w:type="paragraph" w:styleId="Quote"><w:pPr>'
    '<w:ind w:left="567" w:right="567"/><w:spacing w:after="160"/>'
    '</w:pPr><w:rPr><w:i/></w:rPr></w:style>'
    '<w:style w:type="paragraph" w:styleId="ListParagraph"><w:pPr>'
    '<w:ind w:left="720" w:hanging="360"/></w:pPr></w:style>'
    '<w:style w:type="character" w:styleId="Hyperlink"><w:rPr>'
    '<w:color w:val="0563C1"/><w:u w:val="single"/></w:rPr></w:style>'
    '<w:style w:type="character" w:styleId="FootnoteReference"><w:rPr>'
    '<w:vertAlign w:val="superscript"/></w:rPr></w:style>'
    '</w:styles>';

String _headingStyle(int level, int szHalfPt, int spacingAfter) =>
    '<w:style w:type="paragraph" w:styleId="Heading$level">'
    '<w:pPr><w:spacing w:before="$spacingAfter" w:after="80"/>'
    '<w:outlineLvl w:val="${level - 1}"/></w:pPr>'
    '<w:rPr><w:b/><w:sz w:val="$szHalfPt"/></w:rPr></w:style>';

String _buildNumberingXml() =>
    '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>\n'
    '<w:numbering xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">'
    '<w:abstractNum w:abstractNumId="0">'
    '<w:lvl w:ilvl="0"><w:start w:val="1"/><w:numFmt w:val="bullet"/>'
    '<w:lvlText w:val="•"/><w:lvlJc w:val="left"/>'
    '<w:pPr><w:ind w:left="720" w:hanging="360"/></w:pPr></w:lvl>'
    '${_nestedBulletLevels()}'
    '</w:abstractNum>'
    '<w:abstractNum w:abstractNumId="1">'
    '<w:lvl w:ilvl="0"><w:start w:val="1"/><w:numFmt w:val="decimal"/>'
    '<w:lvlText w:val="%1."/><w:lvlJc w:val="left"/>'
    '<w:pPr><w:ind w:left="720" w:hanging="360"/></w:pPr></w:lvl>'
    '${_nestedDecimalLevels()}'
    '</w:abstractNum>'
    '<w:num w:numId="1"><w:abstractNumId w:val="0"/></w:num>'
    '<w:num w:numId="2"><w:abstractNumId w:val="1"/></w:num>'
    '</w:numbering>';

String _nestedBulletLevels() {
  final buf = StringBuffer();
  for (var lvl = 1; lvl <= 5; lvl++) {
    final left = 720 + lvl * 360;
    buf.write(
      '<w:lvl w:ilvl="$lvl"><w:start w:val="1"/><w:numFmt w:val="bullet"/>'
      '<w:lvlText w:val="◦"/><w:lvlJc w:val="left"/>'
      '<w:pPr><w:ind w:left="$left" w:hanging="360"/></w:pPr></w:lvl>',
    );
  }
  return buf.toString();
}

String _nestedDecimalLevels() {
  final buf = StringBuffer();
  final fmts = ['%2.', '%3.', '%4.', '%5.', '%6.'];
  for (var lvl = 1; lvl <= 5; lvl++) {
    final left = 720 + lvl * 360;
    final fmt = fmts[lvl - 1];
    buf.write(
      '<w:lvl w:ilvl="$lvl"><w:start w:val="1"/><w:numFmt w:val="lowerLetter"/>'
      '<w:lvlText w:val="$fmt"/><w:lvlJc w:val="left"/>'
      '<w:pPr><w:ind w:left="$left" w:hanging="360"/></w:pPr></w:lvl>',
    );
  }
  return buf.toString();
}

String _buildNotesXml(List<DocxFootnoteDef> notes, String kind) {
  final buf = StringBuffer()
    ..writeln('<?xml version="1.0" encoding="UTF-8" standalone="yes"?>')
    ..writeln(
      '<w:$kind xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">',
    );
  // Word eist een separator-notitie met id 0.
  buf.writeln(
    '<w:note w:type="separator" w:id="0">'
    '<w:p><w:r><w:separator/></w:r></w:p></w:note>',
  );
  for (final note in notes) {
    buf.writeln(
      '<w:note w:type="normal" w:id="${note.number}">'
      '<w:p><w:r><w:rPr><w:rStyle w:val="FootnoteReference"/></w:rPr>'
      '<w:t xml:space="preserve">${note.number} </w:t></w:r>'
      '${note.inlineXml}</w:p></w:note>',
    );
  }
  buf.writeln('</w:$kind>');
  return buf.toString();
}

String _buildCoreXml(ExportDocumentMetadata meta, String title) {
  final now = DateTime.now().toUtc();
  final buf = StringBuffer()
    ..writeln('<?xml version="1.0" encoding="UTF-8" standalone="yes"?>')
    ..writeln(
      '<cp:coreProperties '
      'xmlns:cp="http://schemas.openxmlformats.org/package/2006/metadata/core-properties" '
      'xmlns:dc="http://purl.org/dc/elements/1.1/" '
      'xmlns:dcterms="http://purl.org/dc/terms/" '
      'xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">',
    )
    ..writeln('<dc:title>${_xmlEscape(title)}</dc:title>')
    ..writeln('<dc:creator>${_xmlEscape(meta.documentAuthor)}</dc:creator>')
    ..writeln(
      '<cp:lastModifiedBy>${_xmlEscape(meta.documentAuthor)}</cp:lastModifiedBy>',
    )
    ..writeln(
      '<dcterms:created xsi:type="dcterms:W3CDTF">${now.toIso8601String().split('.').first}Z</dcterms:created>',
    );
  if (meta.language.isNotEmpty) {
    buf.writeln('<dc:language>${_xmlEscape(meta.language)}</dc:language>');
  }
  if (meta.description.trim().isNotEmpty) {
    buf.writeln(
      '<dc:description>${_xmlEscape(meta.description.trim())}</dc:description>',
    );
  }
  final kw = meta.exportKeywords();
  if (kw.isNotEmpty) {
    buf.writeln('<cp:keywords>${_xmlEscape(kw)}</cp:keywords>');
  }
  buf.writeln('</cp:coreProperties>');
  return buf.toString();
}

String _buildAppXml() =>
    '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>\n'
    '<Properties xmlns="http://schemas.openxmlformats.org/officeDocument/2006/extended-properties">'
    '<Application>$kOciDeckProducer</Application>'
    '</Properties>';

String _buildContentTypesXml({
  required bool hasFootnotes,
  required bool hasEndnotes,
}) {
  final buf = StringBuffer()
    ..writeln('<?xml version="1.0" encoding="UTF-8" standalone="yes"?>')
    ..writeln(
      '<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">',
    )
    ..writeln(
      '<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>',
    )
    ..writeln('<Default Extension="xml" ContentType="application/xml"/>')
    ..writeln(
      '<Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/>',
    )
    ..writeln(
      '<Override PartName="/word/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.styles+xml"/>',
    )
    ..writeln(
      '<Override PartName="/word/numbering.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.numbering+xml"/>',
    );
  if (hasFootnotes) {
    buf.writeln(
      '<Override PartName="/word/footnotes.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.footnotes+xml"/>',
    );
  }
  if (hasEndnotes) {
    buf.writeln(
      '<Override PartName="/word/endnotes.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.endnotes+xml"/>',
    );
  }
  buf
    ..writeln(
      '<Override PartName="/docProps/core.xml" ContentType="application/vnd.openxmlformats-package.core-properties+xml"/>',
    )
    ..writeln(
      '<Override PartName="/docProps/app.xml" ContentType="application/vnd.openxmlformats-officedocument.extended-properties+xml"/>',
    )
    ..writeln('<Default Extension="png" ContentType="image/png"/>')
    ..writeln('<Default Extension="jpg" ContentType="image/jpeg"/>')
    ..writeln('<Default Extension="jpeg" ContentType="image/jpeg"/>')
    ..writeln('<Default Extension="gif" ContentType="image/gif"/>')
    ..writeln('</Types>');
  return buf.toString();
}

String _buildRelsXml() =>
    '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>\n'
    '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
    '<Relationship Id="rId1" '
    'Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" '
    'Target="word/document.xml"/>'
    '<Relationship Id="rId2" '
    'Type="http://schemas.openxmlformats.org/package/2006/relationships/metadata/core-properties" '
    'Target="docProps/core.xml"/>'
    '<Relationship Id="rId3" '
    'Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/extended-properties" '
    'Target="docProps/app.xml"/>'
    '</Relationships>';

String _buildDocumentRelsXml(
  List<_DocxRelation> relations, {
  required bool hasFootnotes,
  required bool hasEndnotes,
}) {
  final buf = StringBuffer()
    ..writeln('<?xml version="1.0" encoding="UTF-8" standalone="yes"?>')
    ..writeln(
      '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">',
    );
  if (hasFootnotes) {
    buf.writeln(
      '<Relationship Id="footnotesRel" '
      'Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/footnotes" '
      'Target="footnotes.xml"/>',
    );
  }
  if (hasEndnotes) {
    buf.writeln(
      '<Relationship Id="endnotesRel" '
      'Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/endnotes" '
      'Target="endnotes.xml"/>',
    );
  }
  buf.writeln(
    '<Relationship Id="stylesRel" '
    'Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" '
    'Target="styles.xml"/>',
  );
  buf.writeln(
    '<Relationship Id="numberingRel" '
    'Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/numbering" '
    'Target="numbering.xml"/>',
  );
  for (final r in relations) {
    final mode = r.targetMode != null ? ' TargetMode="${r.targetMode}"' : '';
    buf.writeln(
      '<Relationship Id="${r.id}" Type="${r.type}" '
      'Target="${r.target}"$mode/>',
    );
  }
  buf.writeln('</Relationships>');
  return buf.toString();
}

String _xmlEscape(String s) =>
    s.replaceAll('&', '&amp;').replaceAll('<', '&lt;').replaceAll('>', '&gt;');

/// Voor tests: de DOCX-bytes bouwen met vaste parameters.
@visibleForTesting
Future<Uint8List> buildDocumentExportDocxForTesting(
  ExportBundle bundle, {
  ExportDocumentMetadata? metadata,
  bool chapterPageBreak = false,
  FootnotePlacement footnotePlacement = FootnotePlacement.page,
  String footnotesTitle = 'Noten',
  HtmlImageResolver? embedImage,
  MermaidSvgResolver? renderMermaid,
  MathSvgResolver? renderMath,
}) => buildDocumentExportDocx(
  bundle,
  metadata: metadata,
  chapterPageBreak: chapterPageBreak,
  footnotePlacement: footnotePlacement,
  footnotesTitle: footnotesTitle,
  embedImage: embedImage,
  renderMermaid: renderMermaid,
  renderMath: renderMath,
);
