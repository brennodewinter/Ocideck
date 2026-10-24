// Service discovery (XEP-0030) over a live [XmppStanzaChannel]. The one caller
// that needs it now is the Jitsi preflight (#2533): the MUC component of a
// deployment is DISCOVERED (`disco#items` on the domain, then `disco#info` on
// each item until one carries the `.../muc` feature) — never assumed to be
// `conference.<domain>`, which is merely the common convention and breaks on
// deployments that name it differently (the testbed uses `muc.meet.jitsi`).
//
// Request/response correlation is by stanza id over the broadcast stream, the
// same shape `XmppMuc` uses for presence. Everything here is bounded: a reply
// deadline, a cap on items walked for `info`, and max JID/field lengths — a
// hostile server may not keep the preflight busy or exhaust memory.
//
// Failures are typed ([DiscoFailure]) so the caller maps them onto its own
// vocabulary (`MeetingFailureReason`); this layer carries no l10n.

import 'dart:async';

import 'package:xml/xml.dart';

import 'xmpp_session.dart' show XmppStanzaChannel;
import 'xmpp_stanza.dart';

const _discoItemsNs = 'http://jabber.org/protocol/disco#items';
const _discoInfoNs = 'http://jabber.org/protocol/disco#info';
const _mucFeature = 'http://jabber.org/protocol/muc';

/// Why a discovery exchange did not succeed.
enum DiscoFailure {
  /// The entity did not answer within the deadline.
  timeout,

  /// The entity answered with an iq-error (or a malformed reply).
  refused,

  /// The session dropped mid-exchange.
  sessionClosed,

  /// Discovery itself worked, but no item advertised the needed feature.
  notFound,
}

/// One `disco#items` entry: an addressable entity on the queried JID.
class DiscoItem {
  const DiscoItem({required this.jid, this.name, this.node});

  final String jid;
  final String? name;
  final String? node;
}

/// The `disco#info` answer of one entity: identity tuples + feature URIs.
class DiscoInfo {
  const DiscoInfo({required this.identities, required this.features});

  /// `category/type` pairs — e.g. `conference/text` for a MUC component.
  final List<({String category, String type})> identities;
  final Set<String> features;

  bool hasFeature(String feature) => features.contains(feature);
}

/// The outcome of one discovery call.
class DiscoResult<T> {
  const DiscoResult.ok(this.value) : failure = null;
  const DiscoResult.failed(this.failure) : value = null;
  final T? value;
  final DiscoFailure? failure;
  bool get ok => failure == null;
}

/// Runs XEP-0030 queries on one live channel. Stateless besides the injected
/// clock/id factory; one instance per session is fine.
class XmppDisco {
  XmppDisco({
    required this.channel,
    this.timeout = const Duration(seconds: 15),
    int Function()? idFactory,
    this.maxItemsToInspect = 32,
  }) : _nextId = idFactory ?? _defaultIdFactory();

  final XmppStanzaChannel channel;
  final Duration timeout;

  /// Upper bound on `disco#info` queries issued after an `items` walk. A
  /// server listing thousands of components must not turn a preflight into
  /// an amplification of our own requests.
  final int maxItemsToInspect;

  final int Function() _nextId;
  static int Function() _defaultIdFactory() {
    var n = 0;
    return () => ++n;
  }

  static const _maxFieldLength = 3071; // RFC 6120 §3 JID cap, reused for fields

  /// `disco#items` on [entity] (a domain or component JID).
  Future<DiscoResult<List<DiscoItem>>> items(String entity) async {
    final reply = await _query(entity, _discoItemsNs);
    if (!reply.ok) return DiscoResult.failed(reply.failure!);
    final query = reply.value!;
    final out = <DiscoItem>[];
    for (final e in query.childElements) {
      if (e.name.local != 'item') continue;
      final jid = e.getAttribute('jid') ?? '';
      if (jid.isEmpty || jid.length > _maxFieldLength) continue;
      final name = e.getAttribute('name');
      final node = e.getAttribute('node');
      out.add(DiscoItem(jid: jid, name: _trim(name), node: _trim(node)));
      if (out.length >= maxItemsToInspect) break;
    }
    return DiscoResult.ok(out);
  }

  /// `disco#info` on [entity].
  Future<DiscoResult<DiscoInfo>> info(String entity) async {
    final reply = await _query(entity, _discoInfoNs);
    if (!reply.ok) return DiscoResult.failed(reply.failure!);
    final query = reply.value!;
    final identities = <({String category, String type})>[];
    final features = <String>{};
    for (final e in query.childElements) {
      switch (e.name.local) {
        case 'identity':
          final category = _trim(e.getAttribute('category')) ?? '';
          final type = _trim(e.getAttribute('type')) ?? '';
          if (category.isNotEmpty) {
            identities.add((category: category, type: type));
          }
        case 'feature':
          final v = e.getAttribute('var');
          if (v != null && v.isNotEmpty && v.length <= _maxFieldLength) {
            features.add(v);
          }
      }
    }
    return DiscoResult.ok(
      DiscoInfo(identities: identities, features: features),
    );
  }

  /// Discover the MUC component serving [domain]: `items` on the domain, then
  /// `info` on each item until one advertises the MUC feature. Returns the
  /// component JID (e.g. `muc.meet.jitsi`), or [DiscoFailure.notFound].
  Future<DiscoResult<String>> findMucComponent(String domain) async {
    final list = await items(domain);
    if (!list.ok) return DiscoResult.failed(list.failure!);
    for (final item in list.value!.take(maxItemsToInspect)) {
      final itemInfo = await info(item.jid);
      if (itemInfo.ok && itemInfo.value!.hasFeature(_mucFeature)) {
        return DiscoResult.ok(item.jid);
      }
    }
    return const DiscoResult.failed(DiscoFailure.notFound);
  }

  String? _trim(String? v) {
    if (v == null) return null;
    final t = v.trim();
    if (t.isEmpty || t.length > _maxFieldLength) return null;
    return t;
  }

  /// Send one `iq get` carrying `<query xmlns=ns>` to [entity] and await the
  /// `iq` reply with our id. Returns the `<query>` payload element.
  Future<DiscoResult<XmlElement>> _query(String entity, String ns) async {
    final id = 'disco-${_nextId()}';
    channel.sendStanza(
      Stanza(
        kind: StanzaKind.iq,
        to: entity,
        id: id,
        type: 'get',
        children: [xmppElement('query', namespace: ns)],
      ),
    );
    try {
      final stanza = await channel.stanzas
          .where((s) => s.kind == StanzaKind.iq && s.id == id)
          .first
          .timeout(timeout);
      if (stanza.type == 'error') {
        return const DiscoResult.failed(DiscoFailure.refused);
      }
      final query = stanza.child('query');
      if (query == null) return const DiscoResult.failed(DiscoFailure.refused);
      return DiscoResult.ok(query);
    } on TimeoutException {
      return const DiscoResult.failed(DiscoFailure.timeout);
    } on StateError {
      // `.first` op een gesloten broadcast stream: de sessie viel weg
      // midden in de uitwisseling.
      return const DiscoResult.failed(DiscoFailure.sessionClosed);
    }
  }
}
