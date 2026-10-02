/// The submission package (FORM_INTAKE.md §5.2–§5.4): a **plain zip** whose interior
/// is readable without OciDeck — the filled template, a manifest, and the photos.
///
/// ```
/// submission.md
/// manifest.json
/// images/<field-id>-<n>.(jpg|png|webp|heic)
/// ```
///
/// [buildFormPackage] makes one on the respondent's side; [readFormPackage] opens
/// one on the organiser's side, and *that* is the part that meets hostile input, so
/// it is written fail-closed and does not trust the zip library with the dangerous
/// parts: it reads the central directory itself (so a duplicate entry name cannot be
/// collapsed away by a library that keeps the first one), refuses what the grammar
/// of §5.4 does not name (a directory, a symlink, an encrypted entry, a `..`),
/// checks that no two entries share bytes, and inflates every entry with a **cap**
/// (its claimed size) so a header that lies about the size cannot make the
/// decompressor produce gigabytes.
///
/// What is checked here is the *package*: names, sizes, the manifest and the hashes
/// it holds. Whether the form is the right one, whether the answers are valid and
/// whether the template text is intact are the validator's questions
/// ([validateForm], [templateTextIssues]), asked of what a package contains.
library;

import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart' as crypto;

import 'form_answer_safety.dart';
import 'form_answers.dart';
import 'form_spec.dart';

/// The manifest version this engine writes and reads.
const int kFormManifestVersion = 1;

const String kSubmissionFileName = 'submission.md';
const String kManifestFileName = 'manifest.json';

/// The limits of §5.4. The defaults are the hard caps; a form or a server may lower
/// them, never raise them past these.
class FormPackageLimits {
  const FormPackageLimits({
    this.maxFiles = 64,
    this.maxImageBytes = 25 * 1024 * 1024,
    this.maxPackageBytes = 120 * 1024 * 1024,
    this.maxExtractedBytes = 160 * 1024 * 1024,
    this.maxTextBytes = 4 * 1024 * 1024,
  });

  final int maxFiles;
  final int maxImageBytes;

  /// The size of the zip itself.
  final int maxPackageBytes;

  /// The sum of the sizes of everything in it, counted while extracting.
  final int maxExtractedBytes;

  /// `submission.md` and `manifest.json` each.
  final int maxTextBytes;
}

// ── identifiers and hashes ──────────────────────────────────────────────────

const String _base32 = 'abcdefghijklmnopqrstuvwxyz234567';

/// 128 random bits as 26 characters of `[a-z2-7]`, with no time component
/// (§5.3): the id is visible in file names and receipts, so it must say nothing
/// about when it was made.
String newFormId(Random random) {
  final bytes = [for (var i = 0; i < 16; i++) random.nextInt(256)];
  var bits = 0;
  var value = 0;
  final out = StringBuffer();
  for (final b in bytes) {
    value = (value << 8) | b;
    bits += 8;
    while (bits >= 5) {
      out.write(_base32[(value >> (bits - 5)) & 31]);
      bits -= 5;
    }
    value &= (1 << bits) - 1;
  }
  if (bits > 0) out.write(_base32[(value << (5 - bits)) & 31]);
  return out.toString();
}

/// Whether [id] is a submission or form id: exactly 26 characters `[a-z2-7]`.
bool isValidFormId(String id) => RegExp(r'^[a-z2-7]{26}$').hasMatch(id);

/// The lower-case hex SHA-256 of [bytes].
String sha256Hex(List<int> bytes) => crypto.sha256.convert(bytes).toString();

/// The hash of a template as the bundle and the manifest define it (§5.1): over the
/// **decoded text** — a Unicode string with any BOM removed, line endings as they
/// are, encoded as UTF-8 — and not over raw file bytes, which a BOM-dropping round
/// trip would change.
String formTemplateHash(String template) => sha256Hex(
  utf8.encode(template.startsWith('﻿') ? template.substring(1) : template),
);

/// The consent text of [field] as it is hashed: what the template says between the
/// field marker and the answer marker, line endings as LF, trimmed (§5.3, §4.6).
String consentTextOf(String template, FormFieldSpec field) => template
    .substring(field.label.start, field.label.end)
    .replaceAll('\r\n', '\n')
    .trim();

// ── the manifest ────────────────────────────────────────────────────────────

class FormManifestFile {
  const FormManifestFile(this.path, this.sha256, this.bytes);

  final String path;
  final String sha256;
  final int bytes;

  Map<String, Object?> toJson() => {
    'path': path,
    'sha256': sha256,
    'bytes': bytes,
  };
}

class FormManifestConsent {
  const FormManifestConsent(this.field, this.accepted, this.textSha256);

  final String field;

  /// A day, `YYYY-MM-DD`: day precision only (§5.3).
  final String accepted;
  final String textSha256;

  Map<String, Object?> toJson() => {
    'field': field,
    'accepted': accepted,
    'text_sha256': textSha256,
  };
}

/// `manifest.json`: only what the form itself asks for, plus integrity data — no
/// device id, no IP, no telemetry.
class FormPackageManifest {
  const FormPackageManifest({
    required this.submissionId,
    required this.formId,
    required this.formVersion,
    required this.formRules,
    required this.templateSha256,
    required this.created,
    required this.clientName,
    this.clientVersion,
    required this.clientRules,
    required this.files,
    required this.consent,
  });

  final String submissionId;
  final String formId;
  final int formVersion;
  final int formRules;
  final String templateSha256;

  /// A day, `YYYY-MM-DD`.
  final String created;
  final String clientName;
  final String? clientVersion;
  final int clientRules;
  final List<FormManifestFile> files;
  final List<FormManifestConsent> consent;

  Map<String, Object?> toJson() => {
    'v': kFormManifestVersion,
    'submission_id': submissionId,
    'form': {
      'id': formId,
      'version': formVersion,
      'rules': formRules,
      'template_sha256': templateSha256,
    },
    'created': created,
    'client': {
      'name': clientName,
      'version': ?clientVersion,
      'rules': clientRules,
    },
    'files': [for (final f in files) f.toJson()],
    'consent': [for (final c in consent) c.toJson()],
  };

  String toJsonText() => const JsonEncoder.withIndent('  ').convert(toJson());
}

// ── problems ────────────────────────────────────────────────────────────────

/// What can be wrong with a package as a package. Stable wire names, like
/// [FormIssueCode]; the organiser's Inbox keys its messages on them.
enum FormPackageIssue {
  /// Not a zip this engine reads: truncated, zip64, multi-disk, a bad directory.
  badZip('bad-zip'),

  /// More entries than the limit allows.
  tooManyFiles('too-many-files'),

  /// The zip, an entry or the sum of the entries is beyond its limit.
  tooLarge('too-large'),

  /// An entry name outside the grammar of §5.4, or a directory, a symlink, an
  /// encrypted or unreadable entry.
  badEntry('bad-entry'),

  /// Two entries with the same name.
  duplicateEntry('duplicate-entry'),

  /// Two entries share bytes of the file, or an entry points outside it.
  overlappingEntries('overlapping-entries'),

  /// An entry that does not inflate to what its header says, or whose checksum is
  /// wrong.
  corruptEntry('corrupt-entry'),

  missingSubmission('missing-submission'),
  missingManifest('missing-manifest'),

  /// `manifest.json` is not JSON, or not a manifest of this version.
  badManifest('bad-manifest'),

  /// An entry the manifest does not list.
  fileNotListed('file-not-listed'),

  /// A file the manifest lists and the package lacks.
  fileMissing('file-missing'),

  /// An entry whose hash or size is not what the manifest says.
  hashMismatch('hash-mismatch');

  const FormPackageIssue(this.wireName);

  final String wireName;
}

class FormPackageProblem {
  const FormPackageProblem(this.issue, {this.path, this.detail});

  final FormPackageIssue issue;

  /// The entry it is about, when it is about one.
  final String? path;

  /// A short plain-English reason for a log; never shown to a respondent as is.
  final String? detail;

  @override
  String toString() =>
      '${issue.wireName}${path == null ? '' : ' [$path]'}'
      '${detail == null ? '' : ': $detail'}';
}

// ── building ────────────────────────────────────────────────────────────────

/// One consent, as the manifest records it, for every consent field of [spec] the
/// respondent has accepted in [submission].
List<FormManifestConsent> consentsAccepted({
  required FormSpec spec,
  required String template,
  required String submission,
  required String day,
}) {
  final answers = extractAnswers(spec, submission);
  return [
    for (final field in spec.fields)
      if (field.type == 'consent' && answers.byId[field.id]?.consent == true)
        FormManifestConsent(
          field.id,
          day,
          sha256Hex(utf8.encode(consentTextOf(template, field))),
        ),
  ];
}

/// The day as `YYYY-MM-DD`, in UTC.
String formDay(DateTime when) {
  final d = when.toUtc();
  String two(int n) => n.toString().padLeft(2, '0');
  return '${d.year.toString().padLeft(4, '0')}-${two(d.month)}-${two(d.day)}';
}

/// The time stamp every entry carries: 1980-01-01 00:00, the earliest a zip can
/// say. A package must not tell when it was made beyond the day the manifest
/// states.
final DateTime _zipEpoch = DateTime.utc(1980);

/// Builds the package of [submission]: the filled template, its photos and a
/// manifest that holds the hash of each.
///
/// [images] are the photos by path (`images/<field>-<n>.<ext>`), already cleaned;
/// only the ones the submission refers to belong here, and the caller passes
/// exactly those. [template] is the *published* template the respondent filled, for
/// its hash and for the consent texts. The result is deterministic: the same inputs
/// give the same bytes, which is what makes "verify with `sha256sum`" honest.
///
/// Throws [ArgumentError] when what is asked is not a package this engine would
/// itself open: an id or a name outside the grammar, too many files, an image over
/// its limit. A client must not make a package its own organiser refuses.
Uint8List buildFormPackage({
  required String submission,
  required String template,
  required FormSpec spec,
  required Map<String, Uint8List> images,
  required String submissionId,
  required DateTime created,
  String clientName = 'OciDeck',
  String? clientVersion,
  required int clientRules,
  FormPackageLimits limits = const FormPackageLimits(),
}) {
  if (!isValidFormId(submissionId)) {
    throw ArgumentError.value(submissionId, 'submissionId', 'not a 26-char id');
  }
  if (images.length + 2 > limits.maxFiles) {
    throw ArgumentError.value(images.length, 'images', 'too many files');
  }
  for (final entry in images.entries) {
    if (!kFormImagePath.hasMatch(entry.key)) {
      throw ArgumentError.value(
        entry.key,
        'images',
        'not a package image name',
      );
    }
    if (entry.value.length > limits.maxImageBytes) {
      throw ArgumentError.value(entry.key, 'images', 'over the image limit');
    }
  }

  final submissionBytes = Uint8List.fromList(utf8.encode(submission));
  final day = formDay(created);
  final names = images.keys.toList()..sort();
  final manifest = FormPackageManifest(
    submissionId: submissionId,
    formId: spec.id,
    formVersion: spec.version,
    formRules: spec.rules,
    templateSha256: formTemplateHash(template),
    created: day,
    clientName: clientName,
    clientVersion: clientVersion,
    clientRules: clientRules,
    files: [
      FormManifestFile(
        kSubmissionFileName,
        sha256Hex(submissionBytes),
        submissionBytes.length,
      ),
      for (final name in names)
        FormManifestFile(name, sha256Hex(images[name]!), images[name]!.length),
    ],
    consent: consentsAccepted(
      spec: spec,
      template: template,
      submission: submission,
      day: day,
    ),
  );
  final manifestBytes = Uint8List.fromList(utf8.encode(manifest.toJsonText()));

  ArchiveFile entry(String name, Uint8List bytes, {required bool deflate}) =>
      ArchiveFile.bytes(
        name,
        bytes,
      )..compression = deflate ? CompressionType.deflate : CompressionType.none;

  final archive = Archive()
    ..add(entry(kSubmissionFileName, submissionBytes, deflate: true))
    ..add(entry(kManifestFileName, manifestBytes, deflate: true));
  for (final name in names) {
    // A photo is already compressed; deflating it again costs time and gains nothing.
    archive.add(entry(name, images[name]!, deflate: false));
  }
  return Uint8List.fromList(ZipEncoder().encode(archive, modified: _zipEpoch));
}

// ── reading ─────────────────────────────────────────────────────────────────

/// The outcome of [readFormPackage].
sealed class FormPackageRead {
  const FormPackageRead();
}

/// A package that is a package: every entry is in the grammar, every size and hash
/// is what the manifest says.
class FormPackageOpened extends FormPackageRead {
  const FormPackageOpened({
    required this.manifest,
    required this.manifestBytes,
    required this.submission,
    required this.submissionBytes,
    required this.images,
  });

  final FormPackageManifest manifest;

  /// `manifest.json` exactly as it was received. An organiser keeps these bytes, not
  /// a rewriting of them: the manifest's hashes make the package verifiable with
  /// `sha256sum`, and that only stays true for what was never touched (§5.3, §7.1).
  final Uint8List manifestBytes;

  /// `submission.md` exactly as it was received, for the same reason.
  final Uint8List submissionBytes;

  /// `submission.md`, decoded from UTF-8.
  final String submission;

  /// The photos by path, as received.
  final Map<String, Uint8List> images;
}

/// A package that is refused, with every reason found. Nothing in it is trusted.
class FormPackageRefused extends FormPackageRead {
  const FormPackageRefused(this.problems);

  final List<FormPackageProblem> problems;
}

class _Entry {
  _Entry(
    this.name,
    this.method,
    this.crc,
    this.compressed,
    this.size,
    this.dataStart,
  );

  final String name;
  final int method;
  final int crc;
  final int compressed;
  final int size;
  final int dataStart;
}

class _Refuse implements Exception {
  const _Refuse(this.problems);

  final List<FormPackageProblem> problems;
}

/// Opens [bytes] as a package, or refuses it. Never throws.
FormPackageRead readFormPackage(
  Uint8List bytes, {
  FormPackageLimits limits = const FormPackageLimits(),
}) {
  try {
    return _read(bytes, limits);
  } on _Refuse catch (r) {
    return FormPackageRefused(r.problems);
  } on RangeError {
    return const FormPackageRefused([
      FormPackageProblem(FormPackageIssue.badZip, detail: 'truncated'),
    ]);
  }
}

Never _fail(FormPackageIssue issue, {String? path, String? detail}) =>
    throw _Refuse([FormPackageProblem(issue, path: path, detail: detail)]);

FormPackageRead _read(Uint8List b, FormPackageLimits limits) {
  if (b.length > limits.maxPackageBytes) {
    _fail(FormPackageIssue.tooLarge, detail: 'the package');
  }
  final entries = _centralDirectory(b, limits);

  // The names first, all of them: a package with a bad name is refused before any
  // byte of it is inflated.
  final problems = <FormPackageProblem>[];
  final seen = <String>{};
  for (final e in entries) {
    if (!_validName(e.name)) {
      problems.add(FormPackageProblem(FormPackageIssue.badEntry, path: e.name));
    } else if (!seen.add(e.name)) {
      problems.add(
        FormPackageProblem(FormPackageIssue.duplicateEntry, path: e.name),
      );
    }
  }
  if (problems.isNotEmpty) throw _Refuse(problems);

  var total = 0;
  for (final e in entries) {
    final cap = e.name.startsWith('images/')
        ? limits.maxImageBytes
        : limits.maxTextBytes;
    if (e.size > cap) {
      _fail(FormPackageIssue.tooLarge, path: e.name, detail: 'the entry');
    }
    total += e.size;
    if (total > limits.maxExtractedBytes) {
      _fail(FormPackageIssue.tooLarge, detail: 'extracted bytes');
    }
  }

  final contents = <String, Uint8List>{
    for (final e in entries) e.name: _extract(b, e),
  };

  if (!contents.containsKey(kSubmissionFileName)) {
    _fail(FormPackageIssue.missingSubmission);
  }
  if (!contents.containsKey(kManifestFileName)) {
    _fail(FormPackageIssue.missingManifest);
  }
  final manifest = _parseManifest(contents[kManifestFileName]!);
  _checkAgainst(manifest, contents);

  final String text;
  try {
    text = const Utf8Decoder().convert(contents[kSubmissionFileName]!);
  } on FormatException {
    _fail(
      FormPackageIssue.corruptEntry,
      path: kSubmissionFileName,
      detail: 'not UTF-8',
    );
  }
  return FormPackageOpened(
    manifest: manifest,
    manifestBytes: contents[kManifestFileName]!,
    submission: text,
    submissionBytes: contents[kSubmissionFileName]!,
    images: {
      for (final e in contents.entries)
        if (e.key.startsWith('images/')) e.key: e.value,
    },
  );
}

bool _validName(String name) =>
    name == kSubmissionFileName ||
    name == kManifestFileName ||
    kFormImagePath.hasMatch(name);

int _u16(Uint8List b, int at) => b[at] | (b[at + 1] << 8);

int _u32(Uint8List b, int at) =>
    b[at] | (b[at + 1] << 8) | (b[at + 2] << 16) | (b[at + 3] << 24);

/// Reads the central directory of [b] — and only that — into entries, refusing
/// anything this engine does not read.
List<_Entry> _centralDirectory(Uint8List b, FormPackageLimits limits) {
  // The end-of-central-directory record, searched backwards past a comment.
  var eocd = -1;
  final first = max(0, b.length - 22 - 0xFFFF);
  for (var i = b.length - 22; i >= first; i--) {
    if (_u32(b, i) == 0x06054b50) {
      eocd = i;
      break;
    }
  }
  if (eocd < 0) _fail(FormPackageIssue.badZip, detail: 'no directory');
  final disk = _u16(b, eocd + 4);
  final cdDisk = _u16(b, eocd + 6);
  final onDisk = _u16(b, eocd + 8);
  final count = _u16(b, eocd + 10);
  final cdOffset = _u32(b, eocd + 16);
  if (disk != 0 || cdDisk != 0 || onDisk != count) {
    _fail(FormPackageIssue.badZip, detail: 'multi-disk');
  }
  if (count == 0xFFFF) _fail(FormPackageIssue.badZip, detail: 'zip64');
  if (count > limits.maxFiles) {
    _fail(FormPackageIssue.tooManyFiles);
  }
  final entries = <_Entry>[];
  var at = cdOffset;
  for (var i = 0; i < count; i++) {
    if (at + 46 > b.length || _u32(b, at) != 0x02014b50) {
      _fail(FormPackageIssue.badZip, detail: 'directory entry');
    }
    final madeBy = _u16(b, at + 4);
    final flags = _u16(b, at + 8);
    final method = _u16(b, at + 10);
    final crc = _u32(b, at + 16);
    final compressed = _u32(b, at + 20);
    final size = _u32(b, at + 24);
    final nameLength = _u16(b, at + 28);
    final extraLength = _u16(b, at + 30);
    final commentLength = _u16(b, at + 32);
    final externalAttributes = _u32(b, at + 38);
    final localOffset = _u32(b, at + 42);
    if (at + 46 + nameLength > b.length) {
      _fail(FormPackageIssue.badZip, detail: 'name out of range');
    }
    final name = latin1.decode(b.sublist(at + 46, at + 46 + nameLength));
    at += 46 + nameLength + extraLength + commentLength;

    if (flags & 0x0001 != 0 || flags & 0x0040 != 0) {
      _fail(FormPackageIssue.badEntry, path: name, detail: 'encrypted');
    }
    if (method != 0 && method != 8) {
      _fail(FormPackageIssue.badEntry, path: name, detail: 'compression');
    }
    // A symbolic link, by the Unix mode a zip made on Unix carries in the high
    // half of the external attributes.
    if (madeBy >> 8 == 3 && ((externalAttributes >> 16) & 0xF000) == 0xA000) {
      _fail(FormPackageIssue.badEntry, path: name, detail: 'symlink');
    }
    // The local header: it must say the same name, and tells where the data starts.
    if (localOffset + 30 > b.length || _u32(b, localOffset) != 0x04034b50) {
      _fail(FormPackageIssue.badZip, detail: 'local header');
    }
    final localName = _u16(b, localOffset + 26);
    final localExtra = _u16(b, localOffset + 28);
    final dataStart = localOffset + 30 + localName + localExtra;
    if (localOffset + 30 + localName > b.length ||
        latin1.decode(
              b.sublist(localOffset + 30, localOffset + 30 + localName),
            ) !=
            name) {
      _fail(
        FormPackageIssue.badEntry,
        path: name,
        detail: 'local name differs',
      );
    }
    entries.add(_Entry(name, method, crc, compressed, size, dataStart));
  }

  // No two entries may share bytes, and none may reach outside the file: a zip
  // that overlaps its entries is a way to make a small file claim a huge one.
  final byStart = [...entries]..sort((x, y) => x.dataStart - y.dataStart);
  var end = 0;
  for (final e in byStart) {
    if (e.dataStart < end || e.dataStart + e.compressed > cdOffset) {
      _fail(FormPackageIssue.overlappingEntries, path: e.name);
    }
    end = e.dataStart + e.compressed;
  }
  return entries;
}

/// Inflates one entry under its own claimed size as the cap, and checks the size
/// and the checksum it came out as.
Uint8List _extract(Uint8List b, _Entry e) {
  final raw = Uint8List.sublistView(b, e.dataStart, e.dataStart + e.compressed);
  final Uint8List out;
  if (e.method == 0) {
    out = Uint8List.fromList(raw);
  } else {
    final sink = _CappedOutput(e.size);
    try {
      Inflate(raw, output: sink);
    } on _TooMuch {
      _fail(
        FormPackageIssue.corruptEntry,
        path: e.name,
        detail: 'inflates past its size',
      );
    } on Object {
      _fail(FormPackageIssue.corruptEntry, path: e.name, detail: 'inflate');
    }
    out = sink.getBytes();
  }
  if (out.length != e.size || getCrc32(out) != e.crc) {
    _fail(FormPackageIssue.corruptEntry, path: e.name, detail: 'size or crc');
  }
  return out;
}

class _TooMuch implements Exception {
  const _TooMuch();
}

/// An output buffer that refuses to hold more than [cap] bytes, so a deflate stream
/// that inflates far past what its header claimed stops at the claim instead of
/// filling memory.
class _CappedOutput extends OutputMemoryStream {
  _CappedOutput(this.cap) : super(size: cap < 32 ? 32 : cap);

  final int cap;

  void _room(int more) {
    if (length + more > cap) throw const _TooMuch();
  }

  @override
  void writeByte(int value) {
    _room(1);
    super.writeByte(value);
  }

  @override
  void writeBytes(List<int> bytes, {int? length}) {
    _room(length ?? bytes.length);
    super.writeBytes(bytes, length: length);
  }

  @override
  void writeStream(InputStream stream) {
    _room(stream.length);
    super.writeStream(stream);
  }
}

// ── the manifest, strictly ──────────────────────────────────────────────────

/// Reads `manifest.json` on its own — the organiser keeps the manifest beside a
/// landed submission and judges it again later — or `null` when it is not a manifest
/// of this version. Only the manifest is checked, not the files it lists: that was
/// done when the package was opened.
FormPackageManifest? readFormManifest(Uint8List bytes) {
  try {
    return _parseManifest(bytes);
  } on _Refuse {
    return null;
  }
}

FormPackageManifest _parseManifest(Uint8List bytes) {
  Never bad(String why) =>
      _fail(FormPackageIssue.badManifest, path: kManifestFileName, detail: why);

  final Object? json;
  try {
    json = jsonDecode(const Utf8Decoder().convert(bytes));
  } on FormatException {
    bad('not JSON');
  }
  if (json is! Map<String, Object?>) bad('not an object');

  Map<String, Object?> object(Object? v, String what) =>
      v is Map<String, Object?> ? v : bad(what);
  String text(Object? v, String what) => v is String ? v : bad(what);
  int number(Object? v, String what) => v is int ? v : bad(what);
  final day = RegExp(r'^\d{4}-\d{2}-\d{2}$');
  final hash = RegExp(r'^[0-9a-f]{64}$');

  if (json['v'] != kFormManifestVersion) bad('version');
  final id = text(json['submission_id'], 'submission_id');
  if (!isValidFormId(id)) bad('submission_id');
  final form = object(json['form'], 'form');
  final client = object(json['client'], 'client');
  final created = text(json['created'], 'created');
  if (!day.hasMatch(created)) bad('created');
  final templateHash = text(form['template_sha256'], 'template_sha256');
  if (!hash.hasMatch(templateHash)) bad('template_sha256');

  final filesJson = json['files'];
  final consentJson = json['consent'];
  if (filesJson is! List || consentJson is! List) bad('files/consent');

  final files = <FormManifestFile>[];
  for (final f in filesJson) {
    final o = object(f, 'file');
    final sha = text(o['sha256'], 'file sha256');
    if (!hash.hasMatch(sha)) bad('file sha256');
    files.add(
      FormManifestFile(
        text(o['path'], 'file path'),
        sha,
        number(o['bytes'], 'file bytes'),
      ),
    );
  }
  final consent = <FormManifestConsent>[];
  for (final c in consentJson) {
    final o = object(c, 'consent');
    final accepted = text(o['accepted'], 'consent accepted');
    final sha = text(o['text_sha256'], 'consent hash');
    if (!day.hasMatch(accepted) || !hash.hasMatch(sha)) bad('consent');
    consent.add(
      FormManifestConsent(text(o['field'], 'consent field'), accepted, sha),
    );
  }
  final version = client['version'];
  if (version != null && version is! String) bad('client version');

  return FormPackageManifest(
    submissionId: id,
    formId: text(form['id'], 'form id'),
    formVersion: number(form['version'], 'form version'),
    formRules: number(form['rules'], 'form rules'),
    templateSha256: templateHash,
    created: created,
    clientName: text(client['name'], 'client name'),
    clientVersion: version as String?,
    clientRules: number(client['rules'], 'client rules'),
    files: files,
    consent: consent,
  );
}

/// The manifest and the package must list the same files, with the hashes and sizes
/// the manifest says (§5.3): "verify with `sha256sum`" holds only if they do.
void _checkAgainst(
  FormPackageManifest manifest,
  Map<String, Uint8List> contents,
) {
  final problems = <FormPackageProblem>[];
  final listed = <String>{};
  for (final file in manifest.files) {
    if (!listed.add(file.path)) {
      problems.add(
        FormPackageProblem(
          FormPackageIssue.badManifest,
          path: file.path,
          detail: 'listed twice',
        ),
      );
      continue;
    }
    final bytes = contents[file.path];
    if (bytes == null || file.path == kManifestFileName) {
      problems.add(
        FormPackageProblem(FormPackageIssue.fileMissing, path: file.path),
      );
    } else if (bytes.length != file.bytes || sha256Hex(bytes) != file.sha256) {
      problems.add(
        FormPackageProblem(FormPackageIssue.hashMismatch, path: file.path),
      );
    }
  }
  for (final name in contents.keys) {
    if (name != kManifestFileName && !listed.contains(name)) {
      problems.add(
        FormPackageProblem(FormPackageIssue.fileNotListed, path: name),
      );
    }
  }
  if (problems.isNotEmpty) throw _Refuse(problems);
}
