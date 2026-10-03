/// The intake protocol, version 1, as pure data (`docs/design/INTAKE_PROTOCOL.md`, FORM_INTAKE.md
/// §6): what the bytes of a request and a response look like, with no network and no key.
///
/// The respondent's client and the reference server both read these, and a third party can write a
/// compatible one from the protocol document and `test/fixtures/intake_protocol_vectors.json`
/// (CC0, D5). Everything here **fails closed**: a value outside its grammar is refused with a
/// reason, never repaired. What a *server* says is read with one deliberate exception to that, set
/// out in the protocol document: members this version does not know are **ignored**, so that a
/// server may add one without raising the protocol version. The signed bundle — the only thing a
/// respondent believes from a server — keeps its own strict rules (`form_bundle.dart`).
///
/// * **Invite link** ([parseInviteLink]): where the respondent gets in (§6.4). A link without the
///   owner's fingerprint is not complete and goes no further — an incomplete link is refused, not
///   accepted with a prompt.
/// * **Server information** ([parseIntakeInfo]): `GET /v1/info`, and the one place a client decides
///   it is too old or too new for a server.
/// * **Arrival note** ([IntakeArrivalNote]) and the **withdrawal secret** (§5.8).
/// * **Errors** ([IntakeErrorCode]): a machine code and an HTTP status for every refusal.
library;

import 'dart:convert';
import 'dart:math';

import 'form_base32.dart';
import 'form_bundle.dart' show isValidApiHost, normalizeFingerprint;
import 'form_package.dart'
    show FormPackageLimits, isValidFormId, newFormId, sha256Hex;
import 'form_rule_values.dart' show isValidCalendarDate;

/// The protocol versions this engine speaks: exactly version 1.
const int kIntakeProtocolMin = 1;
const int kIntakeProtocolMax = 1;

/// The most bytes of any JSON body of this protocol that is not a bundle publication: a note,
/// a list page, an information document. Anything longer is not one.
const int kIntakeMaxJsonBytes = 64 * 1024;

/// The longest contact line or source URL.
const int _maxLine = 200;

// ── invite link ─────────────────────────────────────────────────────────────

/// Why a text is not a complete invite link (§6.4).
enum InviteLinkIssue {
  /// Not a web address at all, or one with a user name in it.
  notALink,

  /// A web address that is not `https`.
  notHttps,

  /// The path does not end in `/f/<form id>`.
  noFormId,

  /// The form id is not 26 characters of `[a-z2-7]`.
  badFormId,

  /// No `api` in the fragment.
  noApi,

  /// `api` is not a host.
  badApi,

  /// **No `fp`.** The link is not complete: the fingerprint is the one thing a respondent has that
  /// the server does not control, and the link stops without it.
  noFingerprint,

  /// `fp` is not a fingerprint.
  badFingerprint,

  /// No `t` in the fragment.
  noToken,

  /// `t` is not an invite token.
  badToken,

  /// A parameter appears twice.
  repeatedParameter,
}

/// An invite link read in full:
/// `https://<shell host>/f/<fid>#api=<api host>&fp=<fingerprint>&t=<token>` (§6.4).
class InviteLink {
  const InviteLink({
    required this.shellBase,
    required this.fid,
    required this.apiHost,
    required this.fingerprint,
    required this.token,
  });

  /// The web form shell the link opens, without a trailing slash: `https://forms.example.org`,
  /// possibly with a path prefix.
  final String shellBase;

  /// The form, 26 characters of `[a-z2-7]`.
  final String fid;

  /// The host of the intake server, lower-case, with its port if it has one. A bundle's
  /// `policy.api_host` must equal it.
  final String apiHost;

  /// The owner's key fingerprint, 52 characters of base32: what the bundle's signature is checked
  /// against.
  final String fingerprint;

  /// The invite token, 26 characters of `[a-z2-7]`.
  final String token;

  /// The link as it is shared. The fragment is never sent to a server.
  String get text => '$shellBase/f/$fid#api=$apiHost&fp=$fingerprint&t=$token';
}

/// What reading an invite link gave.
sealed class InviteLinkResult {
  const InviteLinkResult();
}

class InviteLinkParsed extends InviteLinkResult {
  const InviteLinkParsed(this.link);

  final InviteLink link;
}

class InviteLinkRefused extends InviteLinkResult {
  const InviteLinkRefused(this.issue);

  final InviteLinkIssue issue;
}

/// The invite link in [text], or why it is not one. Surrounding blanks are ignored; the host of
/// `api` is lower-cased (host names have no case) and the fingerprint is read however it was
/// written ([normalizeFingerprint]). A parameter this version does not know is ignored.
InviteLinkResult parseInviteLink(String text) {
  final uri = Uri.tryParse(text.trim());
  if (uri == null || !uri.hasScheme || uri.host.isEmpty) {
    return const InviteLinkRefused(InviteLinkIssue.notALink);
  }
  if (uri.userInfo.isNotEmpty) {
    return const InviteLinkRefused(InviteLinkIssue.notALink);
  }
  if (uri.scheme != 'https') {
    return const InviteLinkRefused(InviteLinkIssue.notHttps);
  }
  final segments = [...uri.pathSegments];
  if (segments.isNotEmpty && segments.last.isEmpty) segments.removeLast();
  if (segments.length < 2 || segments[segments.length - 2] != 'f') {
    return const InviteLinkRefused(InviteLinkIssue.noFormId);
  }
  final fid = segments.last;
  if (!isValidFormId(fid)) {
    return const InviteLinkRefused(InviteLinkIssue.badFormId);
  }
  final prefix = segments.sublist(0, segments.length - 2);

  final params = <String, String>{};
  for (final part in uri.fragment.split('&')) {
    if (part.isEmpty) continue;
    final pair = part.split('=');
    if (pair.length != 2) continue;
    final key = pair[0];
    if (key != 'api' && key != 'fp' && key != 't') continue;
    if (params.containsKey(key)) {
      return const InviteLinkRefused(InviteLinkIssue.repeatedParameter);
    }
    params[key] = pair[1];
  }

  final api = params['api'];
  if (api == null || api.isEmpty) {
    return const InviteLinkRefused(InviteLinkIssue.noApi);
  }
  final apiHost = api.toLowerCase();
  if (!isValidApiHost(apiHost)) {
    return const InviteLinkRefused(InviteLinkIssue.badApi);
  }
  final fp = params['fp'];
  if (fp == null || fp.isEmpty) {
    return const InviteLinkRefused(InviteLinkIssue.noFingerprint);
  }
  final fingerprint = normalizeFingerprint(fp);
  if (fingerprint == null) {
    return const InviteLinkRefused(InviteLinkIssue.badFingerprint);
  }
  final token = params['t'];
  if (token == null || token.isEmpty) {
    return const InviteLinkRefused(InviteLinkIssue.noToken);
  }
  if (!isValidInviteToken(token)) {
    return const InviteLinkRefused(InviteLinkIssue.badToken);
  }
  final port = uri.hasPort ? ':${uri.port}' : '';
  final path = prefix.isEmpty ? '' : '/${prefix.join('/')}';
  return InviteLinkParsed(
    InviteLink(
      shellBase: 'https://${uri.host}$port$path',
      fid: fid,
      apiHost: apiHost,
      fingerprint: fingerprint,
      token: token,
    ),
  );
}

/// A fresh invite token: 128 random bits as 26 characters of `[a-z2-7]`. The organiser's client
/// makes it and sends the server only its hash ([inviteTokenHash]); the server never holds one.
String newInviteToken(Random random) => newFormId(random);

/// Whether [token] is an invite token.
bool isValidInviteToken(String token) => isValidFormId(token);

/// The lower-case hex SHA-256 of the token's text: what the server stores and compares.
String inviteTokenHash(String token) => sha256Hex(utf8.encode(token));

// ── withdrawal secret ───────────────────────────────────────────────────────

/// A fresh withdrawal secret (§5.8): 256 random bits as 52 characters of `[a-z2-7]`. The client
/// keeps it in the copy the respondent saves and sends only [withdrawalSecretHash] with the upload.
String newWithdrawalSecret(Random random) =>
    base32Encode([for (var i = 0; i < 32; i++) random.nextInt(256)]);

/// Whether [secret] is a withdrawal secret: 52 characters that decode to 32 bytes.
bool isValidWithdrawalSecret(String secret) =>
    secret.length == 52 && base32Decode(secret)?.length == 32;

/// The lower-case hex SHA-256 of the secret's text.
String withdrawalSecretHash(String secret) => sha256Hex(utf8.encode(secret));

// ── server information ──────────────────────────────────────────────────────

/// Why a response is not usable as `GET /v1/info`.
enum IntakeInfoIssue {
  /// Not JSON, not an object, too large, or missing a member this client needs.
  notInfo,

  /// The server speaks a protocol older than this client's oldest.
  serverTooOld,

  /// The server speaks a protocol newer than this client's newest.
  serverTooNew,

  /// `limits.max_package_bytes` is not a positive whole number.
  badLimits,

  /// `source_url` is not an `https` address.
  badSourceUrl,

  /// `operator_contact` is empty, too long or has control characters.
  badContact,
}

/// What `GET /v1/info` says.
class IntakeInfo {
  const IntakeInfo({
    required this.protocol,
    required this.maxPackageBytes,
    required this.sourceUrl,
    required this.operatorContact,
  });

  final int protocol;

  /// The most bytes of one sealed package the server takes, **at most** the client's hard cap
  /// (§5.4): a server may lower the cap, never raise it past what the client allows.
  final int maxPackageBytes;

  /// Where the source of the server is: the offer of source EUPL-1.2 asks of a modified server
  /// run as a network service (§6.5).
  final String sourceUrl;

  /// Who to write to about the server: an address or a page, as the operator wrote it.
  final String operatorContact;
}

sealed class IntakeInfoResult {
  const IntakeInfoResult();
}

class IntakeInfoRead extends IntakeInfoResult {
  const IntakeInfoRead(this.info);

  final IntakeInfo info;
}

class IntakeInfoRefused extends IntakeInfoResult {
  const IntakeInfoRefused(this.issue);

  final IntakeInfoIssue issue;
}

/// The information document in [text], or why it cannot be used. Members this version does not
/// know are ignored.
IntakeInfoResult parseIntakeInfo(String text) {
  final json = _jsonObject(text);
  if (json == null) return const IntakeInfoRefused(IntakeInfoIssue.notInfo);
  final protocol = json['protocol'];
  if (protocol is! int || protocol < 0) {
    return const IntakeInfoRefused(IntakeInfoIssue.notInfo);
  }
  if (protocol < kIntakeProtocolMin) {
    return const IntakeInfoRefused(IntakeInfoIssue.serverTooOld);
  }
  if (protocol > kIntakeProtocolMax) {
    return const IntakeInfoRefused(IntakeInfoIssue.serverTooNew);
  }
  final limits = json['limits'];
  final cap = limits is Map ? limits['max_package_bytes'] : null;
  if (cap is! int || cap < 1) {
    return const IntakeInfoRefused(IntakeInfoIssue.badLimits);
  }
  final source = json['source_url'];
  if (source is! String || !_isHttpsUrl(source)) {
    return const IntakeInfoRefused(IntakeInfoIssue.badSourceUrl);
  }
  final contact = json['operator_contact'];
  if (contact is! String || !_isLine(contact)) {
    return const IntakeInfoRefused(IntakeInfoIssue.badContact);
  }
  final hard = const FormPackageLimits().maxPackageBytes;
  return IntakeInfoRead(
    IntakeInfo(
      protocol: protocol,
      maxPackageBytes: min(cap, hard),
      sourceUrl: source,
      operatorContact: contact,
    ),
  );
}

// ── arrival note ────────────────────────────────────────────────────────────

/// The server's answer to an upload (§5.8): **an arrival note, not proof against the server** —
/// it holds its own key and would sign anything, so the note is not signed. It says what the
/// server says it received and when, so that the respondent can quote it.
class IntakeArrivalNote {
  const IntakeArrivalNote({
    required this.sid,
    required this.at,
    required this.ciphertextSha256,
    required this.contact,
  });

  /// The submission id the upload was made under.
  final String sid;

  /// The server's time at arrival, UTC, to the second: `2026-10-04T09:30:12Z`.
  final String at;

  /// The lower-case hex SHA-256 of the ciphertext the server holds.
  final String ciphertextSha256;

  /// Who the respondent writes to about it: the organiser's contact line.
  final String contact;

  Map<String, Object?> toJson() => {
    'sid': sid,
    'at': at,
    'ciphertext_sha256': ciphertextSha256,
    'contact': contact,
  };

  String toJsonText() => jsonEncode(toJson());
}

/// The note in [text], or `null` if it is not a well-formed one. A note whose `sid` or hash is
/// not the one the client asked about is a different matter, for the caller.
IntakeArrivalNote? parseIntakeArrivalNote(String text) {
  final json = _jsonObject(text);
  if (json == null) return null;
  final sid = json['sid'];
  final at = json['at'];
  final hash = json['ciphertext_sha256'];
  final contact = json['contact'];
  if (sid is! String || !isValidFormId(sid)) return null;
  if (at is! String || !isValidIntakeTime(at)) return null;
  if (hash is! String || !RegExp(r'^[0-9a-f]{64}$').hasMatch(hash)) return null;
  if (contact is! String || !_isLine(contact)) return null;
  return IntakeArrivalNote(
    sid: sid,
    at: at,
    ciphertextSha256: hash,
    contact: contact,
  );
}

/// Whether [text] is a UTC time to the second, `2026-10-04T09:30:12Z`, that exists.
bool isValidIntakeTime(String text) {
  final m = RegExp(
    r'^(\d{4}-\d{2}-\d{2})T([01]\d|2[0-3]):([0-5]\d):([0-5]\d)Z$',
  ).firstMatch(text);
  return m != null && isValidCalendarDate(m.group(1)!);
}

// ── errors ──────────────────────────────────────────────────────────────────

/// Every refusal of the protocol: a machine code that goes in the body and the HTTP status it
/// travels with. A client shows its own sentence for the code (in the respondent's language) and
/// keeps the server's sentence as detail.
enum IntakeErrorCode {
  /// The request is malformed: a header, an id or a body outside its grammar.
  badRequest('bad-request', 400),

  /// No `Content-Length`: a streamed upload must say its size before the first byte.
  lengthRequired('length-required', 411),

  /// The invite token is missing, unknown or revoked.
  inviteInvalid('invite-invalid', 401),

  /// The signature of an organiser's request does not hold.
  signatureInvalid('signature-invalid', 401),

  /// The request's time is outside the window.
  requestExpired('request-expired', 401),

  /// The same request was made before.
  requestReplayed('request-replayed', 401),

  /// The signature holds, and the key may not do this.
  notAllowed('not-allowed', 403),

  /// The form is closed for uploads.
  formClosed('form-closed', 403),

  /// No such form.
  formUnknown('form-unknown', 404),

  /// No such submission, or one that was already collected.
  submissionUnknown('submission-unknown', 404),

  /// Another body was sent under a `sid` that already holds one.
  submissionConflict('submission-conflict', 409),

  /// A bundle with a lower `bundle_seq` than the one the server holds.
  bundleRollback('bundle-rollback', 409),

  /// A bundle that does not verify, or one for another form.
  bundleInvalid('bundle-invalid', 422),

  /// A bundle whose `policy.api_host` is not this server's.
  bundleHostMismatch('bundle-host-mismatch', 422),

  /// More bytes than the cap.
  tooLarge('too-large', 413),

  /// Too many requests: the response says when to try again.
  rateLimited('rate-limited', 429),

  /// The server failed.
  serverError('server-error', 500),

  /// The server cannot take it now.
  unavailable('unavailable', 503);

  const IntakeErrorCode(this.wire, this.status);

  /// What goes in the body's `error.code`.
  final String wire;

  /// The HTTP status it travels with.
  final int status;

  /// The code named [wire], or `null` for one this version does not know.
  static IntakeErrorCode? fromWire(String wire) {
    for (final code in values) {
      if (code.wire == wire) return code;
    }
    return null;
  }

  /// The code a bare HTTP [status] stands for, when the body is not ours (a proxy's page): the
  /// first code with that status, or [serverError] for a 5xx and [badRequest] for the rest.
  static IntakeErrorCode forStatus(int status) {
    for (final code in values) {
      if (code.status == status) return code;
    }
    return status ~/ 100 == 5 ? serverError : badRequest;
  }
}

/// A refusal read from a response.
class IntakeError {
  const IntakeError(this.code, this.message);

  final IntakeErrorCode code;

  /// The server's sentence, in its own language; empty when the body was not ours.
  final String message;

  /// The body that carries [code] and [message]: `{"error": {"code": …, "message": …}}`.
  String toJsonText() => jsonEncode({
    'error': {'code': code.wire, 'message': message},
  });
}

/// The refusal in a response with [status] and [body]. A body that is not ours — a proxy's page,
/// a code from a newer server — still gives an error: the one [IntakeErrorCode.forStatus] names,
/// with an empty message.
IntakeError parseIntakeError(int status, String body) {
  final fallback = IntakeErrorCode.forStatus(status);
  final json = _jsonObject(body);
  final error = json?['error'];
  if (error is! Map) return IntakeError(fallback, '');
  final code = error['code'];
  final message = error['message'];
  final known = code is String ? IntakeErrorCode.fromWire(code) : null;
  return IntakeError(
    known ?? fallback,
    message is String && message.length <= 500 ? message : '',
  );
}

// ── shared reading ──────────────────────────────────────────────────────────

/// The JSON object in [text], or `null` if it is too long, not JSON or not an object.
Map<String, Object?>? _jsonObject(String text) {
  if (utf8.encode(text).length > kIntakeMaxJsonBytes) return null;
  try {
    final decoded = jsonDecode(text);
    return decoded is Map<String, Object?> ? decoded : null;
  } on FormatException {
    return null;
  }
}

bool _isLine(String text) =>
    text.trim().isNotEmpty &&
    text.length <= _maxLine &&
    !text.codeUnits.any((c) => c < 0x20 || c == 0x7f);

bool _isHttpsUrl(String text) {
  if (!_isLine(text)) return false;
  final uri = Uri.tryParse(text);
  return uri != null &&
      uri.scheme == 'https' &&
      uri.host.isNotEmpty &&
      uri.userInfo.isEmpty;
}
