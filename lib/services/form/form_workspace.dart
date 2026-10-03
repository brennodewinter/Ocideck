// De werkmap van een organisator (FORM_INTAKE.md §7.1): gewone bestanden, met
// Engelse structuurnamen, die ook zonder OciDeck te lezen zijn.
//
//   <werkmap>/
//   ├── forms/<form-id>/v<versie>/template.<taal>.md   het gepubliceerde formulier
//   ├── submissions/<sid>/
//   │   ├── submission.md        zoals ontvangen — nooit bewerkt
//   │   ├── submission.edit.md   de werkkopie waarin geredigeerd wordt (optioneel)
//   │   ├── images/              de foto's, nog eens gezuiverd bij het binnenhalen
//   │   └── manifest.json        zoals ontvangen; blijft ook na verwijderen staan
//   └── overview.md              het register (§7.3)
//
// Wat hier staat is bestandsbeheer en niets anders: wat een pakket waard is beslist
// `reviewFormPackage`, wat in het register komt de `FormRegister`. Drie regels dragen
// de rest. Een map onder `submissions/` krijgt zijn naam van een **gevalideerd
// inzendnummer**, nooit van een antwoord. Er wordt nooit overschreven: een inzending
// die er al is, is er al. En een inzending verschijnt in één stap (eerst een
// tijdelijke map, dan een hernoeming), zodat een crash nooit een halve inzending
// achterlaat waar de Inbox hem voor een hele houdt.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:ocideck_form_core/ocideck_form_core.dart';
import 'package:path/path.dart' as p;

import '../../utils/atomic_file.dart';

/// Een gepubliceerd formulier zoals de organisator het bewaart.
class PublishedForm {
  const PublishedForm({
    required this.id,
    required this.version,
    required this.lang,
    required this.text,
    required this.path,
  });

  final String id;
  final int version;

  /// De taal van deze tekst (`nl`), of `null` voor een formulier zonder.
  final String? lang;

  /// De hele tekst van het bestand.
  final String text;
  final String path;
}

/// Wat [FormWorkspace.publishForm] deed.
sealed class FormPublishOutcome {
  const FormPublishOutcome();
}

/// Het formulier is bewaard.
class FormPublished extends FormPublishOutcome {
  const FormPublished(this.form);

  final PublishedForm form;
}

/// Dezelfde tekst stond er al.
class FormPublishedAlready extends FormPublishOutcome {
  const FormPublishedAlready(this.form);

  final PublishedForm form;
}

/// Er staat al een andere tekst onder dit formulier, deze versie en deze taal. Een
/// gepubliceerde versie verandert niet meer: "beoordeeld tegen de versie die ze
/// noemt" heeft die tekst nodig (§5.1). Een andere tekst is een nieuwe versie.
class FormPublishConflict extends FormPublishOutcome {
  const FormPublishConflict(this.existing);

  final PublishedForm existing;
}

/// De tekst is geen formulier dat gepubliceerd kan worden: geen formulier, een
/// auteursfout, regels van een nieuwere versie, of een taal die niet als bestandsnaam
/// kan.
class FormPublishRefused extends FormPublishOutcome {
  const FormPublishRefused();
}

/// Het bewaren is mislukt (schijf vol, geen schrijfrechten).
class FormPublishFailed extends FormPublishOutcome {
  const FormPublishFailed();
}

/// Wat [FormWorkspace.land] deed.
enum FormLandOutcome {
  /// De inzending staat in de werkmap.
  landed,

  /// Er was al een inzending met dit nummer; er is niets overschreven.
  exists,

  /// De beoordeling kent het formulier niet (er is niets om tegen te houden), of
  /// een bestandsnaam viel buiten de grammatica.
  refused,

  /// Schrijven mislukte; er is niets achtergebleven.
  failed,
}

/// Een inzending in de werkmap, opnieuw beoordeeld tegen het gepubliceerde formulier.
sealed class FormStoredReviewResult {
  const FormStoredReviewResult();
}

class FormStoredReview extends FormStoredReviewResult {
  const FormStoredReview(this.review, {required this.edited});

  final FormReview review;

  /// De beoordeling gaat over de werkkopie (`submission.edit.md`), niet over wat
  /// binnenkwam: de redactie corrigeert daar, en de lijst moet laten zien of het
  /// gecorrigeerd is.
  final bool edited;
}

/// Er is niets te beoordelen: de inhoud is verwijderd (alleen het minimale record
/// staat er nog), of de bestanden zijn er niet meer of niet te lezen.
class FormStoredUnavailable extends FormStoredReviewResult {
  const FormStoredUnavailable({required this.deleted, this.edited = false});

  /// `submission.md` ontbreekt maar `manifest.json` is er nog en klopt: wat
  /// [FormWorkspace.deleteSubmissionFiles] achterlaat.
  final bool deleted;

  /// Er is een werkkopie (`submission.edit.md`), maar die is niet te lezen: de organisator
  /// moet haar kunnen weggooien om weer bij wat binnenkwam uit te komen.
  final bool edited;
}

/// Wat [FormWorkspace.workingCopy] opleverde.
sealed class FormWorkingCopyResult {
  const FormWorkingCopyResult();
}

/// De werkkopie van een inzending: `submission.edit.md`.
class FormWorkingCopy extends FormWorkingCopyResult {
  const FormWorkingCopy(this.path, {required this.created});

  final String path;

  /// De kopie is nu gemaakt; `false` als ze er al was (en dan met rust is gelaten).
  final bool created;
}

/// Er is niets om een kopie van te maken: de inzending is er niet of is verwijderd.
class FormWorkingCopyUnavailable extends FormWorkingCopyResult {
  const FormWorkingCopyUnavailable();
}

/// Het maken van de kopie mislukte (schijf vol, geen schrijfrechten).
class FormWorkingCopyFailed extends FormWorkingCopyResult {
  const FormWorkingCopyFailed();
}

/// Wat [FormWorkspace.discardWorkingCopy] opleverde.
enum FormDiscardResult {
  /// De werkkopie is verwijderd; de inzending wordt weer beoordeeld zoals ze binnenkwam.
  discarded,

  /// Er was geen werkkopie.
  none,

  /// Verwijderen mislukte (geen schrijfrechten); de werkkopie staat er nog.
  failed,
}

final RegExp _formId = RegExp(r'^[a-z][a-z0-9-]*$');
final RegExp _versionDir = RegExp(r'^v([0-9]+)$');
final RegExp _templateName = RegExp(
  r'^template(?:\.([a-z]{2,3}(?:-[a-z0-9]{2,8})*))?\.md$',
);

class FormWorkspace {
  const FormWorkspace(this.root);

  final String root;

  String get registerPath => p.join(root, kFormRegisterFile);
  String get _formsDir => p.join(root, 'forms');
  String get _submissionsDir => p.join(root, 'submissions');

  /// De map van de inzending [sid]; alleen voor een geldig nummer.
  String submissionPath(String sid) {
    if (!isValidFormId(sid)) {
      throw ArgumentError.value(sid, 'sid', 'not a submission id');
    }
    return p.join(_submissionsDir, sid);
  }

  // ── gepubliceerde formulieren ─────────────────────────────────────────────

  /// Alle formulieren onder `forms/`, en de paden van wat er stond maar niet te
  /// lezen was (geen UTF-8, geen formulier): die verdwijnen niet stil.
  Future<({List<PublishedForm> forms, List<String> unreadable})>
  publishedForms() async {
    final forms = <PublishedForm>[];
    final unreadable = <String>[];
    final root = Directory(_formsDir);
    if (!await root.exists()) return (forms: forms, unreadable: unreadable);
    await for (final formDir in root.list(followLinks: false)) {
      if (formDir is! Directory ||
          !_formId.hasMatch(p.basename(formDir.path))) {
        continue;
      }
      await for (final versionDir in formDir.list(followLinks: false)) {
        final version = _versionDir.firstMatch(p.basename(versionDir.path));
        if (versionDir is! Directory || version == null) continue;
        await for (final file in versionDir.list(followLinks: false)) {
          final name = _templateName.firstMatch(p.basename(file.path));
          if (file is! File || name == null) continue;
          final text = await _readText(file);
          final spec = text == null ? null : _specOf(text);
          // Het formulier hoort in de map die zijn eigen id en versie draagt; een
          // bestand dat ergens anders is neergezet kan niet bewijzen welke versie
          // het is.
          if (spec == null ||
              spec.id != p.basename(formDir.path) ||
              'v${spec.version}' != p.basename(versionDir.path)) {
            unreadable.add(file.path);
            continue;
          }
          forms.add(
            PublishedForm(
              id: spec.id,
              version: spec.version,
              lang: name.group(1),
              text: text!,
              path: file.path,
            ),
          );
        }
      }
    }
    forms.sort((a, b) => a.path.compareTo(b.path));
    return (forms: forms, unreadable: unreadable);
  }

  // ── bundels ───────────────────────────────────────────────────────────────

  /// Waar de bundel van [form] staat: naast zijn sjabloon, onder de naam die de kern geeft
  /// (`template.nl.md` heeft `template.nl.bundle.json`). Een bundel bindt de hash van één tekst
  /// en elke taal is een eigen tekst, dus elke taal heeft zijn eigen bundel.
  String bundlePathOf(PublishedForm form) =>
      p.join(p.dirname(form.path), bundleFileNameFor(p.basename(form.path)));

  /// Alle bundelbestanden van formulier [formId], over alle versies en talen, en de paden van wat
  /// er stond maar niet te lezen was (geen UTF-8).
  Future<
    ({List<({String path, String text})> bundles, List<String> unreadable})
  >
  bundlesOf(String formId) async {
    final bundles = <({String path, String text})>[];
    final unreadable = <String>[];
    final formDir = Directory(p.join(_formsDir, formId));
    if (!_formId.hasMatch(formId) || !await formDir.exists()) {
      return (bundles: bundles, unreadable: unreadable);
    }
    await for (final versionDir in formDir.list(followLinks: false)) {
      if (versionDir is! Directory ||
          _versionDir.firstMatch(p.basename(versionDir.path)) == null) {
        continue;
      }
      await for (final file in versionDir.list(followLinks: false)) {
        if (file is! File || !p.basename(file.path).endsWith('.bundle.json')) {
          continue;
        }
        final text = await _readText(file);
        if (text == null) {
          unreadable.add(file.path);
        } else {
          bundles.add((path: file.path, text: text));
        }
      }
    }
    bundles.sort((a, b) => a.path.compareTo(b.path));
    return (bundles: bundles, unreadable: unreadable);
  }

  /// Bewaart [text] als de bundel van [form], over een eerdere heen: een nieuwe bundel heeft een
  /// hoger volgnummer en vervangt de vorige. `false` als het niet lukt.
  Future<bool> writeBundle(PublishedForm form, String text) async {
    try {
      await writeStringAtomic(File(bundlePathOf(form)), text);
      return true;
    } on FileSystemException {
      return false;
    }
  }

  /// Bewaart [text] als gepubliceerd formulier onder `forms/<id>/v<versie>/`.
  Future<FormPublishOutcome> publishForm(String text) async {
    final spec = _specOf(text);
    final lang = spec?.lang?.toLowerCase();
    if (spec == null || (lang != null && !_langOk(lang))) {
      return const FormPublishRefused();
    }
    final file = File(
      p.join(
        _formsDir,
        spec.id,
        'v${spec.version}',
        lang == null ? 'template.md' : 'template.$lang.md',
      ),
    );
    final form = PublishedForm(
      id: spec.id,
      version: spec.version,
      lang: lang,
      text: text,
      path: file.path,
    );
    try {
      if (await file.exists()) {
        final existing = await _readText(file);
        return existing == text
            ? FormPublishedAlready(form)
            : FormPublishConflict(
                PublishedForm(
                  id: spec.id,
                  version: spec.version,
                  lang: lang,
                  text: existing ?? '',
                  path: file.path,
                ),
              );
      }
      await file.parent.create(recursive: true);
      await writeStringAtomic(file, text);
      return FormPublished(form);
    } on FileSystemException {
      return const FormPublishFailed();
    }
  }

  // ── inzendingen ───────────────────────────────────────────────────────────

  /// De nummers van de inzendingen in de werkmap, gesorteerd. Een map die geen
  /// geldig nummer heeft (een tijdelijke map van een onderbroken landing) telt niet.
  Future<List<String>> submissionIds() async {
    final dir = Directory(_submissionsDir);
    if (!await dir.exists()) return const [];
    return [
      await for (final e in dir.list(followLinks: false))
        if (e is Directory && isValidFormId(p.basename(e.path)))
          p.basename(e.path),
    ]..sort();
  }

  /// Zet de inzending van [package] in de werkmap: `submission.md` en
  /// `manifest.json` zoals ze aankwamen, de foto's zoals [review] ze bewaart.
  /// Nooit over een bestaande inzending heen.
  Future<FormLandOutcome> land(
    FormPackageOpened package,
    FormReview review,
  ) async {
    final sid = package.manifest.submissionId;
    if (review.spec == null || !isValidFormId(sid)) {
      return FormLandOutcome.refused;
    }
    final target = Directory(submissionPath(sid));
    final images = review.images;
    if (images.keys.any((name) => !kFormImagePath.hasMatch(name))) {
      return FormLandOutcome.refused;
    }
    final staging = Directory(
      p.join(_submissionsDir, '.landing-$sid-${_landings++}'),
    );
    try {
      await staging.create(recursive: true);
      await _write(staging, 'submission.md', package.submissionBytes);
      await _write(staging, 'manifest.json', package.manifestBytes);
      for (final MapEntry(key: name, value: bytes) in images.entries) {
        await _write(staging, name, bytes);
      }
      await staging.rename(target.path);
      return FormLandOutcome.landed;
    } on FileSystemException {
      // De hernoeming is de scheidsrechter: staat er al een inzending onder dit
      // nummer (ook van een landing die ons net vóór was), dan is het geen mislukking.
      return await target.exists()
          ? FormLandOutcome.exists
          : FormLandOutcome.failed;
    } finally {
      if (await staging.exists()) await staging.delete(recursive: true);
    }
  }

  /// Beoordeelt de inzending [sid], zoals ze nu in de werkmap staat, opnieuw tegen
  /// het gepubliceerde formulier — de werkkopie als die er is, anders wat binnenkwam.
  ///
  /// Wat de Inbox toont is zo altijd de stand van nu: een correctie in de werkkopie
  /// haalt een punt uit de lijst zonder dat iets anders hoeft te worden bijgewerkt.
  Future<FormStoredReviewResult> reviewStored(String sid) async {
    final dir = submissionPath(sid);
    final manifestBytes = await _readBytes(File(p.join(dir, 'manifest.json')));
    final manifest = manifestBytes == null
        ? null
        : readFormManifest(manifestBytes);
    if (manifestBytes == null ||
        manifest == null ||
        manifest.submissionId != sid) {
      return const FormStoredUnavailable(deleted: false);
    }
    final edit = File(p.join(dir, 'submission.edit.md'));
    final edited = await edit.exists();
    final submissionBytes = await _readBytes(
      edited ? edit : File(p.join(dir, 'submission.md')),
    );
    final text = submissionBytes == null ? null : _decode(submissionBytes);
    if (submissionBytes == null || text == null) {
      return FormStoredUnavailable(
        deleted: submissionBytes == null && !edited,
        edited: edited,
      );
    }
    final review = reviewFormPackage(
      FormPackageOpened(
        manifest: manifest,
        manifestBytes: manifestBytes,
        submission: text,
        submissionBytes: submissionBytes,
        images: await _storedImages(dir),
      ),
      [for (final form in (await publishedForms()).forms) form.text],
    );
    return FormStoredReview(review, edited: edited);
  }

  Future<Map<String, Uint8List>> _storedImages(String submissionDir) async {
    final images = <String, Uint8List>{};
    final folder = Directory(p.join(submissionDir, 'images'));
    if (!await folder.exists()) return images;
    await for (final entity in folder.list(followLinks: false)) {
      final name = 'images/${p.basename(entity.path)}';
      if (entity is! File || !kFormImagePath.hasMatch(name)) continue;
      final bytes = await _readBytes(entity);
      if (bytes != null) images[name] = bytes;
    }
    return images;
  }

  /// De werkkopie van [sid] (`submission.edit.md`), die [reviewStored] voortaan
  /// beoordeelt: wat de redactie wil verbeteren — een fout herstellen, een naam
  /// weglaten — gebeurt daar, nooit in wat binnenkwam (§7.1).
  ///
  /// Is er nog geen kopie, dan wordt ze gemaakt als een letterlijke kopie van
  /// `submission.md`. Is er al een, dan blijft ze zoals ze is: werk dat iemand erin
  /// stak wordt nooit overschreven.
  Future<FormWorkingCopyResult> workingCopy(String sid) async {
    final dir = submissionPath(sid);
    final copy = File(p.join(dir, 'submission.edit.md'));
    try {
      if (await copy.exists()) {
        return FormWorkingCopy(copy.path, created: false);
      }
      final received = await _readBytes(File(p.join(dir, 'submission.md')));
      if (received == null) return const FormWorkingCopyUnavailable();
      await writeBytesAtomic(copy, received);
      return FormWorkingCopy(copy.path, created: true);
    } on FileSystemException {
      return const FormWorkingCopyFailed();
    }
  }

  /// Gooit de werkkopie van [sid] weg, zodat [reviewStored] weer wat binnenkwam
  /// beoordeelt. Alleen `submission.edit.md` gaat: wat binnenkwam, de foto's en het
  /// register blijven. Een verwijzing wordt zelf verwijderd, nooit gevolgd — wat erachter
  /// ligt is niet van de werkmap. Wat [reviewStored] niet als werkkopie ziet (een map met
  /// die naam, een verwijzing naar niets) is er voor dit ook niet.
  Future<FormDiscardResult> discardWorkingCopy(String sid) async {
    final copy = File(p.join(submissionPath(sid), 'submission.edit.md'));
    try {
      if (!await copy.exists()) return FormDiscardResult.none;
      await copy.delete();
      return FormDiscardResult.discarded;
    } on FileSystemException {
      return FormDiscardResult.failed;
    }
  }

  /// Verwijdert wat persoonlijk is van de inzending [sid] — `submission.md`, de
  /// werkkopie en de foto's — en laat `manifest.json` staan: het minimale record
  /// (§7.3). Geeft `false` als de inzending er niet is.
  Future<bool> deleteSubmissionFiles(String sid) async {
    final dir = Directory(submissionPath(sid));
    if (!await dir.exists()) return false;
    for (final name in ['submission.md', 'submission.edit.md', 'images']) {
      final path = p.join(dir.path, name);
      // Een verwijzing naar een map wordt zelf verwijderd, nooit gevolgd: wat erachter
      // ligt is niet van de werkmap (de test hieronder bewaakt dat).
      if (await FileSystemEntity.isDirectory(path)) {
        await Directory(path).delete(recursive: true);
      } else if (await File(path).exists()) {
        await File(path).delete();
      }
    }
    return true;
  }

  // ── register ──────────────────────────────────────────────────────────────

  /// Het register zoals het op schijf staat, of `null` als er nog geen is.
  Future<FormRegisterRead?> readRegister() async {
    final file = File(registerPath);
    if (!await file.exists()) return null;
    final text = await _readText(file);
    if (text == null) return const FormRegisterDamaged('not UTF-8');
    return FormRegister.parse(text);
  }

  /// Bewaart [register]. Een register dat er al is maar niet te lezen valt wordt niet
  /// overschreven (`false`): wat iemand daar schreef gaat niet verloren omdat een
  /// programma er niets van begrijpt.
  Future<bool> saveRegister(FormRegister register) async {
    if (await readRegister() case FormRegisterDamaged()) return false;
    try {
      await Directory(root).create(recursive: true);
      await writeStringAtomic(File(registerPath), register.toMarkdown());
      return true;
    } on FileSystemException {
      return false;
    }
  }

  // ── intern ────────────────────────────────────────────────────────────────

  static int _landings = 0;

  Future<void> _write(Directory base, String relative, Uint8List bytes) async {
    final file = File(p.join(base.path, relative));
    await file.parent.create(recursive: true);
    await writeBytesAtomic(file, bytes);
  }
}

FormSpec? _specOf(String text) => switch (parseForm(text)) {
  ParsedForm(:final spec, canFill: true) => spec,
  _ => null,
};

/// Een taalcode die als bestandsnaamdeel kan: `nl`, `en`, `pt-br`.
bool _langOk(String lang) =>
    RegExp(r'^[a-z]{2,3}(?:-[a-z0-9]{2,8})*$').hasMatch(lang);

Future<String?> _readText(File file) async {
  final bytes = await _readBytes(file);
  return bytes == null ? null : _decode(bytes);
}

Future<Uint8List?> _readBytes(File file) async {
  try {
    return await file.readAsBytes();
  } on FileSystemException {
    return null;
  }
}

String? _decode(Uint8List bytes) {
  try {
    return const Utf8Decoder().convert(bytes);
  } on FormatException {
    return null;
  }
}
