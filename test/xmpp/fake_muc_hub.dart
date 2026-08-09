// Een in-memory N-party MUC voor de XMPP-collab-tests — de `LoopbackHub`-analoog
// voor de stanza-laag (`docs/design/XMPP_COLLAB_TRANSPORT.md` §8). Reflecteert
// groupchat-berichten naar alle leden (inclusief de afzender — daarom werkt
// own-echo-onderdrukking op `senderDevice == deviceId`), routeert directed
// berichten naar één ontvanger, en ondersteunt drop/rejoin zodat een
// gap→resync-scenario wall-clock-vrij te rijden is. Test-only; leeft onder
// `test/` (nooit `lib/`) zodat het nooit de network-sink-guard raakt.

import 'dart:async';

import 'package:ocideck/xmpp/xmpp_session.dart';
import 'package:ocideck/xmpp/xmpp_stanza.dart';

/// Een in-memory MUC die `XmppStanzaChannel` per lid blootstelt. N leden
/// joinen met een unieke nick; groupchat-berichten worden gereflecteerd naar
/// alle leden in één orde (synchrone aflevering in single-threaded Dart
/// garandeert dat), directed berichten gaan naar één ontvanger, en presence
/// wordt uitgezonden naar iedereen. `drop`/`rejoin` simuleert een
/// netwerkonderbreking: een gedropt lid ontvangt niets (de MUC-gap), en bij
/// rejoin hervat het en vuurt `onReconnected` — het signaal dat de
/// transport-laag gebruikt om een resync te triggeren (§4).
class FakeMucHub {
  FakeMucHub(this.roomJid);

  /// De bare room JID, `room@conference.server`.
  final String roomJid;

  final List<FakeMucChannel> _members = [];

  /// De laatste presence-stanza per nick — een echte MUC (XEP-0045 §7.2.2)
  /// stuurt een newcomer de presence van alle bestaande occupants. De fake
  /// houdt ze bij en replayt ze bij [join], zodat een test die de host vóór
  /// de guest opzet (en de host zijn device-keys publiceert vóór de guest's
  /// demux subscribeert) de host-presence alsnog aflevert.
  final Map<String, Stanza> _lastPresence = {};

  /// Join de MUC als [nick] en krijg een kanaal gebonden aan dit lid. De
  /// `boundJid` is `roomJid/nick`. Twee joins met dezelfde nick zijn een
  /// fout — een MUC handhaft unieke nicks. Een newcomer krijgt de presence
  /// van alle bestaande occupants geleverd (XEP-0045 §7.2.2).
  FakeMucChannel join(String nick) {
    if (_members.any((m) => m.nick == nick)) {
      throw StateError('FakeMucHub: nick "$nick" already joined');
    }
    final ch = FakeMucChannel._(this, nick);
    _members.add(ch);
    // Replay bestaande occupants' presence naar de newcomer (XEP-0045 §7.2.2).
    for (final existing in _lastPresence.entries) {
      ch._deliver(existing.value);
    }
    return ch;
  }

  /// Alle actieve (niet-gedropte) leden.
  Iterable<FakeMucChannel> get _active => _members.where((m) => !m._dropped);

  /// Verwerk een uitgaande stanza van [from]. Groupchat wordt gereflecteerd
  /// naar alle leden (inclusief afzender — XEP-0045 reflecteert de afzender
  /// eigen bericht terug, wat own-echo-onderdrukking mogelijk maakt).
  /// Directed berichten gaan naar de opgegeven ontvanger. Presence wordt
  /// uitgezonden naar iedereen.
  void _routeOut(Stanza stanza, FakeMucChannel from) {
    if (from._dropped) return; // een gedropt lid kan niet zenden
    switch (stanza.kind) {
      case StanzaKind.message:
        if (stanza.type == 'groupchat') {
          final reflected = Stanza(
            kind: StanzaKind.message,
            type: 'groupchat',
            from: '$roomJid/${from.nick}',
            to: roomJid,
            id: stanza.id,
            children: stanza.children,
          );
          for (final m in _active.toList()) {
            m._deliver(reflected);
          }
        } else {
          // Directed: routeer naar de specifieke occupant.
          final to = stanza.to;
          if (to == null) return;
          for (final m in _active.toList()) {
            if ('$roomJid/${m.nick}' == to) {
              m._deliver(
                Stanza(
                  kind: StanzaKind.message,
                  type: stanza.type,
                  from: '$roomJid/${from.nick}',
                  to: to,
                  id: stanza.id,
                  children: stanza.children,
                ),
              );
              break;
            }
          }
        }
      case StanzaKind.presence:
        // Presence wordt uitgezonden naar alle leden.
        final reflected = Stanza(
          kind: StanzaKind.presence,
          type: stanza.type,
          from: '$roomJid/${from.nick}',
          to: stanza.to,
          id: stanza.id,
          children: stanza.children,
        );
        _lastPresence[from.nick] = reflected;
        for (final m in _active.toList()) {
          m._deliver(reflected);
        }
      case StanzaKind.iq:
        // IQ's worden niet gerouteerd in deze fake — de collab-data-plane
        // gebruikt alleen groupchat-berichten en presence.
        break;
    }
  }

  /// Verwijder een lid definitief (teardown). Een gedropt lid dat later
  /// verwijderd wordt, stopt ook met bestaan in de hub.
  void _remove(FakeMucChannel channel) => _members.remove(channel);
}

/// Eén lid van een [FakeMucHub]. Implementeert [XmppStanzaChannel] zodat de
/// transport-laag er net zo tegen praat als tegen een echte `XmppSession`.
class FakeMucChannel implements XmppStanzaChannel {
  FakeMucChannel._(this._hub, this.nick);

  final FakeMucHub _hub;

  /// De room-nick van dit lid — de resource van de in-room JID.
  final String nick;

  bool _dropped = false;
  final _inbound = StreamController<Stanza>.broadcast();
  final _reconnected = StreamController<void>.broadcast();
  bool _closed = false;

  /// Optionele onderschepping van uitgaande stanzas vóór routing — voor
  /// tests die de wire-form willen inspecteren (bijv. de recipient-blinded
  /// keyshare). De callback krijgt de stanza te zien; daarna gaat hij normaal
  /// de hub in. Niet voor productie — test-only.
  void Function(Stanza)? intercept;

  @override
  String? get boundJid => '${_hub.roomJid}/$nick';

  @override
  Stream<Stanza> get stanzas => _inbound.stream;

  /// Vuurt bij rejoin (na een drop), als signaal naar de transport-laag om
  /// een resync te triggeren (§4) — het `XmppSession.onReconnected`-equivalent.
  Stream<void> get onReconnected => _reconnected.stream;

  @override
  void sendStanza(Stanza stanza) {
    if (_closed) return;
    intercept?.call(stanza);
    _hub._routeOut(stanza, this);
  }

  void _deliver(Stanza stanza) {
    if (!_dropped && !_closed && !_inbound.isClosed) _inbound.add(stanza);
  }

  /// Simuleer een netwerkdrop: dit lid stopt met ontvangen (de MUC-gap —
  /// berichten die tijdens de drop worden verzonden gaan verloren, zoals een
  /// echte MUC geen `/sync`-cursor redelivert). Kan nog wel zenden tot de
  /// drop actief is (analoog aan een verbinding die net wegvalt).
  void drop() {
    _dropped = true;
  }

  /// Keer terug na een drop: hervat aflevering en vuur `onReconnected` zodat
  /// de transport-laag een resync triggert (§4).
  void rejoin() {
    _dropped = false;
    if (!_reconnected.isClosed) _reconnected.add(null);
  }

  /// Of dit lid momenteel is gedropt.
  bool get isDropped => _dropped;

  /// Sluit het kanaal definitief (teardown). Idempotent.
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    _hub._remove(this);
    if (!_inbound.isClosed) await _inbound.close();
    if (!_reconnected.isClosed) await _reconnected.close();
  }
}
