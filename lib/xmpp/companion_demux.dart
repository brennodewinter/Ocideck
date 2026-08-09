// De companion-demux: één abonnement op `channel.stanzas`, fan-out per
// namespace (`docs/design/XMPP_COLLAB_TRANSPORT.md` §3, §5 brick 7). De MUC
// reflecteert elke OciDeck-payload als één `<message type=groupchat>` met een
// child-element in een `nl.ocideck.*`-namespace. Deze laag bezit dat ene
// abonnement en routeert elke stanza naar de brick die voor die namespace
// heeft geregistreerd — de transport (ops/locks/resync), de key-exchange
// (device keys/keyshare), de snapshot-channel, presence, chat. Zonder deze
// centraal eigenaar zou elke brick eigen abonnement openen en concurreren
// over dezelfde stroom (wat bij Matrix de single-sync-loop-reden is).
//
// Fail-closed: een stanza met een namespace die niemand geregistreerd heeft
// wordt gedropt (gelogd via [onUnknownNamespace] indien gezet), nooit
// doorgelaten — een onbekend payload-type is invoer, geen instructie.

import 'dart:async';

import 'package:xml/xml.dart';

import '../utils/log.dart';
import 'xmpp_session.dart';
import 'xmpp_stanza.dart';

/// Eén abonnement op [channel.stanzas] met fan-out per namespace. Registreer
/// een handler per `nl.ocideck.*`-namespace met [register]; de demux routeert
/// elke inbound stanza naar de handler van het eerste child-element met een
/// bekende namespace. Onbekende namespaces worden fail-closed gedropt.
class CompanionDemux {
  CompanionDemux({
    required XmppStanzaChannel channel,
    this.onUnknownNamespace,
  }) {
    _sub = channel.stanzas.listen(_onStanza, onDone: _onDone);
  }

  /// Optionele callback voor een stanza met een namespace die niemand
  /// geregistreerd heeft. Bedoeld voor diagnostiek; de stanza wordt sowieso
  /// gedropt. Niet voor productie-afhandeling — een onbekend payload-type is
  /// invoer, en de default (loggen + droppen) is fail-closed.
  final void Function(Stanza stanza)? onUnknownNamespace;

  final _handlers = <String, Future<void> Function(Stanza)>{};
  late final StreamSubscription<Stanza> _sub;
  bool _disposed = false;

  /// Seriële verwerkings-queue — elke stanza's handler wordt pas gestart nadat
  /// de vorige is voltooid. Voorkomt CPU-overspoiling door een vloed gelijktijdige
  /// crypto-handlers (#1420). Een uitzondering in één handler breekt de chain
  /// niet (catchError per stanza).
  Future<void> _queue = Future<void>.value();

  /// Registreer [handler] voor [namespace]. Elke inbound stanza met een child
  /// in die namespace wordt ernaar gerouteerd. Eén namespace, één handler —
  /// een tweede registratie overschrijft de eerste (de laatste wint).
  void register(String namespace, Future<void> Function(Stanza) handler) {
    if (_disposed) return;
    _handlers[namespace] = handler;
  }

  /// De namespaces die momenteel een handler hebben — voor diagnostiek en tests.
  Iterable<String> get registeredNamespaces => _handlers.keys;

  void _onStanza(Stanza stanza) {
    if (_disposed) return;
    // Seriële verwerking: keten elke stanza aan de vorige (#1420). Dit beperkt
    // gelijktijdigheid tot 1 — een vloed stanzas start geen vloed gelijktijdige
    // crypto-handlers (AEAD-decryptie, Ed25519-verificatie). De afruil is dat
    // een trage handler (zware snapshot-reassemblage) latere stanzas vertraagt,
    // maar dat is acceptabeler dan een onresponsieve app.
    _queue = _queue.then((_) async {
      if (_disposed) return;
      // Vind het eerste child-element met een xmlns en routeer naar de handler.
      for (final child in stanza.children) {
        final ns = _namespaceOf(child);
        if (ns == null) continue;
        final handler = _handlers[ns];
        if (handler != null) {
          // ponytail: een uitzondering in een handler mag de demux niet
          // stilleggen — log en ga door, als een tweede namespace-brick niet
          // mag blokkeren omdat de eerste een corrupte stanza kreeg.
          try {
            await handler(stanza);
          } catch (e) {
            logWarning('xmpp.demux.handler', e);
          }
          return;
        }
      }
      // Onbekende namespace — fail-closed: log + drop. Log alleen een safe
      // summary (kind, from, to, child-namespace) — niet de volledige stanza
      // XML, die chat-berichten, device-keys of andere payload kan bevatten
      // (#1431).
      if (onUnknownNamespace != null) {
        onUnknownNamespace!(stanza);
      } else {
        logWarning('xmpp.demux.unknownNamespace', _safeSummary(stanza));
      }
    });
  }

  void _onDone() {
    // De stroom is compleet (sessie gesloten). Geen actie nodig — de handlers
    // worden door hun eigenaars opgeruimd. De demux is inert na de stroom.
  }

  /// Een privacy-veilige samenvatting van een stanza voor logging — kind,
  /// from, to, en de child-namespaces. Bevat NIET de inner XML of text content,
  /// die chat-berichten of device-keys kan bevatten (#1431).
  static String _safeSummary(Stanza stanza) {
    final namespaces = stanza.children
        .map((c) => _namespaceOf(c))
        .whereType<String>()
        .join(',');
    return '${stanza.kind.name} from=${stanza.from ?? "?"} '
        'to=${stanza.to ?? "?"} ns=[$namespaces]';
  }

  /// Zoek de namespace van een child-element — zowel de geserialiseerde
  /// `xmlns`-attribuutvorm als de geparsede `namespaceUri` (een round-trip
  //  door `package:xml` kan de ene of de andere vorm opleveren). Spiegelt
  /// `XmppMuc._hasNs`.
  static String? _namespaceOf(XmlElement e) {
    final attr = e.getAttribute('xmlns');
    if (attr != null) return attr;
    return e.name.namespaceUri;
  }

  /// Ruim het abonnement op. Idempotent. De geregistreerde handlers worden
  /// niet gesloten — die zijn van hun eigenaars.
  Future<void> dispose() async {
    _disposed = true;
    _handlers.clear();
    await _sub.cancel();
  }
}
