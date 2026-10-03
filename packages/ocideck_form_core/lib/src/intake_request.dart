/// Signed organiser requests (FORM_INTAKE.md §6.3, `docs/design/INTAKE_PROTOCOL.md`): how an
/// organiser's client proves to an intake server that a request is theirs, with **no account, no
/// session and no bearer secret** to leak.
///
/// An organiser request carries one header:
///
/// ```text
/// Authorization: OciIntake key=<sign>, ts=<seconds>, nonce=<nonce>, sig=<sig>
/// ```
///
/// `key` is the organiser's Ed25519 public key (52 characters of base32 — the `sign` of their
/// entry in the bundle), `ts` the Unix time in whole seconds, `nonce` 128 random bits (26
/// characters, the grammar of an id) and `sig` the Ed25519 signature (103 characters) over the
/// **canonical JSON** ([canonicalJson]) of
///
/// ```text
/// ["ocideck-intake-req-v1", host, method, target, body_sha256, ts, nonce]
/// ```
///
/// where `host` is the host the client addressed (the bundle's `policy.api_host`), `method` the
/// upper-case HTTP method, `target` the request target **as sent, query included** (so an `after=`
/// cannot be changed in flight), and `body_sha256` the lower-case hex SHA-256 of the body bytes —
/// of nothing at all for a request without a body. The tag is the first element, which keeps these
/// signatures apart from the bundle's (`ocideck-intake-bundle-v1\n`) and from the collaboration
/// design's.
///
/// **What a verifier does, in this order** — the order is part of the contract:
///
/// 1. [verifyIntakeRequest]: the header is well formed, `ts` is within [kIntakeRequestWindow] of
///    now, and the signature holds for the key the header names.
/// 2. The server decides whether **that key may do this** (it is an organiser in the form's
///    bundle, or the owner, or on the operator's allowlist).
/// 3. Only then [IntakeNonceCache.accept]: a nonce is remembered for requests that already passed
///    both, so that a stranger signing with their own key cannot fill the cache.
///
/// **This is one of the three files that touch the cryptographic primitives** (`check_packages`
/// rule 10); Ed25519 comes from `package:cryptography`, SHA-256 from `package:crypto`.
library;

import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

import 'form_base32.dart';
import 'form_bundle.dart' show FormSigningKey;
import 'form_jcs.dart';
import 'form_package.dart' show isValidFormId, newFormId, sha256Hex;

/// The first element of what is signed.
const String kIntakeRequestTag = 'ocideck-intake-req-v1';

/// The scheme of the `Authorization` header.
const String kIntakeAuthScheme = 'OciIntake';

/// How far a request's time may be from the verifier's, either way: five minutes.
const Duration kIntakeRequestWindow = Duration(minutes: 5);

final Ed25519 _ed25519 = Ed25519();

/// The lower-case hex SHA-256 of nothing: the `body_sha256` of a request without a body.
final String kIntakeEmptyBodySha256 = sha256Hex(const <int>[]);

/// What is signed, as the canonical JSON text. Public so that a second implementation can check
/// its own preimage against the vector file.
String intakeRequestPreimage({
  required String host,
  required String method,
  required String target,
  required String bodySha256,
  required int ts,
  required String nonce,
}) => canonicalJson([
  kIntakeRequestTag,
  host,
  method,
  target,
  bodySha256,
  ts,
  nonce,
]);

/// A fresh nonce: 128 random bits as 26 characters.
String newIntakeNonce(Random random) => newFormId(random);

/// The `Authorization` header value that signs a request with [key].
///
/// [host] is the host the request goes to, [method] the HTTP method (any case), [target] the
/// request target as it will be sent (path and query), [body] the body bytes (none for a `GET`),
/// [ts] the Unix time in seconds and [nonce] a fresh one ([newIntakeNonce]).
Future<String> signIntakeRequest({
  required FormSigningKey key,
  required String host,
  required String method,
  required String target,
  required int ts,
  required String nonce,
  List<int> body = const [],
}) async {
  final preimage = intakeRequestPreimage(
    host: host,
    method: method.toUpperCase(),
    target: target,
    bodySha256: sha256Hex(body),
    ts: ts,
    nonce: nonce,
  );
  final pair = await _ed25519.newKeyPairFromSeed(key.seed);
  final signature = await _ed25519.sign(utf8.encode(preimage), keyPair: pair);
  return '$kIntakeAuthScheme key=${key.publicKeyText}, ts=$ts, nonce=$nonce, '
      'sig=${base32Encode(signature.bytes)}';
}

/// Why a request is not accepted as signed.
enum IntakeRequestIssue {
  /// No header, another scheme, a member missing, repeated or outside its grammar.
  malformed,

  /// `ts` is outside the window.
  expired,

  /// The signature does not hold for this key and this request.
  badSignature,
}

/// What [verifyIntakeRequest] decided.
sealed class IntakeRequestVerdict {
  const IntakeRequestVerdict();
}

/// The signature holds. **The key is authenticated, not authorised**: whether it may do this is
/// the server's decision, and the nonce is recorded only after it ([IntakeNonceCache.accept]).
class IntakeRequestVerified extends IntakeRequestVerdict {
  const IntakeRequestVerified({
    required this.signKey,
    required this.ts,
    required this.nonce,
  });

  /// The signer's public key, 52 characters of base32.
  final String signKey;

  final int ts;
  final String nonce;
}

class IntakeRequestRefused extends IntakeRequestVerdict {
  const IntakeRequestRefused(this.issue);

  final IntakeRequestIssue issue;
}

/// The four members of a header, read.
class _Auth {
  const _Auth(this.key, this.ts, this.nonce, this.sig);

  final Uint8List key;
  final int ts;
  final String nonce;
  final Uint8List sig;
}

_Auth? _readHeader(String? header) {
  if (header == null || !header.startsWith('$kIntakeAuthScheme ')) return null;
  final params = <String, String>{};
  for (final part in header.substring(kIntakeAuthScheme.length).split(',')) {
    final pair = part.split('=');
    if (pair.length != 2) return null;
    final name = pair[0].trim();
    if (params.containsKey(name)) return null;
    params[name] = pair[1].trim();
  }
  if (params.length != 4) return null;
  final key = base32Decode(params['key'] ?? '');
  final sig = base32Decode(params['sig'] ?? '');
  final tsText = params['ts'];
  final nonce = params['nonce'];
  if (key == null || key.length != 32) return null;
  if (sig == null || sig.length != 64) return null;
  if (tsText == null || !RegExp(r'^[1-9][0-9]{0,11}$').hasMatch(tsText)) {
    return null;
  }
  if (nonce == null || !isValidFormId(nonce)) return null;
  return _Auth(key, int.parse(tsText), nonce, sig);
}

/// Whether [header] signs this request, at [nowSeconds] (Unix time).
///
/// [host], [method] and [target] are what the **server** knows the request to be — its own public
/// host, the method it received, the target it received — never what the header claims, which
/// carries none of them. [bodySha256] is the hash of the body it actually read (or
/// [kIntakeEmptyBodySha256]); a server that streams computes it while reading and verifies after.
Future<IntakeRequestVerdict> verifyIntakeRequest({
  required String? header,
  required String host,
  required String method,
  required String target,
  required String bodySha256,
  required int nowSeconds,
}) async {
  final auth = _readHeader(header);
  if (auth == null) {
    return const IntakeRequestRefused(IntakeRequestIssue.malformed);
  }
  if ((nowSeconds - auth.ts).abs() > kIntakeRequestWindow.inSeconds) {
    return const IntakeRequestRefused(IntakeRequestIssue.expired);
  }
  final preimage = intakeRequestPreimage(
    host: host,
    method: method.toUpperCase(),
    target: target,
    bodySha256: bodySha256,
    ts: auth.ts,
    nonce: auth.nonce,
  );
  final valid = await _ed25519.verify(
    utf8.encode(preimage),
    signature: Signature(
      auth.sig,
      publicKey: SimplePublicKey(auth.key, type: KeyPairType.ed25519),
    ),
  );
  if (!valid) {
    return const IntakeRequestRefused(IntakeRequestIssue.badSignature);
  }
  return IntakeRequestVerified(
    signKey: base32Encode(auth.key),
    ts: auth.ts,
    nonce: auth.nonce,
  );
}

/// What [IntakeNonceCache.accept] decided.
enum IntakeNonceVerdict {
  /// Seen for the first time: remembered, and the request may go on.
  accepted,

  /// Seen before inside the window: a replay.
  replayed,

  /// The cache is full of nonces that are still inside the window: the server answers
  /// `rate-limited` rather than forget one and accept a replay.
  full,
}

/// The nonces a server has seen inside the window, so that a signed request cannot be played
/// again (§6.3). In memory on purpose: a restart forgets them, and what a restart can let through
/// is a replay inside the five-minute window — the same effect as a request made in that window,
/// to an operation that is idempotent or refused a second time by what it does.
class IntakeNonceCache {
  IntakeNonceCache({this.maxEntries = 50000});

  /// The most nonces held at once.
  final int maxEntries;

  /// `signKey:nonce` → the request's `ts`.
  final Map<String, int> _seen = {};

  /// How many nonces are held.
  int get length => _seen.length;

  /// Remembers the nonce of a request that **already passed authentication and authorisation**,
  /// at [nowSeconds].
  IntakeNonceVerdict accept({
    required String signKey,
    required String nonce,
    required int ts,
    required int nowSeconds,
  }) {
    // A nonce is only dangerous while its request's `ts` is still inside the window.
    final horizon = nowSeconds - kIntakeRequestWindow.inSeconds;
    _seen.removeWhere((_, seenTs) => seenTs < horizon);
    final id = '$signKey:$nonce';
    if (_seen.containsKey(id)) return IntakeNonceVerdict.replayed;
    if (_seen.length >= maxEntries) return IntakeNonceVerdict.full;
    _seen[id] = ts;
    return IntakeNonceVerdict.accepted;
  }
}
