import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/services/import/core/result.dart';
import 'package:ocideck/services/import/importers/odp/odp_importer.dart';
import 'package:ocideck/services/import/models/conversion_issue.dart';

// De stabiliteitsbelofte van #877 op de ODP-importer, gelijkwaardig aan PPTX:
// één beschadigd onderdeel wordt genoteerd en overgeslagen, de rest van de dia
// en de volgende dia's blijven — in volgorde.

const _office = 'urn:oasis:names:tc:opendocument:xmlns:office:1.0';
const _draw = 'urn:oasis:names:tc:opendocument:xmlns:drawing:1.0';
const _text = 'urn:oasis:names:tc:opendocument:xmlns:text:1.0';
const _xlink = 'http://www.w3.org/1999/xlink';
const _presentation = 'urn:oasis:names:tc:opendocument:xmlns:presentation:1.0';

String _titleFrame(String title) =>
    '<draw:frame draw:name="Title" presentation:class="title" '
    'svg:x="2cm" svg:y="1cm" svg:width="24cm" svg:height="3cm">'
    '<draw:text-box><text:p>$title</text:p></draw:text-box></draw:frame>';

/// content.xml met twee dia's: de eerste draagt een grafiek waarvan het
/// sub-document onleesbaar is, de tweede een afbeelding die niet in het archief
/// zit.
String _contentXml() =>
    '<?xml version="1.0"?>'
    '<office:document-content xmlns:office="$_office" xmlns:draw="$_draw" '
    'xmlns:text="$_text" xmlns:xlink="$_xlink" xmlns:presentation="$_presentation" '
    'office:version="1.2"><office:body><office:presentation>'
    '<draw:page draw:name="p1" svg:width="28cm" svg:height="15.75cm">'
    '${_titleFrame('Een')}'
    '<draw:frame draw:name="Chart" svg:x="2cm" svg:y="5cm" svg:width="20cm" svg:height="10cm">'
    '<draw:object xlink:href="ObjectCharts/1" xlink:type="simple"/></draw:frame>'
    '</draw:page>'
    '<draw:page draw:name="p2" svg:width="28cm" svg:height="15.75cm">'
    '${_titleFrame('Twee')}'
    '<draw:frame draw:name="Img" svg:x="10cm" svg:y="5cm" svg:width="8cm" svg:height="6cm">'
    '<draw:image xlink:href="Pictures/photo.png" xlink:type="simple"/></draw:frame>'
    '</draw:page>'
    '</office:presentation></office:body></office:document-content>';

Uint8List _zip(Map<String, String> parts) {
  final archive = Archive();
  parts.forEach((name, content) {
    final data = Uint8List.fromList(utf8.encode(content));
    archive.addFile(ArchiveFile(name, data.length, data));
  });
  return Uint8List.fromList(ZipEncoder().encode(archive));
}

void main() {
  test(
    'kapotte grafiek en ontbrekende afbeelding raken alleen hun eigen dia',
    () async {
      final bytes = _zip({
        'content.xml': _contentXml(),
        // Het grafiek-sub-document bestaat maar is geen geldige XML.
        'ObjectCharts/1/content.xml': '<chart:chart><broken',
        // Pictures/photo.png ontbreekt bewust.
      });

      final result = await OdpImporter().importBytes(bytes, path: 'deck.odp');
      expect(result.isOk, isTrue);
      final slides = result.okValue!.slides;

      expect(slides, hasLength(2));
      expect(slides[0].title, 'Een');
      expect(slides[1].title, 'Twee');

      // Dia 1: de grafiek is niet gebouwd, maar de titel en de rest blijven, en
      // het verlies is genoteerd met onderdeel + oorzaak.
      expect(slides[0].chart, isNull);
      final chartIssue = slides[0].parseIssues.singleWhere(
        (i) => i.component == IssueComponent.chart,
      );
      expect(chartIssue.cause, IssueCause.malformedXml);

      // Dia 2: de ontbrekende afbeelding is genoteerd, de dia blijft.
      expect(slides[1].images, isEmpty);
      final mediaIssue = slides[1].parseIssues.singleWhere(
        (i) => i.component == IssueComponent.media,
      );
      expect(mediaIssue.cause, IssueCause.missingPart);
    },
  );
}
