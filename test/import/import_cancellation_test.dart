import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/services/import/bulk_import_runner.dart';
import 'package:ocideck/services/import/core/result.dart';
import 'package:ocideck/services/import/importers/import_failure.dart';
import 'package:ocideck/services/import/importers/importer.dart';
import 'package:ocideck/services/import/models/source_deck.dart';
import 'package:ocideck/services/import/models/source_format.dart';
import 'package:ocideck/services/import/pipeline/import_task.dart';
import 'package:ocideck/services/import/pipeline/importer_registry.dart';
import 'package:ocideck/services/import/presentation_import_service.dart';
import 'package:ocideck/services/import/utils/import_budget.dart';

import 'helpers/pptx_fixture.dart';

/// #875 — annuleren stopt het werk en schrijft géén gedeeltelijke uitvoer.
void main() {
  test('een vooraf geannuleerde import levert een geannuleerde uitkomst zonder '
      'deck', () async {
    final cancel = ImportCancelToken()..cancel();
    final result = await PresentationImportService().importBytes(
      pptxFixture(),
      filename: 'x.pptx',
      cancel: cancel,
    );
    expect(result.wasCancelled, isTrue);
    expect(result.isSuccess, isFalse);
    expect(result.deck, isNull);
  });

  test(
    'de bulk-rij stopt vóór het eerste bestand als de token al af is',
    () async {
      final writes = <String>[];
      final runner = BulkImportRunner(
        writeDeck: (deck, path) async => writes.add(path),
        pathExists: (_) => false,
      );
      final cancel = ImportCancelToken()..cancel();
      final summary = await runner.run(
        [
          BulkImportItem(bytes: pptxFixture(), name: 'a.pptx'),
          BulkImportItem(bytes: pptxFixture(), name: 'b.pptx'),
        ],
        targetDirectory: '/tmp/doel',
        cancel: cancel,
      );
      expect(summary.outcomes, isEmpty);
      expect(summary.notReached, 2);
      expect(writes, isEmpty, reason: 'geannuleerd = niets weggeschreven');
    },
  );

  test('midden in het eerste bestand geannuleerd: niets weggeschreven, de rij '
      'stopt', () async {
    final cancel = ImportCancelToken();
    final writes = <String>[];
    // De nep-importer cancelt de token terwijl hij "parseert"; de kern ziet dat
    // ná de parse en geeft een geannuleerde uitkomst terug — vóór er iets
    // gebouwd of geschreven wordt.
    final runner = BulkImportRunner(
      writeDeck: (deck, path) async => writes.add(path),
      pathExists: (_) => false,
      service: PresentationImportService(
        registry: ImporterRegistry(
          importers: [_CancelDuringParseImporter(cancel)],
        ),
      ),
    );
    final summary = await runner.run(
      [
        BulkImportItem(bytes: pptxFixture(), name: 'a.pptx'),
        BulkImportItem(bytes: pptxFixture(), name: 'b.pptx'),
      ],
      targetDirectory: '/tmp/doel',
      cancel: cancel,
    );
    expect(writes, isEmpty);
    expect(summary.outcomes, isEmpty);
    expect(summary.notReached, 2);
  });
}

/// Een importer die de meegegeven [cancel]-token afgaat terwijl hij "parseert",
/// zodat de gedeelde kern de annulering bij de eerstvolgende werkeenheid ziet.
class _CancelDuringParseImporter extends Importer {
  _CancelDuringParseImporter(this._cancel);

  final ImportCancelToken _cancel;

  @override
  SourceFormat get format => SourceFormat.pptx;

  @override
  String get displayName => 'Cancel-during-parse';

  @override
  Future<Result<ImportFailure, SourceDeck>> importBytes(
    List<int> bytes, {
    String? path,
    void Function(double progress, String message)? onProgress,
    ImportBudget budget = ImportBudget.standard,
    Archive? preDecoded,
  }) async {
    _cancel.cancel();
    return const Ok(SourceDeck(slides: []));
  }
}
