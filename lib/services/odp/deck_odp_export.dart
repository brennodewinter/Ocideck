// ODP (OpenDocument Presentation, ISO 26300) export voor een deck.
//
// Bouwt een ODP-ZIP uit gerenderde slide-afbeeldingen — dezelfde aanpak als
// PPTX: één afbeelding per slide, niet een poging de opmaak na te bootsen.
// De ontvanger krijgt een presentatie die er exact zo uitziet als in de app.
//
// Headless: geen Flutter, geen IO — de aanroeler (export_service.dart) levert
// de afbeeldingen en schrijft de bytes weg. Hergebruikt de `archive`-package
// (al een directe dependency) voor de ZIP-verpakking. Geen nieuwe dependency.
//
// ODP-structuur:
//   mimetype              (oncompressed, eerste entry)
//   META-INF/manifest.xml
//   content.xml           (stijlen + slides)
//   meta.xml              (documentmetadata)
//   Pictures/image-N.png  (slide-afbeeldingen)

import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';

import '../../models/deck.dart' show TlpLevelX;
import '../export_metadata.dart';

/// Slide-breedte en -hoogte in cm (16:9, gelijk aan LibreOffice Impress
/// standaard).
const odpSlideWidthCm = 25.4;
const odpSlideHeightCm = 14.29;

/// Bouwt een ODP (OpenDocument Presentation) uit gerenderde slide-afbeeldingen.
///
/// Headless: geen IO. De aanroeler levert [images] (één PNG per slide) en
/// [metadata], en krijgt de ODT-bytes terug.
Uint8List buildDeckExportOdp({
  required List<Uint8List> images,
  required ExportDocumentMetadata metadata,
  required String fallbackTitle,
}) {
  final archive = Archive();
  void addText(String name, String content) {
    final data = utf8.encode(content);
    archive.add(ArchiveFile(name, data.length, data));
  }

  final slideCount = images.length;

  // mimetype moet de eerste entry zijn, zonder compressie.
  final mimetypeData = utf8.encode(
    'application/vnd.oasis.opendocument.presentation',
  );
  final mimetypeFile = ArchiveFile.bytes('mimetype', mimetypeData);
  mimetypeFile.compression = CompressionType.none;
  archive.add(mimetypeFile);

  addText('META-INF/manifest.xml', _odpManifest(slideCount));
  addText('content.xml', _odpContentXml(slideCount));
  addText('meta.xml', _odpMetaXml(metadata, fallbackTitle: fallbackTitle));

  for (var i = 0; i < slideCount; i++) {
    final png = images[i];
    archive.add(ArchiveFile('Pictures/image${i + 1}.png', png.length, png));
  }

  return ZipEncoder().encodeBytes(archive);
}

String _odpManifest(int slideCount) {
  final buf = StringBuffer()
    ..writeln('<?xml version="1.0" encoding="UTF-8"?>')
    ..writeln(
      '<manifest:manifest '
      'xmlns:manifest="urn:oasis:names:tc:opendocument:xmlns:manifest:1.0" '
      'manifest:version="1.2">',
    )
    ..writeln(
      '<manifest:file-entry manifest:media-type="application/vnd.oasis.opendocument.presentation" manifest:full-path="/"/>',
    )
    ..writeln(
      '<manifest:file-entry manifest:media-type="text/xml" manifest:full-path="content.xml"/>',
    )
    ..writeln(
      '<manifest:file-entry manifest:media-type="text/xml" manifest:full-path="meta.xml"/>',
    );
  for (var i = 1; i <= slideCount; i++) {
    buf.writeln(
      '<manifest:file-entry manifest:media-type="image/png" manifest:full-path="Pictures/image$i.png"/>',
    );
  }
  buf.writeln('</manifest:manifest>');
  return buf.toString();
}

String _odpContentXml(int slideCount) {
  final buf = StringBuffer()
    ..writeln('<?xml version="1.0" encoding="UTF-8"?>')
    ..writeln(
      '<office:document-content '
      'xmlns:office="urn:oasis:names:tc:opendocument:xmlns:office:1.0" '
      'xmlns:draw="urn:oasis:names:tc:opendocument:xmlns:drawing:1.0" '
      'xmlns:style="urn:oasis:names:tc:opendocument:xmlns:style:1.0" '
      'xmlns:fo="urn:oasis:names:tc:opendocument:xmlns:xsl-fo-compatible:1.0" '
      'xmlns:xlink="http://www.w3.org/1999/xlink" '
      'xmlns:svg="urn:oasis:names:tc:opendocument:xmlns:svg-compatible:1.0" '
      'xmlns:text="urn:oasis:names:tc:opendocument:xmlns:text:1.0" '
      'office:version="1.2">',
    )
    ..writeln('<office:automatic-styles>')
    ..writeln(
      '<style:style style:name="dp1" style:family="drawing-page">'
      '<style:drawing-page-properties/>'
      '</style:style>',
    )
    ..writeln(
      '<style:style style:name="gr1" style:family="graphic">'
      '<style:graphic-properties style:wrap="none" draw:auto-grow-height="false"/>'
      '</style:style>',
    )
    ..writeln('</office:automatic-styles>')
    ..writeln('<office:body>')
    ..writeln('<office:presentation>');

  for (var i = 1; i <= slideCount; i++) {
    buf.writeln(
      '<draw:page draw:name="page$i" draw:style-name="dp1">'
      '<draw:frame draw:style-name="gr1" svg:x="0cm" svg:y="0cm" '
      'svg:width="${odpSlideWidthCm}cm" svg:height="${odpSlideHeightCm}cm">'
      '<draw:image xlink:href="Pictures/image$i.png" xlink:type="simple"/>'
      '</draw:frame>'
      '</draw:page>',
    );
  }

  buf
    ..writeln('</office:presentation>')
    ..writeln('</office:body>')
    ..writeln('</office:document-content>');
  return buf.toString();
}

String _odpMetaXml(
  ExportDocumentMetadata metadata, {
  required String fallbackTitle,
}) {
  final now = DateTime.now().toUtc();
  final title = _xmlEscape(metadata.displayTitle(fallbackTitle));
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
    ..writeln('<dc:title>$title</dc:title>')
    ..writeln('<dc:creator>${_xmlEscape(metadata.documentAuthor)}</dc:creator>')
    ..writeln(
      '<meta:creation-date>${now.toIso8601String().split(".").first}Z</meta:creation-date>',
    );
  if (metadata.tlp.label.isNotEmpty) {
    buf.writeln(
      '<meta:user-defined meta:name="TLP">${_xmlEscape(metadata.tlp.label)}</meta:user-defined>',
    );
  }
  buf
    ..writeln('</office:meta>')
    ..writeln('</office:document-meta>');
  return buf.toString();
}

String _xmlEscape(String s) =>
    s.replaceAll('&', '&amp;').replaceAll('<', '&lt;').replaceAll('>', '&gt;');
