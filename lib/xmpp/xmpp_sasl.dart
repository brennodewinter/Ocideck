// SASL for the XMPP stream (RFC 6120 §6; RFC 5802 SCRAM). Pure and offline: these
// produce and consume the SASL exchange messages; the connection layer moves the
// bytes. Kept apart from the socket so the security-critical crypto is unit-tested
// against the RFC 5802 §5 test vector with no network in the way.
//
// Mechanism policy (security-architect design, F2): **SCRAM-SHA-1/256 is
// primary** — it keeps the password off the wire (only a proof crosses) and out
// of the server's logs, and a bring-your-own Prosody often offers only SCRAM.
// **ANONYMOUS** covers public Jitsi (anonymous auth). **PLAIN** sends the
// password and is a fallback used only over a TLS'd (wss) socket that
// `NetGuard.maySendReusableSecret` has cleared — never over an unencrypted
// stream, never in preference to SCRAM.

import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

import '../utils/secure_compare.dart';

/// SASL PLAIN: `base64("\0" authcid "\0" password)`. The caller MUST have gated
/// this behind `NetGuard.maySendReusableSecret` over a live TLS (wss) socket —
/// PLAIN puts the password on the wire.
String saslPlain(String authcid, String password) =>
    base64.encode(utf8.encode('\u0000$authcid\u0000$password'));

/// SASL ANONYMOUS: an optional trace token (an empty response is valid). For
/// servers that grant anonymous access (public Jitsi).
String saslAnonymous([String trace = '']) => base64.encode(utf8.encode(trace));

/// Which digest a [ScramClient] uses.
enum ScramHash { sha1, sha256 }

/// The client half of one SCRAM exchange (RFC 5802). The [clientNonce] is
/// injected so the exchange is deterministic under test; in production it is a
/// fresh random string per authentication.
class ScramClient {
  ScramClient({
    required this.username,
    required this.password,
    required this.clientNonce,
    this.hash = ScramHash.sha1,
  });

  final String username;
  final String password;
  final String clientNonce;
  final ScramHash hash;

  String? _clientFirstBare;
  Uint8List? _saltedPassword;
  String? _authMessage;

  Hash get _digest => hash == ScramHash.sha1 ? sha1 : sha256;

  /// The SASL mechanism name to advertise.
  String get mechanismName =>
      hash == ScramHash.sha1 ? 'SCRAM-SHA-1' : 'SCRAM-SHA-256';

  /// The client-first message, GS2 header included (`n,,` — no channel binding).
  /// The username is SASL-name-escaped (RFC 5802 §5.1).
  String clientFirst() {
    final bare = 'n=${_saslName(username)},r=$clientNonce';
    _clientFirstBare = bare;
    return 'n,,$bare';
  }

  /// Consume the server-first message and return the client-final message,
  /// proof included. Throws [FormatException] on a malformed message, or when the
  /// combined nonce does not extend the client nonce (a replay/MITM guard).
  String clientFinal(String serverFirst) {
    if (_clientFirstBare == null) {
      throw StateError('clientFirst() must be called before clientFinal()');
    }
    final attrs = _parseAttrs(serverFirst);
    final combinedNonce = attrs['r'];
    final salt = attrs['s'];
    final iterations = attrs['i'];
    if (combinedNonce == null || salt == null || iterations == null) {
      throw const FormatException('malformed SCRAM server-first message');
    }
    if (!combinedNonce.startsWith(clientNonce) ||
        combinedNonce == clientNonce) {
      throw const FormatException(
        'SCRAM server nonce does not extend the client nonce',
      );
    }
    final count = int.tryParse(iterations);
    // Upper bound: a hostile server can send an absurd iteration count to
    // pin the client in a PBKDF2 loop (DoS). RFC 5802 sets no maximum, but
    // 100 000 is well above any legitimate server (RFC 7677 recommends
    // 15 000 for SCRAM-SHA-256) and keeps the client responsive.
    if (count == null || count < 1 || count > 100000) {
      throw const FormatException('invalid SCRAM iteration count');
    }

    // base64("n,,") == "biws" — the GS2 header, echoed as the channel-binding
    // attribute since no real channel binding is used.
    const channelBinding = 'biws';
    final clientFinalNoProof = 'c=$channelBinding,r=$combinedNonce';

    final salted = _hi(utf8.encode(password), base64.decode(salt), count);
    _saltedPassword = salted;
    final clientKey = _hmac(salted, utf8.encode('Client Key'));
    final storedKey = Uint8List.fromList(_digest.convert(clientKey).bytes);
    final authMessage = '$_clientFirstBare,$serverFirst,$clientFinalNoProof';
    _authMessage = authMessage;
    final clientSignature = _hmac(storedKey, utf8.encode(authMessage));
    final proof = _xor(clientKey, clientSignature);
    return '$clientFinalNoProof,p=${base64.encode(proof)}';
  }

  /// Verify the server-final `v=` (ServerSignature): proof the server also held
  /// the password (mutual authentication). Call only after [clientFinal]. Uses a
  /// constant-time compare. Returns false on any mismatch or malformed input.
  bool verifyServerFinal(String serverFinal) {
    final signature = _parseAttrs(serverFinal)['v'];
    if (signature == null || _saltedPassword == null || _authMessage == null) {
      return false;
    }
    final serverKey = _hmac(_saltedPassword!, utf8.encode('Server Key'));
    final expected = _hmac(serverKey, utf8.encode(_authMessage!));
    return constantTimeEqualsBytes(base64.decode(signature), expected);
  }

  Uint8List _hmac(List<int> key, List<int> data) =>
      Uint8List.fromList(Hmac(_digest, key).convert(data).bytes);

  /// Hi(str, salt, i) — PBKDF2/HMAC over a single output block (RFC 5802 §2.2).
  Uint8List _hi(List<int> str, List<int> salt, int iterations) {
    final result = _hmac(str, [...salt, 0, 0, 0, 1]);
    var previous = Uint8List.fromList(result);
    for (var i = 1; i < iterations; i++) {
      final next = _hmac(str, previous);
      for (var j = 0; j < result.length; j++) {
        result[j] ^= next[j];
      }
      previous = next;
    }
    return result;
  }

  Uint8List _xor(List<int> a, List<int> b) {
    final out = Uint8List(a.length);
    for (var i = 0; i < a.length; i++) {
      out[i] = a[i] ^ b[i];
    }
    return out;
  }

  /// RFC 5802 §5.1 SASL-name escaping: `=` → `=3D`, `,` → `=2C`.
  String _saslName(String value) =>
      value.replaceAll('=', '=3D').replaceAll(',', '=2C');

  /// Parse `k=v,k=v,…` where each key is one character (SCRAM attributes). A `=`
  /// inside a value (base64 padding) stays with the value — only the first `=`
  /// splits.
  Map<String, String> _parseAttrs(String message) {
    final out = <String, String>{};
    for (final part in message.split(',')) {
      final eq = part.indexOf('=');
      if (eq > 0) out[part.substring(0, eq)] = part.substring(eq + 1);
    }
    return out;
  }
}
