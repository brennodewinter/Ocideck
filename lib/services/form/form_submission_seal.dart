// Een ingevuld pakket verzegelen voor de organisatoren van een bundel (FORM_INTAKE.md §5.1, §5.6).
//
// Wat de invuller van de organisator gelooft staat in de bundel, en dat geloof hangt aan één
// ding dat langs een andere weg kwam: de vingerafdruk. Pas als de bundel daarmee klopt — de
// handtekening, de sjabloon die de invuller zelf heeft, de geldigheid, het volgnummer ten
// opzichte van wat hij al zag — wordt er verzegeld, en dan naar **alle** organisatoren die de
// bundel noemt. Daarna is er een gewoon age-bestand: de organisator opent het met zijn sleutel
// (§5.9), en ook zonder OciDeck.
//
// Wat deze stap weigert is wat de bundel zelf zegt: gesloten, of te groot voor wat de organisator
// wil. De invuller kan er niets aan verhelpen en krijgt te horen wat er aan de hand is, geen
// "doorgaan".
library;

import 'dart:typed_data';

import 'package:ocideck_form_core/ocideck_form_core.dart';

import 'form_submission_export.dart';

/// Wat [sealFormSubmission] opleverde.
sealed class FormSealOutcome {
  const FormSealOutcome();
}

/// Het verzegelde bestand is klaar.
class FormSubmissionSealed extends FormSealOutcome {
  const FormSubmissionSealed({
    required this.bytes,
    required this.fileName,
    required this.organisers,
    required this.pins,
  });

  /// Het age-bestand.
  final Uint8List bytes;

  /// Dezelfde naam als die van het gewone pakket, met `.zip.age`: geen persoonsgegevens.
  final String fileName;

  /// De namen van de organisatoren die het kunnen openen, zoals de bundel ze noemt.
  final List<String> organisers;

  /// De pins na deze bundel: de aanroeper bewaart ze.
  final FormBundlePins pins;
}

/// De ingetypte vingerafdruk is geen vingerafdruk.
class FormSealBadFingerprint extends FormSealOutcome {
  const FormSealBadFingerprint();
}

/// De bundel werd niet geloofd, om [issue]. Er is niets verzegeld.
class FormSealBundleRefused extends FormSealOutcome {
  const FormSealBundleRefused(this.issue);

  final FormBundleIssue issue;
}

/// De bundel is in orde, maar het formulier is gesloten: [closes] was de laatste dag.
class FormSealClosed extends FormSealOutcome {
  const FormSealClosed(this.closes);

  final String closes;
}

/// De bundel is in orde, maar de inzending is groter dan de organisator wil: [cap] bytes.
class FormSealTooLarge extends FormSealOutcome {
  const FormSealTooLarge(this.cap);

  final int cap;
}

/// Het verzegelen zelf weigerde (de kern verzegelt niets wat hij zelf niet zou openen).
class FormSealFailed extends FormSealOutcome {
  const FormSealFailed(this.issue);

  final FormSealIssue issue;
}

/// Verzegelt [built] voor de organisatoren van de bundel in [bundleText].
///
/// [published] is het hele gepubliceerde formulier waarmee de inzending is gebouwd — de bundel
/// moet daarbij horen. [fingerprintText] is wat de invuller intikte; [pins] wat hij eerder zag.
Future<FormSealOutcome> sealFormSubmission({
  required FormSubmissionBuilt built,
  required String bundleText,
  required String published,
  required String fingerprintText,
  required FormBundlePins pins,
  required DateTime now,
}) async {
  final fingerprint = normalizeFingerprint(fingerprintText);
  if (fingerprint == null) return const FormSealBadFingerprint();

  final verified = await verifyFormBundle(
    bundleText,
    templateText: published,
    fingerprint: fingerprint,
    now: now,
    pins: pins,
  );
  if (verified is FormBundleRefused) {
    return FormSealBundleRefused(verified.issue);
  }
  verified as FormBundleVerified;
  final bundle = verified.bundle;

  final closes = bundle.policy.closes;
  if (closes != null && formDay(now).compareTo(closes) > 0) {
    return FormSealClosed(closes);
  }
  final cap = bundle.policy.maxPackageBytes;
  if (cap != null && built.bytes.length > cap) {
    return FormSealTooLarge(cap);
  }

  final result = await sealFormPackage(
    built.bytes,
    recipients: [for (final o in bundle.organisers) o.age],
  );
  if (result is FormSealRefused) return FormSealFailed(result.issue);
  result as FormSealed;

  final stem = built.fileName.endsWith('.zip')
      ? built.fileName.substring(0, built.fileName.length - 4)
      : built.fileName;
  return FormSubmissionSealed(
    bytes: result.bytes,
    fileName: '$stem$kSealedSuffix',
    organisers: [for (final o in bundle.organisers) o.name],
    pins: verified.pins,
  );
}
