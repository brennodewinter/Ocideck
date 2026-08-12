import 'dart:async';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/services/import/core/result.dart';
import 'package:ocideck/services/import/importers/import_failure.dart';
import 'package:ocideck/services/import/importers/importer.dart';
import 'package:ocideck/services/import/models/source_deck.dart';
import 'package:ocideck/services/import/models/source_format.dart';
import 'package:ocideck/services/import/models/source_slide.dart';
import 'package:ocideck/services/import/pipeline/import_runner.dart';
import 'package:ocideck/services/import/pipeline/import_task.dart';
import 'package:ocideck/services/import/pipeline/importer_registry.dart';
import 'package:ocideck/services/import/utils/import_budget.dart';

import 'helpers/pptx_fixture.dart';

/// #875 — de import draait buiten de UI-isolate. Deze suite dekt de gedeelde
/// parse-kern (het web-pad), de echte worker-isolate (het desktop-pad), en de
/// annuleer-, deadline- en foutpaden over de isolategrens.
void main() {
  group('parseAndClassify — de gedeelde kern (web-pad)', () {
    test(
      'leest en classificeert een pptx tot een ParsedPresentation',
      () async {
        final result = await runImportTaskInline(
          ImportRequest(
            bytes: pptxFixture(titel: 'Plan'),
            filename: 'plan.pptx',
          ),
        );
        final parsed = (result as ImportTaskParsed).parsed;
        expect(parsed.deck.slides, isNotEmpty);
        expect(parsed.deck.slides.first.title, 'Plan');
        expect(parsed.classified, hasLength(parsed.deck.slides.length));
      },
    );

    test('een beschadigd archief wordt een corrupt-fout', () async {
      // Een echte zip-kop maar geen leesbaar archief: de kern moet de échte
      // reden geven, niet "geen dia's".
      final result = await runImportTaskInline(
        ImportRequest(bytes: _zipHeaderThenGarbage(), filename: 'stuk.pptx'),
      );
      final failure = (result as ImportTaskFailed).failure;
      expect(failure.reason, ImportFailureReason.corrupt);
      expect(failure.args['bestand'], 'stuk.pptx');
    });

    test('een niet-zip wordt notAPresentation', () async {
      final result = await runImportTaskInline(
        ImportRequest(bytes: corruptFixture(), filename: 'raar.pptx'),
      );
      final failure = (result as ImportTaskFailed).failure;
      expect(failure.reason, ImportFailureReason.notAPresentation);
    });

    test('de cause wordt gesaneerd: geen brontekst in de foutmelding', () {
      // Een FormatException plakt de ontlede bron in toString() — die bron kan
      // persoonsgegevens bevatten. _transportSafe moet die bron strippen voordat
      // de cause de isolate-grens passeert en in de UI landt.
      final sensitive = 'Geheime data van Jan Jansen';
      final failure = ImportTaskFailed(
        ImportFailure(
          'test',
          cause: FormatException('syntax error', sensitive),
        ),
      ).failure;
      expect(failure.cause, isNot(contains(sensitive)));
      expect(failure.cause, contains('FormatException'));
    });
  });

  group('runImportTask — de worker-isolate (desktop-pad)', () {
    test('parseert op een aparte isolate en levert het deck terug', () async {
      final result = await runImportTask(
        ImportRequest(
          bytes: pptxFixture(titel: 'Op afstand'),
          filename: 'x.pptx',
        ),
      );
      final parsed = (result as ImportTaskParsed).parsed;
      expect(parsed.deck.slides, isNotEmpty);
      expect(parsed.deck.slides.first.title, 'Op afstand');
    });

    test('voortgang komt geordend en oplopend binnen', () async {
      final fractions = <double>[];
      final result = await runImportTask(
        ImportRequest(bytes: pptxFixture(), filename: 'x.pptx'),
        onProgress: (p) => fractions.add(p.fraction),
      );
      expect(result, isA<ImportTaskParsed>());
      expect(fractions, isNotEmpty);
      for (var i = 1; i < fractions.length; i++) {
        expect(
          fractions[i],
          greaterThanOrEqualTo(fractions[i - 1]),
          reason: 'voortgang mag niet terugspringen',
        );
      }
      expect(fractions.last, lessThanOrEqualTo(1.0));
    });

    test('de hoofd-isolate blijft vrij tijdens het parsen', () async {
      // Het bewijs dat het werk écht van de UI-isolate af is: een periodieke
      // timer op de hoofd-isolate blijft tikken terwijl een deck met veel dia's
      // op de worker geparseerd wordt. Draaide het parsen synchroon op de
      // hoofd-isolate, dan zou de timer verhongeren en op nul blijven.
      var ticks = 0;
      final timer = Timer.periodic(const Duration(milliseconds: 1), (_) {
        ticks++;
      });
      final result = await runImportTask(
        ImportRequest(bytes: _pptxWithSlides(300), filename: 'groot.pptx'),
      );
      timer.cancel();
      final parsed = (result as ImportTaskParsed).parsed;
      expect(parsed.deck.slides, hasLength(300));
      expect(ticks, greaterThan(0));
    });

    test('een fout reist ongeschonden over de isolategrens', () async {
      final result = await runImportTask(
        ImportRequest(bytes: corruptFixture(), filename: 'raar.pptx'),
      );
      final failure = (result as ImportTaskFailed).failure;
      expect(failure.reason, ImportFailureReason.notAPresentation);
      expect(failure.args['bestand'], 'raar.pptx');
    });
  });

  group('annulering', () {
    test('coöperatief: een vlag die mid-parse omgaat stopt vóór de '
        'classificatie', () async {
      // De nep-importer zet het annuleervlag terwijl hij "parseert"; de kern
      // moet dat bij de eerstvolgende werkeenheid zien en stoppen — niets
      // geclassificeerd, niets half af.
      var cancelled = false;
      final result = await parseAndClassify(
        ImportRequest(bytes: pptxFixture(), filename: 'x.pptx'),
        registry: ImporterRegistry(
          importers: [
            _CannedImporter(
              const SourceDeck(
                slides: [
                  SourceSlide(index: 0, title: 'A'),
                  SourceSlide(index: 1),
                ],
              ),
              onParse: () => cancelled = true,
            ),
          ],
        ),
        report: (_) {},
        isCancelled: () => cancelled,
      );
      expect(result, isA<ImportTaskCancelled>());
    });

    test(
      'een vooraf geannuleerde token stopt de worker-isolate meteen',
      () async {
        final cancel = ImportCancelToken()..cancel();
        final result = await runImportTask(
          ImportRequest(bytes: _pptxWithSlides(300), filename: 'groot.pptx'),
          cancel: cancel,
        );
        // Geannuleerd, en dus zonder data — er is niets gebouwd.
        expect(result, isA<ImportTaskCancelled>());
      },
    );
  });

  group('deadline', () {
    test(
      'een overschreden tijdbudget eindigt als tooLarge met de tijdlabel',
      () async {
        final result = await runImportTaskInline(
          ImportRequest(
            bytes: pptxFixture(),
            filename: 'traag.pptx',
            budget: ImportBudget.forTest(maxDuration: Duration.zero),
          ),
        );
        final failure = (result as ImportTaskFailed).failure;
        expect(failure.reason, ImportFailureReason.tooLarge);
        expect(failure.args['limiet'], contains('verwerkingstijd'));
      },
    );
  });

  group('transport', () {
    test('een niet-verzendbare cause wordt tot een string gesaneerd', () {
      final failed = ImportTaskFailed(
        ImportFailure('kapot', cause: const FormatException('boem')),
      );
      expect(failed.failure.cause, isA<String>());
      expect(failed.failure.reason, ImportFailureReason.other);
    });
  });
}

/// Een importer die een vast [SourceDeck] teruggeeft en, vlak vóór het
/// teruggeven, [onParse] aanroept — waarmee een test een annulering "tijdens het
/// parsen" kan naspelen.
class _CannedImporter extends Importer {
  _CannedImporter(this._deck, {this.onParse});

  final SourceDeck _deck;
  final void Function()? onParse;

  @override
  SourceFormat get format => SourceFormat.pptx;

  @override
  String get displayName => 'Canned';

  @override
  Future<Result<ImportFailure, SourceDeck>> importBytes(
    List<int> bytes, {
    String? path,
    void Function(double progress, String message)? onProgress,
    ImportBudget budget = ImportBudget.standard,
    Archive? preDecoded,
  }) async {
    onParse?.call();
    return Ok(_deck);
  }
}

/// Een zip-kop gevolgd door rommel: leest als een archief-magie maar pakt niet
/// uit — het corrupt-pad.
Uint8List _zipHeaderThenGarbage() =>
    Uint8List.fromList([0x50, 0x4B, 0x03, 0x04, ...List.filled(64, 0x00)]);

const _p = 'http://schemas.openxmlformats.org/presentationml/2006/main';
const _a = 'http://schemas.openxmlformats.org/drawingml/2006/main';
const _r =
    'http://schemas.openxmlformats.org/officeDocument/2006/relationships';
const _pkg = 'http://schemas.openxmlformats.org/package/2006/relationships';

/// Een `.pptx` die [n] dia's declareert (alle wijzend naar dezelfde diapart) —
/// genoeg parswerk om aan te tonen dat de hoofd-isolate vrij blijft.
Uint8List _pptxWithSlides(int n) {
  const slide =
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
      '<Relationship Id="rId$i" Type="$_r/slide" Target="slides/slide1.xml"/>',
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
  final archive = Archive();
  parts.forEach((name, content) {
    archive.addFile(ArchiveFile.bytes(name, utf8Bytes(content)));
  });
  return Uint8List.fromList(ZipEncoder().encode(archive));
}

/// UTF-8-bytes zonder een `dart:convert`-import in de testkop.
List<int> utf8Bytes(String s) => Uint8List.fromList(s.codeUnits);
