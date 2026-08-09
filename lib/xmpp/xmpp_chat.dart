// De sessie-chat over de companion-MUC (`docs/design/XMPP_COLLAB_TRANSPORT.md`
// §5 brick 5, §3, §4, §8, sub-plak 7): de XMPP-tegenhanger van `MatrixChat`.
// Berichten rijden verzegeld + **ondertekend** in een `<chat
// xmlns="nl.ocideck.chat">` op een `<message type=groupchat>` (§3) — een
// gesprek is historie, dus het stapelt (in tegenstelling tot presence).
//
// **Ondertekend**, net als bij Matrix: elk sessie-lid houdt dezelfde epoch-
// sleutel, dus een ondertekend bericht zou één lid er een kunnen vervalsen
// toegeschreven aan een ander — en chat is precies waar "wie zei wat"
// betrouwbaar moet zijn. Dus een bericht wordt verzegeld met een handtekening
// en geopend met een vereiste; een bericht dat de controle faalt wordt
// fail-closed gedropt.
//
// **Sealed-id-dedup (§4)** — het verschil met Matrix. Een MUC heeft geen
// `/sync`-cursor, dus MAM/resync herleveren een bericht, en chat heeft (net als
// `matrix_chat.dart`) geen eigen dedup. Daarom draagt elk `<chat>` een **id =
// hash van de verzegelde bytes** (`sealed.toContent()`, inclusief een verse per-
// seal nonce — een geforceerde botsing is onmogelijk en een replay is correct
// idempotent; een *plaintext* hash zou ten onrechte identieke tekst
// onderdrukken). De dedup-set is **begrensd** (zoals de berichtenlijst).
//
// De dedup-beslissing valt **na** een geslaagde open + handtekeningverificatie:
// een vervalser zonder de ondertekenende sleutel produceert geen geldig
// bericht, dus kan de dedup-set niet vullen met junk om echte berichten te
// onderdrukken. Een replay van een geldig bericht opent (geldige handtekening),
// treft zijn id in de set, en wordt gedropt.
//
// Eigen berichten worden lokaal geëchood op [send] (zodat ze meteen tonen) en
// overgeslagen op receive — de afzender ziet geen duplicaat als zijn eigen
// bericht terugkomt.

import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:xml/xml.dart';

import '../collab/collab_crypto.dart';
import '../collab/collab_device_directory.dart';
import '../utils/log.dart';
import 'companion_demux.dart';
import 'xmpp_session.dart';
import 'xmpp_stanza.dart';
import 'xmpp_transport.dart' show OciDeckNamespace;

/// Één chat-regel, zoals het paneel hem toont.
class ChatMessage {
  const ChatMessage({
    required this.userId,
    required this.deviceId,
    required this.text,
    required this.isSelf,
  });

  final String userId;
  final String deviceId;
  final String text;

  /// True voor een bericht dat dit device verstuurde (lokaal geëchood, rechts
  /// uitgelijnd).
  final bool isSelf;
}

/// Zendt en ontvangt sessie-chat. Registreert zichzelf op de demux voor
/// `nl.ocideck.chat`; de app roept [send]. [onChanged] vuurt als de lijst groeit.
/// Verzegeld + ondertekend + sealed-id-dedup; fail-closed.
class XmppChat {
  XmppChat({
    required XmppStanzaChannel stanzaChannel,
    required CompanionDemux companionDemux,
    required CollabCrypto crypto,
    required this.roomJid,
    required this.directory,
    required this.ownUserId,
    this.maxMessageChars = 4000,
    this.dedupCap = 256,
    this.pendingCap = 256,
  }) : _channel = stanzaChannel,
       _demux = companionDemux,
       _e2ee = crypto {
    _demux.register(OciDeckNamespace.chat, handleChat);
  }

  /// De namespace die één verzegeld + ondertekend chat-bericht draagt (§3). Het
  /// child-element is `<chat>`, met `{'id': sealedId, 'sealed': envelope}` als
  /// JSON-text — het id is de hash van `sealed.toContent()` voor dedup (§4).
  static const chatType = OciDeckNamespace.chat;

  final XmppStanzaChannel _channel;
  final CompanionDemux _demux;
  final CollabCrypto _e2ee;
  final String roomJid;
  final CollabDeviceDirectory directory;

  /// Dit device's adres (room/nick), om een lokaal geëchood eigen bericht toe
  /// te schrijven.
  final String ownUserId;

  /// Cap op één bericht — blijft ruim onder de 512 KiB stanza-cap (§7).
  final int maxMessageChars;

  /// Cap op de dedup-set (§4 "bounded like the message list"). Een vijandige
  /// server mag de set niet uitputten; de afruil is dat een id na verdrijving
  /// niet meer wordt onderdrukt (een oude herlevering kan terugkomen).
  final int dedupCap;

  /// Cap op de pending-buffer — berichten die aankwamen vóór de afzender's
  /// keys of de epoch-sleutel bekend waren. Een vijandige server mag de buffer
  /// niet onbegrensd laten groeien; bij overflow verdrijft het oudste (FIFO).
  final int pendingCap;

  final List<ChatMessage> _messages = [];

  /// Verzegelde berichten die aankwamen vóór de afzender's keys of de epoch-
  /// sleutel bekend waren; heropend in [retryPending] in aankomstvolgorde.
  final List<SealedEnvelope> _pending = [];

  /// Of er gebufferde berichten wachten op retry — voor de syncNow short-circuit
  /// (#1423). Als dit false is, is retryPending een no-op en hoeft syncNow de
  /// call niet te doen.
  bool get hasPending => _pending.isNotEmpty;

  /// De begrensde dedup-set: de sealed-id's van succesvol geopende berichten,
  /// oudste eerst (FIFO-verdrijving als [dedupCap] bereikt is).
  final List<String> _seenIds = [];

  /// Vuurt nadat de berichtenlijst verandert, zodat de provider de UI verversen kan.
  void Function()? onChanged;

  /// Het gesprek tot nu toe, oudste eerst.
  List<ChatMessage> get messages => List.unmodifiable(_messages);

  /// Zend [text] naar de kamer (ondertekend + verzegeld) en echo hem lokaal met-
  /// een. Een leeg of te lang bericht wordt geweigerd.
  Future<void> send(String text) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty || trimmed.length > maxMessageChars) return;
    final sealed = await _e2ee.seal(
      {'text': trimmed},
      room: roomJid,
      type: chatType,
      signed: true,
    );
    final id = _sealedId(sealed);
    _messages.add(
      ChatMessage(
        userId: ownUserId,
        deviceId: _e2ee.deviceId,
        text: trimmed,
        isSelf: true,
      ),
    );
    onChanged?.call();
    _channel.sendStanza(
      Stanza(
        kind: StanzaKind.message,
        type: 'groupchat',
        to: roomJid,
        children: [
          xmppElement(
            'chat',
            namespace: chatType,
            text: jsonEncode({'id': id, 'sealed': sealed.toContent()}),
          ),
        ],
      ),
    );
  }

  /// Verwerk een inbound `<chat>`-stanza (wire aan de demux). Buffert de
  /// verzegeling en opent haar in [retryPending]; een eigen echo wordt gedropt.
  Future<void> handleChat(Stanza stanza) async {
    final child = _childByNs(stanza, chatType);
    if (child == null) return;
    try {
      final decoded = jsonDecode(child.innerText);
      if (decoded is! Map<String, Object?>) {
        logWarning('xmpp.chat.notObject', decoded);
        return;
      }
      final sealedMap = decoded['sealed'];
      if (sealedMap is! Map<String, Object?>) {
        logWarning('xmpp.chat.noSealed', decoded);
        return;
      }
      final sealed = SealedEnvelope.fromContent(sealedMap);
      // Eigen echo — de MUC reflecteert de afzender zijn eigen bericht terug;
      // de lokale echo is al toegevoegd in [send].
      if (sealed.senderDevice == _e2ee.deviceId) return;
      if (_pending.length >= pendingCap) {
        _pending.removeAt(0); // FIFO-verdrijving
      }
      _pending.add(sealed);
      await retryPending();
    } on Exception catch (e) {
      logWarning('xmpp.chat', e);
    }
  }

  /// Heropen gebufferde berichten waarvan de sleutel of afzender nu bekend kan
  /// zijn. Verwerkt de hele lijst in één pas — een nog-niet-openbaar bericht
  /// (onbekende afzender of epoch) blokkeert niet de berichten erachter (geen
  /// head-of-line blocking, #1412); het blijft voor de volgende ronde staan.
  Future<void> retryPending() async {
    var progressed = false;
    final stillPending = <SealedEnvelope>[];
    while (_pending.isNotEmpty) {
      final sealed = _pending.removeAt(0);
      final opened = await _open(sealed);
      if (opened == null) {
        stillPending.add(sealed); // afzender/epoch nog niet — houd
      } else if (opened.isNotEmpty) {
        _messages.add(_messageFrom(opened));
        progressed = true;
      }
      // opened leeg → misvormd/dup/slechte handtekening — drop fail-closed
    }
    _pending.addAll(stillPending);
    if (progressed) onChanged?.call();
  }

  /// Opent [sealed], of null als hij nog niet openbaar is (onbekende afzender
  /// of epoch — houd en retry). Returns een lege map als hij openbaar maar
  /// onbruikbaar is (slechte handtekening/tag, misvormd, of een gedupliceerde
  /// sealed-id — drop). De dedup-check valt ná de geslaagde open + verificatie,
  /// zodat een vervalser de set niet kan vullen (§4).
  Future<Map<String, Object?>?> _open(SealedEnvelope sealed) async {
    final sender = directory.resolve(sealed.senderDevice);
    if (sender == null) return null; // afzender onbekend — houd
    try {
      final opened = await _e2ee.open(
        sealed,
        room: roomJid,
        type: chatType,
        sender: sender,
        requireSignature: true,
      );
      final text = opened['text'];
      if (text is! String) return const {}; // openbaar maar misvormd — drop
      final id = _sealedId(sealed);
      if (_seenIds.contains(id)) return const {}; // replay — drop
      _remember(id);
      return {'text': text, 'device': sealed.senderDevice};
    } on CollabCryptoException catch (e) {
      if (e.reason == 'unknown-epoch') return null; // sleutel nog niet — houd
      logWarning(
        'xmpp.chat.open',
        e,
      ); // slechte handtekening/tag — drop fail-closed
      return const {};
    }
  }

  ChatMessage _messageFrom(Map<String, Object?> opened) {
    final device = opened['device'] as String;
    return ChatMessage(
      userId: directory.addressOf(device) ?? '',
      deviceId: device,
      text: opened['text'] as String,
      isSelf: false,
    );
  }

  /// De sealed-id: SHA-256 over `jsonEncode(sealed.toContent())`. De per-seal
  /// nonce zit in de verzegeling, dus een geforceerde botsing is onmogelijk en
  /// een replay is correct idempotent (§4). Sender en receiver produceren
  /// dezelfde JSON — `toContent()` heeft een vaste sleutelvolgorde — dus dezelfde
  /// hash.
  String _sealedId(SealedEnvelope sealed) =>
      sha256.convert(utf8.encode(jsonEncode(sealed.toContent()))).toString();

  /// Onthoud [id] in de begrensde dedup-set; verdrijf het oudste als de cap
  /// bereikt is (FIFO).
  void _remember(String id) {
    if (_seenIds.length >= dedupCap) _seenIds.removeAt(0);
    _seenIds.add(id);
  }

  /// Ruim de berichtenlijst op — testhulp voor de tampered-signature-test, die
  /// het origineel al via de hub ontving en alleen de verminkte levering wil
  /// meten. Geen productie-API.
  void discardMessages() {
    _messages.clear();
  }

  /// Ruim de demux-registratie op. Idempotent. De directory en de crypto zijn
  /// van de aanroeper — die worden hier niet gesloten.
  Future<void> dispose() async {
    _demux.register(chatType, (_) async {});
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
