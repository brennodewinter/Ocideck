import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/models/deck.dart';
import 'package:ocideck/services/import/bulk_import_runner.dart';
import 'package:ocideck/services/web_asset_store.dart';

import 'helpers/pptx_fixture.dart';

/// De wachtrij achter de bulk-import (#772).
///
/// Twee beloftes staan hier op het spel, en beide zijn stil te breken. Eén: een
/// mislukt bestand stopt de rij niet — wie tien presentaties overzet mag niet
/// bij de eerste onleesbare stranden. Twee: geen enkel deck overschrijft een
/// ander, ook niet wanneer twee bronbestanden dezelfde naam dragen of de map al
/// een gelijknamig bestand bevat. Dat tweede is het gevaarlijkste geval van de
/// hele functie: het gaat er niet van stuk, het maakt alleen werk weg.
void main() {
  setUp(WebAssetStore.clear);
  tearDown(WebAssetStore.clear);

  /// Een schrijver die alleen onthoudt waar hij gevraagd werd te schrijven.
  /// Genoeg voor de naamgeving: het echte schrijven zit in `FileService` en
  /// wordt door de dialoogtest hiernaast op een echte map bewezen.
  ({List<String> paths, DeckWriter write}) recorder({Set<String>? failOn}) {
    final paths = <String>[];
    Future<void> write(Deck deck, String path) async {
      if (failOn != null && failOn.contains(path)) {
        throw const FileSystemException('schijf vol');
      }
      paths.add(path);
    }

    return (paths: paths, write: write);
  }

  BulkImportRunner runner(
    DeckWriter write, {
    Set<String> existing = const {},
  }) => BulkImportRunner(writeDeck: write, pathExists: existing.contains);

  test(
    'twee bestanden met dezelfde naam krijgen elk een eigen bestand',
    () async {
      final rec = recorder();
      final summary = await runner(rec.write).run([
        BulkImportItem(bytes: pptxFixture(), name: 'plan.pptx'),
        BulkImportItem(
          bytes: pptxFixture(titel: 'Anders'),
          name: 'plan.pptx',
        ),
      ], targetDirectory: '/uit');

      expect(summary.succeeded, 2);
      expect(rec.paths, ['/uit/plan.md', '/uit/plan-2.md']);
    },
  );

  test(
    'een bestand dat al in de doelmap staat wordt niet overschreven',
    () async {
      final rec = recorder();
      final summary =
          await runner(
            rec.write,
            existing: {'/uit/plan.md', '/uit/plan-2.md'},
          ).run([
            BulkImportItem(bytes: pptxFixture(), name: 'plan.pptx'),
          ], targetDirectory: '/uit');

      expect(summary.succeeded, 1);
      expect(rec.paths, ['/uit/plan-3.md']);
    },
  );

  test('een onleesbaar bestand stopt de rij niet', () async {
    final rec = recorder();
    final summary = await runner(rec.write).run([
      BulkImportItem(bytes: corruptFixture(), name: 'kapot.pptx'),
      BulkImportItem(bytes: pptxFixture(), name: 'goed.pptx'),
    ], targetDirectory: '/uit');

    expect(summary.outcomes, hasLength(2));
    expect(summary.outcomes.first.isSuccess, isFalse);
    expect(summary.outcomes.first.failure, isNotNull);
    expect(summary.outcomes.last.isSuccess, isTrue);
    expect(summary.succeeded, 1);
    expect(summary.failed, 1);
    expect(rec.paths, ['/uit/goed.md']);
  });

  test('een schrijffout landt op dat ene bestand, niet op de rij', () async {
    final rec = recorder(failOn: {'/uit/een.md'});
    final summary = await runner(rec.write).run([
      BulkImportItem(bytes: pptxFixture(), name: 'een.pptx'),
      BulkImportItem(bytes: pptxFixture(), name: 'twee.pptx'),
    ], targetDirectory: '/uit');

    expect(summary.failed, 1);
    expect(summary.succeeded, 1);
    // De schrijffout reist mee als een `other`-fout met de exception in `cause`;
    // de technische message draagt de oorspronkelijke tekst voor het log.
    expect(summary.outcomes.first.failure?.message, contains('schijf vol'));
    expect(summary.outcomes.first.failure?.cause, isNotNull);
    expect(rec.paths, ['/uit/twee.md']);
  });

  test('stoppen laat de rest ongemoeid en telt hem apart', () async {
    final rec = recorder();
    var done = 0;
    final summary = await runner(rec.write).run(
      [
        BulkImportItem(bytes: pptxFixture(), name: 'een.pptx'),
        BulkImportItem(bytes: pptxFixture(), name: 'twee.pptx'),
        BulkImportItem(bytes: pptxFixture(), name: 'drie.pptx'),
      ],
      targetDirectory: '/uit',
      onFileDone: (_) => done++,
      shouldStop: () => done >= 1,
    );

    expect(rec.paths, ['/uit/een.md']);
    expect(summary.outcomes, hasLength(1));
    // Niet-gedaan is iets anders dan mislukt; de samenvatting mag ze niet op
    // één hoop gooien.
    expect(summary.failed, 0);
    expect(summary.notReached, 2);
  });

  test('de voortgang loopt per bestand mee met de rij', () async {
    final rec = recorder();
    final seen = <(int, int)>[];
    await runner(rec.write).run(
      [
        BulkImportItem(bytes: pptxFixture(), name: 'een.pptx'),
        BulkImportItem(bytes: pptxFixture(), name: 'twee.pptx'),
      ],
      targetDirectory: '/uit',
      onProgress: (p) => seen.add((p.index, p.total)),
    );

    expect(seen.first, (0, 2));
    expect(seen.map((e) => e.$1).toSet(), {0, 1});
    expect(seen.every((e) => e.$2 == 2), isTrue);
  });

  test('de samenvatting telt de dia’s die aandacht vragen op', () async {
    final rec = recorder();
    final summary = await runner(rec.write).run([
      BulkImportItem(bytes: pptxFixture(), name: 'een.pptx'),
    ], targetDirectory: '/uit');

    expect(summary.outcomes.single.slideCount, greaterThan(0));
    expect(summary.problemSlides, summary.outcomes.single.problemSlides);
  });

  group('safeDeckFileStem', () {
    test('haalt weg wat geen bestandsnaam mag zijn', () {
      expect(safeDeckFileStem('Plan/../etc'), 'Planetc');
      expect(safeDeckFileStem('Q3 rapport'), 'Q3_rapport');
      expect(safeDeckFileStem('  spaties  rond '), 'spaties_rond');
    });

    test('een leidend streepje of liggend streepje gaat eraf', () {
      expect(safeDeckFileStem('--rf plan'), 'rf_plan');
      expect(safeDeckFileStem('_verborgen'), 'verborgen');
    });

    test('een titel die niets overhoudt valt terug op een naam', () {
      expect(safeDeckFileStem('///'), 'presentatie');
      expect(safeDeckFileStem('', fallback: 'anders'), 'anders');
    });

    test('een titel ter lengte van een alinea wordt gekapt', () {
      final stem = safeDeckFileStem('a' * 400);
      expect(stem.length, 80);
    });
  });

  test('stemOfFileName geeft de naam zonder map en zonder extensie', () {
    expect(stemOfFileName('map/sub/plan.pptx'), 'plan');
    expect(stemOfFileName(r'C:\map\plan.odp'), 'plan');
    expect(stemOfFileName('zonder-extensie'), 'zonder-extensie');
  });
}

/// Een schrijffout zoals `FileService` er een doorgeeft (volle schijf, geen
/// rechten, map ondertussen weg). Eigen klasse zodat de test geen `dart:io`
/// nodig heeft voor één uitzonderingstype.
class FileSystemException implements Exception {
  const FileSystemException(this.message);
  final String message;
  @override
  String toString() => 'FileSystemException: $message';
}
