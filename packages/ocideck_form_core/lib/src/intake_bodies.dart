/// The bodies of the intake protocol's operations (`docs/design/INTAKE_PROTOCOL.md` §4.2, §4.4, §5):
/// the form a server serves and an organiser publishes, the token and withdrawal requests, and the
/// answers to publishing, listing, acknowledging and withdrawing. Pure data: no network, no key.
///
/// **Who reads what, and how strictly.** A *request* is read by the server, which **refuses a member it
/// does not know** (`bad-request`): what an organiser signs is exactly what is acted on. A *response* is
/// read by a client, which **ignores** a member it does not know, so that a server can add one without
/// raising the protocol version (§2). The signed bundle inside a form keeps its own strict rules
/// (`verifyFormBundle`); this file only carries it. Every reader answers `null` or an issue for what is
/// malformed and never repairs it.
library;

import 'dart:convert';

import 'form_bundle.dart' show kFormMaxBundleBytes;
import 'form_package.dart' show isValidFormId;
import 'intake_protocol.dart'
    show intakeJsonObject, isValidIntakeTime, isValidWithdrawalSecret;

/// A form has between 1 and this many variants (§4.2).
const int kIntakeMaxVariants = 32;

/// The most bytes of one template (§4.2).
const int kIntakeMaxTemplateBytes = 1024 * 1024;

/// The most bytes of a form response or a publication (§4.2, §5.3).
const int kIntakeMaxFormBytes = 8 * 1024 * 1024;

/// The most submissions in one page of a listing (§5.5), and what is taken when no limit is given.
const int kIntakeMaxPageItems = 100;
const int kIntakeDefaultPageItems = 50;

/// The most key ids in an `acked_by`: a bundle names at most 64 organisers.
const int _maxAcked = 64;

/// Whether a form takes uploads.
enum IntakeFormState {
  open,
  closed;

  static IntakeFormState? fromWire(Object? wire) {
    for (final state in values) {
      if (state.name == wire) return state;
    }
    return null;
  }
}

/// One published template with its signed bundle (§4.2). A bundle binds the hash of one text, so each
/// language is a variant of its own.
class IntakeVariant {
  const IntakeVariant({required this.bundle, required this.template});

  /// The bundle object as it was signed and published (FORM_INTAKE.md §5.1).
  final Map<String, Object?> bundle;

  /// The template text, exactly as the bundle's `template_sha256` was taken over it.
  final String template;

  /// The bundle as text, for `verifyFormBundle`. The signature covers the canonical form, so which
  /// JSON text it travelled as does not matter.
  String get bundleText => jsonEncode(bundle);

  Map<String, Object?> toJson() => {'bundle': bundle, 'template': template};
}

/// Why a form response or a publication was not read.
enum IntakeFormIssue {
  /// Too long, not JSON, or not an object.
  notAForm,

  /// `state` is neither `open` nor `closed` — or, in a response, missing.
  badState,

  /// No `variants`, an empty list, or not a list.
  noVariants,

  /// More than [kIntakeMaxVariants].
  tooManyVariants,

  /// A variant that is not `{bundle, template}`: a member missing or of the wrong type, a bundle
  /// above the bundle limit, or (in a request) a member this version does not know.
  badVariant,

  /// A template above [kIntakeMaxTemplateBytes].
  templateTooLarge,

  /// A member of a publication this version does not know.
  unknownMember,
}

/// A form as a server serves it and an organiser publishes it: its [state] and its [variants].
class IntakeForm {
  const IntakeForm({required this.state, required this.variants});

  final IntakeFormState state;
  final List<IntakeVariant> variants;

  Map<String, Object?> toJson() => {
    'state': state.name,
    'variants': [for (final v in variants) v.toJson()],
  };

  String toJsonText() => jsonEncode(toJson());
}

sealed class IntakeFormResult {
  const IntakeFormResult();
}

class IntakeFormRead extends IntakeFormResult {
  const IntakeFormRead(this.form);

  final IntakeForm form;
}

class IntakeFormRefused extends IntakeFormResult {
  const IntakeFormRefused(this.issue, {this.index});

  final IntakeFormIssue issue;

  /// The variant at fault, from 0, when it was one.
  final int? index;
}

/// The answer to `GET /v1/forms/{fid}`, as a client reads it (§4.2): `state` is required, and a member
/// this version does not know is ignored — in the form and in each variant.
IntakeFormResult parseIntakeFormResponse(String text) =>
    _readForm(text, strict: false);

/// The body of `PUT /v1/forms/{fid}`, as the server reads it (§5.3): `state` is optional (`open` when
/// absent) and a member this version does not know is **refused**.
IntakeFormResult parseIntakePublication(String text) =>
    _readForm(text, strict: true);

IntakeFormResult _readForm(String text, {required bool strict}) {
  final json = intakeJsonObject(text, maxBytes: kIntakeMaxFormBytes);
  if (json == null) return const IntakeFormRefused(IntakeFormIssue.notAForm);
  if (strict && json.keys.any((k) => k != 'state' && k != 'variants')) {
    return const IntakeFormRefused(IntakeFormIssue.unknownMember);
  }
  final IntakeFormState? state;
  if (json.containsKey('state')) {
    state = IntakeFormState.fromWire(json['state']);
  } else {
    state = strict ? IntakeFormState.open : null;
  }
  if (state == null) return const IntakeFormRefused(IntakeFormIssue.badState);
  final listed = json['variants'];
  if (listed is! List || listed.isEmpty) {
    return const IntakeFormRefused(IntakeFormIssue.noVariants);
  }
  if (listed.length > kIntakeMaxVariants) {
    return const IntakeFormRefused(IntakeFormIssue.tooManyVariants);
  }
  final variants = <IntakeVariant>[];
  for (var i = 0; i < listed.length; i++) {
    final entry = listed[i];
    if (entry is! Map<String, Object?> ||
        (strict && entry.keys.any((k) => k != 'bundle' && k != 'template'))) {
      return IntakeFormRefused(IntakeFormIssue.badVariant, index: i);
    }
    final bundle = entry['bundle'];
    final template = entry['template'];
    if (bundle is! Map<String, Object?> || template is! String) {
      return IntakeFormRefused(IntakeFormIssue.badVariant, index: i);
    }
    if (utf8.encode(jsonEncode(bundle)).length > kFormMaxBundleBytes) {
      return IntakeFormRefused(IntakeFormIssue.badVariant, index: i);
    }
    if (utf8.encode(template).length > kIntakeMaxTemplateBytes) {
      return IntakeFormRefused(IntakeFormIssue.templateTooLarge, index: i);
    }
    variants.add(IntakeVariant(bundle: bundle, template: template));
  }
  return IntakeFormRead(IntakeForm(state: state, variants: variants));
}

// ── publishing ──────────────────────────────────────────────────────────────

/// The answer to a publication (§5.3): the form, how many variants it now has and the highest
/// `bundle_seq` among them.
class IntakePublishResult {
  const IntakePublishResult({
    required this.fid,
    required this.variants,
    required this.bundleSeq,
  });

  final String fid;
  final int variants;
  final int bundleSeq;

  Map<String, Object?> toJson() => {
    'fid': fid,
    'variants': variants,
    'bundle_seq': bundleSeq,
  };

  String toJsonText() => jsonEncode(toJson());
}

IntakePublishResult? parseIntakePublishResult(String text) {
  final json = intakeJsonObject(text);
  if (json == null) return null;
  final fid = json['fid'];
  final variants = json['variants'];
  final seq = json['bundle_seq'];
  if (fid is! String || !isValidFormId(fid)) return null;
  if (variants is! int || variants < 1 || variants > kIntakeMaxVariants) {
    return null;
  }
  if (seq is! int || seq < 1) return null;
  return IntakePublishResult(fid: fid, variants: variants, bundleSeq: seq);
}

// ── the open token ──────────────────────────────────────────────────────────

/// The body of `PUT /v1/forms/{fid}/token` (§5.4): the hash of the new open token, or `null` to revoke.
/// The server never holds a token, only this hash.
class IntakeTokenRequest {
  const IntakeTokenRequest(this.tokenSha256);

  /// The lower-case hex SHA-256 of the token, or `null` for "no one may upload".
  final String? tokenSha256;

  String toJsonText() => jsonEncode({'token_sha256': tokenSha256});
}

/// The token request in [text], or `null`. The member must be present — `null` is an answer, a missing
/// member is not — and nothing else may be.
IntakeTokenRequest? parseIntakeTokenRequest(String text) {
  final json = intakeJsonObject(text);
  if (json == null || json.length != 1 || !json.containsKey('token_sha256')) {
    return null;
  }
  final hash = json['token_sha256'];
  if (hash == null) return const IntakeTokenRequest(null);
  if (hash is! String || !RegExp(r'^[0-9a-f]{64}$').hasMatch(hash)) return null;
  return IntakeTokenRequest(hash);
}

/// The answer to it: whether a token is now set.
class IntakeTokenResult {
  const IntakeTokenResult({required this.tokenSet});

  final bool tokenSet;

  String toJsonText() => jsonEncode({'token_set': tokenSet});
}

IntakeTokenResult? parseIntakeTokenResult(String text) {
  final set = intakeJsonObject(text)?['token_set'];
  return set is bool ? IntakeTokenResult(tokenSet: set) : null;
}

// ── withdrawing ─────────────────────────────────────────────────────────────

/// The body of `POST /v1/submissions/{sid}/withdraw` (§4.4).
class IntakeWithdrawRequest {
  const IntakeWithdrawRequest(this.secret);

  /// The withdrawal secret, 52 characters; the server hashes it and compares.
  final String secret;

  String toJsonText() => jsonEncode({'secret': secret});
}

/// The withdrawal request in [text], or `null`: exactly `secret`, in the grammar of a secret.
IntakeWithdrawRequest? parseIntakeWithdrawRequest(String text) {
  final json = intakeJsonObject(text);
  if (json == null || json.length != 1) return null;
  final secret = json['secret'];
  return secret is String && isValidWithdrawalSecret(secret)
      ? IntakeWithdrawRequest(secret)
      : null;
}

/// The answer to a withdrawal: the submission, when the withdrawal was recorded, and whether the
/// ciphertext was still there to delete. A repeat answers with the first time.
class IntakeWithdrawResult {
  const IntakeWithdrawResult({
    required this.sid,
    required this.at,
    required this.deleted,
  });

  final String sid;
  final String at;
  final bool deleted;

  String toJsonText() => jsonEncode({'sid': sid, 'at': at, 'deleted': deleted});
}

IntakeWithdrawResult? parseIntakeWithdrawResult(String text) {
  final json = intakeJsonObject(text);
  if (json == null) return null;
  final sid = json['sid'];
  final at = json['at'];
  final deleted = json['deleted'];
  if (sid is! String || !isValidFormId(sid)) return null;
  if (at is! String || !isValidIntakeTime(at)) return null;
  if (deleted is! bool) return null;
  return IntakeWithdrawResult(sid: sid, at: at, deleted: deleted);
}

// ── listing ─────────────────────────────────────────────────────────────────

/// Whether [cursor] is a paging cursor: opaque, 1–64 characters of `[A-Za-z0-9_-]`.
bool isValidIntakeCursor(String cursor) =>
    RegExp(r'^[A-Za-z0-9_-]{1,64}$').hasMatch(cursor);

/// One line of an organiser's listing (§5.5): a submission the server holds, or the tombstone of one
/// that was withdrawn.
class IntakeListedSubmission {
  const IntakeListedSubmission.held({
    required this.sid,
    required this.at,
    required this.bytes,
    required this.ciphertextSha256,
    this.ackedBy = const [],
  }) : withdrawn = false;

  const IntakeListedSubmission.withdrawn({required this.sid, required this.at})
    : withdrawn = true,
      bytes = null,
      ciphertextSha256 = null,
      ackedBy = const [];

  final String sid;

  /// When it arrived — or, for a tombstone, when it was withdrawn.
  final String at;

  final bool withdrawn;

  /// The ciphertext's size and hash; `null` for a tombstone.
  final int? bytes;
  final String? ciphertextSha256;

  /// The key ids of the organisers who acknowledged it.
  final List<String> ackedBy;

  Map<String, Object?> toJson() => withdrawn
      ? {'sid': sid, 'at': at, 'withdrawn': true}
      : {
          'sid': sid,
          'at': at,
          'bytes': bytes,
          'ciphertext_sha256': ciphertextSha256,
          'acked_by': ackedBy,
        };
}

/// One page of a listing: [items] oldest first by `(at, sid)`, and the cursor of the next page, or
/// `null` on the last.
class IntakeSubmissionPage {
  const IntakeSubmissionPage({required this.items, this.next});

  final List<IntakeListedSubmission> items;
  final String? next;

  String toJsonText() => jsonEncode({
    'items': [for (final i in items) i.toJson()],
    'next': next,
  });
}

/// The page in [text], or `null` if any part of it is malformed — one bad line spoils the page, since
/// a list that is silently shorter than the server's is worse than an error.
IntakeSubmissionPage? parseIntakeSubmissionPage(String text) {
  final json = intakeJsonObject(text, maxBytes: 1024 * 1024);
  if (json == null) return null;
  final listed = json['items'];
  final next = json['next'];
  if (listed is! List || listed.length > kIntakeMaxPageItems) return null;
  if (next != null && (next is! String || !isValidIntakeCursor(next))) {
    return null;
  }
  final items = <IntakeListedSubmission>[];
  for (final entry in listed) {
    final item = _readListed(entry);
    if (item == null) return null;
    items.add(item);
  }
  return IntakeSubmissionPage(items: items, next: next as String?);
}

IntakeListedSubmission? _readListed(Object? entry) {
  if (entry is! Map<String, Object?>) return null;
  final sid = entry['sid'];
  final at = entry['at'];
  if (sid is! String || !isValidFormId(sid)) return null;
  if (at is! String || !isValidIntakeTime(at)) return null;
  if (entry['withdrawn'] == true) {
    return IntakeListedSubmission.withdrawn(sid: sid, at: at);
  }
  final bytes = entry['bytes'];
  final hash = entry['ciphertext_sha256'];
  final kids = _readKids(entry['acked_by']);
  if (bytes is! int || bytes < 1) return null;
  if (hash is! String || !RegExp(r'^[0-9a-f]{64}$').hasMatch(hash)) return null;
  if (kids == null) return null;
  return IntakeListedSubmission.held(
    sid: sid,
    at: at,
    bytes: bytes,
    ciphertextSha256: hash,
    ackedBy: kids,
  );
}

// ── acknowledging ───────────────────────────────────────────────────────────

/// The answer to `POST /v1/submissions/{sid}/ack` (§5.5): who has acknowledged the submission now, and
/// whether that was everyone and the server purged the ciphertext.
class IntakeAckResult {
  const IntakeAckResult({required this.ackedBy, required this.purged});

  final List<String> ackedBy;
  final bool purged;

  String toJsonText() => jsonEncode({'acked_by': ackedBy, 'purged': purged});
}

IntakeAckResult? parseIntakeAckResult(String text) {
  final json = intakeJsonObject(text);
  if (json == null) return null;
  final kids = _readKids(json['acked_by']);
  final purged = json['purged'];
  if (kids == null || purged is! bool) return null;
  return IntakeAckResult(ackedBy: kids, purged: purged);
}

/// A list of at most [_maxAcked] key ids, each once; `null` if it is anything else.
List<String>? _readKids(Object? listed) {
  if (listed is! List || listed.length > _maxAcked) return null;
  final kids = <String>[];
  for (final kid in listed) {
    if (kid is! String || !isValidFormId(kid) || kids.contains(kid)) {
      return null;
    }
    kids.add(kid);
  }
  return kids;
}
