import 'package:flutter/foundation.dart' show visibleForTesting;

import 'import_runner_io.dart'
    if (dart.library.html) 'import_runner_web.dart'
    as impl;
import 'import_task.dart';

/// Testhaak: draai de importtaak in-process in plaats van op een worker-isolate.
///
/// Widget-tests draaien onder een fake-async-klok en kunnen een echte isolate
/// niet aansturen — een poort-boodschap komt op de échte event-loop, buiten die
/// klok, dus `pumpAndSettle` zou de import nooit klaar zien. Een widget-test die
/// een echte import triggert zet deze haak op [runImportTaskInline] (en herstelt
/// hem in `tearDown`). Plain `test()`-code laat hem `null` en oefent zo het
/// echte isolate-pad.
@visibleForTesting
ImportTaskRunner? debugImportTaskRunner;

/// Draai één importtaak op het juiste uitvoeringspad voor dit platform (#875).
///
/// Op desktop en mobiel gaat het zware parsen naar een worker-isolate zodat de
/// UI-isolate vrij blijft ([import_runner_io.dart]); op web bestaat geen tweede
/// isolate, dus draait het in-process met coöperatieve yields
/// ([import_runner_web.dart]). Beide paden delen [parseAndClassify] als kern en
/// leveren precies één [ImportTaskResult].
///
/// Deze route gebruikt bewust de standaard [ImporterRegistry] (in de worker
/// gebouwd): een geïnjecteerde registry met nep-importers is niet gegarandeerd
/// verzendbaar over de isolategrens. Wie een eigen registry wil (tests) draait
/// [runImportTaskInline] rechtstreeks.
Future<ImportTaskResult> runImportTask(
  ImportRequest request, {
  void Function(ImportProgress progress)? onProgress,
  ImportCancelToken? cancel,
}) {
  final override = debugImportTaskRunner;
  if (override != null) {
    return override(request, onProgress: onProgress, cancel: cancel);
  }
  return impl.runImportTask(request, onProgress: onProgress, cancel: cancel);
}
