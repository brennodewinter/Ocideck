import 'import_task.dart';

/// Web-uitvoeringspad voor één importtaak: in-process (#875).
///
/// Een browser heeft geen tweede isolate om het werk naartoe te schuiven, dus
/// het parsen draait op dezelfde isolate als de UI. Wat het bruikbaar houdt: de
/// gedeelde kern [parseAndClassify] geeft de event-loop tussen de begrensde
/// werkeenheden een beurt (yields) en toetst de coöperatieve [cancel]-token af,
/// zodat een annuleertik en een voortgangsherteken tussen die eenheden
/// doorkomen. Binnen één werkeenheid — de importer die het hele deck parseert —
/// blokkeert web wél; de geheugen- en tijdgrenzen van het budget begrenzen die.
Future<ImportTaskResult> runImportTask(
  ImportRequest request, {
  void Function(ImportProgress progress)? onProgress,
  ImportCancelToken? cancel,
}) => runImportTaskInline(request, onProgress: onProgress, cancel: cancel);
