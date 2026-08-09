// De sessie-baseline over de companion-MUC (`docs/design/XMPP_COLLAB_TRANSPORT.md`
// §5 brick 3, §4, §6): de XMPP-tegenhanger van `MatrixSnapshotChannel`. Een
// joiner heeft de autoriteit's [CollabSnapshot] nodig — de slide-lijst op een
// versie — om de slide-id-ruimte te delen vóór enige op (§5.5). Een XMPP-stanza
// is begrensd (frame ≤ 512 KiB, §7), dus een volledige baseline rijdt niet op
// één stanza; hij wordt **verzegeld en dan gechunked** over `<snap>`-stanzas,
// en aan de andere kant gereassembleerd.
//
// Verzegeld één keer, gechunked daarna: de hele snapshot wordt als één
// [SealedEnvelope] verzegeld (zodat de AEAD-tag over de hele baseline gaat —
// een gedropte of hervalgorde chunk maakt de gereassembleerde blob
// onopenbaar, fail-closed), en pas de ciphertext-blob wordt over stanzas
// gesplitst. Elke chunk-stanza draagt plaintext routing-metadata (`id`, index,
// count) als JSON-text en één slice van de blob; de inhoud zelf blijft
// ciphertext. Reassemblage is per chunk-id, geopend en handtekening-geverifieerd
// tegen de autoriteit's directory-gehouden sleutels (een snapshot is
// autoritatief, dus de handtekening is vereist — anti-impersonatie, P3).
//
// Twee rollen, twee uitgangen:
//   • **Join.** [firstSnapshot]/[hasSnapshot] — de eerste geopende baseline,
//     die een joiner afwacht vóór zijn sessie start. Een baseline die aankomt
//     vóór de epoch-sleutel (een joiner ziet de chunks vóór zijn keyshare, §6)
//     wordt gebufferd; [retryPending] heropent zodra een sleutel geïnstalleerd
//     is. Spiegelt `MatrixSnapshotChannel`.
//   • **Resync re-baseline (§4).** Na de eerste baseline emit [rebaselines]
//     elke volgende geopende snapshot — de autoriteit re-baselineert op een
//     `<resync>`-verzoek, en de follower re-baseert (`rebaseTo`, forward-only).
//     `MatrixSnapshotChannel` dropt na de eerste; deze laag niet, want de §4-
//     resync is de XMPP-tegenhanger van Matrix's hervatbare `/sync`.
//
// Wire aan de demux voor `nl.ocideck.snapshot`; de autoriteit roept
// [sendSnapshot]. Fail-closed en begrensd: een misvormde, onvolledige,
// onopenbare of te grote snapshot wordt gelogd en gedropt, en de pending-chunk-
// buffers zijn begrensd zodat een vijandige server het geheugen niet kan
// uitputten door chunks te overstromen.

import 'dart:async';
import 'dart:convert';

import 'package:xml/xml.dart';

import '../collab/collab_crypto.dart';
import '../collab/collab_device_directory.dart';
import '../collab/collab_snapshot.dart';
import '../utils/log.dart';
import 'companion_demux.dart';
import 'xmpp_session.dart';
import 'xmpp_stanza.dart';
import 'xmpp_transport.dart' show OciDeckNamespace;

/// Levert de sessie-baseline over de companion-MUC: verzegeld, gechunked over
/// `<snap>`-stanzas, gereassembleerd en geopend aan de andere kant. De eerste
/// geopende baseline voltooit [firstSnapshot] (de join-uitgang); elke volgende
/// emit op [rebaselines] (de §4-resync-re-baseline-uitgang).
class XmppSnapshotChannel {
  XmppSnapshotChannel({
    required XmppStanzaChannel stanzaChannel,
    required CompanionDemux companionDemux,
    required CollabCrypto crypto,
    required this.roomJid,
    required this.directory,
    this.maxChunkChars = 48000,
    this.maxChunks = 512,
    this.maxPendingSnapshots = 4,
    this.maxAssembledSnapshots = 4,
  }) : _channel = stanzaChannel,
       _demux = companionDemux,
       _e2ee = crypto {
    _demux.register(OciDeckNamespace.snapshot, handleSnapshot);
  }

  /// De namespace die één slice van een verzegelde snapshot-blob draagt (§3).
  /// De chunk-metadata (`id`/`i`/`n`) rijdt als JSON-text in het `<snap>`-child,
  /// samen met één slice van de ciphertext-blob in `data`.
  static const snapshotType = OciDeckNamespace.snapshot;

  final XmppStanzaChannel _channel;
  final CompanionDemux _demux;
  final CollabCrypto _e2ee;
  final String roomJid;
  final CollabDeviceDirectory directory;

  /// Ongeveer de plaintext tekens per chunk-stanza — ruim onder de 512 KiB
  /// frame-cap (§7) na JSON + base64-overhead.
  final int maxChunkChars;

  /// Cap op chunks per snapshot en op tegelijk gebufferde snapshots — een
  /// vijandige server mag het geheugen niet uitputten door chunks te
  /// overstromen.
  final int maxChunks;
  final int maxPendingSnapshots;

  /// Cap op gereassembleerde snapshots die nog niet geopend konden worden —
  /// een vijandige server kan _pending vullen, laten reassembleren (wat de
  /// _pending-slot vrijmaakt), en herhalen, zodat _assembled onbegrensd groeit
  /// (#1414). Bij overflow verdrijft het oudste (FIFO).
  final int maxAssembledSnapshots;

  int _out = 0;
  final Map<String, Map<int, String>> _pending = {};

  /// Snapshots die volledig gereassembleerd maar nog niet geopend zijn — omdat
  /// de epoch-sleutel nog niet in huis was (een joiner ziet de chunks vóór zijn
  /// keyshare). [retryPending] heropent zodra een sleutel geïnstalleerd kan
  /// zijn.
  final Map<String, SealedEnvelope> _assembled = {};
  final _first = Completer<CollabSnapshot>();

  /// De re-baseline-uitgang (§4): elke geopende snapshot ná de eerste. De
  /// autoriteit re-baselineert op een `<resync>`-verzoek; de launch luistert
  /// hierop en roept `CollabSession.rebaseTo` (forward-only, autoriteit-
  /// verzegeld — een gesmede baseline faalt closed).
  final _rebaselines = StreamController<CollabSnapshot>.broadcast();

  /// Voltooit met de eerste volledig-gereassembleerde, geopende snapshot — wat
  /// een joiner afwacht vóór zijn sessie start.
  Future<CollabSnapshot> get firstSnapshot => _first.future;

  /// Of al een snapshot is geopend — een non-blocking check voor een join-loop.
  bool get hasSnapshot => _first.isCompleted;

  /// De re-baseline-stroom (§4). Emit elke geopende snapshot ná de eerste.
  Stream<CollabSnapshot> get rebaselines => _rebaselines.stream;

  /// Heropen snapshots die gereassembleerd waren vóór hun epoch-sleutel
  /// beschikbaar was. Roep na een ronde die een keyshare geïnstalleerd kan
  /// hebben.
  Future<void> retryPending() async {
    for (final id in _assembled.keys.toList()) {
      await _tryOpen(id);
    }
  }

  /// Autoriteit: verzegel [snapshot] en verstuur als gechunkte `<snap>`-stanzas.
  /// De AEAD dekt de hele baseline; de handtekening maakt het verifieerbaar de
  /// autoriteit's.
  Future<void> sendSnapshot(CollabSnapshot snapshot) async {
    final sealed = await _e2ee.seal(
      {'snapshot': jsonEncode(snapshot.toJson())},
      room: roomJid,
      type: snapshotType,
      signed: true,
    );
    final blob = jsonEncode(sealed.toContent());
    final id = 'snap-${_e2ee.deviceId}-${_out++}';
    final chunks = _split(blob, maxChunkChars);
    for (var i = 0; i < chunks.length; i++) {
      _channel.sendStanza(
        Stanza(
          kind: StanzaKind.message,
          type: 'groupchat',
          to: roomJid,
          children: [
            xmppElement(
              OciDeckNamespace.localNameOf(snapshotType),
              namespace: snapshotType,
              text: jsonEncode({
                'id': id,
                'i': i,
                'n': chunks.length,
                'data': chunks[i],
              }),
            ),
          ],
        ),
      );
    }
  }

  /// Verwerk een inbound `<snap>`-stanza (wire aan de demux). Buffert chunks en,
  /// zodra een hele snapshot aanwezig is, reassembleert, opent en emit hem.
  Future<void> handleSnapshot(Stanza stanza) async {
    final child = _childByNs(stanza, snapshotType);
    if (child == null) return;
    try {
      final decoded = jsonDecode(child.innerText);
      if (decoded is! Map<String, Object?>) {
        logWarning('xmpp.snapshot.notObject', decoded);
        return;
      }
      final id = decoded['id'];
      final index = decoded['i'];
      final count = decoded['n'];
      final data = decoded['data'];
      if (id is! String ||
          index is! int ||
          count is! int ||
          data is! String ||
          count <= 0 ||
          count > maxChunks ||
          index < 0 ||
          index >= count) {
        logWarning('xmpp.snapshot.badChunk', id);
        return;
      }
      // Afzender-controle op chunk-niveau (#1411): het chunk-`id` bevat de
      // afzender's deviceId (`snap-{deviceId}-{counter}`). Een MUC zet op elke
      // groupchat-message een `from` (room@conf/nick); de directory kent de
      // afzender's deviceId → peerAddress. Een chunk wiens `id` een bekend
      // device claimt wiens adres niet met `from` overeenkomt, is gesmokkeld
      // door een vijandige occupant — drop fail-closed, zodat hij de legitieme
      // baseline niet kan corrumperen.
      if (stanza.from != null) {
        final claimed = _senderDeviceFromId(id);
        if (claimed != null) {
          final knownAddress = directory.addressOf(claimed);
          if (knownAddress != null && knownAddress != stanza.from) {
            logWarning('xmpp.snapshot.senderMismatch', id);
            return;
          }
        }
      }
      final parts = _pending.putIfAbsent(id, () => {});
      if (_pending.length > maxPendingSnapshots) {
        _pending.remove(id);
        logWarning('xmpp.snapshot.tooManyPending', id);
        return;
      }
      parts[index] = data;
      if (parts.length < count) return; // wacht op meer chunks
      _pending.remove(id);
      await _assemble(id, count, parts);
    } on Exception catch (e) {
      logWarning('xmpp.snapshot.chunk', e);
    }
  }

  Future<void> _assemble(String id, int count, Map<int, String> parts) async {
    final blob = StringBuffer();
    for (var i = 0; i < count; i++) {
      blob.write(parts[i]!);
    }
    final decoded = jsonDecode(blob.toString());
    if (decoded is! Map<String, Object?>) {
      logWarning('xmpp.snapshot.notEnvelope', id);
      return;
    }
    _assembled[id] = SealedEnvelope.fromContent(decoded);
    // Begrens _assembled — een vijandige server kan _pending vullen en laten
    // reassembleren (wat de _pending-slot vrijmaakt voor de volgende ronde),
    // zodat _assembled onbegrensd groeit (#1414). Verdrijf het oudste (FIFO).
    if (_assembled.length > maxAssembledSnapshots) {
      _assembled.remove(_assembled.keys.first);
    }
    await _tryOpen(id);
  }

  /// Open een gereassembleerde snapshot. Houdt hem gebufferd als hij nog niet
  /// geopend kan worden — de afzender onbekend, of de epoch-sleutel nog niet
  /// aangekomen (een joiner ziet de chunks vóór zijn keyshare) — zodat
  /// [retryPending] hem heropent. Elke andere fout (een echt slechte tag/
  /// payload) dropt hem fail-closed. De eerste geopende snapshot voltooit
  /// [firstSnapshot]; elke volgende emit op [rebaselines] (§4 re-baseline).
  Future<void> _tryOpen(String id) async {
    final sealed = _assembled[id];
    if (sealed == null) return;
    if (sealed.senderDevice == _e2ee.deviceId) {
      // Eigen echo — de MUC reflecteert de afzender zijn eigen bericht terug.
      _assembled.remove(id);
      return;
    }
    final sender = directory.resolve(sealed.senderDevice);
    if (sender == null) return; // afzender nog onbekend — houd en retry
    try {
      final envelope = await _e2ee.open(
        sealed,
        room: roomJid,
        type: snapshotType,
        sender: sender,
        requireSignature: true,
      );
      _assembled.remove(id);
      final raw = envelope['snapshot'];
      if (raw is! String) {
        logWarning('xmpp.snapshot.noPayload', id);
        return;
      }
      final json = jsonDecode(raw);
      if (json is! Map<String, Object?>) {
        logWarning('xmpp.snapshot.badPayload', id);
        return;
      }
      final snapshot = CollabSnapshot.fromJson(json);
      if (!_first.isCompleted) {
        _first.complete(snapshot);
      } else {
        if (!_rebaselines.isClosed) _rebaselines.add(snapshot);
      }
    } on CollabCryptoException catch (e) {
      if (e.reason == 'unknown-epoch') return; // sleutel nog niet — houd
      _assembled.remove(id); // een echte fout (slechte tag/handtekening): drop
      logWarning('xmpp.snapshot.open', e);
    }
  }

  /// Ruim de demux-registratie en de streams op. Idempotent. De directory en de
  /// crypto zijn van de aanroeper — die worden hier niet gesloten.
  Future<void> dispose() async {
    _demux.register(snapshotType, (_) async {});
    if (!_rebaselines.isClosed) await _rebaselines.close();
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

  List<String> _split(String s, int size) {
    if (s.length <= size) return [s];
    final out = <String>[];
    for (var i = 0; i < s.length; i += size) {
      out.add(s.substring(i, i + size > s.length ? s.length : i + size));
    }
    return out;
  }

  /// Haal de afzender's deviceId uit een chunk-`id` (`snap-{deviceId}-{counter}`).
  /// De counter is het laatste `-`-segment; de deviceId is alles ertussen. Null
  /// als het `id` niet aan het formaat voldoet.
  String? _senderDeviceFromId(String id) {
    if (!id.startsWith('snap-')) return null;
    final rest = id.substring(5);
    final lastDash = rest.lastIndexOf('-');
    if (lastDash <= 0) return null;
    return rest.substring(0, lastDash);
  }
}
