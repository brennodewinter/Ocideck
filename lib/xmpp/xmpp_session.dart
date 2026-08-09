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
const _clientNs = 'jabber:client';

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

/// The stanza-level surface of a live session: what the layers above (MUC, later
/// Jingle) actually need — send a stanza, watch inbound ones, know the bound JID.
/// [XmppSession] is the real implementation; a test drives those layers against a
/// fake channel without standing up a whole session.
abstract interface class XmppStanzaChannel {
  /// The bound full JID (`localpart@domain/resource`), or null before connect.
  String? get boundJid;

  /// Inbound stanzas once live (broadcast: subscribe before the work expecting
  /// replies). Completes when the stream drops.
  Stream<Stanza> get stanzas;

  /// Send a stanza on the live session. A no-op once closed.
  void sendStanza(Stanza stanza);
}

/// Begrensde exponentiële backoff voor reconnect-pogingen: 1s, 2s, 4s, 8s,
/// 16s, gecapt op 30s. Een persistente storing mag niet eindeloos draaien of
/// absurd lang uitstellen — na [XmppSession.maxReconnectAttempts] pogingen
/// gaat de sessie fail-closed.
Duration xmppReconnectDelay(int attempt) {
  // Begrens de shift bij 5 (1<<5 = 32 ≥ 30) zodat een grote attempt-waarde
  // geen int-overflow geeft (1<<64 wordt 0 op een 64-bit int).
  final seconds = min(1 << min(attempt, 5), 30);
  return Duration(seconds: seconds);
}

/// Drives one stream from open through SASL and resource binding to a live
/// session. Call [connect] once; on success use [stanzas]/[sendStanza] until
/// [close].
///
/// With a [reconnectTransportFactory], a stream drop on a live session triggers
/// a supervised reconnect (§4): bounded backoff, re-authenticate, re-bind, then
/// [onRejoin] re-enters the MUC room(s) and [onReconnected] signals the
/// transport layer to resync. The factory always returns a transport to the
/// same NetGuard-cleared host — never a new outbound host; a `<see-other-host>`
/// during reconnect is refused just as on the initial connect.
class XmppSession implements XmppStanzaChannel {
  XmppSession({
    required this.transport,
    required this.settings,
    this.password = '',
    this.resource,
    String Function()? nonceFactory,
    this.timeout = const Duration(seconds: 20),
    this.reconnectTransportFactory,
    this.onRejoin,
    this.maxReconnectAttempts = 5,
    this.reconnectDelay = xmppReconnectDelay,
  }) : _nonce = nonceFactory ?? _defaultNonce;

  /// The active transport — replaced on each reconnect. Mutable because a
  /// reconnect swaps in a fresh [XmppFrameTransport] to the same host.
  XmppFrameTransport transport;
  final XmppSettings settings;
  final String password;
  final Duration timeout;

  /// The resource to request at bind (RFC 6120 §7); null lets the server assign
  /// one. Kept out of the JID so two OciDeck clients on one account never clash.
  final String? resource;
  final String Function() _nonce;

  /// A factory that produces a fresh transport for a reconnect, always to the
  /// same NetGuard-cleared host — never a new outbound host. If null, a stream
  /// drop tears down the session (the pre-reconnect behaviour).
  ///
  /// Async because the real transport ([openXmppFrameTransport]) opens a
  /// WebSocket — a synchronous signature could only return a fake.
  final Future<XmppFrameTransport> Function()? reconnectTransportFactory;

  /// Called after a successful reconnect, so the higher layer can rejoin its
  /// MUC room(s). Receives the session (now live again) as the channel. Returns
  /// `true` als de rejoin slaagde, `false` als de kamer niet betreden kon worden
  /// (bijv. nick-conflict — de oude occupant is nog niet uitgelogd). Bij `false`
  /// gaat `_reconnect` naar de volgende backoff-poging in plaats van succes te
  /// claimen (#1416).
  final Future<bool> Function(XmppStanzaChannel)? onRejoin;

  /// Max reconnect attempts before the session goes fail-closed.
  final int maxReconnectAttempts;

  /// Backoff delay before reconnect attempt *n* (0-indexed). Override for
  /// tests; the default is [xmppReconnectDelay] (exponential, capped at 30s).
  final Duration Function(int) reconnectDelay;

  late _FrameReader _reader;
  final _inbound = StreamController<Stanza>.broadcast();
  final _reconnected = StreamController<void>.broadcast();
  String? _boundJid;
  bool _live = false;
  bool _closed = false;
  bool _reconnecting = false;

  /// Outbound stanzas die tijdens een reconnect werden verzonden (_live =
  /// false). Begrensd op 64 — een aanhoudende stroom tijdens een lange
  /// reconnect mag het geheugen niet uitputten (#1417). Na een geslaagde
  /// reconnect spoelt `_reconnect` de queue naar de nieuwe transport; bij
  /// fail-closed wordt de queue gewist.
  static const _outboundQueueCap = 64;
  final List<String> _outboundQueue = [];

  /// The full JID the server bound (`localpart@domain/resource`), or null before
  /// a successful [connect].
  @override
  String? get boundJid => _boundJid;

  /// Inbound stanzas, once the session is live. Broadcast, so a late listener
  /// only sees stanzas from the moment it subscribes — subscribe before the work
  /// that expects replies (e.g. join a room, then read presence).
  ///
  /// Survives a reconnect: the stream stays open across a drop→reconnect cycle,
  /// so a consumer (the MUC layer) keeps its subscription and receives stanzas
  /// from the new connection without re-subscribing. Completes only when the
  /// session goes fail-closed (max reconnect attempts exceeded) or [close].
  @override
  Stream<Stanza> get stanzas => _inbound.stream;

  /// Fires once after each successful reconnect + [onRejoin], so the transport
  /// layer can trigger a resync (§4 sub-plak 4). Completes when the session
  /// closes for good.
  Stream<void> get onReconnected => _reconnected.stream;

  /// Open the stream, authenticate, and bind a resource. Returns a failed result
  /// (never throws) for an ordinary failure or a policy refusal. On success the
  /// session is LIVE and the caller owns it until [close]; on failure the
  /// transport is already closed.
  Future<XmppSessionResult> connect() async {
    _reader = _FrameReader(transport.inbound);
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
      return _fail(e.failure, detail: e.message);
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
      'not-authorized' ||
      'account-disabled' => XmppSessionFailure.badCredentials,
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
          // A post-auth <see-other-host> is still refused, never followed;
          // classify it as precisely as a pre-auth one (same fail-closed
          // posture — never re-connect to a server-named host).
          throw _BindException(
            'stream error before bind',
            _streamErrorFailure(element),
          );
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
        return; // not a stanza (or a DTD) — ignore, never fatal
      }
      if (!_inbound.isClosed) _inbound.add(stanza);
    }, onClosed: _onStreamDropped);
  }

  /// The server ended the stream on a live session (EOF or error). Mark it
  /// dead. With a [reconnectTransportFactory], keep [stanzas] open and start a
  /// supervised reconnect (§4); without one, close [stanzas] so a consumer
  /// (the MUC layer) learns the room is gone — the pre-reconnect behaviour.
  void _onStreamDropped() {
    _live = false;
    if (reconnectTransportFactory != null && !_closed && !_reconnecting) {
      _reconnecting = true;
      unawaited(_reconnect());
    } else if (!_reconnecting) {
      // No reconnect: tear down as before (pre-reconnect behaviour).
      if (!_inbound.isClosed) _inbound.close();
    }
    // If _reconnecting is already true, the running reconnect loop will see
    // _live is still false and retry — no need to start a second loop.
  }

  /// Supervised reconnect with bounded backoff (§4). Re-runs the full
  /// handshake (open→SASL→bind) on a fresh transport from the factory — always
  /// to the same NetGuard-cleared host, never a new outbound host. On success,
  /// restarts dispatch, calls [onRejoin] so the higher layer re-enters its MUC
  /// room(s), and fires [onReconnected] so the transport layer can resync. On
  /// failure, backs off and retries; after [maxReconnectAttempts] the session
  /// goes fail-closed (stanzas completes, no further attempts).
  Future<void> _reconnect() async {
    try {
      for (var attempt = 0; attempt < maxReconnectAttempts; attempt++) {
        if (_closed) return;
        await Future<void>.delayed(reconnectDelay(attempt));
        if (_closed) return;
        try {
          // Ruim de oude verbinding op en maak een verse transport aan — altijd
          // naar dezelfde host, nooit een nieuwe outbound host.
          await _reader.cancel();
          await transport.close();
          transport = await reconnectTransportFactory!();
          _reader = _FrameReader(transport.inbound);

          final auth = await _authenticate();
          if (auth != null) continue; // SASL-/stream-fout → backoff en opnieuw
          final bound = await _bindResource();
          _boundJid = bound;
          _live = true;
          _startDispatch();
          // Rejoin de kamer(s), dan signaleer de transport-laag voor een resync.
          // Als onRejoin false retourneert (bijv. nick-conflict), claim geen
          // succes — ga naar de volgende backoff-poging (#1416).
          if (onRejoin != null) {
            final rejoined = await onRejoin!(this);
            if (!rejoined) {
              _live = false;
              continue; // rejoin faalde — backoff en opnieuw
            }
          }
          if (!_reconnected.isClosed) _reconnected.add(null);
          // Spoel de outbound-queue — stanzas die tijdens de reconnect werden
          // verzonden, gaan nu alsnog op de wire (#1417).
          _flushOutboundQueue();
          return; // success
        } on TimeoutException {
          continue; // server reageerde niet — backoff en opnieuw
        } on XmppConnectException {
          continue; // transport weigerde of stream sloot — backoff en opnieuw
        } on _BindException {
          continue; // bind faalde — backoff en opnieuw
        } catch (e) {
          logWarning('XmppSession.reconnect poging $attempt faalde', e);
          continue;
        }
      }
      // Max pogingen bereikt — fail-closed: de sessie is dood.
      _boundJid = null;
      _outboundQueue.clear();
      if (!_inbound.isClosed) await _inbound.close();
    } finally {
      _reconnecting = false;
      // Viel de stream opnieuw tijdens onRejoin (nadat we _live = true zetten
      // maar voordat de loop eindigde)? Dan zag _onStreamDropped _reconnecting
      // = true en startte geen nieuwe loop. Start hem nu.
      if (!_live &&
          !_closed &&
          !_inbound.isClosed &&
          reconnectTransportFactory != null) {
        _reconnecting = true;
        unawaited(_reconnect());
      }
    }
  }

  /// Spoel de gebufferde outbound stanzas naar de huidige transport. Leegt de
  /// queue ongeacht of de transport ze accepteert — een send-fout op één stanza
  /// mag niet de hele queue laten hangen.
  void _flushOutboundQueue() {
    if (_outboundQueue.isEmpty) return;
    for (final frame in _outboundQueue) {
      if (!_closed && _live) transport.send(frame);
    }
    _outboundQueue.clear();
  }

  /// Send a stanza on the live session. A no-op once closed. Tijdens een
  /// reconnect (_live = false met een reconnect-factory) wordt de stanza
  /// gebufferd en na een geslaagde reconnect gespoeld (#1417) — in plaats van
  /// stil gedropt te worden.
  @override
  void sendStanza(Stanza stanza) {
    if (_closed) return;
    if (_live) {
      transport.send(stanza.toXmlString());
    } else if (reconnectTransportFactory != null) {
      if (_outboundQueue.length < _outboundQueueCap) {
        _outboundQueue.add(stanza.toXmlString());
      }
    }
    // Geen reconnect-factory en niet live — pre-reconnect gedrag: drop stil.
  }

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    _live = false;
    await _reader.cancel();
    await transport.close();
    if (!_inbound.isClosed) await _inbound.close();
    if (!_reconnected.isClosed) await _reconnected.close();
  }

  // ── helpers ───────────────────────────────────────────────────────────────

  void _send(XmlElement element) {
    // In XMPP-over-WebSocket (RFC 7395) each frame is a standalone XML
    // document — the jabber:client default namespace is NOT inherited from
    // the stream (the <open> frame carries the framing namespace, not
    // jabber:client). Stanzas (iq/message/presence) sent without xmlns land
    // in the empty namespace, which Prosody rejects as "unhandled". Add
    // xmlns="jabber:client" when the element doesn't already carry one.
    final hasNs = element.attributes.any((a) => a.name.local == 'xmlns');
    if (hasNs) {
      transport.send(element.toXmlString());
    } else {
      final withNs = XmlElement(element.name, [
        XmlAttribute(XmlName.parts('xmlns'), _clientNs),
        ...element.attributes,
      ], element.children);
      transport.send(withNs.toXmlString());
    }
  }

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
  const _BindException(
    this.message, [
    this.failure = XmppSessionFailure.resourceBindFailed,
  ]);
  final String message;
  final XmppSessionFailure failure;
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

  /// Max frames buffered before the handshake drains them. A hostile server
  /// can flood frames faster than the handshake pulls them; without a cap the
  /// queue grows unbounded (memory exhaustion).
  static const _maxQueueSize = 256;

  /// Max bytes in one frame. XMPP stanzas are small; a frame above this is
  /// either a malformed stream or a deliberate memory bomb.
  static const _maxFrameBytes = 512 * 1024;

  final _queue = <String>[];
  final _waiters = <Completer<String>>[];
  late final StreamSubscription<String> _sub;
  bool _done = false;
  void Function(String frame)? _drain;
  void Function()? _onClosed;

  void _onData(String frame) {
    // Refuse an oversized frame: a hostile server can send a multi-MB frame
    // to exhaust memory. Drop it rather than allocating it into the queue.
    if (frame.length > _maxFrameBytes) return;
    if (_drain != null) {
      _drain!(frame);
    } else if (_waiters.isNotEmpty) {
      _waiters.removeAt(0).complete(frame);
    } else {
      if (_queue.length >= _maxQueueSize) {
        _sub.cancel();
        _onError(
          const XmppConnectException('XMPP frame queue overflow'),
          StackTrace.empty,
        );
        return;
      }
      _queue.add(frame);
    }
  }

  void _onDone() {
    _done = true;
    _onClosed?.call(); // in drain mode, tell the session the stream ended
    for (final w in _waiters) {
      w.completeError(const XmppConnectException('the XMPP stream closed'));
    }
    _waiters.clear();
  }

  void _onError(Object error, StackTrace stack) {
    _onClosed?.call(); // a live-session error is a stream drop too
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
  /// [onFrame]; [onClosed] fires once when the stream ends or errors. Pull-mode
  /// [next] must not be used after this.
  void drain(void Function(String frame) onFrame, {void Function()? onClosed}) {
    _drain = onFrame;
    _onClosed = onClosed;
    final buffered = List<String>.of(_queue);
    _queue.clear();
    for (final frame in buffered) {
      onFrame(frame);
    }
    if (_done) onClosed?.call(); // stream already ended before we drained
  }

  Future<void> cancel() => _sub.cancel();
}
