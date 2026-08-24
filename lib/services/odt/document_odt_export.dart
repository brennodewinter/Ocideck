// ODT (OpenDocument Text, ISO 26300) export voor een plat-Markdown-document.
//
// Bouwt een ODT-ZIP uit de geprojecteerde body: bewerkbare OpenDocument-XML
// met koppen, alinea's, tabellen, lijsten, voetnoten en afbeeldingen.
// Headless: geen Flutter, geen IO — de aanroeper schrijft de bytes weg.
//
// Hergebruikt de `archive`-package (pubspec: `archive: ^4.0.9`) voor de
// ZIP-verpakking en de `markdown`-package via markdown_to_odt.dart voor de
// ODT-conversie. Geen nieuwe dependency.
//
// ODT-structuur:
//   mimetype              (oncompressed, eerste entry)
//   META-INF/manifest.xml
//   content.xml           (stijlen + body)
//   meta.xml              (documentmetadata)
//   Pictures/image-N.ext  (afbeeldingen)

import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;

import '../../models/deck.dart' show TlpLevelX;
import '../document_export_service.dart' show projectedDocumentBody;
import '../document_footnote_setup.dart';
import '../export_bundle.dart';
import '../export_metadata.dart';
import '../marp_html_service.dart' show HtmlImageResolver;
import 'markdown_to_odt.dart';

/// Bouwt de ODT-bytes voor een document-export. Headless: geen IO.
///
/// De inhoud die de deur uit gaat komt uit [projectedDocumentBody] — de
/// geprojecteerde body via de bundel, nooit de rauwe bron. De
/// projectiegrens blijft intact: deze functie neemt een [ExportBundle] en
/// geen `Deck`.
///
/// [embedImage] levert per afbeeldingsbron een `data:`-URI op (dezelfde
/// callback als de HTML- en ePub-export). De ODT-builder parseert de
/// data-URI, haalt de ruwe bytes eruit, en slaat ze op als aparte bestanden
/// in de ZIP — niet als inline data-URI's, want LibreOffice verwacht
/// aparte bestanden in Pictures/.
Future<Uint8List> buildDocumentExportOdt(
  ExportBundle bundle, {
  ExportDocumentMetadata? metadata,
  bool chapterPageBreak = false,
  FootnotePlacement footnotePlacement = FootnotePlacement.page,
  String footnotesTitle = 'Noten',
  HtmlImageResolver? embedImage,
  String? sourcePath,
  String outputPath = '',
}) async {
  final body = projectedDocumentBody(bundle);
  final meta = metadata ?? ExportDocumentMetadata.fromDeck(bundle.audience);
  final title = meta.displayTitle('Document');

  // 1. Markdown → ODT body-XML.
  var odtBody = markdownToOdtBody(
    body,
    chapterPageBreak: chapterPageBreak,
    footnotesTitle: footnotesTitle,
    footnotePlacement: footnotePlacement,
  );

  // 2. Afbeeldingen: data-URI's → aparte bestanden in de ZIP.
  final images = <_OdtImage>[];
  if (embedImage != null) {
    odtBody = await _processImages(odtBody, embedImage, images);
  }

  // 3. content.xml (stijlen + body).
  final content = _buildContentXml(odtBody);

  // 4. meta.xml.
  final metaXml = _buildMetaXml(meta, title);

  // 5. manifest.xml.
  final manifest = _buildManifest(images);

  // 6. ZIP samenstellen.
  final archive = Archive();

  // mimetype moet de eerste entry zijn, zonder compressie.
  final mimetypeData = utf8.encode('application/vnd.oasis.opendocument.text');
  final mimetypeFile = ArchiveFile.bytes('mimetype', mimetypeData);
  mimetypeFile.compression = CompressionType.none;
  archive.add(mimetypeFile);

  void addText(String name, String content) {
    final data = utf8.encode(content);
    archive.add(ArchiveFile.bytes(name, data));
  }

  addText('META-INF/manifest.xml', manifest);
  addText('content.xml', content);
  addText('meta.xml', metaXml);

  for (final image in images) {
    archive.add(ArchiveFile.bytes('Pictures/${image.name}', image.bytes));
  }

  return ZipEncoder().encodeBytes(archive);
}

/// Eén afbeelding in de ODT-ZIP.
class _OdtImage {
  const _OdtImage(this.name, this.bytes, this.mediaType);

  final String name;
  final Uint8List bytes;
  final String mediaType;
}

/// Vervang alle `<draw:image xlink:href="...">` in [odtBody] door relatieve
/// paden en verzamel de bytes in [images]. Voor elke afbeeldingsbron wordt
/// [embedImage] aangeroepen om een `data:`-URI op te halen; die bytes worden
/// als apart bestand in de ZIP opgeslagen.
Future<String> _processImages(
  String odtBody,
  HtmlImageResolver embedImage,
  List<_OdtImage> images,
) async {
  final imgRegex = RegExp(
    r'<draw:image xlink:href="([^"]*)" xlink:type="simple">',
  );
  final matches = imgRegex.allMatches(odtBody).toList();
  if (matches.isEmpty) return odtBody;

  final seen = <String, String>{};
  var result = odtBody;

  for (final match in matches) {
    final src = match.group(1)!;
    final original = match.group(0)!;

    if (seen.containsKey(src)) {
      final odtPath = seen[src]!;
      result = result.replaceFirst(
        original,
        '<draw:image xlink:href="$odtPath" xlink:type="simple">',
      );
      continue;
    }

    final dataUri = src.startsWith('data:') ? src : await embedImage(src);
    if (dataUri == null) continue;

    final parsed = _parseDataUri(dataUri);
    if (parsed == null) continue;

    final ext = _extensionForMediaType(parsed.mediaType);
    final name = 'image-${images.length}.$ext';
    final odtPath = 'Pictures/$name';
    images.add(_OdtImage(name, parsed.bytes, parsed.mediaType));
    seen[src] = odtPath;

    result = result.replaceFirst(
      original,
      '<draw:image xlink:href="$odtPath" xlink:type="simple">',
    );
  }

  return result;
}

({Uint8List bytes, String mediaType})? _parseDataUri(String uri) {
  final comma = uri.indexOf(',');
  if (comma < 0) return null;
  final header = uri.substring(5, comma);
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

/// content.xml met automatic-styles en body.
String _buildContentXml(String body) {
  final buf = StringBuffer()
    ..writeln('<?xml version="1.0" encoding="UTF-8"?>')
    ..writeln(
      '<office:document-content '
      'xmlns:office="urn:oasis:names:tc:opendocument:xmlns:office:1.0" '
      'xmlns:text="urn:oasis:names:tc:opendocument:xmlns:text:1.0" '
      'xmlns:table="urn:oasis:names:tc:opendocument:xmlns:table:1.0" '
      'xmlns:style="urn:oasis:names:tc:opendocument:xmlns:style:1.0" '
      'xmlns:fo="urn:oasis:names:tc:opendocument:xmlns:xsl-fo-compatible:1.0" '
      'xmlns:xlink="http://www.w3.org/1999/xlink" '
      'xmlns:svg="urn:oasis:names:tc:opendocument:xmlns:svg-compatible:1.0" '
      'xmlns:draw="urn:oasis:names:tc:opendocument:xmlns:drawing:1.0" '
      'office:version="1.2">',
    )
    ..writeln('<office:automatic-styles>')
    ..writeln(_odtStyles)
    ..writeln('</office:automatic-styles>')
    ..writeln('<office:body>')
    ..writeln('<office:text>')
    ..write(body)
    ..writeln('</office:text>')
    ..writeln('</office:body>')
    ..writeln('</office:document-content>');
  return buf.toString();
}

/// meta.xml met documentmetadata (titel, auteur, taal, TLP, datum).
String _buildMetaXml(ExportDocumentMetadata meta, String title) {
  final now = DateTime.now().toUtc();
  final buf = StringBuffer()
    ..writeln('<?xml version="1.0" encoding="UTF-8"?>')
    ..writeln(
      '<office:document-meta '
      'xmlns:office="urn:oasis:names:tc:opendocument:xmlns:office:1.0" '
      'xmlns:dc="http://purl.org/dc/elements/1.1/" '
      'xmlns:meta="urn:oasis:names:tc:opendocument:xmlns:meta:1.0" '
      'office:version="1.2">',
    )
    ..writeln('<office:meta>')
    ..writeln('<dc:title>${_xmlEscape(title)}</dc:title>')
    ..writeln('<dc:creator>${_xmlEscape(meta.documentAuthor)}</dc:creator>')
    ..writeln(
      '<dc:language>${meta.language.isNotEmpty ? meta.language : "nl"}</dc:language>',
    )
    ..writeln(
      '<meta:creation-date>${now.toIso8601String().split(".").first}Z</meta:creation-date>',
    );
  if (meta.description.trim().isNotEmpty) {
    buf.writeln(
      '<dc:description>${_xmlEscape(meta.description.trim())}</dc:description>',
    );
  }
  if (meta.keywords.trim().isNotEmpty) {
    buf.writeln('<dc:subject>${_xmlEscape(meta.keywords.trim())}</dc:subject>');
  }
  if (meta.tlp.label.isNotEmpty) {
    buf.writeln(
      '<meta:user-defined meta:name="TLP">${_xmlEscape(meta.tlp.label)}</meta:user-defined>',
    );
  }
  if (meta.hasUnreviewedAi) {
    buf.writeln(
      '<meta:user-defined meta:name="AI-drafted">contains AI-drafted text that no human has checked</meta:user-defined>',
    );
  }
  buf
    ..writeln('</office:meta>')
    ..writeln('</office:document-meta>');
  return buf.toString();
}

/// META-INF/manifest.xml — lijst alle bestanden in het pakket.
String _buildManifest(List<_OdtImage> images) {
  final buf = StringBuffer()
    ..writeln('<?xml version="1.0" encoding="UTF-8"?>')
    ..writeln(
      '<manifest:manifest '
      'xmlns:manifest="urn:oasis:names:tc:opendocument:xmlns:manifest:1.0" '
      'manifest:version="1.2">',
    )
    ..writeln(
      '<manifest:file-entry manifest:media-type="application/vnd.oasis.opendocument.text" manifest:full-path="/"/>',
    )
    ..writeln(
      '<manifest:file-entry manifest:media-type="text/xml" manifest:full-path="content.xml"/>',
    )
    ..writeln(
      '<manifest:file-entry manifest:media-type="text/xml" manifest:full-path="meta.xml"/>',
    );
  for (final img in images) {
    buf.writeln(
      '<manifest:file-entry manifest:media-type="${img.mediaType}" manifest:full-path="Pictures/${img.name}"/>',
    );
  }
  buf.writeln('</manifest:manifest>');
  return buf.toString();
}

/// ODT-stijlen voor de automatic-styles sectie. Definieert koppen, alinea's,
/// inline-opmaak, tabellen en lijsten die de converter refereert.
const _odtStyles = '''
<style:style style:name="Heading_20_1" style:family="paragraph">
  <style:text-properties fo:font-size="170%" fo:font-weight="bold" style:font-name-asian="Noto Sans CJK SC" style:font-weight-asian="bold" style:font-weight-complex="bold"/>
</style:style>
<style:style style:name="Heading_20_2" style:family="paragraph">
  <style:text-properties fo:font-size="140%" fo:font-weight="bold" style:font-name-asian="Noto Sans CJK SC" style:font-weight-asian="bold" style:font-weight-complex="bold"/>
</style:style>
<style:style style:name="Heading_20_3" style:family="paragraph">
  <style:text-properties fo:font-size="120%" fo:font-weight="bold" style:font-name-asian="Noto Sans CJK SC" style:font-weight-asian="bold" style:font-weight-complex="bold"/>
</style:style>
<style:style style:name="Heading_20_4" style:family="paragraph">
  <style:text-properties fo:font-size="110%" fo:font-weight="bold" style:font-name-asian="Noto Sans CJK SC" style:font-weight-asian="bold" style:font-weight-complex="bold"/>
</style:style>
<style:style style:name="Heading_20_5" style:family="paragraph">
  <style:text-properties fo:font-size="100%" fo:font-weight="bold" style:font-name-asian="Noto Sans CJK SC" style:font-weight-asian="bold" style:font-weight-complex="bold"/>
</style:style>
<style:style style:name="Heading_20_6" style:family="paragraph">
  <style:text-properties fo:font-size="100%" fo:font-weight="bold" fo:font-style="italic" style:font-name-asian="Noto Sans CJK SC" style:font-weight-asian="bold" style:font-weight-complex="bold"/>
</style:style>
<style:style style:name="Strong" style:family="text">
  <style:text-properties fo:font-weight="bold" style:font-weight-asian="bold" style:font-weight-complex="bold"/>
</style:style>
<style:style style:name="Emphasis" style:family="text">
  <style:text-properties fo:font-style="italic" style:font-style-asian="italic" style:font-style-complex="italic"/>
</style:style>
<style:style style:name="Strike" style:family="text">
  <style:text-properties style:text-line-through-style="solid" style:text-line-through-type="single"/>
</style:style>
<style:style style:name="Source_Text" style:family="text">
  <style:text-properties style:font-name="Liberation Mono" fo:font-family="Liberation Mono" style:font-name-asian="Liberation Mono" style:font-name-complex="Liberation Mono"/>
</style:style>
<style:style style:name="Preformatted_Text" style:family="paragraph">
  <style:paragraph-properties fo:margin-top="0cm" fo:margin-bottom="0.2cm" fo:background-color="transparent"/>
  <style:text-properties style:font-name="Liberation Mono" fo:font-family="Liberation Mono" style:font-name-asian="Liberation Mono" style:font-name-complex="Liberation Mono" fo:font-size="90%"/>
</style:style>
<style:style style:name="Quote" style:family="paragraph">
  <style:paragraph-properties fo:margin-left="1cm" fo:margin-right="1cm" fo:margin-top="0.3cm" fo:margin-bottom="0.3cm" fo:text-indent="0cm" style:justify-single-word="false"/>
  <style:text-properties fo:font-style="italic" style:font-style-asian="italic" style:font-style-complex="italic"/>
</style:style>
<style:style style:name="Horizontal_Line" style:family="paragraph">
  <style:paragraph-properties fo:border-bottom="0.5pt solid #000000" fo:padding="0cm" fo:margin-top="0.3cm" fo:margin-bottom="0.3cm"/>
</style:style>
<style:style style:name="Table_20_Heading" style:family="paragraph">
  <style:text-properties fo:font-weight="bold" style:font-weight-asian="bold" style:font-weight-complex="bold"/>
</style:style>
<style:style style:name="Table_20_Contents" style:family="paragraph"/>
<style:style style:name="Table_20_Center" style:family="paragraph">
  <style:paragraph-properties fo:text-align="center" style:justify-single-word="false"/>
</style:style>
<style:style style:name="Table_20_Right" style:family="paragraph">
  <style:paragraph-properties fo:text-align="end" style:justify-single-word="false"/>
</style:style>
<style:style style:name="Graphics" style:family="graphic">
  <style:graphic-properties text:anchor-type="paragraph" svg:x="0cm" svg:y="0cm" style:wrap="none" style:vertical-pos="top" style:vertical-rel="paragraph" style:horizontal-pos="center" style:horizontal-rel="paragraph"/>
</style:style>
<text:list-style text:name="Ordered_List">
  <text:list-level-style-number text:level="1" text:style-name="Number" style:num-format="1." text:start-value="1"/>
  <text:list-level-style-number text:level="2" text:style-name="Number" style:num-format="a." text:start-value="1"/>
  <text:list-level-style-number text:level="3" text:style-name="Number" style:num-format="i." text:start-value="1"/>
  <text:list-level-style-number text:level="4" text:style-name="Number" style:num-format="1." text:start-value="1"/>
  <text:list-level-style-number text:level="5" text:style-name="Number" style:num-format="a." text:start-value="1"/>
  <text:list-level-style-number text:level="6" text:style-name="Number" style:num-format="i." text:start-value="1"/>
  <text:list-level-style-number text:level="7" text:style-name="Number" style:num-format="1." text:start-value="1"/>
  <text:list-level-style-number text:level="8" text:style-name="Number" style:num-format="a." text:start-value="1"/>
  <text:list-level-style-number text:level="9" text:style-name="Number" style:num-format="i." text:start-value="1"/>
  <text:list-level-style-number text:level="10" text:style-name="Number" style:num-format="1." text:start-value="1"/>
</text:list-style>
''';

String _xmlEscape(String s) =>
    s.replaceAll('&', '&amp;').replaceAll('<', '&lt;').replaceAll('>', '&gt;');

/// Voor tests: de ODT-bytes bouwen met vaste parameters.
@visibleForTesting
Future<Uint8List> buildDocumentExportOdtForTesting(
  ExportBundle bundle, {
  ExportDocumentMetadata? metadata,
  bool chapterPageBreak = false,
  FootnotePlacement footnotePlacement = FootnotePlacement.page,
  String footnotesTitle = 'Noten',
  HtmlImageResolver? embedImage,
}) => buildDocumentExportOdt(
  bundle,
  metadata: metadata,
  chapterPageBreak: chapterPageBreak,
  footnotePlacement: footnotePlacement,
  footnotesTitle: footnotesTitle,
  embedImage: embedImage,
);
