// De slide-position-beacon over de companion-MUC
// (`docs/design/XMPP_COLLAB_TRANSPORT.md` §5 brick 4, §3, sub-plak 7): de
// XMPP-tegenhanger van `MatrixPresence`. Welke slide elke co-auteur bekijkt,
// zodat iedereen iedereen ziet. De slide-id rijdt **verzegeld** in een
// `<pos xmlns="nl.ocideck.presence">` op een `<message type=groupchat>` (§3) —
// de MUC ziet alleen ciphertext, nooit *waar* iemand kijkt.
//
// Presence is een **huidig feit, geen historie**: de laatste per afzender wint
// (latest-per-sender), in plaats van te stapelen als chat. Een tweede `<pos>`
// van hetzelfde device overschrijft de eerste — precies zoals Matrix's room-
// state dat via de state-key deed, maar dan zonder de power-gated ordering die
// een homeserver gratis gaf (§2); de verzegeling + de directory's pin-on-first-
// use betalen hier wat de room-state gratis gaf.
//
// Net als een op is presence **niet autoritair** — een verkeerde positie
// verplaatst een stip, meer niet — dus hij wordt verzegeld **zonder**
// handtekening en geopend zonder er een te eisen. Een device vertrouwt alleen
// een presence wiens afzender een geverifieerde peer in de directory is; al het
// andere wordt fail-closed gedropt. Een presence die aankomt vóór de epoch-
// sleutel of vóór de afzender bekend is, wordt gebufferd en in [retryPending]
// heropend — een joiner ziet een peer's presence op dezelfde stroom als (of
// vóór) zijn keyshare (§6).

import 'dart:async';
import 'dart:convert';

import 'package:xml/xml.dart';

import '../collab/collab_crypto.dart';
import '../collab/collab_device_directory.dart';
import '../utils/log.dart';
import 'companion_demux.dart';
import 'xmpp_session.dart';
import 'xmpp_stanza.dart';
import 'xmpp_transport.dart' show OciDeckNamespace;

/// Waar één peer-device naar kijkt, voor de presence-UI.
class PeerPresence {
  const PeerPresence({
    required this.userId,
    required this.deviceId,
    required this.slideId,
  });

  final String userId;
  final String deviceId;

  /// De id van de slide die deze peer momenteel bekijkt of bewerkt.
  final String slideId;
}

/// Kondigt dit device's huidige slide aan en neemt peers' presence over — de
/// presence-vlak van een XMPP-sessie. Registreert zichzelf op de demux voor
/// `nl.ocideck.presence`; de app roept [announce] als de lokale selectie
/// verandert. Latest-per-sender, verzegeld, fail-closed.
class XmppPresenceBeacon {
  XmppPresenceBeacon({
    required XmppStanzaChannel stanzaChannel,
    required CompanionDemux companionDemux,
    required CollabCrypto crypto,
    required this.roomJid,
    required this.directory,
    this.pendingCap = 256,
  }) : _channel = stanzaChannel,
       _demux = companionDemux,
       _e2ee = crypto {
    _demux.register(OciDeckNamespace.presence, handlePresence);
  }

  /// De namespace die de verzegelde slide-id draagt (§3). Het child-element is
  /// `<pos>` (de wire-tabel), met de verzegeling als JSON-text.
  static const presenceType = OciDeckNamespace.presence;

  final XmppStanzaChannel _channel;
  final CompanionDemux _demux;
  final CollabCrypto _e2ee;
  final String roomJid;
  final CollabDeviceDirectory directory;

  /// De laatste presence per peer-device (this device uitgesloten).
  final Map<String, PeerPresence> _peers = {};

  /// Presence die aankwam vóór de epoch-sleutel of de afzender's device-keys
  /// bekend waren — een joiner ziet een peer's presence vóór zijn keyshare.
  /// Keyed per device, laatste wint; [retryPending] heropent ze. Begrensd op
  /// [pendingCap] — een vijandige server kan de map niet onbegrensd vullen met
  /// nep-afzenders (#1413).
  final Map<String, SealedEnvelope> _pending = {};

  /// Cap op de pending-map. Bij overflow verdrijft het oudste device (FIFO).
  final int pendingCap;

  /// Of er gebufferde presence wacht op retry — voor de syncNow short-circuit
  /// (#1423).
  bool get hasPending => _pending.isNotEmpty;

  /// Vuurt nadat een peer's presence verandert, zodat de provider de UI verversen kan.
  void Function()? onChanged;

  /// De laatste slide die dit device aankondigde — om een overbodige herzend te
  /// skippen.
  String? _lastAnnounced;

  /// Elke peer's laatst bekende positie (this device uitgesloten).
  List<PeerPresence> get peers => _peers.values.toList();

  /// Kondig aan dat dit device nu op [slideId] zit. Overschrijft dit device's
  /// eigen presence; een no-op als de slide niet veranderde. Verzegeld zodat de
  /// server ciphertext ziet.
  Future<void> announce(String slideId) async {
    if (slideId == _lastAnnounced) return;
    _lastAnnounced = slideId;
    final sealed = await _e2ee.seal(
      {'slide': slideId},
      room: roomJid,
      type: presenceType,
      signed: false,
    );
    _channel.sendStanza(
      Stanza(
        kind: StanzaKind.message,
        type: 'groupchat',
        to: roomJid,
        children: [
          xmppElement(
            'pos',
            namespace: presenceType,
            text: jsonEncode(sealed.toContent()),
          ),
        ],
      ),
    );
  }

  /// Verwerk een inbound `<pos>`-stanza (wire aan de demux). Buffert de
  /// verzegeling per afzender (laatste wint) en probeert hem te openen; een
  /// nog-niet-openbare wordt gebufferd voor [retryPending].
  Future<void> handlePresence(Stanza stanza) async {
    final child = _childByNs(stanza, presenceType);
    if (child == null) return;
    try {
      final decoded = jsonDecode(child.innerText);
      if (decoded is! Map<String, Object?>) {
        logWarning('xmpp.presence.notObject', decoded);
        return;
      }
      final sealed = SealedEnvelope.fromContent(decoded);
      // Eigen echo — de MUC reflecteert de afzender zijn eigen bericht terug.
      if (sealed.senderDevice == _e2ee.deviceId) return;
      // Begrens de pending-map: een vijandige server die nep-afzenders stuurt
      // mag het geheugen niet uitputten (#1413). Bij een nieuw device over de
      // cap verdrijft het oudste (FIFO — de map behoudt invoegvolgorde).
      if (!_pending.containsKey(sealed.senderDevice) &&
          _pending.length >= pendingCap) {
        _pending.remove(_pending.keys.first);
      }
      _pending[sealed.senderDevice] = sealed; // laatste wint; _tryOpen verwerkt
      await _tryOpen(sealed.senderDevice);
    } on Exception catch (e) {
      logWarning('xmpp.presence', e);
    }
  }

  /// Heropen presence die gebufferd was vóór de sleutel of afzender bekend was.
  /// Roep na een ronde die een keyshare geïnstalleerd of een device geleerd kan
  /// hebben.
  Future<void> retryPending() async {
    for (final device in _pending.keys.toList()) {
      await _tryOpen(device);
    }
  }

  Future<void> _tryOpen(String device) async {
    final sealed = _pending[device];
    if (sealed == null) return;
    final sender = directory.resolve(device);
    if (sender == null) return; // afzender nog onbekend — houd en retry
    try {
      final opened = await _e2ee.open(
        sealed,
        room: roomJid,
        type: presenceType,
        sender: sender,
      );
      _pending.remove(device);
      final slide = opened['slide'];
      if (slide is! String) return;
      _peers[device] = PeerPresence(
        userId: directory.addressOf(device) ?? '',
        deviceId: device,
        slideId: slide,
      );
      onChanged?.call();
    } on CollabCryptoException catch (e) {
      if (e.reason == 'unknown-epoch') return; // sleutel nog niet — houd
      _pending.remove(device); // een echte fout (slechte tag): drop fail-closed
      logWarning('xmpp.presence.open', e);
    }
  }

  /// Ruim de demux-registratie op. Idempotent. De directory en de crypto zijn
  /// van de aanroeper — die worden hier niet gesloten.
  Future<void> dispose() async {
    _demux.register(presenceType, (_) async {});
  }

  // ── helpers ────────────────────────────────────────────────────────────────

  /// Vind het eerste child-element met [namespace] — zowel de geserialiseerde
  /// `xmlns`-attribuutvorm als de geparsede `namespaceUri`. Spiegelt
  /// `XmppTransport._childByNs`.
  static XmlElement? _childByNs(Stanza stanza, String namespace) {
    for (final child in stanza.children) {
      final ns = child.getAttribute('xmlns') ?? child.name.namespaceUri;
      if (ns == namespace) return child;
    }
    return null;
  }
}
