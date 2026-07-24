import 'dart:typed_data';

import '../../models/deck.dart';
import 'core/result.dart';
import 'deck_builder.dart';
import 'importers/import_failure.dart';
import 'models/source_deck.dart';
import 'models/slide_failure_policy.dart';
import 'models/source_format.dart';
import 'pipeline/problem_slide.dart';
import 'pipeline/slide_classifier.dart';
import 'pipeline/format_detector.dart';
import 'pipeline/importer_registry.dart';
import 'utils/archive_utils.dart';

/// The result of importing one presentation file.
///
/// Exactly one of [deck] or [failure] is set. On success [deck] is a ready
/// OciDeck [Deck] (the caller serialises it via `FileService.saveDeck`) and
/// [problemSlides] lists the source slides that carried real, non-salvaged loss
/// so the UI can offer a per-slide decision. On failure [failure] explains why,
/// with a message the UI can show.
class PresentationImportResult {
  const PresentationImportResult.success(
    this.deck, {
    this.problemSlides = const [],
  }) : failure = null;

  const PresentationImportResult.failed(this.failure)
    : deck = null,
      problemSlides = const [];

  final Deck? deck;
  final List<ProblemSlide> problemSlides;
  final ImportFailure? failure;

  bool get isSuccess => deck != null;
}

/// Een gelezen en geclassificeerde presentatie die nog gebouwd moet worden.
///
/// Bestaat omdat het beslismoment ertússen valt: de gebruiker kiest wát er met
/// een probleemdia gebeurt vóórdat die dia er is. Zonder deze tussenstand zou
/// de vraag stellen betekenen dat je het bestand twee keer parseert — en een
/// Keynote van vijftig dia's parseer je niet twee keer om één vraag.
///
/// [problemSlides] is de analyse: de dia's met écht verlies, met per dia een
/// voorstel. [build] maakt er het deck van, met het beleid dat de gebruiker
/// koos (of het standaardbeleid als hij niets koos).
class PreparedImport {
  /// Positioneel en privé: een benoemde parameter kan in Dart niet met een
  /// underscore beginnen, en de vier dragers zijn interne staat. Er is precies
  /// één aanroeper ([PresentationImportService.prepare]), dus de volgorde is
  /// daar te overzien.
  PreparedImport(
    this.problemSlides,
    this._sourceDeck,
    this._classified,
    this._title,
    this._builder,
  );

  /// De dia's met écht verlies, waarover iets te beslissen valt.
  final List<ProblemSlide> problemSlides;

  final SourceDeck _sourceDeck;
  final List<ClassifiedSlide> _classified;
  final String _title;
  final DeckBuilder _builder;

  /// Bouw het deck. [policies] is per bron-diaindex; wat er niet in staat
  /// krijgt best-effort.
  BuiltDeck build({Map<int, SlideFailurePolicy> policies = const {}}) =>
      _builder.build(
        _sourceDeck,
        _classified,
        title: _title,
        policies: policies,
      );
}

/// De uitkomst van het voorbereiden: precies één van [prepared] of [failure].
class PreparedImportResult {
  const PreparedImportResult.success(this.prepared) : failure = null;
  const PreparedImportResult.failed(this.failure) : prepared = null;

  final PreparedImport? prepared;
  final ImportFailure? failure;

  bool get isSuccess => prepared != null;
}

/// Orchestrates a single presentation import end-to-end, on bytes only (no
/// `dart:io`), so it runs unchanged on web and desktop.
///
/// Steps: cap the input size, detect the format, look up the importer (a clear
/// failure when the format is not supported yet), parse to a `SourceDeck`,
/// classify every slide, then hand the whole to [DeckBuilder] which produces the
/// real OciDeck [Deck]. Nothing is written to disk here — materialising the
/// slide images happens later, on save (see [DeckBuilder]).
class PresentationImportService {
  PresentationImportService({ImporterRegistry? registry, DeckBuilder? builder})
    : _registry = registry ?? ImporterRegistry(),
      _builder = builder ?? DeckBuilder();

  final ImporterRegistry _registry;
  final DeckBuilder _builder;

  /// Import [bytes] (the raw file) named [filename] en bouw het deck in één
  /// stap. [onProgress] krijgt een 0..1-breuk plus een korte statusmelding.
  ///
  /// De gemaksroute voor wie niets te vragen heeft: de bulk-wachtrij, en de
  /// tests. Wie de gebruiker wél wil laten kiezen gebruikt [prepare], stelt de
  /// vraag, en roept daarna `PreparedImport.build` met het gekozen beleid.
  Future<PresentationImportResult> importBytes(
    Uint8List bytes, {
    required String filename,
    void Function(double progress, String message)? onProgress,
    Map<int, SlideFailurePolicy> policies = const {},
  }) async {
    final prep = await prepare(
      bytes,
      filename: filename,
      onProgress: onProgress,
    );
    final prepared = prep.prepared;
    if (prepared == null) {
      return PresentationImportResult.failed(prep.failure!);
    }
    final built = prepared.build(policies: policies);
    onProgress?.call(1.0, 'Klaar.');
    return PresentationImportResult.success(
      built.deck,
      problemSlides: built.problemSlides,
    );
  }

  /// Lees en classificeer, maar bouw nog niet — zodat de aanroeper eerst kan
  /// vragen wat er met de probleemdia's moet gebeuren.
  Future<PreparedImportResult> prepare(
    Uint8List bytes, {
    required String filename,
    void Function(double progress, String message)? onProgress,
  }) async {
    onProgress?.call(0.02, 'Formaat herkennen…');
    if (bytes.length > maxArchiveInputSize) {
      return PreparedImportResult.failed(
        ImportFailure(
          '$filename is groter dan '
          '${maxArchiveInputSize ~/ (1024 * 1024 * 1024)} GiB en wordt niet '
          'verwerkt.',
        ),
      );
    }

    // Validéren, niet alleen herkennen: de integriteitsuitkomst zegt of dit
    // überhaupt een leesbaar archief is. Die weggooien en toch gaan parsen
    // leverde bij een beschadigd bestand de melding "geen dia's gevonden" op —
    // niet te onderscheiden van een lege presentatie.
    final validation = validateFormatFromBytes(bytes, basename: filename);
    if (!validation.isValid) {
      return PreparedImportResult.failed(
        ImportFailure('$filename: ${validation.error}'),
      );
    }
    final format = validation.format;
    final importer = _registry.importerFor(format);
    if (importer == null) {
      return PreparedImportResult.failed(
        ImportFailure(
          format == SourceFormat.unknown
              ? '$filename: dit bestand is geen herkende presentatie '
                    '(pptx/odp/key).'
              : '$filename: het ${format.name}-formaat wordt nog niet '
                    'ondersteund.',
        ),
      );
    }

    final imported = await importer.importBytes(
      bytes,
      path: filename,
      onProgress: (f, m) => onProgress?.call(0.05 + 0.80 * f, m),
    );
    final SourceDeck sourceDeck;
    switch (imported) {
      case Err(:final f):
        return PreparedImportResult.failed(f);
      case Ok(:final v):
        sourceDeck = v;
    }

    onProgress?.call(0.88, 'Slides classificeren…');
    final classified = [
      for (final slide in sourceDeck.slides) classifySlide(slide),
    ];

    onProgress?.call(0.94, 'Deck opbouwen…');
    return PreparedImportResult.success(
      PreparedImport(
        _builder.analyse(classified),
        sourceDeck,
        classified,
        sourceDeck.title.isNotEmpty ? sourceDeck.title : _stemOf(filename),
        _builder,
      ),
    );
  }

  /// The filename without its directory or extension — the deck-title fallback
  /// when the source declares no title. Path-separator-safe without `dart:io`.
  String _stemOf(String filename) {
    final base = filename.split(RegExp(r'[\\/]')).last;
    final dot = base.lastIndexOf('.');
    return dot > 0 ? base.substring(0, dot) : base;
  }
}
