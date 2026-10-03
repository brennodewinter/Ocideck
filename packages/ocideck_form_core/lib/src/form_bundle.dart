/// The bundle (FORM_INTAKE.md §5.1): how a respondent learns the organisers' keys, and how
/// a loose template learns who stands behind it.
///
/// A template contains **no keys**, so on its own it can never be sealed, and a loose file
/// carries nothing to check authenticity against. The bundle — a JSON file beside the
/// template, `<template>.bundle.json`, or the same object from a server — fixes both. The
/// **form owner's Ed25519 key signs it**; the respondent checks that signature against a
/// **fingerprint that came by another road** than the bundle (§6.4): the organiser's call
/// text, or the invite link. Without one the bundle is **refused, not accepted with a
/// prompt** — a prompt would show a name taken from the very bundle being verified, which a
/// layperson cannot judge and a hostile template would always pass.
///
/// **This is one of the two files that touch the cryptographic primitives**
/// (`check_packages` rule 10); the other is `form_seal.dart`. Ed25519 comes from
/// `package:cryptography`, SHA-256 from `package:crypto`.
///
/// ## Details the design left open, as built
///
/// * **Encodings.** Every binary field is lower-case base32 without padding ([base32Encode]):
///   `sign` (a 32-byte public key, 52 characters), `sig` (64 bytes, 103), `kid` (16 bytes,
///   26 — the grammar of a `sid`) and the fingerprint (32 bytes, 52). Hashes stay hex, as in
///   the manifest.
/// * **The fingerprint** is the SHA-256 of the owner's 32-byte public key, in the same base32
///   ([formKeyFingerprint]); people write it in groups of four ([formatFingerprint]) and
///   [normalizeFingerprint] reads it back whichever way it was typed.
/// * **Who is the owner.** The signer is the organiser whose `sign` key hashes to the
///   fingerprint. The owner is therefore one of `organisers`; a bundle whose listed keys
///   include none that matches is a [FormBundleIssue.fingerprintMismatch].
/// * **`kid`** is derived, never chosen: the first 128 bits of the SHA-256 of the organiser's
///   canonical `age1…` recipient, as base32 ([organiserKid]). A bundle that carries another
///   value is refused, so a server cannot attribute a key to an organiser who does not hold it.
/// * **The signature** is Ed25519 over `ocideck-intake-bundle-v1\n` followed by the JCS
///   ([canonicalJson]) of the object **without `sig`**. The tag keeps it apart from request
///   signatures and from the collaboration design's.
///
/// ## Verified in this order
///
/// size and JSON → fingerprint → signer → signature → structure → template → expiry → host →
/// pin. The fingerprint and the signature come first: nothing in a bundle that was not signed
/// by the key the respondent was told to trust is believed, not even a "this form is closed".
library;

import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as crypto;
import 'package:cryptography/cryptography.dart';

import 'form_base32.dart';
import 'form_jcs.dart';
import 'form_package.dart';
import 'form_parser.dart';
import 'form_rule_values.dart';
import 'form_seal.dart';
import 'form_spec.dart';
import 'rules_version.dart';

/// The domain tag in front of what is signed (§5.1).
const String kBundleSignatureTag = 'ocideck-intake-bundle-v1\n';

/// The bundle version this engine reads and writes.
const int kFormBundleVersion = 1;

/// The most bytes of bundle text read. A bundle is a few kilobytes; a megabyte is not one.
const int kFormMaxBundleBytes = 256 * 1024;

/// The suffix of a bundle file beside its template: `recept.nl.md` has
/// `recept.nl.bundle.json`.
String bundleFileNameFor(String templateFileName) {
  final base = templateFileName.endsWith('.md')
      ? templateFileName.substring(0, templateFileName.length - 3)
      : templateFileName;
  return '$base.bundle.json';
}

// ── keys and fingerprints ───────────────────────────────────────────────────

final Ed25519 _ed25519 = Ed25519();

/// An organiser's signing key: a 32-byte Ed25519 seed (the secret) and what follows from it.
class FormSigningKey {
  const FormSigningKey._(this.seed, this.publicKey);

  /// The secret. The organiser keeps it in the keychain; losing it means signing a new
  /// bundle with another key, which every respondent then meets as a changed fingerprint.
  final Uint8List seed;

  final Uint8List publicKey;

  /// The public key as it stands in a bundle's `sign`.
  String get publicKeyText => base32Encode(publicKey);

  /// The fingerprint of this key (§6.4), 52 characters.
  String get fingerprint => formKeyFingerprint(publicKey);
}

/// A fresh signing key.
Future<FormSigningKey> generateFormSigningKey() {
  final random = Random.secure();
  return formSigningKeyFromSeed(
    Uint8List.fromList(List.generate(32, (_) => random.nextInt(256))),
  );
}

/// The signing key of [seed] (32 bytes), or throws [ArgumentError].
Future<FormSigningKey> formSigningKeyFromSeed(Uint8List seed) async {
  if (seed.length != 32) {
    throw ArgumentError.value(
      seed.length,
      'seed',
      'an Ed25519 seed is 32 bytes',
    );
  }
  final pair = await _ed25519.newKeyPairFromSeed(seed);
  final key = await pair.extractPublicKey();
  return FormSigningKey._(
    Uint8List.fromList(seed),
    Uint8List.fromList(key.bytes),
  );
}

/// The fingerprint of an Ed25519 [publicKey]: the base32 of its SHA-256.
String formKeyFingerprint(List<int> publicKey) =>
    base32Encode(_sha256(publicKey));

/// [fingerprint] in groups of four, for people: `abcd-efgh-…`.
String formatFingerprint(String fingerprint) {
  final groups = <String>[];
  for (var i = 0; i < fingerprint.length; i += 4) {
    groups.add(fingerprint.substring(i, min(i + 4, fingerprint.length)));
  }
  return groups.join('-');
}

/// The fingerprint in [text] as 52 characters of base32, however it was written — upper or
/// lower case, grouped with hyphens, blanks or line breaks — or `null` if it is not one.
String? normalizeFingerprint(String text) {
  final plain = text.replaceAll(RegExp(r'[\s-]'), '').toLowerCase();
  if (plain.length != 52) return null;
  final bytes = base32Decode(plain);
  return bytes != null && bytes.length == 32 ? plain : null;
}

/// The key id of an organiser: the first 128 bits of the SHA-256 of [ageRecipient], as
/// base32 (26 characters).
String organiserKid(String ageRecipient) =>
    base32Encode(_sha256(utf8.encode(ageRecipient)).sublist(0, 16));

List<int> _sha256(List<int> bytes) => crypto.sha256.convert(bytes).bytes;

// ── the model ───────────────────────────────────────────────────────────────

/// One organiser in a bundle.
class FormBundleOrganiser {
  const FormBundleOrganiser({
    required this.name,
    required this.age,
    required this.sign,
    required this.kid,
  });

  /// What the respondent is shown — a team or a person ("Redactie").
  final String name;

  /// The `age1…` recipient packages are sealed to.
  final String age;

  /// The Ed25519 public key, base32.
  final String sign;

  /// [organiserKid] of [age].
  final String kid;

  Map<String, Object?> toJson() => {
    'name': name,
    'age': age,
    'sign': sign,
    'kid': kid,
  };
}

/// The bundle's policy: what the form says about itself that is not a key.
class FormBundlePolicy {
  const FormBundlePolicy({
    this.apiHost,
    this.closes,
    this.maxPackageBytes,
    this.retainUnused,
  });

  /// The host of the intake server, with an optional port. Signed: the client refuses a
  /// bundle that names another host than the one it called. Absent on the file route.
  final String? apiHost;

  /// The last day a submission is accepted, `YYYY-MM-DD`.
  final String? closes;

  /// A cap lower than the client's own; never higher (§5.4).
  final int? maxPackageBytes;

  /// How long the organiser keeps what was not used, in words (the form's notice says the
  /// same).
  final String? retainUnused;

  Map<String, Object?> toJson() => {
    if (apiHost != null) 'api_host': apiHost,
    if (closes != null) 'closes': closes,
    if (maxPackageBytes != null) 'max_package_bytes': maxPackageBytes,
    if (retainUnused != null) 'retain_unused': retainUnused,
  };
}

/// A bundle: signed, or as it was read.
class FormBundle {
  const FormBundle({
    required this.fid,
    required this.formId,
    required this.formVersion,
    required this.formRules,
    required this.templateSha256,
    required this.organisers,
    required this.policy,
    required this.bundleSeq,
    required this.expires,
    required this.signature,
  });

  /// 128 random bits, 26 characters of `[a-z2-7]`.
  final String fid;
  final String formId;
  final int formVersion;
  final int formRules;
  final String templateSha256;
  final List<FormBundleOrganiser> organisers;
  final FormBundlePolicy policy;

  /// Monotonic: a client keeps the highest it has seen and refuses a lower one.
  final int bundleSeq;

  /// The day after which the bundle is not believed, `YYYY-MM-DD`. Mandatory.
  final String expires;

  /// The Ed25519 signature, base32 (103 characters).
  final String signature;

  /// The object that is signed: every field but `sig`.
  Map<String, Object?> signedObject() => {
    'v': kFormBundleVersion,
    'fid': fid,
    'form': {'id': formId, 'version': formVersion, 'rules': formRules},
    'template_sha256': templateSha256,
    'organisers': [for (final o in organisers) o.toJson()],
    'policy': policy.toJson(),
    'bundle_seq': bundleSeq,
    'expires': expires,
  };

  Map<String, Object?> toJson() => {...signedObject(), 'sig': signature};

  /// The file's text: indented, one trailing newline. Formatting is not signed, so a
  /// reader may reformat it freely.
  String toJsonText() =>
      '${const JsonEncoder.withIndent('  ').convert(toJson())}\n';

  /// The organiser whose signing key hashes to [fingerprint], or `null`.
  FormBundleOrganiser? ownerOf(String fingerprint) {
    for (final organiser in organisers) {
      final key = base32Decode(organiser.sign);
      if (key != null && formKeyFingerprint(key) == fingerprint) {
        return organiser;
      }
    }
    return null;
  }
}

// ── pins ────────────────────────────────────────────────────────────────────

/// The highest `bundle_seq` seen per (`fid`, owner fingerprint), as a client keeps it
/// (§5.1): a server cannot replay an older bundle that still lists a departed organiser or
/// an older consent text. Immutable; [accepting] gives the next state.
class FormBundlePins {
  const FormBundlePins([this._seen = const {}]);

  factory FormBundlePins.fromJson(Object? json) {
    if (json is! Map) return const FormBundlePins();
    final seen = <String, int>{};
    for (final entry in json.entries) {
      final value = entry.value;
      if (entry.key is String && value is int && value >= 1) {
        seen[entry.key as String] = value;
      }
    }
    return FormBundlePins(seen);
  }

  final Map<String, int> _seen;

  static String _key(String fid, String fingerprint) => '$fid@$fingerprint';

  /// The highest sequence seen for this form and owner, or `null`.
  int? seqFor(String fid, String fingerprint) => _seen[_key(fid, fingerprint)];

  /// These pins plus [bundle], if it is higher than what was there.
  FormBundlePins accepting(FormBundle bundle, String fingerprint) {
    final key = _key(bundle.fid, fingerprint);
    final before = _seen[key];
    if (before != null && before >= bundle.bundleSeq) return this;
    return FormBundlePins({..._seen, key: bundle.bundleSeq});
  }

  Map<String, Object?> toJson() => Map<String, Object?>.of(_seen);
}

// ── verifying ───────────────────────────────────────────────────────────────

/// Why a bundle was not accepted. Each one stops the respondent: none has a "continue".
enum FormBundleIssue {
  /// Larger than [kFormMaxBundleBytes], not JSON, or not an object of the shape of §5.1 —
  /// including a number outside what the signature covers.
  notABundle,

  /// `v` is not the version this engine reads.
  unsupportedVersion,

  /// No fingerprint was given (the link or the call text is incomplete): "ask the organiser
  /// for the full invitation".
  noFingerprint,

  /// A fingerprint was given and it is not a fingerprint.
  badFingerprint,

  /// No organiser in the bundle holds the key the fingerprint names: this form does not come
  /// from who the invitation says.
  fingerprintMismatch,

  /// The signature is not the owner's over this bundle.
  badSignature,

  /// Signed, but a field is not what §5.1 allows: an organiser's key, name or `kid`, a date,
  /// the `fid`, a cap, a host.
  badStructure,

  /// The template's hash is not the bundle's `template_sha256`, or the template is not a form,
  /// or it is another form, version or rules version than the bundle says.
  templateMismatch,

  /// The form asks for rules this engine does not know (`rules=` higher than supported).
  rulesTooNew,

  /// `expires` is before today. The day it names is the last day the bundle is believed.
  expired,

  /// The bundle's `api_host` is not the host the client called.
  hostMismatch,

  /// `bundle_seq` is lower than the highest this client has seen for the form and owner.
  rollback,
}

/// The outcome of [verifyFormBundle].
sealed class FormBundleResult {
  const FormBundleResult();
}

/// A bundle that is the owner's, for this template, and fresh.
class FormBundleVerified extends FormBundleResult {
  const FormBundleVerified({
    required this.bundle,
    required this.owner,
    required this.fingerprint,
    required this.pins,
  });

  final FormBundle bundle;

  /// The organiser whose key the fingerprint names.
  final FormBundleOrganiser owner;

  /// The owner's fingerprint, 52 characters.
  final String fingerprint;

  /// The pins after this bundle: store them.
  final FormBundlePins pins;
}

/// A bundle that was not accepted.
class FormBundleRefused extends FormBundleResult {
  const FormBundleRefused(this.issue, {this.detail});

  final FormBundleIssue issue;

  /// A short reason for a log; never a key.
  final String? detail;
}

final RegExp _host = RegExp(
  r'^[a-z0-9](?:[a-z0-9.-]{0,251}[a-z0-9])?(?::[0-9]{1,5})?$',
);

const Set<String> _topKeys = {
  'v',
  'fid',
  'form',
  'template_sha256',
  'organisers',
  'policy',
  'bundle_seq',
  'expires',
  'sig',
};

/// Verifies [bundleText] for [templateText], against a [fingerprint] that came out of band.
///
/// [now] is the day for `expires`. [expectedApiHost] is the host the client called, when it
/// called one (the file route has none). [pins] are what the client has seen before.
/// Never throws.
Future<FormBundleResult> verifyFormBundle(
  String bundleText, {
  required String templateText,
  required String? fingerprint,
  required DateTime now,
  String? expectedApiHost,
  FormBundlePins pins = const FormBundlePins(),
}) async {
  if (utf8.encode(bundleText).length > kFormMaxBundleBytes) {
    return const FormBundleRefused(
      FormBundleIssue.notABundle,
      detail: 'too large',
    );
  }
  final Object? decoded;
  try {
    decoded = jsonDecode(bundleText);
  } on FormatException {
    return const FormBundleRefused(
      FormBundleIssue.notABundle,
      detail: 'not JSON',
    );
  }
  if (decoded is! Map<String, Object?>) {
    return const FormBundleRefused(
      FormBundleIssue.notABundle,
      detail: 'not an object',
    );
  }
  if (decoded['v'] != kFormBundleVersion) {
    return const FormBundleRefused(FormBundleIssue.unsupportedVersion);
  }
  if (fingerprint == null || fingerprint.trim().isEmpty) {
    return const FormBundleRefused(FormBundleIssue.noFingerprint);
  }
  final fp = normalizeFingerprint(fingerprint);
  if (fp == null) {
    return const FormBundleRefused(FormBundleIssue.badFingerprint);
  }

  // The signer: whichever listed key the fingerprint names. Read just enough of the
  // organisers to find it; the structure is judged after the signature.
  final listed = decoded['organisers'];
  if (listed is! List) {
    return const FormBundleRefused(
      FormBundleIssue.notABundle,
      detail: 'organisers',
    );
  }
  Uint8List? signerKey;
  for (final entry in listed) {
    final text = entry is Map ? entry['sign'] : null;
    final key = text is String ? base32Decode(text) : null;
    if (key != null && key.length == 32 && formKeyFingerprint(key) == fp) {
      signerKey = key;
      break;
    }
  }
  if (signerKey == null) {
    return const FormBundleRefused(FormBundleIssue.fingerprintMismatch);
  }

  final signature = decoded['sig'];
  final sigBytes = signature is String ? base32Decode(signature) : null;
  if (sigBytes == null || sigBytes.length != 64) {
    return const FormBundleRefused(FormBundleIssue.badSignature, detail: 'sig');
  }
  final signedPart = {...decoded}..remove('sig');
  final String canonical;
  try {
    canonical = canonicalJson(signedPart);
  } on FormJcsError catch (e) {
    return FormBundleRefused(FormBundleIssue.notABundle, detail: e.message);
  }
  final valid = await _ed25519.verify(
    utf8.encode('$kBundleSignatureTag$canonical'),
    signature: Signature(
      sigBytes,
      publicKey: SimplePublicKey(signerKey, type: KeyPairType.ed25519),
    ),
  );
  if (!valid) return const FormBundleRefused(FormBundleIssue.badSignature);

  final parsed = _parse(decoded);
  if (parsed is String) {
    return FormBundleRefused(FormBundleIssue.badStructure, detail: parsed);
  }
  final bundle = parsed as FormBundle;

  if (bundle.templateSha256 != formTemplateHash(templateText)) {
    return const FormBundleRefused(
      FormBundleIssue.templateMismatch,
      detail: 'template hash',
    );
  }
  final form = parseForm(templateText);
  if (form is! ParsedForm ||
      form.spec.id != bundle.formId ||
      form.spec.version != bundle.formVersion ||
      form.spec.rules != bundle.formRules) {
    return const FormBundleRefused(
      FormBundleIssue.templateMismatch,
      detail: 'not the form the bundle names',
    );
  }
  if (!supportsFormRules(bundle.formRules)) {
    return const FormBundleRefused(FormBundleIssue.rulesTooNew);
  }
  if (bundle.expires.compareTo(formDay(now)) < 0) {
    return const FormBundleRefused(FormBundleIssue.expired);
  }
  if (expectedApiHost != null &&
      bundle.policy.apiHost != expectedApiHost.toLowerCase()) {
    return const FormBundleRefused(FormBundleIssue.hostMismatch);
  }
  final pinned = pins.seqFor(bundle.fid, fp);
  if (pinned != null && bundle.bundleSeq < pinned) {
    return const FormBundleRefused(FormBundleIssue.rollback);
  }
  final owner = bundle.ownerOf(fp)!;
  return FormBundleVerified(
    bundle: bundle,
    owner: owner,
    fingerprint: fp,
    pins: pins.accepting(bundle, fp),
  );
}

/// The typed bundle of a decoded, signed object, or the reason it is not one (a `String`).
Object _parse(Map<String, Object?> json) {
  for (final key in json.keys) {
    if (!_topKeys.contains(key)) return 'unknown member "$key"';
  }
  final fid = json['fid'];
  if (fid is! String || !isValidFormId(fid)) return 'fid';
  final form = json['form'];
  if (form is! Map ||
      form.keys.any((k) => !const {'id', 'version', 'rules'}.contains(k))) {
    return 'form';
  }
  final formId = form['id'];
  final formVersion = form['version'];
  final formRules = form['rules'];
  if (formId is! String || !RegExp(r'^[a-z][a-z0-9-]*$').hasMatch(formId)) {
    return 'form.id';
  }
  if (formVersion is! int || formVersion < 1) return 'form.version';
  if (formRules is! int || formRules < 1) return 'form.rules';
  final templateSha256 = json['template_sha256'];
  if (templateSha256 is! String ||
      !RegExp(r'^[0-9a-f]{64}$').hasMatch(templateSha256)) {
    return 'template_sha256';
  }
  final listed = json['organisers'];
  if (listed is! List || listed.length > kFormMaxRecipients) {
    return 'organisers';
  }
  final organisers = <FormBundleOrganiser>[];
  final seen = <String>{};
  for (final entry in listed) {
    if (entry is! Map ||
        entry.keys.any(
          (k) => !const {'name', 'age', 'sign', 'kid'}.contains(k),
        )) {
      return 'organiser';
    }
    final name = entry['name'];
    final age = entry['age'];
    final sign = entry['sign'];
    final kid = entry['kid'];
    if (name is! String ||
        name.trim().isEmpty ||
        name.length > 80 ||
        name.codeUnits.any((c) => c < 0x20 || c == 0x7f)) {
      return 'organiser.name';
    }
    if (age is! String || !isAgeRecipient(age)) return 'organiser.age';
    final key = sign is String ? base32Decode(sign) : null;
    if (key == null || key.length != 32) return 'organiser.sign';
    if (kid is! String || kid != organiserKid(age)) return 'organiser.kid';
    if (!seen.add(age) || !seen.add(sign as String) || !seen.add(kid)) {
      return 'organiser repeated';
    }
    organisers.add(
      FormBundleOrganiser(name: name, age: age, sign: sign, kid: kid),
    );
  }
  final policyJson = json['policy'];
  if (policyJson is! Map ||
      policyJson.keys.any(
        (k) => !const {
          'api_host',
          'closes',
          'max_package_bytes',
          'retain_unused',
        }.contains(k),
      )) {
    return 'policy';
  }
  final apiHost = policyJson['api_host'];
  final closes = policyJson['closes'];
  final maxBytes = policyJson['max_package_bytes'];
  final retain = policyJson['retain_unused'];
  if (policyJson.containsKey('api_host') &&
      (apiHost is! String || !_host.hasMatch(apiHost))) {
    return 'policy.api_host';
  }
  if (policyJson.containsKey('closes') &&
      (closes is! String || !isValidCalendarDate(closes))) {
    return 'policy.closes';
  }
  if (policyJson.containsKey('max_package_bytes') &&
      (maxBytes is! int ||
          maxBytes < 1 ||
          maxBytes > const FormPackageLimits().maxPackageBytes)) {
    return 'policy.max_package_bytes';
  }
  if (policyJson.containsKey('retain_unused') &&
      (retain is! String ||
          retain.trim().isEmpty ||
          retain.length > 200 ||
          retain.codeUnits.any((c) => c < 0x20 || c == 0x7f))) {
    return 'policy.retain_unused';
  }
  final seq = json['bundle_seq'];
  if (seq is! int || seq < 1) return 'bundle_seq';
  final expires = json['expires'];
  if (expires is! String || !isValidCalendarDate(expires)) return 'expires';
  return FormBundle(
    fid: fid,
    formId: formId,
    formVersion: formVersion,
    formRules: formRules,
    templateSha256: templateSha256,
    organisers: organisers,
    policy: FormBundlePolicy(
      apiHost: apiHost as String?,
      closes: closes as String?,
      maxPackageBytes: maxBytes as int?,
      retainUnused: retain as String?,
    ),
    bundleSeq: seq,
    expires: expires,
    signature: json['sig'] as String,
  );
}

// ── creating ────────────────────────────────────────────────────────────────

/// What [createFormBundle] could not do.
enum FormBundleCreateIssue {
  /// The template is not a form (it does not parse), or says another id/version than given.
  notAForm,

  /// An organiser's name, age recipient or signing key is not usable, or one repeats.
  badOrganiser,

  /// The key that signs is not one of the organisers: the owner must be listed (§5.1).
  signerNotListed,

  /// The bundle as built would not pass its own verification — a date, a cap, a host, the
  /// fid. [FormBundleCreateRefused.detail] names the field.
  invalid,
}

/// The outcome of [createFormBundle].
sealed class FormBundleCreateResult {
  const FormBundleCreateResult();
}

/// A signed bundle that verifies.
class FormBundleCreated extends FormBundleCreateResult {
  const FormBundleCreated(this.bundle);

  final FormBundle bundle;

  /// The file's text.
  String get text => bundle.toJsonText();
}

/// A bundle that was not made.
class FormBundleCreateRefused extends FormBundleCreateResult {
  const FormBundleCreateRefused(this.issue, {this.detail});

  final FormBundleCreateIssue issue;
  final String? detail;
}

/// One organiser as given to [createFormBundle]: the `kid` is derived.
class FormBundleOrganiserInput {
  const FormBundleOrganiserInput({
    required this.name,
    required this.age,
    required this.signPublicKey,
  });

  final String name;

  /// The `age1…` recipient.
  final String age;

  /// The 32-byte Ed25519 public key.
  final Uint8List signPublicKey;
}

/// Makes and signs a bundle for [template] (the published text of one version of a form).
///
/// The signer, [owner], must be one of [organisers] (by its public key). The result is
/// **checked by [verifyFormBundle] before it is returned**, against the owner's own
/// fingerprint: a bundle that would not pass what a respondent will do with it is not
/// handed out. Never throws.
Future<FormBundleCreateResult> createFormBundle({
  required String fid,
  required String template,
  required List<FormBundleOrganiserInput> organisers,
  required FormSigningKey owner,
  required int bundleSeq,
  required String expires,
  required DateTime now,
  FormBundlePolicy policy = const FormBundlePolicy(),
}) async {
  final form = parseForm(template);
  if (form is! ParsedForm) {
    return const FormBundleCreateRefused(FormBundleCreateIssue.notAForm);
  }
  final listed = <FormBundleOrganiser>[];
  for (final input in organisers) {
    if (!isAgeRecipient(input.age) || input.signPublicKey.length != 32) {
      return const FormBundleCreateRefused(FormBundleCreateIssue.badOrganiser);
    }
    listed.add(
      FormBundleOrganiser(
        name: input.name,
        age: input.age,
        sign: base32Encode(input.signPublicKey),
        kid: organiserKid(input.age),
      ),
    );
  }
  if (!listed.any((o) => o.sign == owner.publicKeyText)) {
    return const FormBundleCreateRefused(FormBundleCreateIssue.signerNotListed);
  }
  final unsigned = FormBundle(
    fid: fid,
    formId: form.spec.id,
    formVersion: form.spec.version,
    formRules: form.spec.rules,
    templateSha256: formTemplateHash(template),
    organisers: listed,
    policy: policy,
    bundleSeq: bundleSeq,
    expires: expires,
    signature: '',
  );
  final String canonical;
  try {
    canonical = canonicalJson(unsigned.signedObject());
  } on FormJcsError catch (e) {
    return FormBundleCreateRefused(
      FormBundleCreateIssue.invalid,
      detail: e.message,
    );
  }
  final pair = await _ed25519.newKeyPairFromSeed(owner.seed);
  final signature = await _ed25519.sign(
    utf8.encode('$kBundleSignatureTag$canonical'),
    keyPair: pair,
  );
  final signed = FormBundle(
    fid: fid,
    formId: unsigned.formId,
    formVersion: unsigned.formVersion,
    formRules: unsigned.formRules,
    templateSha256: unsigned.templateSha256,
    organisers: listed,
    policy: policy,
    bundleSeq: bundleSeq,
    expires: expires,
    signature: base32Encode(signature.bytes),
  );
  final check = await verifyFormBundle(
    signed.toJsonText(),
    templateText: template,
    fingerprint: owner.fingerprint,
    now: now,
    expectedApiHost: policy.apiHost,
  );
  if (check is FormBundleRefused) {
    final structural = check.issue == FormBundleIssue.badStructure;
    return FormBundleCreateRefused(
      structural &&
              check.detail != null &&
              check.detail!.startsWith('organiser')
          ? FormBundleCreateIssue.badOrganiser
          : FormBundleCreateIssue.invalid,
      detail: check.detail ?? check.issue.name,
    );
  }
  return FormBundleCreated(signed);
}
