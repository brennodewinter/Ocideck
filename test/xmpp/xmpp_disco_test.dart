// Tests for XmppDisco (#2533): XEP-0030 items/info parsing and MUC-component
// discovery over a scripted channel. Bounds covered: iq-error → refused,
// missing feature → notFound, silence → timeout, stream close → sessionClosed,
// and the item-walk cap.

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/xmpp/xmpp_disco.dart';
import 'package:ocideck/xmpp/xmpp_session.dart';
import 'package:ocideck/xmpp/xmpp_stanza.dart';

/// A channel that answers iq-gets per `to` with a scripted reply — the reply
/// is queued as a microtask so it lands after the query's `.first`
/// subscription exists (broadcast streams drop pre-subscription events).
class _ScriptedChannel implements XmppStanzaChannel {
  _ScriptedChannel(this.replies);

  /// `to` → a builder producing the reply stanza XML for our request id.
  /// A missing entry means "the server never answers" (timeout path).
  final Map<String, String Function(String id)> replies;

  final _inbound = StreamController<Stanza>.broadcast();
  final sent = <Stanza>[];

  @override
  String? boundJid = 'guest@anon.example/res';

  @override
  Stream<Stanza> get stanzas => _inbound.stream;

  @override
  void sendStanza(Stanza stanza) {
    sent.add(stanza);
    final build = replies[stanza.to];
    if (build != null) {
      scheduleMicrotask(() {
        if (!_inbound.isClosed) _inbound.add(Stanza.parse(build(stanza.id!)));
      });
    }
  }

  void drop() => _inbound.close();
}

String _items(String id, List<String> jids) =>
    '<iq type="result" id="$id"><query xmlns="http://jabber.org/protocol/disco#items">'
    '${jids.map((j) => '<item jid="$j"/>').join()}'
    '</query></iq>';

String _info(String id, List<String> features) =>
    '<iq type="result" id="$id"><query xmlns="http://jabber.org/protocol/disco#info">'
    '<identity category="conference" type="text"/>'
    '${features.map((f) => '<feature var="$f"/>').join()}'
    '</query></iq>';

const _muc = 'http://jabber.org/protocol/muc';

void main() {
  test('items parses jids and attributes', () async {
    final ch = _ScriptedChannel({
      'd.example': (id) => _items(id, ['a.d.example', 'b.d.example']),
    });
    final r = await XmppDisco(channel: ch).items('d.example');
    expect(r.ok, isTrue);
    expect(r.value!.map((i) => i.jid), ['a.d.example', 'b.d.example']);
    expect(ch.sent.single.type, 'get');
  });

  test(
    'findMucComponent walks items until one advertises the MUC feature',
    () async {
      final ch = _ScriptedChannel({
        'meet.jitsi': (id) =>
            _items(id, ['focus.meet.jitsi', 'muc.meet.jitsi']),
        'focus.meet.jitsi': (id) => _info(id, ['urn:xmpp:ping']),
        'muc.meet.jitsi': (id) => _info(id, [_muc]),
      });
      final r = await XmppDisco(channel: ch).findMucComponent('meet.jitsi');
      expect(r.ok, isTrue);
      expect(r.value, 'muc.meet.jitsi');
      // items on the domain + info on focus + info on muc = 3 queries.
      expect(ch.sent.length, 3);
    },
  );

  test('notFound when no item advertises MUC', () async {
    final ch = _ScriptedChannel({
      'd.example': (id) => _items(id, ['x.d.example']),
      'x.d.example': (id) => _info(id, ['urn:xmpp:ping']),
    });
    final r = await XmppDisco(channel: ch).findMucComponent('d.example');
    expect(r.failure, DiscoFailure.notFound);
  });

  test('an iq-error maps to refused', () async {
    final ch = _ScriptedChannel({
      'd.example': (id) =>
          '<iq type="error" id="$id"><error type="cancel">'
          '<service-unavailable xmlns="urn:ietf:params:xml:ns:xmpp-stanzas"/>'
          '</error></iq>',
    });
    final r = await XmppDisco(channel: ch).items('d.example');
    expect(r.failure, DiscoFailure.refused);
  });

  test('silence maps to timeout', () async {
    final ch = _ScriptedChannel({});
    final r = await XmppDisco(
      channel: ch,
      timeout: const Duration(milliseconds: 30),
    ).items('d.example');
    expect(r.failure, DiscoFailure.timeout);
  });

  test('a dropped session maps to sessionClosed', () async {
    final ch = _ScriptedChannel({});
    final disco = XmppDisco(channel: ch, timeout: const Duration(seconds: 30));
    final pending = disco.items('d.example');
    ch.drop();
    expect((await pending).failure, DiscoFailure.sessionClosed);
  });

  test('the items walk is capped', () async {
    final many = List.generate(50, (i) => 'c$i.d.example');
    final ch = _ScriptedChannel({
      'd.example': (id) => _items(id, many),
      for (final j in many) j: (id) => _info(id, []),
    });
    final r = await XmppDisco(
      channel: ch,
      maxItemsToInspect: 5,
    ).findMucComponent('d.example');
    expect(r.failure, DiscoFailure.notFound);
    // items + at most 5 info queries.
    expect(ch.sent.length, lessThanOrEqualTo(6));
  });
}
