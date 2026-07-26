import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/services/import/core/result.dart';
import 'package:ocideck/services/import/importers/import_failure.dart';
import 'package:ocideck/services/import/importers/importer.dart';
import 'package:ocideck/services/import/importers/keynote/key_importer.dart';
import 'package:ocideck/services/import/importers/odp/odp_importer.dart';
import 'package:ocideck/services/import/importers/pptx/pptx_importer.dart';
import 'package:ocideck/services/import/models/source_deck.dart';
import 'package:ocideck/services/import/models/source_format.dart';
import 'package:ocideck/services/import/pipeline/importer_registry.dart';
import 'package:ocideck/services/import/presentation_import_service.dart';
import 'package:ocideck/services/import/utils/import_budget.dart';
import 'package:ocideck/services/import/utils/xml_utils.dart';

import 'helpers/key_fixtures.dart' as kf;

/// Het centrale resourcebudget (#874): de tel-caps op dia's, de vertaling van
/// een overschrijding naar de reden `tooLarge`, en het bewijs dat het archief
/// maar één keer wordt uitgepakt.
///
/// De zip-, entry- en Snappy-grenzen worden in `archive_utils_test.dart` en
/// `snappy_test.dart` bewaakt; dit bestand dekt de dia-tellingen en het
/// service-brede gedrag.
void main() {
  group('de dia-telling wordt begrensd', () {
    test('pptx met te veel dia\'s eindigt als tooLarge', () async {
      final result = await PptxImporter().importBytes(
        _pptxWithSlides(6),
        path: 'veel.pptx',
        budget: _slideBudget(4),
      );
      expect(result.isOk, isFalse);
      final failure = result.errValue!;
      expect(failure.reason, ImportFailureReason.tooLarge);
      expect(failure.args['limiet'], contains('dia'));
    });

    test('odp met te veel pagina\'s eindigt als tooLarge', () async {
      final result = await OdpImporter().importBytes(
        _odpWithPages(6),
        path: 'veel.odp',
        budget: _slideBudget(4),
      );
      expect(result.isOk, isFalse);
      final failure = result.errValue!;
      expect(failure.reason, ImportFailureReason.tooLarge);
      expect(failure.args['limiet'], contains('dia'));
    });

    test('binnen de grens blijft de import gewoon slagen', () async {
      final result = await PptxImporter().importBytes(
        _pptxWithSlides(3),
        path: 'weinig.pptx',
        budget: _slideBudget(4),
      );
      expect(result.isOk, isTrue);
      expect(result.okValue!.slides, hasLength(3));
    });
  });

  test('key met te veel IWA-objecten eindigt als tooLarge', () async {
    // Drie IWA-objecten in één stroom; budget van twee. De `objects`-map groeit
    // met de bron, dus die telling wordt begrensd vóór de reconstructie.
    final stream = kf.iwaStream([
      ...kf.record(1, 1, kf.stringPayload('een')),
      ...kf.record(2, 1, kf.stringPayload('twee')),
      ...kf.record(3, 1, kf.stringPayload('drie')),
    ]);
    final bytes = kf.zip({'Index/Document.iwa': stream});
    final result = await KeyImporter().importBytes(
      bytes,
      path: 'veel.key',
      budget: ImportBudget.forTest(maxIwaObjects: 2),
    );
    expect(result.isOk, isFalse);
    expect(result.errValue!.reason, ImportFailureReason.tooLarge);
    expect(result.errValue!.args['limiet'], contains('IWA-objecten'));
  });

  test('de service vertaalt een budgetoverschrijding naar tooLarge', () async {
    // De hele keten: uitpakken, valideren, importeren met een piepklein budget.
    final service = PresentationImportService(budget: _slideBudget(4));
    final result = await service.importBytes(
      _pptxWithSlides(6),
      filename: 'groot/veel.pptx',
    );
    expect(result.isSuccess, isFalse);
    expect(result.failure!.reason, ImportFailureReason.tooLarge);
    // De service vult de bestandsnaam aan zodat de melding compleet is (#806).
    expect(result.failure!.args['bestand'], 'groot/veel.pptx');
    expect(result.failure!.args['limiet'], contains('dia'));
  });

  test('het archief wordt maar één keer uitgepakt', () async {
    // Het geheugenbewijs uit #874: het "meerdere volledige kopieën"-risico is
    // precies een tweede keer uitpakken (een tweede Archive met het hele
    // bestand erin). De service pakt één keer uit en geeft het [Archive] door;
    // de importer krijgt het als [preDecoded] en pakt niet opnieuw uit. Dit is
    // een deterministisch bewijs — een RSS-meting is onder de gedeelde
    // testrunner te wisselvallig om een piek betrouwbaar te toetsen.
    final spy = _SpyImporter();
    final service = PresentationImportService(
      registry: ImporterRegistry(importers: [spy]),
    );
    final result = await service.importBytes(
      _pptxEnvelope(),
      filename: 'demo.pptx',
    );
    expect(result.isSuccess, isTrue);
    expect(
      spy.receivedPreDecoded,
      isNotNull,
      reason:
          'de importer hoort het al-uitgepakte archief te krijgen, '
          'zodat hetzelfde bestand niet twee keer wordt uitgepakt',
    );
  });

  group('een te groot XML-onderdeel wordt niet geparseerd', () {
    test('boven de grens komt er null terug', () {
      final tooBig = '<a>${'x' * 200}</a>';
      expect(
        parseXmlSafe(tooBig, budget: ImportBudget.forTest(maxXmlPartBytes: 32)),
        isNull,
      );
    });

    test('binnen de grens parseert gewoon', () {
      final doc = parseXmlSafe(
        '<a>hoi</a>',
        budget: ImportBudget.forTest(maxXmlPartBytes: 4096),
      );
      expect(doc, isNotNull);
      expect(doc!.rootElement.name.local, 'a');
    });
  });
}

/// Een budget dat alleen de dia-telling knijpt; de overige assen ruim genoeg
/// dat de kleine fixtures er niet toevallig op vallen.
ImportBudget _slideBudget(int maxSlides) => ImportBudget.forTest(
  maxSlides: maxSlides,
  maxSourceBytes: 64 * 1024,
  maxUncompressedEntry: 64 * 1024,
  maxUncompressedTotal: 256 * 1024,
  maxArchiveEntries: 256,
);

const _p = 'http://schemas.openxmlformats.org/presentationml/2006/main';
const _a = 'http://schemas.openxmlformats.org/drawingml/2006/main';
const _r =
    'http://schemas.openxmlformats.org/officeDocument/2006/relationships';
const _pkg = 'http://schemas.openxmlformats.org/package/2006/relationships';

/// Een `.pptx` die [n] dia's declareert (alle wijzend naar dezelfde diapart —
/// genoeg om de tel-cap te raken, want die kijkt naar het aantal `sldId`-knopen
/// vóór de parseerlus).
Uint8List _pptxWithSlides(int n) {
  final slide =
      '<?xml version="1.0"?>'
      '<p:sld xmlns:a="$_a" xmlns:p="$_p" xmlns:r="$_r"><p:cSld><p:spTree>'
      '<p:sp><p:nvSpPr><p:cNvPr id="2" name="Title"/><p:cNvSpPr/>'
      '<p:nvPr><p:ph type="title"/></p:nvPr></p:nvSpPr><p:spPr/>'
      '<p:txBody><a:bodyPr/><a:lstStyle/><a:p><a:r><a:t>Titel</a:t></a:r></a:p>'
      '</p:txBody></p:sp>'
      '</p:spTree></p:cSld></p:sld>';
  final sldIds = [
    for (var i = 1; i <= n; i++) '<p:sldId id="${255 + i}" r:id="rId$i"/>',
  ].join();
  final rels = [
    for (var i = 1; i <= n; i++)
      '<Relationship Id="rId$i" Type="$_r/slide" '
          'Target="slides/slide1.xml"/>',
  ].join();
  final parts = <String, String>{
    'ppt/presentation.xml':
        '<?xml version="1.0"?>'
        '<p:presentation xmlns:a="$_a" xmlns:p="$_p" xmlns:r="$_r">'
        '<p:sldSz cx="12192000" cy="6858000"/>'
        '<p:sldIdLst>$sldIds</p:sldIdLst></p:presentation>',
    'ppt/_rels/presentation.xml.rels':
        '<?xml version="1.0"?>'
        '<Relationships xmlns="$_pkg">$rels</Relationships>',
    'ppt/slides/slide1.xml': slide,
  };
  return _zip(parts);
}

const _office = 'urn:oasis:names:tc:opendocument:xmlns:office:1.0';
const _draw = 'urn:oasis:names:tc:opendocument:xmlns:drawing:1.0';

/// Een `.odp` die [n] pagina's declareert.
Uint8List _odpWithPages(int n) {
  final pages = List.filled(n, '<draw:page draw:name="p"/>').join();
  final parts = <String, String>{
    'mimetype': 'application/vnd.oasis.opendocument.presentation',
    'content.xml':
        '<?xml version="1.0"?>'
        '<office:document-content xmlns:office="$_office" xmlns:draw="$_draw">'
        '<office:body><office:presentation>$pages'
        '</office:presentation></office:body></office:document-content>',
  };
  return _zip(parts);
}

/// Een minimaal geldig pptx-omhulsel met alleen de markering — genoeg voor de
/// formaatdetectie; de spy-importer negeert de inhoud.
Uint8List _pptxEnvelope() =>
    _zip({'ppt/presentation.xml': '<p:presentation xmlns:p="$_p"/>'});

Uint8List _zip(Map<String, String> parts) {
  final archive = Archive();
  parts.forEach((name, content) {
    final data = Uint8List.fromList(content.codeUnits);
    archive.addFile(ArchiveFile.bytes(name, data));
  });
  return Uint8List.fromList(ZipEncoder().encode(archive));
}

/// Een importer die onthoudt of hij het al-uitgepakte archief kreeg.
class _SpyImporter extends Importer {
  Archive? receivedPreDecoded;

  @override
  SourceFormat get format => SourceFormat.pptx;

  @override
  String get displayName => 'Spy';

  @override
  Future<Result<ImportFailure, SourceDeck>> importBytes(
    List<int> bytes, {
    String? path,
    void Function(double progress, String message)? onProgress,
    ImportBudget budget = ImportBudget.standard,
    Archive? preDecoded,
  }) async {
    receivedPreDecoded = preDecoded;
    return Ok(const SourceDeck(slides: []));
  }
}
