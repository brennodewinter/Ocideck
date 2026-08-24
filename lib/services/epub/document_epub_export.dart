// ePub 3-export voor een plat-Markdown-document.
//
// Bouwt een EPUB 3-ZIP uit de geprojecteerde body: herflowbare XHTML met
// koppen als navigatie, noten achterin, en afbeeldingen als aparte entries.
// Headless: geen Flutter, geen IO — de aanroeper schrijft de bytes weg.
//
// Hergebruikt de `archive`-package (pubspec: `archive: ^4.0.9`) voor de
// ZIP-verpakking en de `markdown`-package via markdown_to_xhtml.dart voor de
// XHTML-conversie. Geen nieuwe dependency.
//
// EPUB 3-structuur:
//   mimetype              (oncompressed, eerste entry)
//   META-INF/container.xml
//   OEBPS/content.opf     (manifest + spine + metadata)
//   OEBPS/nav.xhtml       (navigatie-document)
//   OEBPS/document.xhtml  (de inhoud)
//   OEBPS/style.css       (basisstijl)
//   OEBPS/images/image-N.ext (afbeeldingen)

import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;

import '../../models/deck.dart' show TlpLevelX;
import '../export_bundle.dart';
import '../export_metadata.dart';
import '../marp_html_service.dart' show HtmlImageResolver;
import '../document_export_service.dart' show projectedDocumentBody;
import 'markdown_to_xhtml.dart';

/// Bouwt de EPUB 3-bytes voor een document-export. Headless: geen IO.
///
/// De inhoud die de deur uit gaat komt uit [projectedDocumentBody] — de
/// geprojecteerde body via de bundel, nooit de rauwe bron. De
/// projectiegrens blijft intact: deze functie neemt een [ExportBundle] en
/// geen `Deck`.
///
/// [embedImage] levert per afbeeldingsbron een `data:`-URI op (dezelfde
/// callback als de HTML-export). De EPUB-builder parseert de data-URI, haalt
/// de ruwe bytes eruit, en slaat ze op als aparte bestanden in de ZIP — niet
/// als inline data-URI's, want e-readers verwachten aparte bestanden.
Future<Uint8List> buildDocumentExportEpub(
  ExportBundle bundle, {
  ExportDocumentMetadata? metadata,
  bool chapterPageBreak = false,
  String footnotesTitle = 'Noten',
  HtmlImageResolver? embedImage,
  String? sourcePath,
  String outputPath = '',
}) async {
  final body = projectedDocumentBody(bundle);
  final meta = metadata ?? ExportDocumentMetadata.fromDeck(bundle.audience);
  final title = meta.displayTitle('Document');

  // 1. Markdown → XHTML.
  var xhtml = markdownToXhtml(
    body,
    chapterPageBreak: chapterPageBreak,
    footnotesTitle: footnotesTitle,
  );

  // 2. Afbeeldingen: data-URI's → aparte bestanden in de ZIP.
  final images = <_EpubImage>[];
  if (embedImage != null) {
    xhtml = await _processImages(xhtml, embedImage, images);
  }

  // 3. Navigatie-document (nav.xhtml) met koppen als inhoudsopgave.
  final nav = _buildNav(xhtml, title);

  // 4. Content-document (document.xhtml).
  final document = _buildDocumentXhtml(xhtml, title, meta);

  // 5. OPF (content.opf).
  final opf = _buildOpf(meta, title, images);

  // 6. CSS.
  const css = _epubCss;

  // 7. ZIP samenstellen.
  final archive = Archive();

  // mimetype moet de eerste entry zijn, zonder compressie.
  final mimetypeData = utf8.encode('application/epub+zip');
  final mimetypeFile = ArchiveFile.bytes('mimetype', mimetypeData);
  mimetypeFile.compression = CompressionType.none;
  archive.add(mimetypeFile);

  void addText(String name, String content) {
    final data = utf8.encode(content);
    archive.add(ArchiveFile.bytes(name, data));
  }

  addText('META-INF/container.xml', _containerXml);
  addText('OEBPS/content.opf', opf);
  addText('OEBPS/nav.xhtml', nav);
  addText('OEBPS/document.xhtml', document);
  addText('OEBPS/style.css', css);

  for (final image in images) {
    archive.add(ArchiveFile.bytes('OEBPS/images/${image.name}', image.bytes));
  }

  return ZipEncoder().encodeBytes(archive);
}

/// Eén afbeelding in de EPUB-ZIP.
class _EpubImage {
  const _EpubImage(this.name, this.bytes, this.mediaType);

  final String name;
  final Uint8List bytes;
  final String mediaType;
}

/// Vervang alle `<img src="...">` in [xhtml] door relatieve paden en
/// verzamel de bytes in [images]. Voor elke afbeeldingsbron wordt
/// [embedImage] aangeroepen om een `data:`-URI op te halen; die bytes worden
/// als apart bestand in de ZIP opgeslagen. Afbeeldingen waarvoor
/// [embedImage] `null` teruggeeft of die al een `data:`-URI zijn die niet te
/// parsen is, blijven staan zoals ze zijn.
Future<String> _processImages(
  String xhtml,
  HtmlImageResolver embedImage,
  List<_EpubImage> images,
) async {
  final imgRegex = RegExp(r'<img src="([^"]*)" alt="([^"]*)"/>');
  final matches = imgRegex.allMatches(xhtml).toList();
  if (matches.isEmpty) return xhtml;

  // Bron → EPUB-pad mapping, zodat dezelfde afbeelding niet twee keer wordt
  // opgeslagen.
  final seen = <String, String>{};
  var result = xhtml;

  for (final match in matches) {
    final src = match.group(1)!;
    final alt = match.group(2)!;
    final original = match.group(0)!;

    // Reeds verwerkt? Hergebruik het pad.
    if (seen.containsKey(src)) {
      final epubPath = seen[src]!;
      result = result.replaceFirst(
        original,
        '<img src="$epubPath" alt="$alt"/>',
      );
      continue;
    }

    // Als het al een data-URI is, parse direct; anders vraag embedImage om
    // een data-URI op te halen.
    final dataUri = src.startsWith('data:') ? src : await embedImage(src);
    if (dataUri == null) continue;

    final parsed = _parseDataUri(dataUri);
    if (parsed == null) continue;

    final ext = _extensionForMediaType(parsed.mediaType);
    final name = 'image-${images.length}.$ext';
    final epubPath = 'images/$name';
    images.add(_EpubImage(name, parsed.bytes, parsed.mediaType));
    seen[src] = epubPath;

    result = result.replaceFirst(original, '<img src="$epubPath" alt="$alt"/>');
  }

  return result;
}

({Uint8List bytes, String mediaType})? _parseDataUri(String uri) {
  // data:<mime>;base64,<data>
  final comma = uri.indexOf(',');
  if (comma < 0) return null;
  final header = uri.substring(5, comma); // na "data:"
  final data = uri.substring(comma + 1);
  if (!header.contains('base64')) return null;
  final mime = header.split(';').first;
  try {
    final bytes = base64Decode(data);
    return (bytes: Uint8List.fromList(bytes), mediaType: mime);
  } on FormatException {
    return null;
  }
}

String _extensionForMediaType(String mediaType) => switch (mediaType) {
  'image/png' => 'png',
  'image/jpeg' => 'jpg',
  'image/gif' => 'gif',
  'image/svg+xml' => 'svg',
  'image/webp' => 'webp',
  _ => 'bin',
};

/// META-INF/container.xml — wijst naar de OPF.
const _containerXml = '''<?xml version="1.0" encoding="UTF-8"?>
<container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container">
  <rootfiles>
    <rootfile full-path="OEBPS/content.opf" media-type="application/oebps-package+xml"/>
  </rootfiles>
</container>''';

/// Het navigatie-document (nav.xhtml) met koppen als inhoudsopgave.
String _buildNav(String xhtml, String title) {
  // Haal H1/H2-koppen uit de XHTML voor de inhoudsopgave.
  final headings = <_NavHeading>[];
  final headingRegex = RegExp(
    r'<(h[12])[^>]*>(.*?)</h[12]>',
    caseSensitive: false,
  );
  var id = 0;
  for (final match in headingRegex.allMatches(xhtml)) {
    final level = match.group(1)!;
    final text = _stripTags(match.group(2)!);
    if (text.trim().isEmpty) continue;
    headings.add(_NavHeading(level, text, 'heading-$id'));
    id++;
  }

  final buf = StringBuffer()
    ..writeln('<?xml version="1.0" encoding="UTF-8"?>')
    ..writeln(
      '<html xmlns="http://www.w3.org/1999/xhtml" '
      'xmlns:epub="http://www.idpf.org/2007/ops" '
      'lang="nl">',
    )
    ..writeln('<head><meta charset="utf-8"/>')
    ..writeln('<title>${_xmlEscape(title)}</title>')
    ..writeln('<link rel="stylesheet" type="text/css" href="style.css"/>')
    ..writeln('</head><body>')
    ..writeln('<nav epub:type="toc" id="toc">')
    ..writeln('<h1>${_xmlEscape(title)}</h1><ol>');

  for (final h in headings) {
    buf.writeln(
      '<li><a href="document.xhtml#${h.id}">${_xmlEscape(h.text)}</a></li>',
    );
  }

  buf
    ..writeln('</ol></nav>')
    ..writeln('</body></html>');
  return buf.toString();
}

/// Het content-document (document.xhtml) met de volledige inhoud.
String _buildDocumentXhtml(
  String xhtml,
  String title,
  ExportDocumentMetadata meta,
) {
  // Voeg id's toe aan H1/H2-koppen voor de navigatie.
  var id = 0;
  final withIds = xhtml.replaceAllMapped(RegExp(r'<(h[12])([^>]*)>'), (m) {
    final replacement = '<${m.group(1)}${m.group(2)} id="heading-$id">';
    id++;
    return replacement;
  });

  final lang = meta.language.isNotEmpty ? meta.language : 'nl';
  final buf = StringBuffer()
    ..writeln('<?xml version="1.0" encoding="UTF-8"?>')
    ..writeln(
      '<html xmlns="http://www.w3.org/1999/xhtml" '
      'xmlns:epub="http://www.idpf.org/2007/ops" '
      'lang="$lang">',
    )
    ..writeln('<head><meta charset="utf-8"/>')
    ..writeln('<title>${_xmlEscape(title)}</title>')
    ..writeln('<link rel="stylesheet" type="text/css" href="style.css"/>')
    ..writeln('</head><body>')
    ..write(withIds)
    ..writeln('</body></html>');
  return buf.toString();
}

/// De OPF (content.opf) met metadata, manifest en spine.
String _buildOpf(
  ExportDocumentMetadata meta,
  String title,
  List<_EpubImage> images,
) {
  final buf = StringBuffer()
    ..writeln('<?xml version="1.0" encoding="UTF-8"?>')
    ..writeln(
      '<package xmlns="http://www.idpf.org/2007/opf" '
      'version="3.0" unique-identifier="bookid">',
    )
    ..writeln('<metadata xmlns:dc="http://purl.org/dc/elements/1.1/">')
    ..writeln(
      '  <dc:identifier id="bookid">ocideck-${DateTime.now().millisecondsSinceEpoch}</dc:identifier>',
    )
    ..writeln('  <dc:title>${_xmlEscape(title)}</dc:title>')
    ..writeln(
      '  <dc:language>${meta.language.isNotEmpty ? meta.language : "nl"}</dc:language>',
    )
    ..writeln('  <dc:creator>${_xmlEscape(meta.documentAuthor)}</dc:creator>');

  if (meta.description.trim().isNotEmpty) {
    buf.writeln(
      '  <dc:description>${_xmlEscape(meta.description.trim())}</dc:description>',
    );
  }
  if (meta.keywords.trim().isNotEmpty) {
    buf.writeln(
      '  <dc:subject>${_xmlEscape(meta.keywords.trim())}</dc:subject>',
    );
  }
  if (meta.tlp.label.isNotEmpty) {
    buf.writeln('  <dc:rights>TLP: ${_xmlEscape(meta.tlp.label)}</dc:rights>');
  }
  if (meta.hasUnreviewedAi) {
    buf.writeln(
      '  <dc:rights>contains AI-drafted text that no human has checked</dc:rights>',
    );
  }

  buf
    ..writeln(
      '  <meta property="dcterms:modified">${DateTime.now().toUtc().toIso8601String().split(".").first}Z</meta>',
    )
    ..writeln('</metadata>')
    ..writeln('<manifest>')
    ..writeln(
      '  <item id="nav" href="nav.xhtml" media-type="application/xhtml+xml" properties="nav"/>',
    )
    ..writeln(
      '  <item id="document" href="document.xhtml" media-type="application/xhtml+xml"/>',
    )
    ..writeln('  <item id="css" href="style.css" media-type="text/css"/>');

  for (var i = 0; i < images.length; i++) {
    final img = images[i];
    buf.writeln(
      '  <item id="img-$i" href="images/${img.name}" media-type="${img.mediaType}"/>',
    );
  }

  buf
    ..writeln('</manifest>')
    ..writeln('<spine>')
    ..writeln('  <itemref idref="document"/>')
    ..writeln('</spine>')
    ..writeln('</package>');
  return buf.toString();
}

/// Basis-CSS voor de ePub — herflowbare tekst met leesbare standaardopmaak.
const _epubCss = '''body {
  font-family: serif;
  line-height: 1.6;
  margin: 1em;
}
h1 { font-size: 1.8em; margin-top: 1em; }
h2 { font-size: 1.4em; margin-top: 0.8em; }
h3 { font-size: 1.2em; margin-top: 0.6em; }
h4, h5, h6 { font-size: 1.1em; margin-top: 0.5em; }
img { max-width: 100%; height: auto; }
table { border-collapse: collapse; width: 100%; margin: 1em 0; }
th, td { border: 1px solid #ccc; padding: 0.4em 0.6em; text-align: left; }
th { background: #f0f0f0; font-weight: bold; }
blockquote { margin: 1em 0; padding-left: 1em; border-left: 3px solid #ccc; color: #555; }
code { font-family: monospace; font-size: 0.9em; }
pre { background: #f5f5f5; padding: 0.8em; overflow-x: auto; white-space: pre-wrap; }
pre code { background: none; padding: 0; }
.ocideck-footnotes { margin-top: 2em; border-top: 1px solid #ccc; padding-top: 1em; }
.ocideck-fnback { text-decoration: none; }
.ocideck-timeline th { white-space: nowrap; }
''';

class _NavHeading {
  const _NavHeading(this.level, this.text, this.id);
  final String level;
  final String text;
  final String id;
}

String _stripTags(String s) => s.replaceAll(RegExp(r'<[^>]*>'), '');

String _xmlEscape(String s) =>
    s.replaceAll('&', '&amp;').replaceAll('<', '&lt;').replaceAll('>', '&gt;');

/// Voor tests: de EPUB-bytes bouwen met een vaste timestamp.
@visibleForTesting
Future<Uint8List> buildDocumentExportEpubForTesting(
  ExportBundle bundle, {
  ExportDocumentMetadata? metadata,
  bool chapterPageBreak = false,
  String footnotesTitle = 'Noten',
  HtmlImageResolver? embedImage,
}) => buildDocumentExportEpub(
  bundle,
  metadata: metadata,
  chapterPageBreak: chapterPageBreak,
  footnotesTitle: footnotesTitle,
  embedImage: embedImage,
);
