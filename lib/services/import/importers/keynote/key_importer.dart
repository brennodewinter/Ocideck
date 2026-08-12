import 'dart:typed_data';

import 'package:archive/archive.dart';

import '../../core/result.dart';
import '../../models/body_block.dart';
import '../../models/conversion_issue.dart';
import '../../models/source_format.dart';
import '../../models/source_deck.dart';
import '../../models/source_image.dart';
import '../../models/source_slide.dart';
import '../../utils/archive_utils.dart';
import '../../utils/import_budget.dart';
import '../../../../utils/log.dart';
import '../import_failure.dart';
import '../importer.dart';
import 'iwa/iwa_archive.dart';
import 'iwa/iwa_document.dart';
import 'iwa/proto_wire.dart';
import 'iwa/slide_reconstructor.dart';
import 'iwa/snappy.dart';
import 'key_context.dart';
import 'key_plist.dart';
import 'key_text_salvage.dart';

/// Imports an Apple Keynote (`.key`) presentation.
///
/// Keynote's real content (slides, text, shapes, layout) is encoded as
/// Snappy-compressed IWA protobuf messages under `Index/`. Full schema-based
/// reconstruction (which needs Apple's runtime `TSPRegistry` typeId map) is a
/// later step; this importer salvages what is available now:
/// - `preview.jpg` — a rendered image of the first slide, emitted as a single
///   large-image OciDeck slide.
/// - **IWA text salvage** — every `Index/*.iwa` is Snappy-decompressed and
///   walked for UTF-8 text fields; the recovered words/phrases become a
///   "Geredde tekst" bullet slide (best-effort, noisy but lossless-ish).
/// - Deck title/author from `Metadata/Properties.plist` when it is an XML
///   plist (the pipeline falls back to the file name otherwise).
///
/// Because layout, tables, charts, media, and slide order are still locked in
/// the unparsed IWA schema, a deck-wide [ConversionIssue] is recorded so the
/// writer appends an honest "Niet overgenomen van dit document" note slide.
class KeyImporter extends Importer {
  KeyImporter({KeyTextSalvage? textSalvage})
    : textSalvage = textSalvage ?? KeyTextSalvage();

  final KeyTextSalvage textSalvage;

  @override
  SourceFormat get format => SourceFormat.key;

  @override
  String get displayName => 'Apple Keynote (.key)';

  @override
  Future<Result<ImportFailure, SourceDeck>> importBytes(
    List<int> bytes, {
    String? path,
    void Function(double progress, String message)? onProgress,
    ImportBudget budget = ImportBudget.standard,
    Archive? preDecoded,
  }) async {
    if (preDecoded == null && !_looksLikeZip(bytes)) {
      // Zonder deze controle zou een niet-zip stilletjes doorlopen naar "geen
      // voorbeeldafbeelding en geen IWA-tekst gevonden": `ZipDecoder` geeft
      // sinds archive 4 een léég archief terug in plaats van te struikelen, en
      // een leeg archief is niet te onderscheiden van een `.key` waar niets
      // in zit. De gebruiker verdient de echte reden.
      logError(
        'KeyImporter: ${path ?? 'bestand'} begint niet met de zip-magie',
        const FormatException('geen zip-archief'),
      );
      return const Err(
        ImportFailure(
          'Kon het .key niet lezen: dit bestand is geen zip-archief.',
          reason: ImportFailureReason.notAPresentation,
          args: {'formaat': 'key'},
        ),
      );
    }
    // Houd bij welke stap loopt, zodat een onverwachte uitzondering in de
    // foutmelding kan zeggen wáár het misging — zonder dit is "Kon het .key
    // niet lezen" een raadsel voor de gebruiker en voor ons.
    var step = 'archief uitpakken';
    try {
      final archive = preDecoded ?? safeDecodeZip(bytes, budget: budget);
      final ctx = KeyContext(archive);

      step = 'voorbeeldafbeelding zoeken';
      onProgress?.call(0.2, 'Voorbeeldafbeelding zoeken…');
      final preview = _readPreview(ctx);

      step = 'IWA-objecten inlezen';
      onProgress?.call(0.4, 'IWA-objecten inlezen…');
      final doc = _loadDocument(ctx, budget);

      // Preferred path: schema-aware reconstruction (real slide text, ordered).
      step = 'slides reconstrueren';
      onProgress?.call(0.6, 'Slides reconstrueren…');
      final reconstructor = doc == null
          ? null
          : SlideReconstructor(doc, ctx: ctx);
      final reconstructed =
          reconstructor?.reconstruct() ?? const <SourceSlide>[];
      if (reconstructed.length > budget.maxSlides) {
        throw ImportBudgetException('${budget.maxSlides} dia\'s');
      }

      final slides = <SourceSlide>[];
      var schemaBased = false;
      var fallbackTextFound = false;
      if (reconstructed.isNotEmpty) {
        schemaBased = true;
        slides.addAll(reconstructed);
      } else {
        // Fallback: noisy UTF-8 text salvage + the preview render.
        step = 'IWA-tekst salvage';
        onProgress?.call(0.6, 'IWA-tekst salvage…');
        final salvagedText = textSalvage.salvage(ctx, budget: budget);
        fallbackTextFound = salvagedText.isNotEmpty;
        if (preview != null) {
          slides.add(
            SourceSlide(index: 0, title: 'Voorbeeld', images: [preview]),
          );
        }
        if (salvagedText.isNotEmpty) {
          slides.add(
            SourceSlide(
              index: slides.length,
              title: 'Geredde tekst',
              bodyBlocks: [
                for (var i = 0; i < salvagedText.length; i++)
                  BodyBlock(
                    kind: BodyBlockKind.bullet,
                    text: salvagedText[i],
                    level: 0,
                    order: i,
                  ),
              ],
            ),
          );
        }
      }

      if (slides.isEmpty) {
        // Geen preview én geen tekst: zeg wát er wel in het archief zat, zodat
        // de gebruiker (en wij) kunnen zien of het een nieuw Keynote-formaat
        // is, een leeg bestand, of iets anders.
        return Err(
          ImportFailure(
            'Geen voorbeeldafbeelding en geen IWA-tekst gevonden — dit .key '
            'kan (nog) niet worden geconverteerd. ${_archiveSummary(ctx)}',
            reason: ImportFailureReason.unreadable,
            args: {'formaat': 'key'},
          ),
        );
      }

      onProgress?.call(0.85, 'Metadata uitlezen…');
      final meta = deckMetadataFromPlist(ctx);

      final reconstructorIssues =
          reconstructor?.issues ?? const <ConversionIssue>[];
      return Ok(
        SourceDeck(
          slides: slides,
          title: meta.title,
          author: meta.author,
          issues: [
            _iwaIssue(
              slideCount: _iwaSlideCount(ctx),
              schemaBased: schemaBased,
              previewSalvaged: !schemaBased && preview != null,
              textSalvaged: !schemaBased && fallbackTextFound,
            ),
            ...reconstructorIssues,
          ],
        ),
      );
    } on ImportBudgetException catch (e) {
      logError(
        'KeyImporter: ${path ?? 'bestand'} overschrijdt het importbudget '
        '(${e.limitLabel})',
        e,
      );
      return Err(
        ImportFailure(
          'De presentatie overschrijdt de importlimiet (${e.limitLabel}).',
          cause: e,
          reason: ImportFailureReason.tooLarge,
          args: {'formaat': 'key', 'limiet': e.limitLabel},
        ),
      );
    } on Exception catch (e) {
      logError('KeyImporter failed for ${path ?? 'bestand'} (stap: $step)', e);
      return Err(
        ImportFailure(
          'Kon het .key niet lezen (stap: $step).',
          cause: e,
          reason: ImportFailureReason.unreadable,
          args: const {'formaat': 'key'},
        ),
      );
    }
  }

  /// De zip local-file-header-magie (`PK\x03\x04`) waarmee elk `.key` begint.
  bool _looksLikeZip(List<int> bytes) =>
      bytes.length >= 4 &&
      bytes[0] == 0x50 &&
      bytes[1] == 0x4B &&
      bytes[2] == 0x03 &&
      bytes[3] == 0x04;

  /// Een korte samenvatting van wat er in het archief zat, voor de
  /// diagnostische foutmelding wanneer noch preview noch IWA-tekst werd gevonden.
  /// Vertelt de gebruiker (en ons) of het een nieuw formaat is, een leeg
  /// bestand, of iets anders — zonder de bestandsinhoud zelf te onthullen.
  String _archiveSummary(KeyContext ctx) {
    final names = ctx.entryNames;
    final iwaCount = names
        .where((n) => n.startsWith('Index/') && n.endsWith('.iwa'))
        .length;
    final hasPreview = names.any((n) => n.toLowerCase().startsWith('preview'));
    final hasMetadata = names.any((n) => n.startsWith('Metadata/'));
    return 'Archief: ${names.length} bestanden, $iwaCount IWA-bestanden, '
        'preview: ${hasPreview ? 'ja' : 'nee'}, '
        'metadata: ${hasMetadata ? 'ja' : 'nee'}.';
  }

  /// Decompress and parse every `Index/*.iwa` into a single [IwaDocument].
  /// Returns `null` when no IWA parts could be parsed.
  ///
  /// [budget] caps each Snappy stream and the total number of IWA objects: the
  /// `objects` map grows with the source, so a crafted archive could otherwise
  /// drive it without bound. The object-count check sits outside the per-part
  /// `try` on purpose — inside it, the `on Object` clause would swallow the
  /// [ImportBudgetException] and keep going.
  IwaDocument? _loadDocument(KeyContext ctx, ImportBudget budget) {
    final snappy = SnappyDecompressor(budget: budget);
    final wire = ProtoWire();
    final archive = IwaArchive(wire);
    final objects = <int, IwaObject>{};
    for (final name in ctx.entryNames) {
      if (!name.startsWith('Index/') || !name.endsWith('.iwa')) continue;
      final bytes = ctx.readPartBytes(name);
      if (bytes == null) continue;
      try {
        final decompressed = snappy.decompressIwaStream(bytes);
        objects.addAll(archive.parse(decompressed));
      } on Object catch (e) {
        logError('KeyImporter: kon $name niet decoderen', e);
        continue;
      }
      if (objects.length > budget.maxIwaObjects) {
        throw ImportBudgetException('${budget.maxIwaObjects} IWA-objecten');
      }
    }
    if (objects.isEmpty) return null;
    return IwaDocument(objects);
  }

  /// Read `preview.jpg` (falling back to any root `preview*.jpg`/`*.png`) into
  /// a [SourceImage]; `null` when no preview is present.
  SourceImage? _readPreview(KeyContext ctx) {
    const preferred = ['preview.jpg', 'preview.png'];
    for (final name in preferred) {
      final bytes = ctx.readPartBytes(name);
      if (bytes != null) {
        return _image(name, bytes);
      }
    }
    for (final name in ctx.entryNames) {
      final lower = name.toLowerCase();
      if (!lower.contains('/') &&
          lower.startsWith('preview') &&
          (lower.endsWith('.jpg') || lower.endsWith('.png'))) {
        final bytes = ctx.readPartBytes(name);
        if (bytes != null) return _image(name, bytes);
      }
    }
    return null;
  }

  SourceImage _image(String name, List<int> bytes) => SourceImage(
    bytes: Uint8List.fromList(bytes),
    ext: _ext(name),
    name: name,
  );

  /// A rough upper bound on the slide count: the number of `Index/*.iwa`
  /// entries minus the non-slide ones (document, masters, touchups). Used only
  /// for the loss note wording; never affects the output slides.
  int _iwaSlideCount(KeyContext ctx) {
    final iwa = ctx.entryNames
        .where((n) => n.startsWith('Index/') && n.endsWith('.iwa'))
        .toList();
    if (iwa.length <= 2) return 0;
    return iwa.length - 2;
  }

  String _ext(String name) {
    final dot = name.lastIndexOf('.');
    if (dot < 0) return 'jpg';
    final ext = name.substring(dot + 1).toLowerCase();
    return ext.isEmpty ? 'jpg' : ext;
  }

  ConversionIssue _iwaIssue({
    required int slideCount,
    required bool schemaBased,
    required bool previewSalvaged,
    required bool textSalvaged,
  }) {
    if (schemaBased) {
      // Zeg wat er écht gebeurt. Deze tekst stond te beweren dat tabellen,
      // grafieken en media niet overkwamen, terwijl de SlideReconstructor ze
      // via de Table-/Chart-/MediaReconstructor wel degelijk invult. Een
      // notitiedia die de gebruiker een verlies meldt dat er niet is, is
      // erger dan geen notitie: hij laat hem zoeken naar iets wat er staat.
      return const ConversionIssue(
        slideIndex: -1,
        feature: 'Keynote IWA-intern',
        description:
            'IWA-structuur gedeeltelijk geparseerd — de vormgeving (thema, '
            'kleuren, posities) is niet overgenomen; tekst, slide-volgorde, '
            'notities en, waar de structuren herkend werden, tabellen, '
            'grafieken en media wel',
        salvagedAs:
            'tekst, volgorde, notities en herkende tabellen, grafieken en media',
      );
    }
    // Eén vaste sleutel per combinatie, niet `bits.join(' + ')`: een
    // samengestelde string is per taal onvindbaar, en de notitie wordt vertaald
    // opgeslagen (#806). Drie combinaties zijn zinvol; geen enkele is null.
    final salvaged = switch ((previewSalvaged, textSalvaged)) {
      (true, true) => 'voorbeeldafbeelding en tekst',
      (true, false) => 'voorbeeldafbeelding',
      (false, true) => 'tekst',
      (false, false) => null,
    };
    return ConversionIssue(
      slideIndex: -1,
      feature: 'Keynote IWA-intern (~{n} dia’s)',
      description:
          'IWA-structuur niet volledig geparseerd — opmaak, tabellen, '
          'grafieken, media en slide-volgorde niet overgenomen',
      salvagedAs: salvaged,
      args: {'n': '$slideCount'},
    );
  }
}
