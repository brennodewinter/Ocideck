// De XMPP-collab-data-plane: `XmppTransport implements CollabTransport`
// (`docs/design/XMPP_COLLAB_TRANSPORT.md` §3–5). Draagt ops/locks verzegeld
// over de companion-MUC, op dezelfde `CollabTransport`-naad waarop
// `collab_session.dart` vandaag al tegen `LoopbackTransport` en
// `MatrixRelayTransport` praat — de autoriteit/versie/lock-logica verandert
// niet, alleen de buis eronder.
//
// Wat deze laag toevoegt boven de Matrix-relay (§4): een **gap→resync**-pad.
// Matrix's `/sync` levert gap-vrij en hervatbaar; een MUC doet dat niet — een
// kortstondig offline lid *mist* berichten, zonder cursor om ze opnieuw te
// leveren. De follower-regel in `collab_session.dart` accepteert een op pas
// bij `version + 1`; een gat laat het deck daar stil bevriezen. Deze
// transport detecteert een gat (een op met `version > verwacht+1`, of een
// reconnect-signaal) en emits een verzegeld `<resync>`-verzoek; de autoriteit
// coalesceert gelijktijdige verzoeken tot één re-baseline (§4 N1: een
// onbegrensd verzoek zou elke occupant een deck-brede broadcast kunnen
// forceren, versterkt K× bij gelijktijdige reconnects).
//
// **Sleutels vooraf gedeeld** in deze sub-plak — de key-exchange (sub-plak 5)
// bouwt de admission-gated distributie; hier arriveert de crypto al gekoeld.
// De verzegeling gebruikt de BESTAANDE `CollabCrypto.seal/open` (mode-isolatie
// zit al in de room-AAD: `ocideck-<hash>@conference.<domain>` vs. Matrix
// `!local:server` zijn structureel disjunct), dus dit is NIET afhankelijk van
// de gepoorte crypto-sub-plak 2.

import 'dart:async';
import 'dart:convert';

import 'package:xml/xml.dart';

import '../collab/collab_codec.dart';
import '../collab/collab_crypto.dart';
import '../collab/collab_transport.dart';
import '../collab/deck_op.dart';
import '../utils/log.dart';
import 'companion_demux.dart';
import 'xmpp_session.dart';
import 'xmpp_stanza.dart';

/// De OciDeck-namespaces op de companion-MUC (§3). Elk payload-type rijdt als
/// één child-element in zijn eigen namespace op een `<message type=groupchat>`.
class OciDeckNamespace {
  static const op = 'nl.ocideck.op';
  static const lock = 'nl.ocideck.lock';
  static const resync = 'nl.ocideck.resync';
  static const snapshot = 'nl.ocideck.snapshot';
  static const chat = 'nl.ocideck.chat';
  static const presence = 'nl.ocideck.presence';
  static const keyshare = 'nl.ocideck.keyshare';
  static const device = 'nl.ocideck.device';

  /// De XML-local-name voor een namespace — het laatste segment na de punt.
  /// `nl.ocideck.op` → `op`, `nl.ocideck.resync` → `resync`.
  static String localNameOf(String namespace) => namespace.split('.').last;
}

/// Resolves een sender-device-id naar zijn binding-geverifieerde publieke
/// sleutels, zodat een inbound verzegeld event geopend kan worden. In
/// productie backed door de device-directory; in tests een in-memory map.
/// Returns null voor een onbekend device → het event wordt fail-closed
/// gedropt (of uitgesteld, zie de deferred-backlog).
typedef XmppPeerResolver =
    Future<DevicePublicKeys?> Function(String senderDevice);

/// Wat `_tryApply` besloot over één op/lock-stanza.
enum _ApplyOutcome { applied, permanentDrop, retryLater }

/// Een op/lock-stanza die is uitgesteld omdat de key-state nog niet in huis
/// was — de afzender onbekend, of de epoch-sleutel nog niet geïnstalleerd —
/// met hoeveel sync-ronden het al heeft gewacht (zie de backlog-cap).
class _DeferredStanza {
  _DeferredStanza(this.stanza, this.namespace, this.rounds);

  final Stanza stanza;
  final String namespace;
  final int rounds;
}

/// Een [CollabTransport] over de verzegelde companion-MUC. Construeer er één
/// per deelnemer tegen een gedeelde [roomJid]; [crypto] moet al de
/// sessie-epoch-sleutel bevatten (sleutels vooraf gedeeld in deze sub-plak).
///
/// [demux] is de gedeelde fan-out die één `channel.stanzas`-abonnement bezit;
/// deze transport registreert er handlers op voor `op`, `lock` en `resync`.
/// [channel] is voor het zenden (de demux is inbound-only).
///
/// [onReconnected] is het reconnect-signaal (van `XmppSession.onReconnected`);
/// een drop→rejoin triggert een resync (§4). [onResyncRequested] is de
/// autoriteit-kant callback: een gecoalesceerd `<resync>`-verzoek kwam binnen,
/// stuur nu een re-baseline (de snapshot-channel doet dat in sub-plak 6; de
/// test kan het direct afhandelen).
class XmppTransport implements CollabTransport {
  XmppTransport({
    required XmppStanzaChannel stanzaChannel,
    required CompanionDemux companionDemux,
    required CollabCrypto crypto,
    required this.roomJid,
    required XmppPeerResolver peerResolver,
    this.onResyncRequested,
    Stream<void>? onReconnected,
    this.resyncMinInterval = const Duration(seconds: 2),
    this.resyncCoalesceWindow = const Duration(seconds: 1),
  }) : _channel = stanzaChannel,
       _demux = companionDemux,
       _e2ee = crypto,
       _resolvePeer = peerResolver {
    _demux.register(OciDeckNamespace.op, _onOpStanza);
    _demux.register(OciDeckNamespace.lock, _onLockStanza);
    _demux.register(OciDeckNamespace.resync, _onResyncStanza);
    if (onReconnected != null) {
      _reconnectSub = onReconnected.listen((_) => _requestResync());
    }
  }

  final XmppStanzaChannel _channel;
  final CompanionDemux _demux;
  final CollabCrypto _e2ee;
  final String roomJid;
  final XmppPeerResolver _resolvePeer;

  /// Autoriteit-kant: een gecoalesceerd `<resync>`-verzoek kwam binnen. De
  /// caller (snapshot-channel in sub-plak 6, of de test) stuurt nu de
  /// re-baseline. Alleen gezet op de autoriteit; op een follower mag dit
  /// null zijn (een follower heeft geen baseline om te sturen). Mutable: de
  /// launch wijst hem toe nadat de transport en de snapshot-channel zijn
  /// opgebouwd (de transport bestaat voor de snapshot-channel).
  Future<void> Function()? onResyncRequested;

  /// Follower-kant: minimum-tussenpauze tussen twee `<resync>`-emissies,
  /// zodat één follower de kamer niet overstroomt (§4 N1). In tests op
  /// `Duration.zero` of kort te zetten.
  final Duration resyncMinInterval;

  /// Autoriteit-kant: het coalesce-venster — gelijktijdige verzoeken binnen
  /// dit venster worden tot één `onResyncRequested` samengevoegd, zodat N
  /// reconnects één re-baseline veroorzaken, niet N (§4 N1).
  final Duration resyncCoalesceWindow;

  final _ops = StreamController<DeckOp>.broadcast();
  final _locks = StreamController<LockEvent>.broadcast();
  StreamSubscription<void>? _reconnectSub;
  bool _disposed = false;

  /// Serialiseert deze transport's eigen sends zodat de verzegelde stanzas
  /// de kamer bereiken in de volgorde waarin de ops werden aangemaakt, ook
  /// als `sendOp`/`setLock`-aanroepen overlappen. De seal is async, dus twee
  /// fire-and-forget sends (de autoriteit herbroadcast meerdere ops per
  /// bewerking zonder awaiten) kunnen racen — een follower accepteert pas
  /// `version + 1`, dus een omgedraaide op valt eruit en de decks divergeren
  /// (#1040). Spiegelt `MatrixRelayTransport._sendChain`.
  Future<void> _sendChain = Future<void>.value();

  /// Op/lock-stanzas die aankwamen voordat de key-state nodig om ze te openen
  /// in huis was — de afzender's device-sleutels of de epoch-sleutel. Zonder
  /// deze backlog zou een geldige op als "onbekende afzender" worden gedropt
  /// en voor altijd verloren (#1041). Opnieuw geprobeerd in aankomst-volgorde
  /// bij elke nieuwe stanza, begrensd op aantal en ronden.
  final List<_DeferredStanza> _deferred = [];
  static const int _maxDeferred = 256;
  static const int _maxDeferralRounds = 16;

  /// De hoogste op-versie die deze transport heeft gezien — voor
  /// gap-detectie. Een op met `version > _lastSeenVersion + 1` (en
  /// `version > 0`) betekent een gat: er ontbreekt minstens één op.
  int _lastSeenVersion = 0;

  /// Wanneer de laatste `<resync>` werd geemit (follower-kant rate-limiter).
  DateTime? _lastResyncRequest;

  /// Wanneer de laatste re-baseline werd afgehandeld (autoriteit-kant
  /// coalesce-venster).
  DateTime? _lastResyncHandled;

  @override
  String get participantId => _e2ee.deviceId;

  @override
  Stream<DeckOp> get ops => _ops.stream;

  @override
  Stream<LockEvent> get locks => _locks.stream;

  @override
  Future<void> sendOp(DeckOp op) {
    _ensureLive();
    return _serializeSend('op', () async {
      final sealed = await _e2ee.seal(
        {'kind': 'op', 'from': participantId, 'op': deckOpToJson(op)},
        room: roomJid,
        type: OciDeckNamespace.op,
        // Autoritatieve ops (versie toegekend) dragen de autoriteit's
        // handtekening (P3 anti-impersonatie); een follower-intent (versie 0)
        // hoeft dat niet.
        signed: op.version > 0,
      );
      _sendSealedGroupchat(OciDeckNamespace.op, sealed);
    });
  }

  @override
  Future<void> setLock(
    String slideId, {
    required bool held,
    bool forced = false,
  }) {
    _ensureLive();
    final event = LockEvent(
      slideId: slideId,
      held: held,
      participantId: participantId,
      forced: forced,
    );
    // Locks delen de seriële keten met ops zodat hun relatieve volgorde ook
    // bewaard blijft (een lock en de bewerking die hij bewaakt mogen op de
    // wire niet kruisen).
    return _serializeSend('lock', () async {
      final sealed = await _e2ee.seal(
        {'kind': 'lock', 'from': participantId, 'lock': lockEventToJson(event)},
        room: roomJid,
        type: OciDeckNamespace.lock,
        signed: false,
      );
      _sendSealedGroupchat(OciDeckNamespace.lock, sealed);
    });
  }

  /// Voeg [send] toe aan de seriële [_sendChain] zodat het strikt na elke
  /// eerdere send van deze transport draait. Een fout wordt gelogd (gecontroleerd,
  /// geen stille drop) en blokkeert de keten niet — een latere send draait nog.
  Future<void> _serializeSend(String kind, Future<void> Function() send) {
    final done = _sendChain.then((_) => send());
    _sendChain = done.then(
      (_) {},
      onError: (Object e) => logWarning('xmpp.transport.send.$kind', e),
    );
    return done;
  }

  /// Verzend een verzegelde envelope als één `<message type=groupchat>` met
  /// een child in [namespace]. De envelope rijdt als `jsonEncode(sealed
  /// .toContent())` in het text van het child-element (§3).
  void _sendSealedGroupchat(String namespace, SealedEnvelope sealed) {
    _channel.sendStanza(
      Stanza(
        kind: StanzaKind.message,
        type: 'groupchat',
        to: roomJid,
        children: [
          xmppElement(
            OciDeckNamespace.localNameOf(namespace),
            namespace: namespace,
            text: jsonEncode(sealed.toContent()),
          ),
        ],
      ),
    );
  }

  // ── inbound: op/lock ──────────────────────────────────────────────────────

  Future<void> _onOpStanza(Stanza stanza) =>
      _dispatch([(stanza, OciDeckNamespace.op)]);

  Future<void> _onLockStanza(Stanza stanza) =>
      _dispatch([(stanza, OciDeckNamespace.lock)]);

  /// Verwerk op/lock-stanzas: de uitgestelde backlog eerst (zodat
  /// cross-stanza-volgorde bewaard blijft), dan de [fresh]. Een stanza die
  /// nog steeds niet geopend kan worden wordt opnieuw uitgesteld, begrensd
  /// op aantal en ronden. Spiegelt `MatrixRelayTransport._dispatchData`.
  Future<void> _dispatch(List<(Stanza, String)> fresh) async {
    if (_disposed) return;
    final backlog = List<_DeferredStanza>.from(_deferred);
    _deferred.clear();
    final queue = <(Stanza, String)>[
      for (final d in backlog) (d.stanza, d.namespace),
      ...fresh,
    ];
    final rounds = <String, int>{
      for (final d in backlog) _stanzaKey(d.stanza, d.namespace): d.rounds,
    };
    for (final (stanza, ns) in queue) {
      if (_disposed) return;
      final outcome = await _tryApply(stanza, ns);
      if (outcome == _ApplyOutcome.retryLater) {
        final key = _stanzaKey(stanza, ns);
        final next = (rounds[key] ?? 0) + 1;
        if (next <= _maxDeferralRounds) {
          _deferred.add(_DeferredStanza(stanza, ns, next));
        } else {
          logWarning('xmpp.transport.deferred.expired', key);
        }
      }
    }
    if (_deferred.length > _maxDeferred) {
      _deferred.removeRange(0, _deferred.length - _maxDeferred);
    }
  }

  /// Probeer één stanza te openen en te emitren. Onderscheidt een permanente
  /// drop (misvormd, of eigen echo) van een uitstelbare miss (afzender nog
  /// onbekend, of envelope nog niet openbaar omdat de epoch-sleutel in
  /// aankomst is). Beide — gesmeed en nog-niet-gekoeld — komen hier als
  /// `retryLater` naar boven, dus de aanroeper begrenst hoelang ze worden
  /// herprobeerd.
  Future<_ApplyOutcome> _tryApply(Stanza stanza, String namespace) async {
    final child = _childByNs(stanza, namespace);
    if (child == null) return _ApplyOutcome.permanentDrop;
    final SealedEnvelope sealed;
    try {
      sealed = SealedEnvelope.fromContent(
        jsonDecode(child.innerText) as Map<String, Object?>,
      );
    } on Exception catch (e) {
      logWarning('xmpp.transport.malformed', e);
      return _ApplyOutcome.permanentDrop;
    }
    if (sealed.senderDevice == participantId) {
      return _ApplyOutcome.permanentDrop; // eigen echo
    }
    final sender = await _resolvePeer(sealed.senderDevice);
    if (sender == null) return _ApplyOutcome.retryLater;
    try {
      final envelope = await _e2ee.open(
        sealed,
        room: roomJid,
        type: namespace,
        sender: sender,
      );
      _emit(namespace, envelope);
      return _ApplyOutcome.applied;
    } on Exception catch (e) {
      logWarning('xmpp.transport.open', e);
      return _ApplyOutcome.retryLater;
    }
  }

  /// Emit een geopend op/lock-event op de juiste stream, met gap-detectie voor
  /// ops (§4). Een op met `version > _lastSeenVersion + 1` (en `version > 0`)
  /// betekent een gat — de follower-regel laat hem vallen en het deck bevriest;
  /// emit een `<resync>`-verzoek (rate-limited) zodat de autoriteit re-baselineert.
  void _emit(String namespace, Map<String, Object?> envelope) {
    switch (namespace) {
      case OciDeckNamespace.op:
        final op = deckOpFromJson(_asObject(envelope['op']));
        _maybeDetectGap(op);
        _ops.add(op);
      case OciDeckNamespace.lock:
        _locks.add(lockEventFromJson(_asObject(envelope['lock'])));
    }
  }

  /// Gap-detectie (§4): een op-versie die verder ligt dan verwacht wijst op
  /// een gemiste op. Update `_lastSeenVersion` en emit een resync bij een gat.
  void _maybeDetectGap(DeckOp op) {
    if (op.version > 0 && op.version > _lastSeenVersion + 1) {
      _requestResync();
    }
    if (op.version > _lastSeenVersion) {
      _lastSeenVersion = op.version;
    }
  }

  // ── inbound: resync ───────────────────────────────────────────────────────

  /// Autoriteit-kant: verwerk een inbound `<resync>`-verzoek. Het verzoek is
  /// verzegeld (alleen een gekoeld lid kan het verzenden) — openen bewijst
  /// keying. Coalesceer gelijktijdige verzoeken binnen [_resyncCoalesceWindow]
  /// tot één `onResyncRequested`, zodat N reconnects één re-baseline geven (§4 N1).
  Future<void> _onResyncStanza(Stanza stanza) async {
    if (_disposed) return;
    final child = _childByNs(stanza, OciDeckNamespace.resync);
    if (child == null) return;
    final SealedEnvelope sealed;
    try {
      sealed = SealedEnvelope.fromContent(
        jsonDecode(child.innerText) as Map<String, Object?>,
      );
    } on Exception catch (e) {
      logWarning('xmpp.transport.resync.malformed', e);
      return;
    }
    if (sealed.senderDevice == participantId) return; // eigen verzoek
    final sender = await _resolvePeer(sealed.senderDevice);
    if (sender == null) return; // onbekende afzender — fail-closed
    try {
      await _e2ee.open(
        sealed,
        room: roomJid,
        type: OciDeckNamespace.resync,
        sender: sender,
      );
    } on Exception catch (e) {
      logWarning('xmpp.transport.resync.open', e);
      return; // niet-gekoeld / gesmeed — fail-closed
    }
    // Coalesceer: als er recent een re-baseline is afgehandeld, drop het
    // verzoek — de re-baseline dekt deze follower ook.
    final now = DateTime.now();
    if (_lastResyncHandled != null &&
        now.difference(_lastResyncHandled!) < resyncCoalesceWindow) {
      return;
    }
    _lastResyncHandled = now;
    await onResyncRequested?.call();
  }

  // ── resync-emissie (follower-kant) ─────────────────────────────────────────

  /// Emit een verzegeld `<resync>`-verzoek, tenzij de rate-limiter het
  /// blokkeert (§4 N1 — een onbegrensd verzoek zou elke occupant een
  /// deck-brede broadcast kunnen forceren). Geemit bij een gap of een
  /// reconnect-signaal.
  void _requestResync() {
    if (_disposed) return;
    final now = DateTime.now();
    if (_lastResyncRequest != null &&
        now.difference(_lastResyncRequest!) < resyncMinInterval) {
      return; // rate-limited
    }
    _lastResyncRequest = now;
    unawaited(_sendResyncRequest());
  }

  Future<void> _sendResyncRequest() async {
    try {
      final sealed = await _e2ee.seal(
        {'kind': 'resync', 'from': participantId},
        room: roomJid,
        type: OciDeckNamespace.resync,
        signed: false,
      );
      _sendSealedGroupchat(OciDeckNamespace.resync, sealed);
    } on Exception catch (e) {
      logWarning('xmpp.transport.resync.send', e);
    }
  }

  // ── teardown ───────────────────────────────────────────────────────────────

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    await _reconnectSub?.cancel();
    _reconnectSub = null;
    // De demux is gedeeld — wij registreren alleen af, wij bezitten hem niet.
    // De handler-registraties worden gewist door de demux zelf bij zijn dispose.
    await _ops.close();
    await _locks.close();
  }

  void _ensureLive() {
    if (_disposed) {
      throw StateError('use of a disposed XmppTransport');
    }
  }

  // ── helpers ────────────────────────────────────────────────────────────────

  /// Vind het eerste child-element met [namespace] — zowel de geserialiseerde
  /// `xmlns`-attribuutvorm als de geparsede `namespaceUri`. Spiegelt
  /// `XmppMuc._hasNs`.
  static XmlElement? _childByNs(Stanza stanza, String namespace) {
    for (final child in stanza.children) {
      final ns = child.getAttribute('xmlns') ?? child.name.namespaceUri;
      if (ns == namespace) return child;
    }
    return null;
  }

  static String _stanzaKey(Stanza stanza, String namespace) =>
      '${stanza.id ?? stanza.toXmlString()}:$namespace';

  static Map<String, Object?> _asObject(Object? value) {
    if (value is Map<String, Object?>) return value;
    if (value is Map) return value.map((k, v) => MapEntry('$k', v));
    throw const FormatException('expected an object in a sealed envelope');
  }
}
