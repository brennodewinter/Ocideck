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
// versleuteld en de Inbox zegt dat. Een verzegeld bestand (`.zip.age`, §5.6) gaat eerst
// door de redactiesleutel (§5.9) en is daarna een gewone zip: vanaf daar is er één keten.
library;

import 'dart:typed_data';

import 'package:ocideck_form_core/ocideck_form_core.dart';

import 'form_image_service.dart';
import 'form_keys.dart';
import 'form_workspace.dart';

/// De uitkomst van het binnenhalen van één pakket.
sealed class FormImportOutcome {
  const FormImportOutcome();
}

/// De inzending staat in de werkmap.
class FormImported extends FormImportOutcome {
  const FormImported(
    this.review, {
    required this.registerSaved,
    required this.wasSealed,
  });

  final FormReview review;

  /// Het kwam verzegeld binnen en is met de redactiesleutel geopend.
  final bool wasSealed;

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

/// Waarom er geen redactiesleutel is om een verzegeld bestand mee te openen.
enum FormImportKeyProblem {
  /// Dit platform heeft geen sleutelhanger.
  unavailable,

  /// Er is nog geen redactiesleutel aangemaakt of hersteld.
  absent,

  /// De sleutelhanger gaf geen antwoord: wat erin staat is onbekend.
  unreadable,

  /// Er staat iets, maar het is geen redactiesleutel van deze versie.
  damaged,
}

/// Het bestand is verzegeld en er is geen sleutel om het mee te openen. Er is niets
/// geprobeerd en niets geland.
class FormImportNeedsKey extends FormImportOutcome {
  const FormImportNeedsKey(this.problem);

  final FormImportKeyProblem problem;
}

/// Het bestand is verzegeld en ging niet open (of niet voor deze sleutel), zie [issue].
/// Er is niets geland. Een bestand dat opende maar geen pakket bleek, is een
/// [FormImportNotAPackage].
class FormImportNotOpened extends FormImportOutcome {
  const FormImportNotOpened(this.issue);

  final FormUnsealIssue issue;
}

/// Haalt het bestand [bytes] binnen: een gewone zip, of een verzegeld bestand dat met de
/// redactiesleutel uit [keys] wordt geopend. [now] is de dag van ontvangst (de klok als
/// naad voor de test).
///
/// Een verzegeld bestand wordt nooit aan de zip-lezer gegeven en een zip nooit aan de
/// sleutel: wat er aan de kop uitziet als age, is verzegeld ([looksLikeAge]).
Future<FormImportOutcome> importFormFile(
  FormWorkspace workspace,
  Uint8List bytes, {
  required DateTime now,
  required FormKeyService keys,
}) async {
  if (!looksLikeAge(bytes)) {
    return importFormPackage(workspace, bytes, now: now);
  }
  final String identity;
  switch (await keys.read()) {
    case FormKeyPresent(:final key):
      identity = key.ageIdentity;
    case FormKeyUnavailable():
      return const FormImportNeedsKey(FormImportKeyProblem.unavailable);
    case FormKeyAbsent():
      return const FormImportNeedsKey(FormImportKeyProblem.absent);
    case FormKeyUnreadable():
      return const FormImportNeedsKey(FormImportKeyProblem.unreadable);
    case FormKeyDamaged():
      return const FormImportNeedsKey(FormImportKeyProblem.damaged);
  }
  final opened = await openSealedPackage(bytes, identities: [identity]);
  switch (opened) {
    case FormUnsealRefused(issue: FormUnsealIssue.notAPackage, :final problems):
      return FormImportNotAPackage(problems);
    case FormUnsealRefused(:final issue):
      return FormImportNotOpened(issue);
    case FormUnsealed(:final package):
      return _importOpened(workspace, package, now: now, wasSealed: true);
  }
}

/// Haalt [bytes], een gewone zip, binnen in [workspace].
Future<FormImportOutcome> importFormPackage(
  FormWorkspace workspace,
  Uint8List bytes, {
  required DateTime now,
}) async {
  final read = readFormPackage(bytes);
  if (read is FormPackageRefused) return FormImportNotAPackage(read.problems);
  return _importOpened(
    workspace,
    read as FormPackageOpened,
    now: now,
    wasSealed: false,
  );
}

Future<FormImportOutcome> _importOpened(
  FormWorkspace workspace,
  FormPackageOpened package, {
  required DateTime now,
  required bool wasSealed,
}) async {
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
    wasSealed: wasSealed,
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
