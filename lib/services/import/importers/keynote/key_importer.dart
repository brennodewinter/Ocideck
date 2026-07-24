import 'dart:typed_data';

import '../../core/result.dart';
import '../../models/body_block.dart';
import '../../models/conversion_issue.dart';
import '../../models/source_format.dart';
import '../../models/source_deck.dart';
import '../../models/source_image.dart';
import '../../models/source_slide.dart';
import '../../utils/archive_utils.dart';
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
  }) async {
    if (!_looksLikeZip(bytes)) {
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
        ),
      );
    }
    try {
      final archive = safeDecodeZip(bytes);
      final ctx = KeyContext(archive);

      onProgress?.call(0.2, 'Voorbeeldafbeelding zoeken…');
      final preview = _readPreview(ctx);

      onProgress?.call(0.4, 'IWA-objecten inlezen…');
      final doc = _loadDocument(ctx);

      // Preferred path: schema-aware reconstruction (real slide text, ordered).
      onProgress?.call(0.6, 'Slides reconstrueren…');
      final reconstructor = doc == null
          ? null
          : SlideReconstructor(doc, ctx: ctx);
      final reconstructed =
          reconstructor?.reconstruct() ?? const <SourceSlide>[];

      final slides = <SourceSlide>[];
      var schemaBased = false;
      var fallbackTextFound = false;
      if (reconstructed.isNotEmpty) {
        schemaBased = true;
        slides.addAll(reconstructed);
      } else {
        // Fallback: noisy UTF-8 text salvage + the preview render.
        onProgress?.call(0.6, 'IWA-tekst salvage…');
        final salvagedText = textSalvage.salvage(ctx);
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
        return const Err(
          ImportFailure(
            'Geen voorbeeldafbeelding en geen IWA-tekst gevonden — dit .key '
            'kan (nog) niet worden geconverteerd.',
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
    } on Exception catch (e) {
      logError('KeyImporter failed for ${path ?? 'bestand'}', e);
      return Err(ImportFailure('Kon het .key niet lezen.', cause: e));
    }
  }

  /// De zip local-file-header-magie (`PK\x03\x04`) waarmee elk `.key` begint.
  bool _looksLikeZip(List<int> bytes) =>
      bytes.length >= 4 &&
      bytes[0] == 0x50 &&
      bytes[1] == 0x4B &&
      bytes[2] == 0x03 &&
      bytes[3] == 0x04;

  /// Decompress and parse every `Index/*.iwa` into a single [IwaDocument].
  /// Returns `null` when no IWA parts could be parsed.
  IwaDocument? _loadDocument(KeyContext ctx) {
    final snappy = SnappyDecompressor();
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
      return const ConversionIssue(
        slideIndex: -1,
        feature: 'Keynote IWA-intern',
        description:
            'IWA-structuur gedeeltelijk geparseerd — opmaak, tabellen, '
            'grafieken en media niet overgenomen; tekst, slide-volgorde en '
            'notities wel gereconstrueerd',
        salvagedAs: 'tekst, volgorde en notities per dia',
      );
    }
    final salvagedBits = <String>[
      if (previewSalvaged) 'voorbeeldafbeelding',
      if (textSalvaged) 'tekst',
    ];
    return ConversionIssue(
      slideIndex: -1,
      feature: 'Keynote IWA-intern (~$slideCount dia\'s)',
      description:
          'IWA-structuur niet volledig geparseerd — opmaak, tabellen, '
          'grafieken, media en slide-volgorde niet overgenomen',
      salvagedAs: salvagedBits.isEmpty ? null : salvagedBits.join(' + '),
    );
  }
}
