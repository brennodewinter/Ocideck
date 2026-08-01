import 'dart:typed_data';

import '../../models/deck.dart';
import '../markdown_safety.dart';
import '../markdown_service.dart';
import '../web_asset_store.dart';
import 'deck_builder.dart';
import 'importers/import_failure.dart';
import 'models/source_deck.dart';
import 'models/slide_failure_policy.dart';
import 'pipeline/import_runner.dart';
import 'pipeline/import_task.dart';
import 'pipeline/importer_registry.dart';
import 'pipeline/problem_slide.dart';
import 'pipeline/slide_classifier.dart';
import 'utils/import_budget.dart';

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
  }) : failure = null,
       wasCancelled = false;

  const PresentationImportResult.failed(this.failure)
    : deck = null,
      problemSlides = const [],
      wasCancelled = false;

  /// De gebruiker heeft de import gestopt. Geen deck, geen fout — niets is half
  /// af, want de deckbouw begint pas ná een geslaagde parse (#875).
  const PresentationImportResult.cancelled()
    : deck = null,
      problemSlides = const [],
      failure = null,
      wasCancelled = true;

  final Deck? deck;
  final List<ProblemSlide> problemSlides;
  final ImportFailure? failure;
  final bool wasCancelled;

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
  ///
  /// De definitieve serialisatie gaat nog eens door de fail-closed
  /// [MarkdownSafetyScanner] — dezelfde poort die een vreemd `.md` bij het openen
  /// bewaakt (#876). De uitkomst reist mee in [BuiltDeck.safetyFindings]; is die
  /// niet leeg, dan hoort de aanroeper het deck te weigeren.
  BuiltDeck build({Map<int, SlideFailurePolicy> policies = const {}}) {
    final built = _builder.build(
      _sourceDeck,
      _classified,
      title: _title,
      policies: policies,
    );
    return BuiltDeck(
      deck: built.deck,
      problemSlides: built.problemSlides,
      safetyFindings: scanDeckForUnsafeContent(built.deck),
    );
  }
}

/// Genereer de definitieve Markdown van [deck] en scan hem met de fail-closed
/// [MarkdownSafetyScanner] — dezelfde poort die het openen van een vreemd `.md`
/// bewaakt. Leeg betekent veilig (#876). De importbouw neutraliseert brontekst
/// al aan de bron; dit is het vangnet dat bewijst dat de definitieve uitvoer
/// geen uitvoerbare inhoud draagt, en dat een opgeslagen import dus bij het
/// heropenen niet door diezelfde poort wordt tegengehouden.
List<MarkdownSafetyFinding> scanDeckForUnsafeContent(Deck deck) =>
    MarkdownSafetyScanner.scan(MarkdownService().generateDeck(deck));

/// De uitkomst van het voorbereiden: precies één van geslaagd, mislukt of
/// geannuleerd.
class PreparedImportResult {
  const PreparedImportResult.success(this.prepared)
    : failure = null,
      wasCancelled = false;
  const PreparedImportResult.failed(this.failure)
    : prepared = null,
      wasCancelled = false;

  /// De gebruiker heeft het lezen gestopt vóór het deck er was (#875).
  const PreparedImportResult.cancelled()
    : prepared = null,
      failure = null,
      wasCancelled = true;

  final PreparedImport? prepared;
  final ImportFailure? failure;
  final bool wasCancelled;

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
  /// Zonder [registry] gaat het zware parsen naar het platform-uitvoeringspad
  /// ([runImportTask]): een worker-isolate op desktop, in-process op web. Wórdt
  /// er een registry geïnjecteerd (tests, met nep-importers), dan draait het
  /// bewust in-process met díe registry — nep-importers zijn niet gegarandeerd
  /// verzendbaar over de isolategrens (#875).
  PresentationImportService({
    ImporterRegistry? registry,
    DeckBuilder? builder,
    this._budget = ImportBudget.standard,
  }) : _builder = builder ?? DeckBuilder(),
       _runTask = registry == null
           ? runImportTask
           : ((request, {onProgress, cancel}) => runImportTaskInline(
               request,
               registry: registry,
               onProgress: onProgress,
               cancel: cancel,
             ));

  final DeckBuilder _builder;
  final ImportTaskRunner _runTask;

  /// Het resourcebudget dat elke import begrenst (#874). Standaard
  /// [ImportBudget.standard]; een test geeft een piepklein budget mee om een
  /// overschrijdingspad te raken.
  final ImportBudget _budget;

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
    ImportCancelToken? cancel,
  }) async {
    final prep = await prepare(
      bytes,
      filename: filename,
      onProgress: onProgress,
      cancel: cancel,
    );
    if (prep.wasCancelled) return const PresentationImportResult.cancelled();
    final prepared = prep.prepared;
    if (prepared == null) {
      return PresentationImportResult.failed(prep.failure!);
    }
    final BuiltDeck built;
    try {
      built = prepared.build(policies: policies);
    } on WebAssetBudgetExceeded catch (e) {
      return PresentationImportResult.failed(
        ImportFailure(
          'Webgeheugen vol tijdens import van $filename.',
          cause: e,
          reason: ImportFailureReason.memoryBudgetExceeded,
          args: {'bestand': filename},
        ),
      );
    }
    if (built.safetyFindings.isNotEmpty) {
      return PresentationImportResult.failed(
        ImportFailure(
          '$filename bevat uitvoerbare inhoud en is niet geïmporteerd.',
          reason: ImportFailureReason.unsafeContent,
          args: {'bestand': filename},
        ),
      );
    }
    onProgress?.call(1.0, 'Klaar.');
    return PresentationImportResult.success(
      built.deck,
      problemSlides: built.problemSlides,
    );
  }

  /// Lees en classificeer, maar bouw nog niet — zodat de aanroeper eerst kan
  /// vragen wat er met de probleemdia's moet gebeuren.
  ///
  /// Het zware werk (uitpakken, valideren, parsen, classificeren) gaat via
  /// [_runTask] naar het worker-uitvoeringspad; hier op de hoofd-isolate blijft
  /// alleen de lichte deckanalyse over, want die raakt de procesglobale
  /// `WebAssetStore` en de l10n-`translate`-closure (#875). [cancel] stopt het
  /// lezen onderweg; dan komt er een [PreparedImportResult.cancelled].
  Future<PreparedImportResult> prepare(
    Uint8List bytes, {
    required String filename,
    void Function(double progress, String message)? onProgress,
    ImportCancelToken? cancel,
  }) async {
    final task = await _runTask(
      ImportRequest(bytes: bytes, filename: filename, budget: _budget),
      onProgress: onProgress == null
          ? null
          : (p) => onProgress(p.fraction, p.message),
      cancel: cancel,
    );

    switch (task) {
      case ImportTaskCancelled():
        return const PreparedImportResult.cancelled();
      case ImportTaskFailed(:final failure):
        // De worker vult de bestandsnaam al aan; geen tweede keer nodig.
        return PreparedImportResult.failed(failure);
      case ImportTaskParsed(:final parsed):
        onProgress?.call(0.94, 'Deck opbouwen…');
        final sourceDeck = parsed.deck;
        return PreparedImportResult.success(
          PreparedImport(
            _builder.analyse(parsed.classified),
            sourceDeck,
            parsed.classified,
            sourceDeck.title.isNotEmpty ? sourceDeck.title : _stemOf(filename),
            _builder,
          ),
        );
    }
  }

  /// The filename without its directory or extension — the deck-title fallback
  /// when the source declares no title. Path-separator-safe without `dart:io`.
  String _stemOf(String filename) {
    final base = filename.split(RegExp(r'[\\/]')).last;
    final dot = base.lastIndexOf('.');
    return dot > 0 ? base.substring(0, dot) : base;
  }
}
