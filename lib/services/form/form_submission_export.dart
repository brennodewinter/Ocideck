// Van een ingevuld formulier naar het inzendpakket (FORM_INTAKE.md §5.2, fase 1): de
// controle vlak vóór het versturen en het bouwen van de zip die de invuller mailt.
//
// Alles wat de invulpagina al wist (de antwoorden, de feiten over de foto's) komt
// uit de [FormFill]; wat daar niet in zit en hier wél nodig is, is het formulier
// *zoals het gepubliceerd werd*. Dat is de basis voor twee dingen: de hash in het
// manifest (waaraan de organisator ziet op welke versie dit een antwoord is) en de
// controle dat de tekst buiten de antwoorden nog van het formulier is — dezelfde
// controle die de organisator bij het binnenhalen doet, zodat een invuller niet
// iets maakt wat zijn eigen organisator weigert.
//
// Foto's worden hier nog één keer gezuiverd. Ze staan al schoon in de map van het
// document, maar een antwoord kan ook naar een bestand verwijzen dat er met de
// hand is neergezet; wat het pakket verlaat is dus altijd het resultaat van
// `cleanImage`, niet wat toevallig op schijf staat.
library;

import 'dart:math';
import 'dart:typed_data';

import 'package:ocideck_form_core/ocideck_form_core.dart';

/// De uitkomst van [buildFormSubmission].
sealed class FormSubmissionResult {
  const FormSubmissionResult();
}

/// Het pakket is klaar.
class FormSubmissionBuilt extends FormSubmissionResult {
  const FormSubmissionBuilt({
    required this.bytes,
    required this.fileName,
    required this.photos,
  });

  /// De zip.
  final Uint8List bytes;

  /// Een bestandsnaam zonder persoonsgegevens: het formulier en het begin van het
  /// inzendnummer.
  final String fileName;

  /// Het aantal foto's erin.
  final int photos;
}

/// Er staat nog iets open (een fout in een antwoord); de pagina laat zien wat.
class FormSubmissionBlocked extends FormSubmissionResult {
  const FormSubmissionBlocked(this.problems);

  final List<FormProblem> problems;
}

/// Het formulier waaruit de antwoorden komen is niet het gepubliceerde: de tekst
/// buiten de antwoorden is anders, of een van beide is geen formulier meer.
class FormSubmissionWrongForm extends FormSubmissionResult {
  const FormSubmissionWrongForm(this.problem);

  final FormProblem problem;
}

/// Een foto uit een antwoord is er niet meer, niet te lezen, of geen foto.
class FormSubmissionPhotoUnreadable extends FormSubmissionResult {
  const FormSubmissionPhotoUnreadable(this.path);

  final String path;
}

/// Het pakket zou iets bevatten wat de eigen lezer weigert (te veel bestanden, een
/// foto boven de limiet): de bouwer weigerde.
class FormSubmissionRefused extends FormSubmissionResult {
  const FormSubmissionRefused(this.reason);

  final String reason;
}

/// Controleert [fill] en bouwt er het pakket van.
///
/// [frontMatter] en `fill.text` samen zijn het document zoals het verstuurd wordt;
/// [published] is het hele gepubliceerde formulier, front matter en al.
/// [readImage] geeft de bytes van een foto op zijn pad in het antwoord, of `null`
/// als hij er niet is. [random] en [now] zijn de naden voor het inzendnummer en de
/// datum; in een test zijn het vaste waarden.
Future<FormSubmissionResult> buildFormSubmission({
  required FormFill fill,
  required String frontMatter,
  required String published,
  required Future<Uint8List?> Function(String path) readImage,
  required DateTime now,
  required Random random,
  String? clientVersion,
}) async {
  final submission = frontMatter + fill.text;
  final altered = templateTextIssues(published, submission);
  if (altered.isNotEmpty) return FormSubmissionWrongForm(altered.first);
  final problems = fill.gateIssues();
  if (formIssuesBlock(problems)) return FormSubmissionBlocked(problems);

  final images = <String, Uint8List>{};
  for (final field in fill.spec.fields) {
    for (final image in fill.answerOf(field.id).images) {
      final bytes = await readImage(image.path);
      final report = bytes == null ? null : cleanImage(bytes);
      if (report == null) return FormSubmissionPhotoUnreadable(image.path);
      images[image.path] = report.bytes;
    }
  }

  final sid = newFormId(random);
  try {
    final bytes = buildFormPackage(
      submission: submission,
      template: published,
      spec: fill.spec,
      images: images,
      submissionId: sid,
      created: now,
      clientVersion: clientVersion,
      clientRules: kFormRulesVersion,
    );
    return FormSubmissionBuilt(
      bytes: bytes,
      fileName: '${fill.spec.id}-${sid.substring(0, 6)}.zip',
      photos: images.length,
    );
  } on ArgumentError catch (e) {
    return FormSubmissionRefused('${e.message}');
  }
}
