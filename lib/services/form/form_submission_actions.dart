// Wat een organisator met een binnengekomen inzending doet (FORM_INTAKE.md §7.3): de
// status wisselen, haar intrekken, haar verwijderen. Het zijn bestandsbewerkingen op
// de werkmap en het register; de regels erachter (de gesloten statuslijst, het
// minimale record) zitten in `FormRegister` en `FormWorkspace`.
//
// Elke bewerking meldt wat er gebeurd is, niet alleen of het gelukt is: een register
// dat niet te lezen is wordt nooit overschreven, en verwijderen mag daar niet op
// wachten — het gaat om wat persoonlijk is, en dat moet weg ook als het register
// stuk is. Dan staat in de uitkomst dat het register is blijven staan.
library;

import 'dart:io';

import 'package:ocideck_form_core/ocideck_form_core.dart';

import 'form_workspace.dart';

/// De uitkomst van een wijziging in het register.
enum FormActionOutcome {
  /// Gedaan en bewaard.
  done,

  /// Er is geen rij met dit nummer (meer), of de wijziging mag niet: een status
  /// buiten de lijst van het formulier, een verwijderde inzending, een dag die geen
  /// dag is.
  refused,

  /// Het register is er niet te lezen; er is niets overschreven.
  registerDamaged,

  /// Het register kon niet worden geschreven.
  notSaved,
}

/// De uitkomst van [deleteSubmission].
enum FormDeleteOutcome {
  /// De inhoud is weg en het register is bijgewerkt (of er was geen rij).
  deleted,

  /// De inhoud is weg, maar het register kon niet worden bijgewerkt: het is niet te
  /// lezen of niet te schrijven. Wat persoonlijk is staat er niet meer; de rij moet
  /// met de hand.
  deletedRegisterNotUpdated,

  /// Er is geen inzending met dit nummer in de werkmap.
  notFound,

  /// Verwijderen mislukte; wat er al weg was is weg.
  failed,
}

/// Zet de status van [sid] op [status], als dat een van [states] is.
Future<FormActionOutcome> setSubmissionStatus(
  FormWorkspace workspace,
  String sid,
  String status,
  List<String> states,
) => _change(workspace, (r) => r.withStatus(sid, status, states));

/// Zet de dag waarop [sid] is ingetrokken; een lege [day] maakt het ongedaan.
Future<FormActionOutcome> setSubmissionWithdrawal(
  FormWorkspace workspace,
  String sid,
  String day,
) async {
  if (day.isNotEmpty && !isValidCalendarDate(day)) {
    return FormActionOutcome.refused;
  }
  return _change(workspace, (r) => r.withWithdrawal(sid, day));
}

Future<FormActionOutcome> _change(
  FormWorkspace workspace,
  FormRegister? Function(FormRegister register) change,
) async {
  final current = await workspace.readRegister();
  if (current is FormRegisterDamaged) return FormActionOutcome.registerDamaged;
  if (current is! FormRegisterParsed) return FormActionOutcome.refused;
  final next = change(current.register);
  if (next == null) return FormActionOutcome.refused;
  return await workspace.saveRegister(next)
      ? FormActionOutcome.done
      : FormActionOutcome.notSaved;
}

/// Verwijdert de inhoud van [sid] (antwoorden, werkkopie, foto's) en laat het minimale
/// record staan: het manifest en de rij, zonder wat persoonlijk is — behalve de velden
/// in [keep], die het formulier vooraf in zijn notice heeft aangekondigd.
Future<FormDeleteOutcome> deleteSubmission(
  FormWorkspace workspace,
  String sid, {
  List<String> keep = const [],
}) async {
  try {
    if (!await workspace.deleteSubmissionFiles(sid)) {
      return FormDeleteOutcome.notFound;
    }
  } on FileSystemException {
    // Een schijf die weigert, een map die iemand anders vasthoudt: voor de
    // organisator is het één ding, het is niet gelukt.
    return FormDeleteOutcome.failed;
  }
  final current = await workspace.readRegister();
  if (current == null) return FormDeleteOutcome.deleted;
  if (current is! FormRegisterParsed) {
    return FormDeleteOutcome.deletedRegisterNotUpdated;
  }
  final next = current.register.withDeletion(sid, keep: keep);
  if (next == null) return FormDeleteOutcome.deleted;
  return await workspace.saveRegister(next)
      ? FormDeleteOutcome.deleted
      : FormDeleteOutcome.deletedRegisterNotUpdated;
}
