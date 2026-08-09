// De XMPP-sleuteluitwisseling (`docs/design/XMPP_COLLAB_TRANSPORT.md` §5 brick 2,
// §5.1, §7). Vestigt de sessie-sleutels veilig over de companion-MUC — de
// XMPP-tegenhanger van `MatrixKeyExchange`, maar met drie kritieke verschillen
// die voortvloeien uit wat een MUC niet gratis geeft (§2):
//
//   • **Device-keys als signed-rot presence-extensie** (`<x xmlns="nl.ocideck.
//     device">`), niet als power-gated room-state. Presence is ongeordend en
//     ongegated (elke occupant/server kan het uitzenden), dus de §5.1
//     signed-rot-epoch + pin-on-first-use + rot-monotoniciteit betalen de
//     veiligheid die Matrix's geordende state gratis gaf.
//   • **Deny-by-default admission-gated keying** — NIET de fail-open Matrix-
//     spiegel (`MatrixKeyExchange.ensureKeyed` sleutelt elk bekend device
//     onvoorwaardelijk, omdat Matrix admission de room's job is). De kamer is
//     afleidbaar uit de (vaak publieke) Jitsi-URL, dus keying-on-presence
//     zou iedereen met de link de epoch-sleutel geven. De autoriteit sleutelt
//     alleen devices in een expliciete approval-set (§7 SA-F4).
//   • **Recipient-blinded broadcast `<keyshare>`** — niet een directed
//     to-device bericht. De epoch-sleutel rijdt als één `<message type=
//     groupchat>` per ontvanger, maar de wrap bevat geen cleartext `to`/`from`
//     (§5.1 N3) — elke occupant trial-opent de zijne; alleen de bedoelde
//     ontvanger kan de ECDH-afgeleide wrap-sleutel vinden en de AEAD-tag
//     verifiëren.
//
// De crypto-primitieven (seal/open/rekey/wrap/install) zijn `CollabCrypto`'s
// (sub-plak 2 landde de §5.1-uitbreiding: signed rot in de binding,
// recipient-blinded wrap). Deze laag voert ze over de draad. Fail-closed
// doorheen: een misvormde presence, een onverifieerbare binding, een
// rot-replay, een identiteitswissel, of een niet-geopende keyshare wordt
// gelogd en gedropt, nooit vertrouwd uit het bericht zelf.

import 'dart:convert';

import 'package:xml/xml.dart';

import '../collab/collab_crypto.dart';
import '../collab/collab_device_directory.dart';
import '../utils/log.dart';
import 'companion_demux.dart';
import 'xmpp_session.dart';
import 'xmpp_stanza.dart';
import 'xmpp_transport.dart' show OciDeckNamespace;

/// Vestigt de sessie-sleutels over de companion-MUC met signed-rot presence
/// en recipient-blinded broadcast keyshare, admission-gated via een
/// deny-by-default approval-set. Construeer er één per deelnemer; de demux
/// routeert `nl.ocideck.device` (presence) en `nl.ocideck.keyshare`
/// (groupchat) naar deze exchange.
///
/// De autoriteit onderhoudt de approval-set ([approve]/[isApproved]) en
/// sleutelt alleen goedgekeurde devices ([ensureKeyed]). Een follower
/// trial-opent elke inbound keyshare en installeert de zijne.
class XmppKeyExchange {
  XmppKeyExchange({
    required XmppStanzaChannel stanzaChannel,
    required CompanionDemux companionDemux,
    required CollabCrypto crypto,
    required this.roomJid,
    required this.directory,
    required DevicePublicKeys ownKeys,
  }) : _channel = stanzaChannel,
       _demux = companionDemux,
       _e2ee = crypto,
       _own = ownKeys {
    _demux.register(OciDeckNamespace.device, handleDevicePresence);
    _demux.register(OciDeckNamespace.keyshare, handleKeyshare);
  }

  final XmppStanzaChannel _channel;
  final CompanionDemux _demux;
  final CollabCrypto _e2ee;
  final String roomJid;
  final CollabDeviceDirectory directory;
  DevicePublicKeys _own;

  /// Dit device's eigen publieke sleutels — de verificatie-UI fingerprint
  /// ze als de "jij"-entry die co-auteurs out-of-band vergelijken.
  DevicePublicKeys get ownKeys => _own;

  /// Every known peer device, verified into the directory.
  Iterable<PeerDevice> get peers => directory.peers;

  /// De deny-by-default approval-set (§7 SA-F4). Alleen de autoriteit
  /// vult deze via [approve] (de bestaande TOFU/fingerprint-flow). Een
  /// device niet in deze set wordt nooit gesleuteld.
  final Set<String> _approved = {};

  /// Devices die al gesleuteld zijn deze epoch. Gereset bij [distributeEpoch].
  final Set<String> _keyed = {};

  /// Keur een device goed voor keying (autoriteit, via de TOFU/fingerprint-
  /// flow). Een niet-goedgekeurd device wordt nooit gesleuteld — deny-by-
  /// default.
  void approve(String deviceId) => _approved.add(deviceId);

  /// Of [deviceId] in de approval-set staat.
  bool isApproved(String deviceId) => _approved.contains(deviceId);

  /// Het aantal devices dat deze epoch al gesleuteld is. De launch leest dit
  /// vóór en ná [ensureKeyed] om te weten of een newcomer net gesleuteld is —
  /// zo ja, dan stuurt de autoriteit hem de baseline (§6: de snapshot komt ná
  /// de keyshare bij een newcomer, want een MUC levert geen `/sync`-achtergrond).
  int get keyedDeviceCount => _keyed.length;

  /// Werk de eigen publieke sleutels bij (na een key-rotatie) en herpubliceer.
  /// De nieuwe [ownKeys] moeten dezelfde identiteit hebben (pin-on-first-use
  /// geldt ook voor jezelf) met een hogere signed rot.
  void updateOwnKeys(DevicePublicKeys ownKeys) => _own = ownKeys;

  /// Bouw de `<x xmlns="nl.ocideck.device">` presence-extensie voor [keys] —
  /// voor [XmppMuc.join]'s `presenceExtensions`-parameter, zodat de join-
  /// presence de device-keys direct meedraagt (§6).
  static XmlElement devicePresenceExtension(DevicePublicKeys keys) =>
      xmppElement(
        'x',
        namespace: OciDeckNamespace.device,
        text: jsonEncode(keys.toJson()),
      );

  /// Publiceer dit device's publieke sleutels als een signed-rot presence-
  /// extensie (`<x xmlns="nl.ocideck.device">`). Stuur dit bij join (naast
  /// de join-presence via [devicePresenceExtension]) en bij elke key-rotatie.
  /// De MUC reflecteert de presence naar alle occupants; elk die de
  /// `nl.ocideck.device`-namespace registreert, ingest via [handleDevicePresence].
  Future<void> publishDeviceKeys() async {
    _channel.sendStanza(
      Stanza(
        kind: StanzaKind.presence,
        to: roomJid,
        children: [devicePresenceExtension(_own)],
      ),
    );
  }

  /// Autoriteit: begin een verse epoch en distribueer de epoch-sleutel als
  /// recipient-blinded broadcast `<keyshare>` aan elk van [members]. Elke
  /// member moet al in de [directory] staan (zijn device-keys gepubliceerd
  /// en geïngest), zodat de wrap aan het juiste agreement-key gebonden is.
  /// De wrap zelf bevat geen cleartext ontvanger (§5.1 N3) — elke occupant
  /// trial-opent de zijne.
  Future<void> distributeEpoch(List<DevicePublicKeys> members) async {
    final result = await _e2ee.rekey(members);
    _keyed.clear();
    for (var i = 0; i < members.length; i++) {
      await _sendKeyshare(result.wraps[i]);
      _keyed.add(members[i].deviceId);
    }
  }

  /// Autoriteit: sleutel elk **goedgekeurd** device dat deze epoch nog niet
  /// gesleuteld is (een newcomer die net zijn device-keys publiceerde).
  /// Deny-by-default: een device niet in de approval-set wordt overgeslagen,
  /// nooit gesleuteld (§7 SA-F4). Idempotent — devices al gesleuteld worden
  /// overgeslagen.
  Future<void> ensureKeyed() async {
    for (final deviceId in directory.knownDevices) {
      if (deviceId == _e2ee.deviceId) continue; // niet jezelf
      if (_keyed.contains(deviceId)) continue; // al gesleuteld
      if (!_approved.contains(deviceId)) continue; // deny-by-default
      final member = directory.resolve(deviceId);
      if (member == null) continue;
      final wrap = await _e2ee.wrapEpochTo(member);
      await _sendKeyshare(wrap);
      _keyed.add(deviceId);
    }
  }

  /// Verzend één recipient-blinded keyshare als `<message type=groupchat>`
  /// met een `<keyshare xmlns="nl.ocideck.keyshare">`-child. De wire-form
  /// (WrappedKey.toJson) bevat geen cleartext `to`/`from` (§5.1 N3).
  Future<void> _sendKeyshare(WrappedKey wrap) async {
    _channel.sendStanza(
      Stanza(
        kind: StanzaKind.message,
        type: 'groupchat',
        to: roomJid,
        children: [
          xmppElement(
            OciDeckNamespace.localNameOf(OciDeckNamespace.keyshare),
            namespace: OciDeckNamespace.keyshare,
            text: jsonEncode(wrap.toJson()),
          ),
        ],
      ),
    );
  }

  /// Verwerk een inbound device-key presence: ingest in de directory met
  /// rot-monotoniciteit. Wire aan de demux voor `nl.ocideck.device`.
  ///
  /// Rot-monotoniciteit (§5.1, NEW-5): voor een bekend device accepteer een
  /// rot-bump alleen als de signed rot strikt toeneemt. Een replay met
  /// dezelfde of lagere rot wordt geweigerd — de directory's pin-on-first-
  /// use zou het als een same-identity update accepteren, maar de rot-check
  /// gaat eerst. De directory's `ingest` weigert daarnaast een identiteits-
  /// wissel (SA-F3) en een onverifieerbare binding (§5.3).
  Future<void> handleDevicePresence(Stanza stanza) async {
    final child = _childByNs(stanza, OciDeckNamespace.device);
    if (child == null) return;
    final DevicePublicKeys keys;
    try {
      keys = DevicePublicKeys.fromJson(
        jsonDecode(child.innerText) as Map<String, Object?>,
      );
    } on Exception catch (e) {
      logWarning('xmpp.keyexchange.device.parse', e);
      return;
    }
    // Eigen presence niet ingesten — de MUC reflecteert de afzender zijn
    // eigen presence terug (XEP-0045), maar je hoeft jezelf niet te leren.
    if (keys.deviceId == _e2ee.deviceId) return;

    // Rot-monotoniciteit: voor een bekend device moet de signed rot strikt
    // toenemen. Een replay (zelfde of lagere rot) wordt geweigerd vóór de
    // directory's ingest — anders zou een same-identity update het
    // accepteren en de rot-epoch degraderen (§5.1 N2, NEW-5).
    final existing = directory.resolve(keys.deviceId);
    if (existing != null && keys.rot <= existing.rot) {
      logWarning('xmpp.keyexchange.rotReplay', keys.deviceId);
      return;
    }

    // De peer-address is de in-room JID (room@conf/nick) — de server zet
    // deze op de presence. De directory gebruikt ze om een keyshare te
    // adresseren en om de afzender van een blinded keyshare te resolveren.
    final peerAddress = stanza.from ?? roomJid;
    await directory.ingest(peerAddress: peerAddress, keys: keys);
  }

  /// Verwerk een inbound keyshare: trial-open tegen elke kandidaat-afzender
  /// uit de directory. De wrap bevat geen cleartext afzender (§5.1 N3) — de
  /// afzender wordt uit de stanza's `from` (room@conf/nick) afgeleid, en de
  /// directory levert de kandidaat-devices voor die nick. Alleen de
  /// authentieke afzender's identiteit laat de handtekening verifiëren, en
  /// alleen de bedoelde ontvanger kan de ECDH-afgeleide wrap-sleutel vinden.
  ///
  /// Een keyshare die niet voor dit device is, wordt stil gedropt — elke
  /// occupant trial-opent elke broadcast keyshare; falen is geen fout.
  Future<void> handleKeyshare(Stanza stanza) async {
    final child = _childByNs(stanza, OciDeckNamespace.keyshare);
    if (child == null) return;
    final WrappedKey wrap;
    try {
      wrap = WrappedKey.fromJson(
        jsonDecode(child.innerText) as Map<String, Object?>,
      );
    } on Exception catch (e) {
      logWarning('xmpp.keyexchange.keyshare.parse', e);
      return;
    }
    // Eigen keyshare niet installeren — de MUC reflecteert de afzender zijn
    // eigen bericht terug, en de autoriteit heeft de epoch-sleutel al. De
    // autoriteit staat niet in zijn eigen directory (handleDevicePresence slaat
    // het eigen device over), dus candidates is leeg en de check hieronder dropt
    // hem. Een nick-based check is onbetrouwbaar (#1415): de MUC-nick en de
    // XMPP-resource hebben geen relatie, en een toevallige nick-botsing kan een
    // andere deelnemer's keyshare incorrect droppen.
    final senderAddress = stanza.from ?? roomJid;
    final candidates = directory.devicesForAddress(senderAddress).toList();
    if (candidates.isEmpty) {
      logWarning('xmpp.keyexchange.keyshare.unknownSender', senderAddress);
      return;
    }
    for (final sender in candidates) {
      try {
        await _e2ee.installEpochKey(wrap, sender);
        return; // geïnstalleerd — deze keyshare was voor ons
      } on CollabCryptoException {
        continue; // verkeerde afzender of niet-geopend — probeel de volgende
      }
    }
    // Geen matchende device — deze keyshare was niet voor ons. Niet een
    // fout: elke occupant trial-opent elke broadcast keyshare; alleen de
    // bedoelde ontvanger slaagt.
  }

  /// Ruim de demux-registraties op. Idempotent. De directory en de crypto
  /// zijn van de aanroeper — die worden hier niet gesloten.
  Future<void> dispose() async {
    _demux.register(OciDeckNamespace.device, (_) async {});
    _demux.register(OciDeckNamespace.keyshare, (_) async {});
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
