// The XMPP-over-WebSocket connection state machine (F2, `NATIVE_CALLS.md` §5),
// driven to SASL authentication. Written against [XmppFrameTransport] so the whole
// flow is unit-tested with an in-memory fake and stored server frames — no socket.
// Reaching SASL success proves the account works, which is all a "test connection"
// needs; resource binding and the live session are F3.
//
// Security posture (security-architect design): SCRAM keeps the password off the
// wire and out of server logs and is tried first; ANONYMOUS covers public Jitsi;
// PLAIN is a fallback used only when `NetGuard.maySendReusableSecret` clears it
// over the (already TLS-wrapped) wss socket. A `<stream:error>` carrying
// `<see-other-host>` is refused, never followed — a hostile server must not
// redirect the stream to an internal address after the NetGuard host check.
//
// Failures are a typed [XmppAuthFailure], never a prose string: this layer carries
// no l10n (layering), so the UI maps the code to a translated message.

import 'dart:async';
import 'dart:convert';

import 'package:xml/xml.dart';

import '../models/xmpp_settings.dart';
import '../utils/log.dart';
import '../utils/net_guard.dart';
import 'xmpp_frame_transport.dart';
import 'xmpp_sasl.dart';
import 'xmpp_stanza.dart';

const _framingNs = 'urn:ietf:params:xml:ns:xmpp-framing';
const _saslNs = 'urn:ietf:params:xml:ns:xmpp-sasl';

/// Why an authentication attempt did not succeed. Mapped to a translated message
/// at the UI boundary.
enum XmppAuthFailure {
  /// The server offered no SASL mechanism OciDeck can use.
  noUsableMechanism,

  /// The username or password was rejected.
  badCredentials,

  /// The server did not prove it holds the password (SCRAM mutual auth).
  mutualAuthFailed,

  /// The server tried to redirect the stream to another host; refused.
  serverRedirect,

  /// The server closed the stream or replied unexpectedly.
  serverError,

  /// The server did not respond in time.
  timeout,

  /// The stream closed before authentication completed.
  streamClosed,

  /// The connection could not be opened (host refused, non-wss, TLS untrusted).
  transportRefused,

  /// The handshake failed for an unexpected reason.
  handshake,
}

/// The outcome of an authentication attempt. Never carries the password or the
/// raw exchange — only whether it worked, which mechanism, and a typed failure.
class XmppAuthResult {
  const XmppAuthResult.success(this.mechanism)
    : ok = true,
      failure = null,
      detail = null;
  const XmppAuthResult.failed(this.failure, {this.detail})
    : ok = false,
      mechanism = null;

  final bool ok;
  final String? mechanism;
  final XmppAuthFailure? failure;

  /// A non-translatable technical specific (a transport message, a SCRAM parse
  /// error), for diagnostics only — never the primary user-facing text.
  final String? detail;
}

/// Drives one stream from open to SASL authentication over an injected
/// [transport].
class XmppConnection {
  XmppConnection({
    required this.transport,
    required this.settings,
    this.password = '',
    String Function()? nonceFactory,
    this.timeout = const Duration(seconds: 20),
  }) : _nonce = nonceFactory ?? _defaultNonce;

  final XmppFrameTransport transport;
  final XmppSettings settings;
  final String password;
  final Duration timeout;
  final String Function() _nonce;

  late final _FrameReader _reader = _FrameReader(transport.inbound);

  /// Open the stream and authenticate. Returns a failed result (never throws) for
  /// an ordinary auth failure or a policy refusal; always closes the transport.
  Future<XmppAuthResult> authenticate() async {
    try {
      _send(
        xmppElement(
          'open',
          namespace: _framingNs,
          attributes: {'to': settings.domain, 'version': '1.0'},
        ),
      );
      final offered = await _awaitFeatures();
      if (offered is XmppAuthResult) return offered; // a stream-error refusal
      final chosen = _chooseMechanism(offered as Set<String>);
      if (chosen == null) {
        return const XmppAuthResult.failed(XmppAuthFailure.noUsableMechanism);
      }
      return await _runSasl(chosen);
    } on TimeoutException {
      return const XmppAuthResult.failed(XmppAuthFailure.timeout);
    } on XmppConnectException catch (e) {
      return XmppAuthResult.failed(
        XmppAuthFailure.transportRefused,
        detail: e.message,
      );
    } catch (e) {
      logWarning('XmppConnection.authenticate failed', e);
      return const XmppAuthResult.failed(XmppAuthFailure.handshake);
    } finally {
      await _reader.cancel();
      await transport.close();
    }
  }

  // ── stream negotiation ──────────────────────────────────────────────────────

  /// Read frames until `<stream:features>`; return the offered SASL mechanisms,
  /// or an [XmppAuthResult] refusal on a stream error / see-other-host.
  Future<Object> _awaitFeatures() async {
    while (true) {
      final element = _parse(await _reader.next(timeout));
      if (element == null) continue;
      switch (element.name.local) {
        case 'error':
          return _streamErrorResult(element);
        case 'features':
          return _mechanismsOf(element);
        // <open> (framing) and anything else before features: keep reading.
      }
    }
  }

  Set<String> _mechanismsOf(XmlElement features) {
    final container = features.descendantElements.firstWhere(
      (e) => e.name.local == 'mechanisms',
      orElse: () => XmlElement(XmlName.parts('mechanisms')),
    );
    return container.childElements
        .where((e) => e.name.local == 'mechanism')
        .map((e) => e.innerText.trim())
        .where((m) => m.isNotEmpty)
        .toSet();
  }

  XmppAuthResult _streamErrorResult(XmlElement error) {
    final redirect = error.descendantElements.any(
      (e) => e.name.local == 'see-other-host',
    );
    // Fail closed on a redirect: it could point at an internal host past the
    // NetGuard check (RFC 6120 §4.9.3.6). Refuse rather than re-connect.
    return XmppAuthResult.failed(
      redirect ? XmppAuthFailure.serverRedirect : XmppAuthFailure.serverError,
    );
  }

  /// SCRAM-SHA-256 > SCRAM-SHA-1 > PLAIN (only when the secret gate clears);
  /// ANONYMOUS when there is no localpart to log in as. Never PLAIN over a
  /// non-cleared line, never PLAIN in preference to SCRAM.
  String? _chooseMechanism(Set<String> offered) {
    if (settings.isAnonymous) {
      return offered.contains('ANONYMOUS') ? 'ANONYMOUS' : null;
    }
    if (offered.contains('SCRAM-SHA-256')) return 'SCRAM-SHA-256';
    if (offered.contains('SCRAM-SHA-1')) return 'SCRAM-SHA-1';
    if (offered.contains('PLAIN') && _mayUsePlain()) return 'PLAIN';
    return null;
  }

  bool _mayUsePlain() {
    // PLAIN puts the password on the wire, so it needs the reusable-secret gate.
    // Map wss→https / ws→http for the gate, which only knows the http(s) schemes.
    final scheme = settings.endpoint?.scheme.toLowerCase();
    final gate = switch (scheme) {
      'wss' => 'https',
      'ws' => 'http',
      _ => scheme,
    };
    return NetGuard.maySendReusableSecret(gate, host: settings.host);
  }

  // ── SASL ────────────────────────────────────────────────────────────────────

  Future<XmppAuthResult> _runSasl(String mechanism) {
    return switch (mechanism) {
      'ANONYMOUS' => _saslSimple('ANONYMOUS', null),
      'PLAIN' => _saslSimple('PLAIN', saslPlain(settings.localpart, password)),
      'SCRAM-SHA-1' => _saslScram(ScramHash.sha1),
      'SCRAM-SHA-256' => _saslScram(ScramHash.sha256),
      _ => Future.value(
        const XmppAuthResult.failed(XmppAuthFailure.serverError),
      ),
    };
  }

  /// A one-shot mechanism (ANONYMOUS/PLAIN): send `<auth>` and read the outcome.
  Future<XmppAuthResult> _saslSimple(String mechanism, String? initial) async {
    _send(
      xmppElement(
        'auth',
        namespace: _saslNs,
        attributes: {'mechanism': mechanism},
        text: initial,
      ),
    );
    return _readSaslOutcome(mechanism, null);
  }

  Future<XmppAuthResult> _saslScram(ScramHash hash) async {
    final scram = ScramClient(
      username: settings.localpart,
      password: password,
      clientNonce: _nonce(),
      hash: hash,
    );
    _send(
      xmppElement(
        'auth',
        namespace: _saslNs,
        attributes: {'mechanism': scram.mechanismName},
        text: base64.encode(utf8.encode(scram.clientFirst())),
      ),
    );
    final challenge = _parse(await _reader.next(timeout));
    if (challenge == null || challenge.name.local != 'challenge') {
      return _outcomeFrom(challenge, scram.mechanismName, null);
    }
    final serverFirst = utf8.decode(base64.decode(challenge.innerText.trim()));
    final String clientFinal;
    try {
      clientFinal = scram.clientFinal(serverFirst);
    } on FormatException catch (e) {
      return XmppAuthResult.failed(
        XmppAuthFailure.serverError,
        detail: e.message,
      );
    }
    _send(
      xmppElement(
        'response',
        namespace: _saslNs,
        text: base64.encode(utf8.encode(clientFinal)),
      ),
    );
    return _readSaslOutcome(scram.mechanismName, scram);
  }

  Future<XmppAuthResult> _readSaslOutcome(
    String mechanism,
    ScramClient? scram,
  ) async {
    return _outcomeFrom(_parse(await _reader.next(timeout)), mechanism, scram);
  }

  XmppAuthResult _outcomeFrom(
    XmlElement? element,
    String mechanism,
    ScramClient? scram,
  ) {
    if (element == null) {
      return const XmppAuthResult.failed(XmppAuthFailure.serverError);
    }
    switch (element.name.local) {
      case 'success':
        if (scram != null) {
          final serverFinal = utf8.decode(
            base64.decode(element.innerText.trim()),
          );
          if (!scram.verifyServerFinal(serverFinal)) {
            // The server did not prove it holds the password: refuse the login.
            return const XmppAuthResult.failed(XmppAuthFailure.mutualAuthFailed);
          }
        }
        return XmppAuthResult.success(mechanism);
      case 'failure':
        return _failureOutcome(element);
      default:
        return const XmppAuthResult.failed(XmppAuthFailure.serverError);
    }
  }

  XmppAuthResult _failureOutcome(XmlElement failure) {
    final condition = failure.childElements
        .map((e) => e.name.local)
        .firstWhere((n) => n != 'text', orElse: () => 'not-authorized');
    return switch (condition) {
      'not-authorized' || 'account-disabled' => const XmppAuthResult.failed(
        XmppAuthFailure.badCredentials,
      ),
      _ => XmppAuthResult.failed(
        XmppAuthFailure.serverError,
        detail: condition,
      ),
    };
  }

  void _send(XmlElement element) => transport.send(element.toXmlString());

  XmlElement? _parse(String frame) {
    final XmlDocument document;
    try {
      document = XmlDocument.parse(frame);
    } on XmlException {
      return null;
    }
    if (document.doctypeElement != null) return null; // XXE: XMPP forbids DTDs
    return document.rootElement;
  }

  static String _defaultNonce() {
    // A per-authentication nonce. Uniqueness (not unpredictability) is what SCRAM
    // needs of the client nonce; microsecond time plus a hashCode is enough and
    // avoids pulling in a CSPRNG dependency here.
    final now = DateTime.now().microsecondsSinceEpoch;
    return base64Url
        .encode(utf8.encode('$now.${Object().hashCode}'))
        .replaceAll('=', '');
  }
}

/// Buffers inbound frames so the state machine can pull them one at a time
/// (request/response), even when several arrive together.
class _FrameReader {
  _FrameReader(Stream<String> stream) {
    _sub = stream.listen(
      _onData,
      onDone: _onDone,
      onError: _onError,
      cancelOnError: false,
    );
  }

  final _queue = <String>[];
  final _waiters = <Completer<String>>[];
  late final StreamSubscription<String> _sub;
  bool _done = false;

  void _onData(String frame) {
    if (_waiters.isNotEmpty) {
      _waiters.removeAt(0).complete(frame);
    } else {
      _queue.add(frame);
    }
  }

  void _onDone() {
    _done = true;
    for (final w in _waiters) {
      w.completeError(const XmppConnectException('the XMPP stream closed'));
    }
    _waiters.clear();
  }

  void _onError(Object error, StackTrace stack) {
    for (final w in _waiters) {
      w.completeError(error, stack);
    }
    _waiters.clear();
  }

  Future<String> next(Duration timeout) {
    if (_queue.isNotEmpty) return Future.value(_queue.removeAt(0));
    if (_done) {
      return Future.error(const XmppConnectException('the XMPP stream closed'));
    }
    final completer = Completer<String>();
    _waiters.add(completer);
    return completer.future.timeout(timeout);
  }

  Future<void> cancel() => _sub.cancel();
}
