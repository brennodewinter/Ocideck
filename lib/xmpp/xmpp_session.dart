// A live XMPP client session (F3, `NATIVE_CALLS.md` §5): open the stream,
// authenticate (SASL), restart the stream, bind a resource, and then STAY OPEN —
// routing inbound stanzas to a stream and letting callers send stanzas. This is
// the persistent primitive the higher layers ride: MUC (XEP-0045, the Jitsi
// conference room and OciDeck's companion room, §5.1) and later Jingle. It
// supersedes the one-shot `XmppConnection` of F2 — a session that closes right
// after `connect()` is exactly the old "test connection", so the two are one
// primitive now, not two.
//
// Written against [XmppFrameTransport] so the whole flow is unit-tested with an
// in-memory fake and stored server frames — no socket. Security posture is
// inherited from F2 and unchanged: SCRAM keeps the password off the wire and is
// tried first; ANONYMOUS covers public Jitsi; PLAIN is used only when
// `NetGuard.maySendReusableSecret` clears it over the (already TLS-wrapped) wss
// socket; a `<see-other-host>` stream redirect is refused, never followed.
//
// Failures are a typed [XmppSessionFailure], never prose: this layer carries no
// l10n (layering), so the UI maps the code to a translated message.

import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:xml/xml.dart';

import '../models/xmpp_settings.dart';
import '../utils/log.dart';
import '../utils/net_guard.dart';
import 'xmpp_frame_transport.dart';
import 'xmpp_sasl.dart';
import 'xmpp_stanza.dart';

const _framingNs = 'urn:ietf:params:xml:ns:xmpp-framing';
const _saslNs = 'urn:ietf:params:xml:ns:xmpp-sasl';
const _bindNs = 'urn:ietf:params:xml:ns:xmpp-bind';

/// Why bringing a session up did not succeed. Mapped to a translated message at
/// the UI boundary.
enum XmppSessionFailure {
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

  /// Authentication succeeded but binding a resource did not.
  resourceBindFailed,

  /// The server did not respond in time.
  timeout,

  /// The connection could not be opened (host refused, non-wss, TLS untrusted).
  transportRefused,

  /// The handshake failed for an unexpected reason.
  handshake,
}

/// The outcome of [XmppSession.connect]. Never carries the password or the raw
/// exchange — only whether it worked, the mechanism, the bound full JID, or a
/// typed failure. On success the session is live until [XmppSession.close].
class XmppSessionResult {
  const XmppSessionResult.ok({required this.mechanism, required this.boundJid})
    : failure = null,
      detail = null;
  const XmppSessionResult.failed(this.failure, {this.detail})
    : mechanism = null,
      boundJid = null;

  bool get ok => failure == null;
  final String? mechanism;

  /// The full JID (`user@domain/resource`) the server bound, on success.
  final String? boundJid;
  final XmppSessionFailure? failure;

  /// A non-translatable technical specific (a transport message, a SCRAM parse
  /// error), for diagnostics only — never the primary user-facing text.
  final String? detail;
}

/// Drives one stream from open through SASL and resource binding to a live
/// session. Call [connect] once; on success use [stanzas]/[sendStanza] until
/// [close].
class XmppSession {
  XmppSession({
    required this.transport,
    required this.settings,
    this.password = '',
    this.resource,
    String Function()? nonceFactory,
    this.timeout = const Duration(seconds: 20),
  }) : _nonce = nonceFactory ?? _defaultNonce;

  final XmppFrameTransport transport;
  final XmppSettings settings;
  final String password;
  final Duration timeout;

  /// The resource to request at bind (RFC 6120 §7); null lets the server assign
  /// one. Kept out of the JID so two OciDeck clients on one account never clash.
  final String? resource;
  final String Function() _nonce;

  late final _FrameReader _reader = _FrameReader(transport.inbound);
  final _inbound = StreamController<Stanza>.broadcast();
  String? _boundJid;
  bool _live = false;
  bool _closed = false;

  /// The full JID the server bound (`localpart@domain/resource`), or null before
  /// a successful [connect].
  String? get boundJid => _boundJid;

  /// Inbound stanzas, once the session is live. Broadcast, so a late listener
  /// only sees stanzas from the moment it subscribes — subscribe before the work
  /// that expects replies (e.g. join a room, then read presence).
  Stream<Stanza> get stanzas => _inbound.stream;

  /// Open the stream, authenticate, and bind a resource. Returns a failed result
  /// (never throws) for an ordinary failure or a policy refusal. On success the
  /// session is LIVE and the caller owns it until [close]; on failure the
  /// transport is already closed.
  Future<XmppSessionResult> connect() async {
    try {
      final auth = await _authenticate();
      if (auth != null) return _fail(auth); // a SASL/stream failure
      final bound = await _bindResource();
      _boundJid = bound;
      _live = true;
      _startDispatch();
      return XmppSessionResult.ok(mechanism: _mechanism!, boundJid: bound);
    } on TimeoutException {
      return _fail(XmppSessionFailure.timeout);
    } on XmppConnectException catch (e) {
      return _fail(XmppSessionFailure.transportRefused, detail: e.message);
    } on _BindException catch (e) {
      return _fail(XmppSessionFailure.resourceBindFailed, detail: e.message);
    } catch (e) {
      logWarning('XmppSession.connect failed', e);
      return _fail(XmppSessionFailure.handshake);
    }
  }

  Future<XmppSessionResult> _fail(
    XmppSessionFailure failure, {
    String? detail,
  }) async {
    await close();
    return XmppSessionResult.failed(failure, detail: detail);
  }

  String? _mechanism;

  // ── authentication (SASL) ─────────────────────────────────────────────────

  /// Open the stream and run SASL. Returns null on success (mechanism recorded),
  /// or the failure to report.
  Future<XmppSessionFailure?> _authenticate() async {
    _openStream();
    final offered = await _awaitFeatures();
    if (offered is XmppSessionFailure) return offered; // stream-error refusal
    final chosen = _chooseMechanism(offered as Set<String>);
    if (chosen == null) return XmppSessionFailure.noUsableMechanism;
    return _runSasl(chosen);
  }

  void _openStream() {
    _send(
      xmppElement(
        'open',
        namespace: _framingNs,
        attributes: {'to': settings.domain, 'version': '1.0'},
      ),
    );
  }

  /// Read frames until `<stream:features>`; return the offered SASL mechanisms,
  /// or an [XmppSessionFailure] on a stream error / see-other-host.
  Future<Object> _awaitFeatures() async {
    while (true) {
      final element = _parse(await _reader.next(timeout));
      if (element == null) continue;
      switch (element.name.local) {
        case 'error':
          return _streamErrorFailure(element);
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

  XmppSessionFailure _streamErrorFailure(XmlElement error) {
    final redirect = error.descendantElements.any(
      (e) => e.name.local == 'see-other-host',
    );
    // Fail closed on a redirect: it could point at an internal host past the
    // NetGuard check (RFC 6120 §4.9.3.6). Refuse rather than re-connect.
    return redirect
        ? XmppSessionFailure.serverRedirect
        : XmppSessionFailure.serverError;
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

  Future<XmppSessionFailure?> _runSasl(String mechanism) {
    return switch (mechanism) {
      'ANONYMOUS' => _saslSimple('ANONYMOUS', null),
      'PLAIN' => _saslSimple('PLAIN', saslPlain(settings.localpart, password)),
      'SCRAM-SHA-1' => _saslScram(ScramHash.sha1),
      'SCRAM-SHA-256' => _saslScram(ScramHash.sha256),
      _ => Future.value(XmppSessionFailure.serverError),
    };
  }

  /// A one-shot mechanism (ANONYMOUS/PLAIN): send `<auth>` and read the outcome.
  Future<XmppSessionFailure?> _saslSimple(
    String mechanism,
    String? initial,
  ) async {
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

  Future<XmppSessionFailure?> _saslScram(ScramHash hash) async {
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
    } on FormatException {
      return XmppSessionFailure.serverError;
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

  Future<XmppSessionFailure?> _readSaslOutcome(
    String mechanism,
    ScramClient? scram,
  ) async {
    return _outcomeFrom(_parse(await _reader.next(timeout)), mechanism, scram);
  }

  XmppSessionFailure? _outcomeFrom(
    XmlElement? element,
    String mechanism,
    ScramClient? scram,
  ) {
    if (element == null) return XmppSessionFailure.serverError;
    switch (element.name.local) {
      case 'success':
        if (scram != null) {
          final serverFinal = utf8.decode(
            base64.decode(element.innerText.trim()),
          );
          if (!scram.verifyServerFinal(serverFinal)) {
            // The server did not prove it holds the password: refuse the login.
            return XmppSessionFailure.mutualAuthFailed;
          }
        }
        _mechanism = mechanism;
        return null; // success
      case 'failure':
        return _failureOutcome(element);
      default:
        return XmppSessionFailure.serverError;
    }
  }

  XmppSessionFailure _failureOutcome(XmlElement failure) {
    final condition = failure.childElements
        .map((e) => e.name.local)
        .firstWhere((n) => n != 'text', orElse: () => 'not-authorized');
    return switch (condition) {
      'not-authorized' || 'account-disabled' =>
        XmppSessionFailure.badCredentials,
      _ => XmppSessionFailure.serverError,
    };
  }

  // ── resource binding ──────────────────────────────────────────────────────

  /// After SASL, XMPP requires a stream restart, then the client binds a resource
  /// (RFC 6120 §7). Returns the bound full JID; throws [_BindException] on
  /// anything unexpected.
  Future<String> _bindResource() async {
    _openStream(); // restart the stream after SASL
    await _awaitPostAuthFeatures(); // features carrying <bind/>
    const bindId = 'bind-1';
    _send(
      xmppElement(
        'iq',
        attributes: {'type': 'set', 'id': bindId},
        children: [
          xmppElement(
            'bind',
            namespace: _bindNs,
            children: [
              if (resource != null) xmppElement('resource', text: resource),
            ],
          ),
        ],
      ),
    );
    final reply = _parse(await _reader.next(timeout));
    if (reply == null ||
        reply.name.local != 'iq' ||
        reply.getAttribute('type') != 'result') {
      throw const _BindException('resource bind was refused');
    }
    final jid = reply.descendantElements
        .firstWhere(
          (e) => e.name.local == 'jid',
          orElse: () => XmlElement(XmlName.parts('jid')),
        )
        .innerText
        .trim();
    if (jid.isEmpty) throw const _BindException('bind result carried no JID');
    return jid;
  }

  /// Read frames until the post-restart `<stream:features>`, tolerating the
  /// framing `<open>` echo. A stream error here is fatal to bind.
  Future<void> _awaitPostAuthFeatures() async {
    while (true) {
      final element = _parse(await _reader.next(timeout));
      if (element == null) continue;
      switch (element.name.local) {
        case 'error':
          throw const _BindException('stream error before bind');
        case 'features':
          return;
      }
    }
  }

  // ── live dispatch ─────────────────────────────────────────────────────────

  /// Hand every remaining and future frame to [stanzas] as a parsed [Stanza].
  /// A frame that is not a valid stanza (or carries a DTD) is dropped, not fatal.
  void _startDispatch() {
    _reader.drain((frame) {
      if (_closed) return;
      final Stanza stanza;
      try {
        stanza = Stanza.parse(frame);
      } on FormatException {
        return; // not a stanza (or a DTD) — ignore
      }
      if (!_inbound.isClosed) _inbound.add(stanza);
    });
  }

  /// Send a stanza on the live session. A no-op once closed.
  void sendStanza(Stanza stanza) {
    if (_closed || !_live) return;
    transport.send(stanza.toXmlString());
  }

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    _live = false;
    await _reader.cancel();
    await transport.close();
    if (!_inbound.isClosed) await _inbound.close();
  }

  // ── helpers ───────────────────────────────────────────────────────────────

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
    // SCRAM wants a client nonce that is both unique and unpredictable
    // (RFC 5802 §5.1). Random.secure() is a CSPRNG in dart:math — no dependency.
    // 24 random bytes, base64url (its alphabet has no ',', which SCRAM forbids).
    final rng = Random.secure();
    final bytes = List<int>.generate(24, (_) => rng.nextInt(256));
    return base64Url.encode(bytes).replaceAll('=', '');
  }
}

class _BindException implements Exception {
  const _BindException(this.message);
  final String message;
  @override
  String toString() => 'XMPP bind failed: $message';
}

/// Buffers inbound frames so the handshake can pull them one at a time
/// (request/response), then [drain] switches to pushing every frame to a sink
/// once the session goes live.
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
  void Function(String frame)? _drain;

  void _onData(String frame) {
    if (_drain != null) {
      _drain!(frame);
    } else if (_waiters.isNotEmpty) {
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

  /// Switch to push mode: flush what is buffered and route every future frame to
  /// [onFrame]. Pull-mode [next] must not be used after this.
  void drain(void Function(String frame) onFrame) {
    _drain = onFrame;
    final buffered = List<String>.of(_queue);
    _queue.clear();
    for (final frame in buffered) {
      onFrame(frame);
    }
  }

  Future<void> cancel() => _sub.cancel();
}
