import 'dart:async';
import 'dart:isolate';

import '../importers/import_failure.dart';
import 'import_task.dart';

/// Desktop/mobiel uitvoeringspad voor één importtaak: op een worker-isolate
/// (#875).
///
/// Het zware parsen draait op een aparte isolate, zodat de UI-isolate vrij
/// blijft om frames te tekenen en invoer te verwerken. Voortgang en het
/// eindresultaat reizen als platte data over één [ReceivePort] terug (FIFO, dus
/// geordend). Precies één uitkomst: een latch laat de eerste van {resultaat,
/// annulering, workerfout} winnen en negeert wat daarna nog binnenkomt.
///
/// **Annuleren = de worker doden.** Dat is onmiddellijk en veilig: de worker
/// bezit geen bestand, socket of ander extern middel, en er is niets half af —
/// de deckbouw begint pas ná deze taak, op de hoofd-isolate. Coöperatief
/// signaleren zou de worker niet mid-parse bereiken (het parsen van één
/// werkeenheid geeft de event-loop geen beurt), dus doden is hier zowel sterker
/// als eenvoudiger.
Future<ImportTaskResult> runImportTask(
  ImportRequest request, {
  void Function(ImportProgress progress)? onProgress,
  ImportCancelToken? cancel,
}) async {
  final receive = ReceivePort();
  final result = Completer<ImportTaskResult>();

  // Latch: precies één uitkomst.
  void settle(ImportTaskResult r) {
    if (!result.isCompleted) result.complete(r);
  }

  final Isolate isolate;
  try {
    isolate = await Isolate.spawn(
      _worker,
      _WorkerConfig(request, receive.sendPort),
      onError: receive.sendPort,
      errorsAreFatal: true,
      debugName: 'presentation-import',
    );
  } on Object catch (e) {
    receive.close();
    return ImportTaskFailed(
      ImportFailure(
        'Kon de importtaak niet starten: $e',
        cause: e,
        reason: ImportFailureReason.other,
      ),
    );
  }

  receive.listen((Object? message) {
    switch (message) {
      case ImportProgress():
        onProgress?.call(message);
      case ImportTaskResult():
        settle(message);
      case List():
        // De onError-payload is [fout, stacktrace]: de worker is onverwacht
        // gestopt. Behandel als een leesfout in plaats van de UI te laten hangen.
        settle(
          ImportTaskFailed(
            ImportFailure(
              'De importtaak is onverwacht gestopt: ${message.first}',
              reason: ImportFailureReason.other,
            ),
          ),
        );
    }
  });

  // Annuleren: zodra de token afgaat, laat de latch de annulering winnen. De
  // worker wordt hieronder gedood zodra we de uitkomst hebben.
  unawaited(
    cancel?.whenCancelled.then((_) => settle(const ImportTaskCancelled())),
  );

  final outcome = await result.future;
  isolate.kill(priority: Isolate.immediate);
  receive.close();
  return outcome;
}

/// De verzendbare opdracht voor de worker: de taak plus de poort om voortgang
/// en het resultaat over terug te sturen.
class _WorkerConfig {
  const _WorkerConfig(this.request, this.sendPort);

  final ImportRequest request;
  final SendPort sendPort;
}

/// Het instappunt van de worker-isolate. Draait de gedeelde parse-kern en stuurt
/// elke voortgangsstap plus de ene eindtoestand terug.
///
/// [isCancelled] is hier altijd `false`: een annulering vanaf de hoofd-isolate
/// is in de worker niet af te lezen (isolates delen geen geheugen) en wordt in
/// plaats daarvan door [runImportTask] met een kill afgehandeld.
Future<void> _worker(_WorkerConfig config) async {
  final send = config.sendPort;
  final result = await parseAndClassify(
    config.request,
    report: send.send,
    isCancelled: () => false,
  );
  send.send(result);
}
