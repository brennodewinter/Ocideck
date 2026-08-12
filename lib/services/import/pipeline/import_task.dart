/// Het serialiseerbare opdracht-/resultaat-/voortgangscontract voor de
/// presentatie-import, plus de gedeelde parse-kern die het draait (#875).
///
/// De import splitst op één grens. Het zware, CPU- en geheugenintensieve deel —
/// uitpakken, valideren, parsen (XML/IWA/Snappy), reconstrueren en classificeren
/// — draait via [parseAndClassify] op een worker-isolate (desktop) of in-process
/// met yields (web); zie `import_runner.dart`. Het lichte deel — het bouwen van
/// het echte OciDeck-[Deck] — blijft op de hoofd-isolate, want dat raakt de
/// procesglobale `WebAssetStore` en de l10n-`translate`-closure, en geen van
/// beide reist over een isolategrens.
///
/// Wat wél reist, doet dat als platte data: [ImportRequest] naar binnen,
/// [ImportTaskResult] naar buiten. Dart kopieert die objecten over de poort;
/// alleen [ImportFailure.cause] kan een niet-verzendbare exception dragen, dus
/// die wordt bij het verpakken tot een string gesaneerd — hij dient toch alleen
/// het log.
library;

import 'dart:async';
import 'dart:typed_data';

import 'package:archive/archive.dart';

import '../core/result.dart';
import '../importers/import_failure.dart';
import '../models/source_deck.dart';
import '../models/source_format.dart';
import '../utils/archive_utils.dart';
import '../utils/import_budget.dart';
import '../../../utils/log.dart';
import 'format_detector.dart';
import 'importer_registry.dart';
import 'slide_classifier.dart';

/// Draait één [ImportRequest] naar een [ImportTaskResult] — het naadtype tussen
/// de service, de platform-runner en de testhaak.
typedef ImportTaskRunner =
    Future<ImportTaskResult> Function(
      ImportRequest request, {
      void Function(ImportProgress progress)? onProgress,
      ImportCancelToken? cancel,
    });

/// De opdracht: de ruwe bytes, de naam waaronder ze gekozen zijn, en het
/// resourcebudget dat elke grens (geheugen, iteraties, tijd) begrenst.
class ImportRequest {
  const ImportRequest({
    required this.bytes,
    required this.filename,
    this.budget = ImportBudget.standard,
  });

  final Uint8List bytes;
  final String filename;
  final ImportBudget budget;
}

/// Eén voortgangsstap: een 0..1-breuk plus een korte statusmelding.
///
/// [message] is de ruwe Nederlandse sleutel; de UI doet er `l10n.d(message)`
/// omheen. Zo blijft de kern vrij van een `BuildContext` en toch vertaalbaar.
class ImportProgress {
  const ImportProgress(this.fraction, this.message);

  final double fraction;
  final String message;
}

/// De geslaagde uitkomst van de parse-kern: een gelezen bronpresentatie plus
/// de per-dia-classificatie, klaar om op de hoofd-isolate tot een deck te
/// bouwen.
class ParsedPresentation {
  const ParsedPresentation(this.deck, this.classified);

  final SourceDeck deck;
  final List<ClassifiedSlide> classified;
}

/// De uitkomst van één importtaak: precies één van geslaagd, mislukt of
/// geannuleerd. Een `sealed` type zodat de aanroeper alle drie de gevallen moet
/// afhandelen — geen stille vierde toestand.
sealed class ImportTaskResult {
  const ImportTaskResult();
}

/// Geslaagd: de gelezen en geclassificeerde presentatie.
final class ImportTaskParsed extends ImportTaskResult {
  const ImportTaskParsed(this.parsed);

  final ParsedPresentation parsed;
}

/// Mislukt: waaróm, als een [ImportFailure] die de UI naar een vertaalde
/// melding omzet. De [cause] is bij het bouwen tot een string gesaneerd zodat
/// de fout gegarandeerd over een isolategrens reist.
final class ImportTaskFailed extends ImportTaskResult {
  ImportTaskFailed(ImportFailure failure) : failure = _transportSafe(failure);

  final ImportFailure failure;
}

/// Geannuleerd: de aanroeper heeft het werk gestopt. Draagt geen data — er is
/// bewust niets half af (de deckbouw begint pas ná een geslaagde parse).
final class ImportTaskCancelled extends ImportTaskResult {
  const ImportTaskCancelled();
}

/// Een failure waarvan de [ImportFailure.cause] gegarandeerd verzendbaar is:
/// een gevangen exception kan van alles zijn, dus we bewaren alleen zijn
/// tekst — gesaneerd via [sanitizeError], zodat een `FormatException` niet
/// per ongeluk de brontekst (en daarmee persoonsgegevens uit een dia-veld)
/// meeneemt over de isolategrens en in de UI landt. De reden en de args —
/// waar de UI-melding op steunt — blijven intact.
ImportFailure _transportSafe(ImportFailure f) => f.cause == null
    ? f
    : ImportFailure(
        f.message,
        cause: sanitizeError(f.cause!).toString(),
        reason: f.reason,
        args: f.args,
      );

/// Een coöperatief annuleersignaal voor de in-process (web) route, en de trigger
/// waarop de isolate-route de worker beëindigt.
///
/// Bewust geen deel van [ImportBudget]: dat budget is const en wordt over de
/// isolategrens gekopieerd, en een gekopieerd vlag zou de worker nooit bereiken.
/// De token leeft daarom op de hoofd-isolate; de runner vertaalt hem naar de
/// juiste daad per platform (zie `import_runner_io.dart` / `_web.dart`).
class ImportCancelToken {
  final Completer<void> _completer = Completer<void>();

  /// Of er om annulering is gevraagd.
  bool get isCancelled => _completer.isCompleted;

  /// Voltooit zodra er geannuleerd is; de isolate-runner racet hierop om de
  /// worker te beëindigen.
  Future<void> get whenCancelled => _completer.future;

  /// Vraag annulering. Idempotent: een tweede aanroep doet niets.
  void cancel() {
    if (!_completer.isCompleted) _completer.complete();
  }
}

/// Hoe vaak de classificatielus de event-loop een beurt geeft. Elke dia een
/// yield is nodeloos veel `await`s voor een deck van tweeduizend dia's; elke
/// [_yieldEvery] dia's is genoeg om op web een annuleertik en een herteken te
/// verwerken zonder merkbare overhead.
const int _yieldEvery = 16;

/// Geef de event-loop één beurt. Op web laat dit een annuleertik en een
/// voortgangsherteken door; in een worker-isolate is het een goedkope niets.
Future<void> _yield() => Future<void>.delayed(Duration.zero);

/// Lees, valideer, parse en classificeer [request] — de gedeelde parse-kern.
///
/// Dit is de body van de oude `PresentationImportService.prepare`-stappen 1–3,
/// uitgetild zodat hij op een worker-isolate (desktop) én in-process (web) kan
/// draaien. Hij raakt geen `dart:io`, geen Flutter-bindings en geen procesglobale
/// staat, dus hij is zowel verzendbaar-veilig als web-veilig.
///
/// [report] krijgt elke voortgangsstap; [isCancelled] wordt coöperatief
/// afgetoetst bij elke begrensde werkeenheid. Bij een geraakte annulering of een
/// overschreden tijddeadline eindigt de kern netjes met [ImportTaskCancelled]
/// respectievelijk een [ImportTaskFailed] — nooit half.
Future<ImportTaskResult> parseAndClassify(
  ImportRequest request, {
  ImporterRegistry? registry,
  required void Function(ImportProgress progress) report,
  required bool Function() isCancelled,
}) async {
  final reg = registry ?? ImporterRegistry();
  final budget = request.budget;
  final filename = request.filename;
  final clock = Stopwatch()..start();

  bool overDeadline() => clock.elapsed > budget.maxDuration;
  ImportTaskResult deadlineFailure() => ImportTaskFailed(
    ImportFailure(
      '$filename overschrijdt de importlimiet (${budget.durationLabel}).',
      reason: ImportFailureReason.tooLarge,
      args: {'bestand': filename, 'limiet': budget.durationLabel},
    ),
  );

  if (isCancelled()) return const ImportTaskCancelled();
  report(const ImportProgress(0.02, 'Formaat herkennen…'));
  await _yield();

  // Decodeer het archief één keer. Zowel de formaatvalidatie als de importer
  // werken daarna op ditzelfde [Archive]; zo wordt hetzelfde bestand nooit
  // tweemaal uitgepakt (#874). Elke budgetoverschrijding eindigt hier
  // gecontroleerd, vóórdat er iets zwaars gebeurt.
  final Archive archive;
  try {
    archive = safeDecodeZip(request.bytes, budget: budget);
  } on ImportBudgetException catch (e) {
    return ImportTaskFailed(
      ImportFailure(
        '$filename overschrijdt de importlimiet (${e.limitLabel}).',
        reason: ImportFailureReason.tooLarge,
        args: {'bestand': filename, 'limiet': e.limitLabel},
      ),
    );
  } on FormatException {
    // Geen zip-magie: dit is geen presentatie (en niet: beschadigd).
    return ImportTaskFailed(
      ImportFailure(
        '$filename: dit bestand is geen geldig zip-archief (pptx/odp/key).',
        reason: ImportFailureReason.notAPresentation,
        args: {'bestand': filename},
      ),
    );
  } on Exception catch (e) {
    // Wel een zip-kop, maar het uitpakken struikelt: beschadigd archief.
    return ImportTaskFailed(
      ImportFailure(
        '$filename lijkt beschadigd: het archief kan niet worden uitgepakt.',
        cause: e,
        reason: ImportFailureReason.corrupt,
        args: {'bestand': filename},
      ),
    );
  }

  if (isCancelled()) return const ImportTaskCancelled();
  if (overDeadline()) return deadlineFailure();

  final validation = validateFormatFromArchive(archive, basename: filename);
  if (!validation.isValid) {
    return ImportTaskFailed(
      ImportFailure(
        '$filename: ${validation.error}',
        reason: validation.reason ?? ImportFailureReason.notAPresentation,
        args: {'bestand': filename},
      ),
    );
  }
  final format = validation.format;
  final importer = reg.importerFor(format);
  if (importer == null) {
    return ImportTaskFailed(
      format == SourceFormat.unknown
          ? ImportFailure(
              '$filename: dit bestand is geen herkende presentatie '
              '(pptx/odp/key).',
              reason: ImportFailureReason.notAPresentation,
              args: {'bestand': filename},
            )
          : ImportFailure(
              '$filename: het ${format.name}-formaat wordt nog niet '
              'ondersteund.',
              reason: ImportFailureReason.formatNotSupported,
              args: {'bestand': filename, 'formaat': format.name},
            ),
    );
  }

  if (isCancelled()) return const ImportTaskCancelled();
  await _yield();

  final imported = await importer.importBytes(
    request.bytes,
    path: filename,
    budget: budget,
    preDecoded: archive,
    onProgress: (f, m) => report(ImportProgress(0.05 + 0.80 * f, m)),
  );
  final SourceDeck sourceDeck;
  switch (imported) {
    case Err(:final f):
      // De importer kent de bestandsnaam niet altijd; de service wel. Vul hem
      // aan zodat de melding "Kon {bestand} niet lezen" compleet is.
      return ImportTaskFailed(f.withArg('bestand', filename));
    case Ok(:final v):
      sourceDeck = v;
  }

  if (isCancelled()) return const ImportTaskCancelled();
  if (overDeadline()) return deadlineFailure();

  report(const ImportProgress(0.88, 'Slides classificeren…'));
  final classified = <ClassifiedSlide>[];
  for (var i = 0; i < sourceDeck.slides.length; i++) {
    if (isCancelled()) return const ImportTaskCancelled();
    if (overDeadline()) return deadlineFailure();
    classified.add(classifySlide(sourceDeck.slides[i]));
    if (i % _yieldEvery == _yieldEvery - 1) await _yield();
  }

  return ImportTaskParsed(ParsedPresentation(sourceDeck, classified));
}

/// Draai [parseAndClassify] gewoon hier, op de aanroepende isolate.
///
/// Dit is zowel de web-route (er is geen tweede isolate in een browser) als de
/// route die de service kiest wanneer een test een eigen [ImporterRegistry] met
/// nep-importers injecteert — die importers zijn niet gegarandeerd verzendbaar,
/// dus ze mogen de isolategrens niet over. De coöperatieve [cancel]-token en de
/// yields in de kern geven de event-loop tussen de werkeenheden een beurt.
Future<ImportTaskResult> runImportTaskInline(
  ImportRequest request, {
  ImporterRegistry? registry,
  void Function(ImportProgress progress)? onProgress,
  ImportCancelToken? cancel,
}) => parseAndClassify(
  request,
  registry: registry,
  report: (p) => onProgress?.call(p),
  isCancelled: () => cancel?.isCancelled ?? false,
);
