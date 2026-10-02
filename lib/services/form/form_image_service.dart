// De foto's van een formulier: wat er gebeurt tussen "ik kies een foto" en "de foto
// staat in het antwoord" (FORM_INTAKE.md §5.5), en wat de invulpagina van de foto's
// in een document weet (de feiten voor `FormFill.withImageFacts`).
//
// Een foto van een telefoon draagt een positie, een tijdstip, een apparaat. Die gaan
// eruit **vóór** de foto in het document komt, niet bij het versturen: wat op schijf
// staat is al schoon, en een pakket dat later wordt gemaakt kan dus nooit een
// onbedoeld uitgelekte plaats meenemen. De zuivering zelf is `cleanImage` uit het
// pakket (segmentniveau, zonder opnieuw te coderen). Wat hier bijkomt is wat dat pakket
// niet kan: een beeldontsleutelaar. Elk bestand dat geen HEIC is wordt écht gedecodeerd
// — in een eigen isolate, met een plafond op het aantal beeldpunten — want een
// kopbestand met een geldige kop bewijst niet dat het een foto is (een polyglot).
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show compute;
import 'package:image/image.dart' as img;
import 'package:ocideck_form_core/ocideck_form_core.dart';
import 'package:path/path.dart' as p;

import '../../utils/atomic_file.dart';
import '../../utils/project_path.dart';

/// Het plafond aan beeldpunten dat nog gedecodeerd wordt. Daarboven is het een
/// weigering, geen poging: een bestand dat zich als 60.000 × 60.000 voordoet is een
/// decompressiebom, geen foto. Een telefoon van 200 megapixel zit er net onder.
const int kFormMaxPixels = 200 * 1000 * 1000;

/// Hoeveel bytes een bestand hoogstens mag zijn om nog te verwerken.
const int kFormMaxImageBytes = 64 * 1024 * 1024;

/// Waarom een foto niet kon worden toegevoegd.
enum FormImageRefusal {
  /// Geen JPEG, PNG, WebP of HEIC, of een bestand waar de bouw van de kop al
  /// niet klopt (een afgebroken segment, een verkeerde checksum).
  notAPhoto,

  /// Te groot om veilig te verwerken: te veel bytes of te veel beeldpunten.
  tooLarge,

  /// De kop zegt dat het een foto is, maar de decoder kan er geen beeld van maken.
  unreadable,

  /// Het bestand kon niet worden geschreven.
  writeFailed,
}

/// Een foto die de controle is door gekomen.
class FormImageIntake {
  const FormImageIntake(this.report, this.fact);

  /// De schoongemaakte bytes en wat eruit is gehaald.
  final FormImageReport report;

  /// Wat de validator van deze foto moet weten.
  final FormImageFact fact;
}

/// De uitkomst van [intakeFormImage]: een foto, of de reden dat het er geen is.
sealed class FormImageIntakeResult {
  const FormImageIntakeResult();
}

class FormImageAccepted extends FormImageIntakeResult {
  const FormImageAccepted(this.intake);

  final FormImageIntake intake;
}

class FormImageRejected extends FormImageIntakeResult {
  const FormImageRejected(this.reason);

  final FormImageRefusal reason;
}

/// Zuivert [bytes] en laat ze decoderen, of weigert.
///
/// Een HEIC wordt niet gedecodeerd (besluit D4): OciDeck heeft geen HEIC-decoder en
/// opent zo'n bestand nooit zelf; het blijft zoals het is en heet *niet gecontroleerd*.
Future<FormImageIntakeResult> intakeFormImage(Uint8List bytes) async {
  if (bytes.isEmpty) return const FormImageRejected(FormImageRefusal.notAPhoto);
  if (bytes.length > kFormMaxImageBytes) {
    return const FormImageRejected(FormImageRefusal.tooLarge);
  }
  final report = cleanImage(bytes);
  if (report == null) {
    return const FormImageRejected(FormImageRefusal.notAPhoto);
  }
  if (report.unverified) {
    return FormImageAccepted(
      FormImageIntake(
        report,
        FormImageFact(
          bytes: report.bytes.length,
          format: report.kind.extension,
          unverified: true,
        ),
      ),
    );
  }

  final width = report.width!;
  final height = report.height!;
  if (width < 1 || height < 1 || width * height > kFormMaxPixels) {
    return const FormImageRejected(FormImageRefusal.tooLarge);
  }
  if (!await compute(_decodes, report.bytes)) {
    return const FormImageRejected(FormImageRefusal.unreadable);
  }
  return FormImageAccepted(
    FormImageIntake(
      report,
      FormImageFact(
        displayedWidth: report.displayedWidth,
        bytes: report.bytes.length,
        format: report.kind.extension,
      ),
    ),
  );
}

/// Of [bytes] tot een beeld te decoderen zijn. Draait in een isolate.
///
/// Dit is de poort die een polyglot tegenhoudt: een kop die klopt bewijst niet dat
/// er een foto achter zit. De afmetingen uit de kop worden bewust niet nog eens
/// tegen die van de decoder gelegd — beide lezen dezelfde kop, en een JPEG zet de
/// decoder recht terwijl een PNG met een draairichting dat niet doet.
bool _decodes(Uint8List bytes) {
  try {
    return img.decodeImage(bytes) != null;
  } on Object {
    // De decoders gooien van alles (een RangeError, een eigen uitzondering, een
    // FormatException); wat het ook is, dit bestand is geen te lezen foto.
    return false;
  }
}

/// Een foto die in de map van het document is gezet.
class FormImageStored {
  const FormImageStored(this.path, this.intake);

  /// Het pad zoals het in het antwoord komt: `images/<veld>-<n>.<ext>`.
  final String path;
  final FormImageIntake intake;
}

/// Zet [intake] in `images/` naast het document onder de naam `<veld>-<n>.<ext>`
/// (§5.4): een originele bestandsnaam kan een naam of een tijdstempel dragen
/// (`oma-sien-met-kleindochter.jpg`), en de bestandsnaamgrammatica van een pakket
/// kent alleen `[a-z0-9-]` tot 64 tekens. [taken] zijn de paden die al in gebruik
/// zijn; het eerste vrije nummer wordt genomen, en een bestaand bestand wordt nooit
/// overschreven.
Future<FormImageStored?> storeFormImage({
  required String projectPath,
  required String fieldId,
  required FormImageIntake intake,
  Set<String> taken = const {},
}) async {
  final directory = Directory(p.join(projectPath, 'images'));
  final ext = intake.report.kind.extension;
  // Het veld-id mag lang zijn; de naam hoort onder de 64 tekens te blijven.
  final base = fieldId.length > 50 ? fieldId.substring(0, 50) : fieldId;
  try {
    await directory.create(recursive: true);
    for (var n = 1; n < 10000; n++) {
      final relative = 'images/$base-$n.$ext';
      if (taken.contains(relative)) continue;
      final file = File(p.join(projectPath, relative));
      if (await file.exists()) continue;
      await writeBytesAtomic(file, intake.report.bytes);
      return FormImageStored(relative, intake);
    }
  } on FileSystemException {
    return null;
  }
  return null;
}

/// De uitkomst van een hele keuze foto's.
class FormImageBatch {
  const FormImageBatch(this.stored, this.refused);

  final List<FormImageStored> stored;

  /// Per geweigerde foto de reden, in de volgorde van de keuze.
  final List<FormImageRefusal> refused;

  /// De antwoordregels voor de gelukte foto's.
  List<FormImageRef> get refs => [
    for (final s in stored) FormImageRef(s.path, '', null),
  ];

  /// De feiten per pad.
  Map<String, FormImageFact> get facts => {
    for (final s in stored) s.path: s.intake.fact,
  };

  /// De paden waaruit een positie is gehaald: de invulpagina zegt dat.
  Set<String> get scrubbedPaths => {
    for (final s in stored)
      if (s.intake.report.removed.gps) s.path,
  };
}

/// Verwerkt de gekozen bestanden, één voor één: lezen, zuiveren, controleren,
/// opslaan. Een foto die niet door de controle komt wordt geweigerd; de andere gaan
/// gewoon door.
Future<FormImageBatch> addFormImages({
  required String projectPath,
  required String fieldId,
  required List<Future<Uint8List> Function()> readers,
  Set<String> taken = const {},
}) async {
  final stored = <FormImageStored>[];
  final refused = <FormImageRefusal>[];
  for (final read in readers) {
    final Uint8List bytes;
    try {
      bytes = await read();
    } on Object {
      refused.add(FormImageRefusal.notAPhoto);
      continue;
    }
    switch (await intakeFormImage(bytes)) {
      case FormImageRejected(:final reason):
        refused.add(reason);
      case FormImageAccepted(:final intake):
        final saved = await storeFormImage(
          projectPath: projectPath,
          fieldId: fieldId,
          intake: intake,
          taken: taken,
        );
        if (saved == null) {
          refused.add(FormImageRefusal.writeFailed);
        } else {
          stored.add(saved);
        }
    }
  }
  return FormImageBatch(stored, refused);
}

/// Wat bekend is van de foto's die al in een document staan: bestaat het bestand,
/// wat is het écht, hoe breed. Alleen de kop wordt gelezen en gemeten
/// (`cleanImage`), niet gedecodeerd — de zware controle gebeurde bij het toevoegen,
/// en de organisator doet hem opnieuw bij het importeren. Een bestand buiten de map
/// van het document, of een ontbrekend bestand, krijgt `exists: false`.
Future<Map<String, FormImageFact>> probeFormImages(
  Iterable<String> paths, {
  required String projectPath,
}) async {
  final facts = <String, FormImageFact>{};
  for (final path in paths) {
    final resolved = resolveContainedRealPath(path, projectPath);
    if (resolved == null) {
      facts[path] = const FormImageFact(exists: false);
      continue;
    }
    try {
      final file = File(resolved);
      final length = await file.length();
      if (length > kFormMaxImageBytes) {
        facts[path] = FormImageFact(bytes: length, unverified: true);
        continue;
      }
      final report = cleanImage(await file.readAsBytes());
      if (report == null) {
        // Er staat iets, maar het is geen foto die OciDeck kan lezen: een lege
        // `format` laat de validator het type als "past niet" melden.
        facts[path] = FormImageFact(bytes: length, format: 'unknown');
        continue;
      }
      facts[path] = FormImageFact(
        displayedWidth: report.displayedWidth,
        bytes: length,
        format: report.kind.extension,
        unverified: report.unverified,
      );
    } on FileSystemException {
      facts[path] = const FormImageFact(exists: false);
    }
  }
  return facts;
}
