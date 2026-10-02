// Een binnengekomen inzendpakket in de werkmap brengen (FORM_INTAKE.md §7.2).
//
// De keten, en elke schakel weigert in plaats van te raden: het pakket lezen
// (`readFormPackage`, onder limieten), elke foto écht laten decoderen (dat kan alleen
// hier, het pakket heeft geen decoder), de inzending beoordelen tegen het
// *gepubliceerde* formulier (`reviewFormPackage`), de bestanden in de werkmap zetten
// en pas dan de rij in het register. Een inzending met een fout komt er wel in — de
// redactie kan hem bijwerken in een werkkopie — maar met de status `needs-fixing`:
// niets wordt stilzwijgend aangenomen en niets stilzwijgend weggegooid (§4.11).
//
// Een gewone zip is in de fasen 1 en 2 een toegestane invoer; hij is onderweg niet
// versleuteld en de Inbox zegt dat.
library;

import 'dart:typed_data';

import 'package:ocideck_form_core/ocideck_form_core.dart';

import 'form_image_service.dart';
import 'form_workspace.dart';

/// De uitkomst van het binnenhalen van één pakket.
sealed class FormImportOutcome {
  const FormImportOutcome();
}

/// De inzending staat in de werkmap.
class FormImported extends FormImportOutcome {
  const FormImported(this.review, {required this.registerSaved});

  final FormReview review;

  /// Of de rij in het register is gezet. `false` bij een register dat niet te lezen
  /// is of niet te schrijven: de inzending staat er dan wel, en het register is met
  /// rust gelaten.
  final bool registerSaved;

  String get sid => review.manifest.submissionId;

  /// Er is een fout tegen het gepubliceerde formulier: status `needs-fixing`.
  bool get needsFixing => !review.acceptable;
}

/// Er was al een inzending met dit nummer; er is niets overschreven.
class FormImportDuplicate extends FormImportOutcome {
  const FormImportDuplicate(this.sid);

  final String sid;
}

/// Het bestand is geen inzendpakket dat deze lezer opent.
class FormImportNotAPackage extends FormImportOutcome {
  const FormImportNotAPackage(this.problems);

  final List<FormPackageProblem> problems;
}

/// Het pakket is een pakket, maar er is geen formulier om het tegen te houden: het
/// noemt een formulier of versie die niet in de werkmap staat (`template-unknown`),
/// of het gepubliceerde formulier is onbruikbaar.
class FormImportUnknownForm extends FormImportOutcome {
  const FormImportUnknownForm(this.review);

  final FormReview review;
}

/// Schrijven in de werkmap mislukte; er is niets achtergebleven.
class FormImportFailed extends FormImportOutcome {
  const FormImportFailed();
}

/// Haalt [bytes] binnen in [workspace]. [now] is de dag van ontvangst (de klok als
/// naad voor de test).
Future<FormImportOutcome> importFormPackage(
  FormWorkspace workspace,
  Uint8List bytes, {
  required DateTime now,
}) async {
  final read = readFormPackage(bytes);
  if (read is FormPackageRefused) return FormImportNotAPackage(read.problems);
  final package = read as FormPackageOpened;

  final published = await workspace.publishedForms();
  final review = reviewFormPackage(package, [
    for (final form in published.forms) form.text,
  ], undecodable: await _undecodable(package.images));
  final spec = review.spec;
  if (spec == null) return FormImportUnknownForm(review);

  switch (await workspace.land(package, review)) {
    case FormLandOutcome.exists:
      return FormImportDuplicate(package.manifest.submissionId);
    case FormLandOutcome.refused || FormLandOutcome.failed:
      return const FormImportFailed();
    case FormLandOutcome.landed:
      break;
  }
  return FormImported(
    review,
    registerSaved: await _register(workspace, spec, review, now),
  );
}

/// De foto's die een echte decode weigert. HEIC wordt nooit gedecodeerd (D4) en komt
/// hier dus nooit in.
Future<Set<String>> _undecodable(Map<String, Uint8List> images) async => {
  for (final MapEntry(key: path, value: bytes) in images.entries)
    if (await intakeFormImage(bytes) is FormImageRejected) path,
};

/// Zet de rij van [review] in het register. `false` als dat niet kan: het register
/// is beschadigd of niet te schrijven. Een rij die er al stond blijft zoals ze was.
Future<bool> _register(
  FormWorkspace workspace,
  FormSpec spec,
  FormReview review,
  DateTime now,
) async {
  final current = await workspace.readRegister();
  final register = switch (current) {
    null => FormRegister.empty(spec),
    FormRegisterParsed(:final register) => register,
    FormRegisterDamaged() => null,
  };
  if (register == null) return false;
  final next = register.withSubmission(review, received: formDay(now));
  return next == null || await workspace.saveRegister(next);
}
