import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/models/slide.dart';
import 'package:ocideck/services/import/core/result.dart';
import 'package:ocideck/services/import/importers/import_failure.dart';
import 'package:ocideck/services/import/importers/importer.dart';
import 'package:ocideck/services/import/models/body_block.dart';
import 'package:ocideck/services/import/models/source_deck.dart';
import 'package:ocideck/services/import/models/source_format.dart';
import 'package:ocideck/services/import/models/source_slide.dart';
import 'package:ocideck/services/import/pipeline/importer_registry.dart';
import 'package:ocideck/services/import/presentation_import_service.dart';
import 'package:ocideck/services/web_asset_store.dart';

/// A stand-in importer that returns a canned [SourceDeck], so the service's
/// orchestration can be tested without a real archive parser. Detection keys on
/// the `.pptx` extension, so a non-zip payload still routes here.
class _FakeImporter extends Importer {
  _FakeImporter(this._deck, {this.failure});

  final SourceDeck _deck;
  final ImportFailure? failure;

  @override
  SourceFormat get format => SourceFormat.pptx;

  @override
  String get displayName => 'Fake PPTX';

  @override
  Future<Result<ImportFailure, SourceDeck>> importBytes(
    List<int> bytes, {
    String? path,
    void Function(double progress, String message)? onProgress,
  }) async {
    final f = failure;
    return f != null ? Err(f) : Ok(_deck);
  }
}

PresentationImportService _serviceFor(
  SourceDeck deck, {
  ImportFailure? failure,
}) => PresentationImportService(
  registry: ImporterRegistry(
    importers: [_FakeImporter(deck, failure: failure)],
  ),
);

/// Een minimaal geldig pptx-omhulsel.
///
/// De service valideert tegenwoordig eerst of dit überhaupt een leesbaar
/// zip-archief is (een beschadigd bestand las anders als "geen dia's
/// gevonden"). De fake importer negeert de bytes; het omhulsel is er alleen
/// zodat de validatie de invoer terecht doorlaat.
Uint8List _pptxEnvelope() {
  final archive = Archive();
  final data = utf8.encode('<p:presentation/>');
  archive.addFile(ArchiveFile('ppt/presentation.xml', data.length, data));
  return Uint8List.fromList(ZipEncoder().encode(archive));
}

void main() {
  setUp(WebAssetStore.clear);
  tearDown(WebAssetStore.clear);

  test('an unsupported (but recognised) format fails cleanly', () async {
    // Only the fake pptx importer is registered; an .odp routes to no importer.
    final service = _serviceFor(const SourceDeck(slides: []));
    final result = await service.importBytes(
      Uint8List.fromList([1, 2, 3, 4]),
      filename: 'deck.odp',
    );
    expect(result.isSuccess, isFalse);
    expect(result.deck, isNull);
    expect(result.failure!.message, contains('odp'));
  });

  test('an unknown file is rejected before any parsing is attempted', () async {
    // Rommel haalt de integriteitscontrole niet: de gebruiker hoort dat zijn
    // bestand onleesbaar is, niet dat er "geen dia's" in zaten.
    final service = _serviceFor(const SourceDeck(slides: []));
    final result = await service.importBytes(
      Uint8List.fromList([1, 2, 3, 4]),
      filename: 'notes.txt',
    );
    expect(result.isSuccess, isFalse);
    expect(result.failure!.message, contains('geen geldig zip-archief'));
  });

  test('een geldig archief zonder presentatiemarkering wordt geweigerd', () {
    // Wél een zip, maar geen pptx/odp/key erin: ook dat mag niet stil als een
    // lege presentatie eindigen.
    final archive = Archive();
    final data = utf8.encode('hoi');
    archive.addFile(ArchiveFile('readme.txt', data.length, data));
    final bytes = Uint8List.fromList(ZipEncoder().encode(archive));
    final service = _serviceFor(const SourceDeck(slides: []));
    return service.importBytes(bytes, filename: 'raar.zip').then((result) {
      expect(result.isSuccess, isFalse);
      expect(result.failure!.message, contains('zip-archief'));
    });
  });

  test(
    'a successful import builds a deck and reports progress to 1.0',
    () async {
      final source = SourceDeck(
        title: 'Bronrapport',
        slides: [
          const SourceSlide(index: 0, title: 'Titel'),
          SourceSlide(
            index: 1,
            title: 'Punten',
            bodyBlocks: [
              const BodyBlock(kind: BodyBlockKind.bullet, text: 'een'),
            ],
          ),
        ],
      );
      var lastProgress = 0.0;
      final result = await _serviceFor(source).importBytes(
        _pptxEnvelope(),
        filename: 'demo.pptx',
        onProgress: (p, _) => lastProgress = p,
      );
      expect(result.isSuccess, isTrue);
      expect(result.deck!.title, 'Bronrapport');
      expect(result.deck!.slides.first.type, SlideType.title);
      expect(result.deck!.slides[1].type, SlideType.bullets);
      expect(lastProgress, 1.0);
    },
  );

  test(
    'the deck title falls back to the filename stem when the source is untitled',
    () async {
      final result = await _serviceFor(
        const SourceDeck(slides: [SourceSlide(index: 0, title: 'X')]),
      ).importBytes(_pptxEnvelope(), filename: 'road/Q3-cijfers.pptx');
      expect(result.deck!.title, 'Q3-cijfers');
    },
  );

  test('an importer failure is surfaced as the result failure', () async {
    final service = _serviceFor(
      const SourceDeck(slides: []),
      failure: const ImportFailure('kapot archief'),
    );
    final result = await service.importBytes(
      _pptxEnvelope(),
      filename: 'demo.pptx',
    );
    expect(result.isSuccess, isFalse);
    expect(result.failure!.message, 'kapot archief');
  });

  test('problem slides propagate from the builder', () async {
    final source = SourceDeck(
      slides: [
        SourceSlide(
          index: 0,
          title: 'Met audio',
          bodyBlocks: [const BodyBlock(kind: BodyBlockKind.bullet, text: 'x')],
          audioFileName: 'a.mp3',
        ),
      ],
    );
    final result = await _serviceFor(
      source,
    ).importBytes(_pptxEnvelope(), filename: 'demo.pptx');
    expect(result.isSuccess, isTrue);
    expect(result.problemSlides, isNotEmpty);
    expect(result.problemSlides.single.sourceSlideNumber, 1);
  });
}
