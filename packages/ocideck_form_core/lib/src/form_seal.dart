/// Sealing (FORM_INTAKE.md §5.6): a sealed package is the plain zip of §5.2 inside an
/// [age](https://age-encryption.org) v1 file with **X25519 recipients**.
///
/// **This is the one file that touches the age implementation** (`package:dartage`); the
/// `check_packages` gate keeps it so. Everything the rest of the engine needs — a key
/// pair, the recipient of an identity, sealing, opening — goes through here, and what
/// comes out is a result, never an exception from the library underneath.
///
/// ## What is and is not sealed
///
/// Sealing gives confidentiality and integrity of the package. It does **not**
/// authenticate the sender (§5.7): the organisers' recipients are public by design, so
/// anyone can seal a package for any `sid`. The maker check (§7.4) is the control for that.
///
/// ## A deliberate subset
///
/// Only the **binary** format with **native X25519** recipients is read and written.
/// Passphrases (scrypt), armor, and the other recipient types the library knows (hybrid
/// post-quantum, tag) are refused, not ignored: a sealed package opened by anything this
/// engine did not choose is a package whose protection nobody reviewed. A file made by
/// the reference `age` tool for an `age1…` recipient opens here, and the other way round.
///
/// ## Binding the plaintext to its context
///
/// `age` has no associated data, so the binding is done by what is inside (§5.6): after
/// opening, [openSealedPackage] requires the manifest's `submission_id`, `form.id` and
/// `form.version` to equal what the caller *asked for*. A ciphertext a server moved from
/// form A to form B of the same organiser opens fine — and fails that check.
///
/// ## Limits
///
/// The ciphertext is bounded before anything is decrypted ([maxSealedBytes]), and the
/// header is bounded by [kFormMaxAgeHeaderBytes] — a hostile file cannot ask for work or
/// memory the format does not need.
library;

import 'dart:typed_data';

import 'package:dartage/dartage.dart';

import 'form_package.dart';

/// The suffix of a sealed package's file name: `<sid>.zip.age`.
const String kSealedSuffix = '.zip.age';

/// The most bytes an age header may take here. One X25519 stanza is about 200 bytes;
/// this leaves room for a few hundred organisers and not for a hostile megabyte.
const int kFormMaxAgeHeaderBytes = 64 * 1024;

/// The most recipients a package is sealed to. An organiser team is four to six people
/// (§7.6); more is a mistake, and each recipient costs a stanza in every package.
const int kFormMaxRecipients = 64;

/// The age STREAM layout: 64 KiB of plaintext per chunk, 16 bytes of tag each, behind a
/// 16-byte file nonce.
const int _chunk = 65536;
const int _tag = 16;
const int _nonce = 16;

/// The most bytes a sealed file may take for packages of at most
/// [FormPackageLimits.maxPackageBytes]: the header budget, the nonce, and a tag per chunk.
int maxSealedBytes([FormPackageLimits limits = const FormPackageLimits()]) {
  final chunks = (limits.maxPackageBytes + _chunk - 1) ~/ _chunk + 1;
  return kFormMaxAgeHeaderBytes +
      _nonce +
      limits.maxPackageBytes +
      chunks * _tag;
}

// ── keys ────────────────────────────────────────────────────────────────────

/// A fresh age identity: `AGE-SECRET-KEY-1…`, upper case. It is the secret; the
/// organiser keeps it in the keychain and can export it as it stands, so a sealed file
/// can be opened without OciDeck (§5.9).
String generateAgeIdentity() => X25519Identity.generate().encoded;

/// The `age1…` recipient of [identity], or `null` if [identity] is not an X25519 identity
/// in the canonical form.
Future<String?> ageRecipientOf(String identity) async {
  try {
    return (await X25519Identity.parse(identity).recipient()).encoded;
  } on AgeException {
    return null;
  }
}

/// Whether [text] is an `age1…` X25519 recipient in the canonical (lower case) form.
bool isAgeRecipient(String text) {
  try {
    X25519Recipient.parse(text);
    return true;
  } on AgeException {
    return false;
  }
}

/// Whether [text] is an `AGE-SECRET-KEY-1…` X25519 identity in the canonical (upper case)
/// form.
bool isAgeIdentity(String text) {
  try {
    X25519Identity.parse(text);
    return true;
  } on AgeException {
    return false;
  }
}

// ── sealing ─────────────────────────────────────────────────────────────────

/// What [sealFormPackage] could not do.
enum FormSealIssue {
  /// No recipient at all: a package nobody can open.
  noRecipients,

  /// More recipients than [kFormMaxRecipients].
  tooManyRecipients,

  /// A recipient that is not an `age1…` X25519 recipient.
  badRecipient,

  /// The bytes are not a package this engine reads — it will not seal what it would
  /// itself refuse to open.
  notAPackage,
}

/// The outcome of [sealFormPackage].
sealed class FormSealResult {
  const FormSealResult();
}

/// A sealed package.
class FormSealed extends FormSealResult {
  const FormSealed({
    required this.bytes,
    required this.sha256,
    required this.submissionId,
    required this.fileName,
  });

  /// The age file.
  final Uint8List bytes;

  /// The lower-case hex SHA-256 of [bytes]: what an organiser's client records per `sid`
  /// at first fetch, and flags as `replaced` when it changes (§5.6).
  final String sha256;

  final String submissionId;

  /// `<sid>.zip.age`.
  final String fileName;
}

/// A package that was not sealed, and why.
class FormSealRefused extends FormSealResult {
  const FormSealRefused(this.issue, {this.detail});

  final FormSealIssue issue;

  /// A short reason for a log; never a key.
  final String? detail;
}

/// Seals the package [zip] to [recipients] (`age1…` strings). Never throws.
///
/// The zip is read first ([readFormPackage]): a client that would refuse a package on
/// arrival should not be able to send one. Recipients that repeat are sealed to once.
Future<FormSealResult> sealFormPackage(
  Uint8List zip, {
  required List<String> recipients,
  FormPackageLimits limits = const FormPackageLimits(),
}) async {
  if (recipients.isEmpty) {
    return const FormSealRefused(FormSealIssue.noRecipients);
  }
  final parsed = <String, X25519Recipient>{};
  for (final text in recipients) {
    try {
      final recipient = X25519Recipient.parse(text);
      parsed[recipient.encoded] = recipient;
    } on AgeException {
      return const FormSealRefused(FormSealIssue.badRecipient);
    }
  }
  if (parsed.length > kFormMaxRecipients) {
    return const FormSealRefused(FormSealIssue.tooManyRecipients);
  }
  final read = readFormPackage(zip, limits: limits);
  if (read is! FormPackageOpened) {
    return FormSealRefused(
      FormSealIssue.notAPackage,
      detail: read is FormPackageRefused
          ? read.problems.map((p) => p.issue.wireName).join(', ')
          : null,
    );
  }
  final sealed = await AgeEncrypter(recipients: parsed.values).encrypt(zip);
  final sid = read.manifest.submissionId;
  return FormSealed(
    bytes: sealed,
    sha256: sha256Hex(sealed),
    submissionId: sid,
    fileName: '$sid$kSealedSuffix',
  );
}

// ── opening ─────────────────────────────────────────────────────────────────

/// Why a sealed file was not opened. Every one is a refusal: nothing is partly opened.
enum FormUnsealIssue {
  /// The file is larger than a sealed package can be ([maxSealedBytes]).
  tooLarge,

  /// Not an age v1 binary file, or a header that does not parse — an armored file, a
  /// truncated header, a stanza that is not well formed.
  notAge,

  /// An identity that is not an `AGE-SECRET-KEY-1…` X25519 identity, or none at all: the
  /// caller's own key store is broken, not the file.
  badIdentity,

  /// The header parses, and none of the recipient stanzas is for any of the identities:
  /// the wrong key, a package sealed to other organisers, or a type of recipient this
  /// engine does not read.
  noIdentityMatched,

  /// Something that authenticates did not: the header MAC, a chunk, a missing or extra
  /// final chunk. The file was changed, cut short or never was an age file for this key.
  tampered,

  /// It opened, and what is inside is not a package this engine reads.
  notAPackage,

  /// It opened, and the manifest names another submission than the one asked for.
  wrongSubmission,

  /// It opened, and the manifest names another form or version than the one asked for.
  wrongForm,
}

/// The outcome of [openSealedPackage].
sealed class FormUnsealResult {
  const FormUnsealResult();
}

/// A sealed package that was opened, and is the package that was asked for.
class FormUnsealed extends FormUnsealResult {
  const FormUnsealed({
    required this.zip,
    required this.package,
    required this.sha256,
  });

  /// The plain zip — from here on nothing is proprietary.
  final Uint8List zip;

  /// The zip, read: the manifest, `submission.md` and the photos, as received.
  final FormPackageOpened package;

  /// The SHA-256 of the sealed file that was opened, in lower-case hex.
  final String sha256;
}

/// A sealed file that was not opened, and why.
class FormUnsealRefused extends FormUnsealResult {
  const FormUnsealRefused(this.issue, {this.problems = const []});

  final FormUnsealIssue issue;

  /// With [FormUnsealIssue.notAPackage]: every reason the package was refused.
  final List<FormPackageProblem> problems;
}

/// The outcome of [openAge].
sealed class FormAgeOpen {
  const FormAgeOpen();
}

/// An age file that was opened: its plaintext.
class FormAgeOpened extends FormAgeOpen {
  const FormAgeOpened(this.plaintext);

  final Uint8List plaintext;
}

/// An age file that was not opened: [issue] is one of [FormUnsealIssue.notAge],
/// [FormUnsealIssue.badIdentity], [FormUnsealIssue.noIdentityMatched] and
/// [FormUnsealIssue.tampered].
class FormAgeRefused extends FormAgeOpen {
  const FormAgeRefused(this.issue);

  final FormUnsealIssue issue;
}

/// Opens the age file [sealed] with [identities] (`AGE-SECRET-KEY-1…`): the age layer
/// alone, without asking what is inside. [openSealedPackage] is this plus the package and
/// its binding; the test vectors of the age project (`test/form_seal_vectors_test.dart`)
/// go through here. Never throws.
Future<FormAgeOpen> openAge(Uint8List sealed, List<String> identities) async {
  final parsed = <X25519Identity>[];
  try {
    for (final text in identities) {
      parsed.add(X25519Identity.parse(text));
    }
  } on AgeException {
    return const FormAgeRefused(FormUnsealIssue.badIdentity);
  }
  if (parsed.isEmpty) return const FormAgeRefused(FormUnsealIssue.badIdentity);
  try {
    final plaintext = await AgeDecrypter(
      identities: parsed,
      maxHeaderBytes: kFormMaxAgeHeaderBytes,
    ).decrypt(sealed);
    return FormAgeOpened(plaintext);
  } on AgeException catch (error) {
    return FormAgeRefused(switch (error.code) {
      AgeExceptionCode.noIdentityMatched => FormUnsealIssue.noIdentityMatched,
      AgeExceptionCode.authenticationFailed => FormUnsealIssue.tampered,
      _ => FormUnsealIssue.notAge,
    });
  }
}

/// Opens the sealed package [sealed] with [identities] and checks it is the one asked
/// for. Never throws; every failure is a [FormUnsealRefused].
///
/// [expectedSid], [expectedFormId] and [expectedFormVersion] are what the caller *asked
/// for* — the `sid` it fetched, the form it is importing for. Any that is given must
/// equal what the manifest says (§5.6).
Future<FormUnsealResult> openSealedPackage(
  Uint8List sealed, {
  required List<String> identities,
  FormPackageLimits limits = const FormPackageLimits(),
  String? expectedSid,
  String? expectedFormId,
  int? expectedFormVersion,
}) async {
  if (sealed.length > maxSealedBytes(limits)) {
    return const FormUnsealRefused(FormUnsealIssue.tooLarge);
  }
  final opened = await openAge(sealed, identities);
  if (opened is FormAgeRefused) return FormUnsealRefused(opened.issue);
  final zip = (opened as FormAgeOpened).plaintext;
  final read = readFormPackage(zip, limits: limits);
  if (read is! FormPackageOpened) {
    return FormUnsealRefused(
      FormUnsealIssue.notAPackage,
      problems: read is FormPackageRefused ? read.problems : const [],
    );
  }
  final manifest = read.manifest;
  if (expectedSid != null && manifest.submissionId != expectedSid) {
    return const FormUnsealRefused(FormUnsealIssue.wrongSubmission);
  }
  if ((expectedFormId != null && manifest.formId != expectedFormId) ||
      (expectedFormVersion != null &&
          manifest.formVersion != expectedFormVersion)) {
    return const FormUnsealRefused(FormUnsealIssue.wrongForm);
  }
  return FormUnsealed(zip: zip, package: read, sha256: sha256Hex(sealed));
}
