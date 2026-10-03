// Het boek samenstellen (FORM_INTAKE.md §7.5): de inzendingen die de organisator koos,
// door een hoofdstuksjabloon, tot één nieuw document in `book/` van de werkmap.
//
// De zuivere kern is `compileBook` in het pakket (wat in een hoofdstuk komt, de
// codeblokken, de lege regels, wat ingetrokken is). Hier staat het werk eromheen: het
// register lezen, de inzendingen openen zoals ze nu zijn (de werkkopie voor wat
// binnenkwam), de foto's kopiëren en het boek met zijn sidecar schrijven.
//
// Drie dingen maken dat een boek te vertrouwen is. Het schrijft **één nieuw document** en
// nooit over een bestaand heen. De foto's komen uit wat de werkmap bewaart — al schoon
// — onder een naam met het inzendnummer, zodat twee inzendingen nooit één bestand delen.
// En wat *over* het boek gaat — welke inzendingen erin zitten, onder welke toestemming —
// staat in een sidecar ernaast, niet in de tekst: een HTML-commentaar zou in de lezer
// zichtbaar zijn, en een regel die een bewerking in de visuele editor niet overleeft is
// geen terugverwijzing.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:ocideck_form_core/ocideck_form_core.dart';
import 'package:path/path.dart' as p;

import '../../models/asset_rights.dart';
import '../../utils/atomic_file.dart';
import 'form_workspace.dart';

/// De uitkomst van [compileFormBook].
sealed class FormBookOutcome {
  const FormBookOutcome();
}

/// Het boek is geschreven.
class FormBookWritten extends FormBookOutcome {
  const FormBookWritten({
    required this.path,
    required this.chapters,
    required this.images,
    required this.withdrawn,
    required this.skipped,
    required this.missingImages,
  });

  /// Het pad van het boek (`book/<naam>.md`).
  final String path;

  /// Het aantal hoofdstukken.
  final int chapters;

  /// Het aantal foto's dat is gekopieerd.
  final int images;

  /// Geselecteerd, maar ingetrokken: niet in het boek.
  final int withdrawn;

  /// Geselecteerd, maar niet te lezen of van een andere versie van het formulier.
  final int skipped;

  /// Foto's die het antwoord noemt en die er niet meer zijn: het boek verwijst naar
  /// een bestand dat ontbreekt.
  final int missingImages;
}

/// De naam is leeg of valt buiten wat een bestandsnaam hier mag zijn.
class FormBookBadName extends FormBookOutcome {
  const FormBookBadName();
}

/// Er staat al een boek met deze naam; dat wordt nooit overschreven.
class FormBookNameTaken extends FormBookOutcome {
  const FormBookNameTaken();
}

/// Het sjabloon noemt velden die het formulier niet heeft.
class FormBookUnknownFields extends FormBookOutcome {
  const FormBookUnknownFields(this.ids);

  final List<String> ids;
}

/// Er is niets om in het boek te zetten: geen inzending met een gekozen status, of
/// alles ingetrokken of niet te lezen.
class FormBookEmpty extends FormBookOutcome {
  const FormBookEmpty({required this.withdrawn, required this.skipped});

  final int withdrawn;
  final int skipped;
}

/// Het register is er niet te lezen: er valt niet uit te kiezen.
class FormBookRegisterDamaged extends FormBookOutcome {
  const FormBookRegisterDamaged();
}

/// Schrijven mislukte; het boek zelf is niet geschreven.
class FormBookFailed extends FormBookOutcome {
  const FormBookFailed();
}

/// Een naam die als bestandsnaam kan: letters, cijfers, streepje en underscore.
final RegExp _bookName = RegExp(r'^[A-Za-z0-9][A-Za-z0-9_-]{0,63}$');

/// Stelt het boek samen van de inzendingen van [form] met een van [states] als status.
///
/// [template] is de tekst van het hoofdstuksjabloon. Een inzending van een andere versie
/// van het formulier, of die niet te lezen is, telt als overgeslagen. [now] is de dag
/// van samenstellen voor de sidecar.
///
/// Met [onlySid] komt alleen die inzending in het boek, wat haar status ook is: dat is
/// het hoofdstuk voor de controle door de maker (§7.4). Een ingetrokken of verwijderde
/// inzending komt er ook dan niet in.
Future<FormBookOutcome> compileFormBook(
  FormWorkspace workspace, {
  required FormSpec form,
  required String template,
  required Set<String> states,
  required String name,
  required DateTime now,
  String? orderBy,
  String? groupBy,
  String? onlySid,
}) async {
  if (!_bookName.hasMatch(name)) return const FormBookBadName();
  final bookDir = p.join(workspace.root, 'book');
  final target = File(p.join(bookDir, '$name.md'));
  if (await target.exists()) return const FormBookNameTaken();

  final register = await workspace.readRegister();
  if (register is FormRegisterDamaged) return const FormBookRegisterDamaged();
  final rows = register is FormRegisterParsed
      ? [
          for (final row in register.register.rows)
            if (!row.isDeleted &&
                (onlySid == null
                    ? states.contains(row.status)
                    : row.sid == onlySid))
              row,
        ]
      : const <FormRegisterRow>[];

  final submissions = <CompileSubmission>[];
  final reviews = <String, FormReview>{};
  var skipped = 0;
  FormSpec? spec;
  for (final row in rows) {
    final stored = await workspace.reviewStored(row.sid);
    final review = stored is FormStoredReview ? stored.review : null;
    final answers = review?.answers;
    if (review == null ||
        answers == null ||
        review.spec?.id != form.id ||
        review.spec?.version != form.version) {
      skipped++;
      continue;
    }
    spec ??= review.spec;
    reviews[row.sid] = review;
    submissions.add(
      CompileSubmission(
        sid: row.sid,
        answers: answers,
        withdrawn: row.isWithdrawn,
      ),
    );
  }
  final withdrawn = submissions.where((s) => s.withdrawn).length;
  if (spec == null || submissions.length == withdrawn) {
    return FormBookEmpty(withdrawn: withdrawn, skipped: skipped);
  }

  final result = compileBook(
    template: ChapterTemplate(template),
    spec: spec,
    submissions: submissions,
    orderBy: orderBy,
    groupBy: groupBy,
  );
  if (result is BookRefused) return FormBookUnknownFields(result.unknown);
  final book = result as BookCompiled;

  try {
    await Directory(bookDir).create(recursive: true);
    final copied = await _copyImages(bookDir, book.images, reviews);
    await writeStringAtomic(
      File(p.join(bookDir, '$name.compile.json')),
      _sidecar(spec, template, book, reviews, now),
    );
    await writeStringAtomic(target, book.markdown);
    return FormBookWritten(
      path: target.path,
      chapters: book.included.length,
      images: copied.copied,
      withdrawn: withdrawn,
      skipped: skipped,
      missingImages: copied.missing,
    );
  } on FileSystemException {
    return const FormBookFailed();
  }
}

/// Zet de foto's van het boek naast het boek, onder hun nieuwe naam. Een foto die de
/// werkmap niet meer heeft wordt geteld, niet verzwegen.
Future<({int copied, int missing})> _copyImages(
  String bookDir,
  List<ChapterImage> images,
  Map<String, FormReview> reviews,
) async {
  var copied = 0;
  var missing = 0;
  for (final image in images) {
    final Uint8List? bytes = reviews[image.sid]?.images[image.from];
    if (bytes == null) {
      missing++;
      continue;
    }
    final file = File(p.join(bookDir, image.to));
    await file.parent.create(recursive: true);
    await writeBytesAtomic(file, bytes);
    copied++;
  }
  return (copied: copied, missing: missing);
}

/// Wat *over* het boek gaat: het formulier, het sjabloon, de hoofdstukken in volgorde
/// met de toestemming waaronder elke inzending is gedaan, en per foto haar hash, haar
/// maker en het bewijs waaronder ze er mag staan. Niets daarvan hoeft in de tekst.
///
/// Het bewijs per foto heeft de vorm van [AssetRightsProvenance] (§7.5) en hangt aan de
/// **sha-256 van de bytes**, niet aan de bestandsnaam: dat is de sleutel waaronder de
/// rechtencontrole van de assetpool haar bevindingen bewaart, dus wie de foto later in
/// een pool zet vindt het bewijs terug. Dit boek is een document, en de controle kijkt nog
/// niet naar documentfoto's — dit legt het bewijs vast, het sluit die controle niet.
String _sidecar(
  FormSpec spec,
  String template,
  BookCompiled book,
  Map<String, FormReview> reviews,
  DateTime now,
) {
  final photos = <String, List<Map<String, Object?>>>{};
  for (final image in book.images) {
    final review = reviews[image.sid]!;
    final bytes = review.images[image.from];
    photos.putIfAbsent(image.sid, () => []).add({
      'file': image.to,
      if (bytes != null) 'sha256': sha256Hex(bytes),
      'provenance': _photoProvenance(spec, image, review).toJson(),
    });
  }
  return '${const JsonEncoder.withIndent('  ').convert({
    'v': 1,
    'created': formDay(now),
    'form': {'id': spec.id, 'version': spec.version, 'template_sha256': formTemplateHash(template)},
    'chapters': [
      for (final sid in book.included) {
          'sid': sid,
          'form_sha256': reviews[sid]!.manifest.templateSha256,
          'consent': [for (final c in reviews[sid]!.manifest.consent) c.toJson()],
          'images': photos[sid] ?? const [],
        },
    ],
  })}\n';
}

/// De maker van de foto is wat de inzender als titel gaf. De licentie is de toestemming
/// die de inzender bij het inzenden gaf, met als bewijs welk formulier, welke inzending en
/// de hash van de tekst waarmee ze instemde: de hash laat zien *welke* tekst dat was. Een
/// formulier zonder toestemmingsveld levert geen licentie en geen bewijs — dat staat dan
/// zo in het bestand, en wordt niet aangevuld met iets wat er niet is.
AssetRightsProvenance _photoProvenance(
  FormSpec spec,
  ChapterImage image,
  FormReview review,
) {
  final consent = review.manifest.consent;
  final credit = image.credit;
  return AssetRightsProvenance(
    creator: credit == null || credit.isEmpty ? null : credit,
    license: consent.isEmpty ? null : 'form-consent',
    licenseEvidence: consent.isEmpty
        ? null
        : '${spec.id}@${spec.version} ${image.sid}: ${[for (final c in consent) '${c.field} ${c.accepted} sha256:${c.textSha256}'].join('; ')}',
  );
}
