import 'dart:typed_data';

import 'package:path/path.dart' as p;

import '../../models/deck.dart';
import 'presentation_import_service.dart';

/// Eén bestand in de importwachtrij: de bytes plus de naam waaronder de
/// gebruiker het koos. Bewust dezelfde vorm als de enkelvoudige import — de
/// wachtrij voegt volgorde toe, geen ander materiaal.
class BulkImportItem {
  const BulkImportItem({required this.bytes, required this.name});

  final Uint8List bytes;
  final String name;
}

/// Wat er van één bestand terechtkwam. Precies één van [savedPath] en [error]
/// is gevuld: een import die stil half slaagt is erger dan een die faalt, en
/// deze klasse maakt dat onmogelijk om te vergeten.
class BulkImportOutcome {
  const BulkImportOutcome.saved(
    this.sourceName, {
    required this.savedPath,
    required this.slideCount,
    required this.problemSlides,
  }) : error = null;

  const BulkImportOutcome.failed(this.sourceName, {required this.error})
    : savedPath = null,
      slideCount = 0,
      problemSlides = 0;

  final String sourceName;

  /// Het geschreven `.md`-bestand, of null wanneer dit bestand mislukte.
  final String? savedPath;
  final int slideCount;

  /// Hoeveel dia's van dit bestand echt verlies opliepen en dus aandacht
  /// vragen — hetzelfde getal dat de enkelvoudige import in de melding zet.
  final int problemSlides;

  /// De reden van mislukken, in de bewoording van de importdienst.
  final String? error;

  bool get isSuccess => savedPath != null;
}

/// De uitkomst van de hele rij, in de volgorde waarin hij verwerkt is.
class BulkImportSummary {
  const BulkImportSummary({
    required this.outcomes,
    required this.targetDirectory,
    required this.notReached,
  });

  final List<BulkImportOutcome> outcomes;
  final String targetDirectory;

  /// Bestanden die niet meer aan de beurt kwamen doordat de gebruiker stopte.
  /// Apart van [failed]: niet-gedaan is iets anders dan mislukt.
  final int notReached;

  int get succeeded => outcomes.where((o) => o.isSuccess).length;
  int get failed => outcomes.where((o) => !o.isSuccess).length;
  int get problemSlides => outcomes.fold(0, (sum, o) => sum + o.problemSlides);
}

/// Waar de rij op dit moment staat. [fileProgress] is de voortgang binnen het
/// huidige bestand (0..1); [index] is 0-gebaseerd.
class BulkImportProgress {
  const BulkImportProgress({
    required this.index,
    required this.total,
    required this.name,
    required this.fileProgress,
    required this.message,
  });

  final int index;
  final int total;
  final String name;
  final double fileProgress;
  final String message;
}

/// Het wegschrijven van één omgezet deck. Een naad, geen gemak: de wachtrij
/// zelf blijft daardoor vrij van `dart:io` — net als de rest van
/// `lib/services/import/` — en de aanroeper (de dialoog) levert
/// `FileService.saveDeck` aan.
typedef DeckWriter = Future<void> Function(Deck deck, String filePath);

/// Of er op dit pad al iets staat. Zelfde reden als [DeckWriter]: het
/// bestandssysteem hoort niet in deze laag thuis, maar botsingsvrij benoemen
/// wél — dat is de regel die getoetst moet kunnen worden.
typedef PathExistsProbe = bool Function(String path);

/// Bestandsnaam-veilige stam voor een deck, dezelfde sanering als
/// `FileService.saveDeckAsDetailed` gebruikt voor de voorinvulling: alles wat
/// geen letter, cijfer, spatie of koppelteken is gaat eruit, spaties worden
/// liggende streepjes.
///
/// Twee dingen bovenop die sanering, omdat de naam hier niet langs een
/// systeemvenster komt maar rechtstreeks een pad wordt: een leidend `-` of `_`
/// gaat weg (een naam die als optievlag of verborgen bestand leest), en de
/// lengte wordt gekapt — een titel uit een vreemde presentatie kan een hele
/// alinea zijn en sommige bestandssystemen kappen dan zelf, halverwege.
String safeDeckFileStem(String title, {String fallback = 'presentatie'}) {
  final cleaned = title
      .trim()
      .replaceAll(RegExp(r'[^\w\s-]'), '')
      .replaceAll(RegExp(r'\s+'), '_')
      .replaceAll(RegExp(r'^[_-]+'), '');
  final capped = cleaned.length > 80 ? cleaned.substring(0, 80) : cleaned;
  return capped.isEmpty ? fallback : capped;
}

/// Verwerkt een rij presentatiebestanden één voor één: omzetten via
/// [PresentationImportService] en het resultaat als eigen `.md` in de doelmap
/// wegschrijven.
///
/// Twee regels maken de rij bruikbaar in plaats van broos. Eén mislukt bestand
/// stopt de rij niet — de fout wordt vastgelegd en de volgende gaat door, want
/// bij tien bestanden is stoppen bij de eerste onleesbare het slechtste
/// antwoord. En elk deck krijgt een botsingsvrije naam: twee bronbestanden met
/// dezelfde titel (of een naam die al in de map staat) mogen elkaar nooit
/// overschrijven, ook niet wanneer de gebruiker dezelfde map twee keer kiest.
class BulkImportRunner {
  BulkImportRunner({
    required this.writeDeck,
    required this.pathExists,
    PresentationImportService? service,
  }) : _service = service ?? PresentationImportService();

  final DeckWriter writeDeck;
  final PathExistsProbe pathExists;
  final PresentationImportService _service;

  /// Verwerk [items] in deze volgorde naar [targetDirectory].
  ///
  /// [shouldStop] wordt vóór elk bestand gevraagd; wie stopt, stopt tussen twee
  /// bestanden — nooit halverwege een schrijfactie, want een half geschreven
  /// projectmap is geen uitkomst die iemand kan gebruiken.
  Future<BulkImportSummary> run(
    List<BulkImportItem> items, {
    required String targetDirectory,
    void Function(BulkImportProgress progress)? onProgress,
    void Function(BulkImportOutcome outcome)? onFileDone,
    bool Function()? shouldStop,
  }) async {
    final outcomes = <BulkImportOutcome>[];
    // De namen die deze ronde zelf al uitgedeeld heeft. Het bestand bestaat pas
    // ná het schrijven, dus zonder dit boekhoudinkje zouden twee gelijk
    // genoemde bronbestanden allebei dezelfde vrije naam krijgen.
    final claimed = <String>{};
    for (var i = 0; i < items.length; i++) {
      if (shouldStop?.call() ?? false) break;
      final item = items[i];
      void report(double fraction, String message) => onProgress?.call(
        BulkImportProgress(
          index: i,
          total: items.length,
          name: item.name,
          fileProgress: fraction,
          message: message,
        ),
      );
      report(0, '');
      final outcome = await _importOne(
        item,
        targetDirectory: targetDirectory,
        claimed: claimed,
        report: report,
      );
      outcomes.add(outcome);
      onFileDone?.call(outcome);
    }
    return BulkImportSummary(
      outcomes: outcomes,
      targetDirectory: targetDirectory,
      notReached: items.length - outcomes.length,
    );
  }

  Future<BulkImportOutcome> _importOne(
    BulkImportItem item, {
    required String targetDirectory,
    required Set<String> claimed,
    required void Function(double, String) report,
  }) async {
    try {
      final result = await _service.importBytes(
        item.bytes,
        filename: item.name,
        onProgress: report,
      );
      final deck = result.deck;
      if (deck == null) {
        return BulkImportOutcome.failed(
          item.name,
          error: result.failure?.message ?? item.name,
        );
      }
      final path = _allocatePath(
        targetDirectory,
        deck.title.isNotEmpty ? deck.title : stemOfFileName(item.name),
        claimed,
      );
      await writeDeck(deck, path);
      return BulkImportOutcome.saved(
        item.name,
        savedPath: path,
        slideCount: deck.slides.length,
        problemSlides: result.problemSlides.length,
      );
    } catch (e) {
      // Ook een schrijffout (volle schijf, geen rechten, map ondertussen weg)
      // hoort hier te landen: de rij loopt door, en de gebruiker leest per
      // bestand wat er misging in plaats van één algemene mislukking.
      return BulkImportOutcome.failed(item.name, error: '$e');
    }
  }

  /// Een vrij pad voor deze deck-titel. Botst de naam met een bestand in de map
  /// of met een naam die deze ronde al uitgedeeld is, dan komt er `-2`, `-3`, …
  /// achter. Bewust een koppelteken en geen ` (2)` zoals bij de importmappen:
  /// de saneerder haalt haakjes juist wég uit een naam, en die er daarna weer
  /// in zetten leest als een tweede regel.
  String _allocatePath(String directory, String title, Set<String> claimed) {
    final base = safeDeckFileStem(title);
    var candidate = base;
    var next = 2;
    while (claimed.contains(candidate.toLowerCase()) ||
        pathExists(p.join(directory, '$candidate.md'))) {
      candidate = '$base-$next';
      next++;
    }
    claimed.add(candidate.toLowerCase());
    return p.join(directory, '$candidate.md');
  }
}

/// De bestandsnaam zonder map of extensie — de terugval voor een deck dat zelf
/// geen titel meebrengt. Padscheiding-veilig zonder `dart:io`.
String stemOfFileName(String filename) {
  final base = filename.split(RegExp(r'[\\/]')).last;
  final dot = base.lastIndexOf('.');
  return dot > 0 ? base.substring(0, dot) : base;
}
