import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/xmpp/xmpp_stanza.dart';
import 'package:xml/xml.dart';

void main() {
  group('round-trips', () {
    test('a groupchat message survives serialise → parse', () {
      final sent = Stanza(
        kind: StanzaKind.message,
        to: 'room@conference.example/nick',
        id: 'm1',
        type: 'groupchat',
        children: [xmppElement('body', text: 'hallo')],
      );
      final got = Stanza.parse(sent.toXmlString());
      expect(got.kind, StanzaKind.message);
      expect(got.to, 'room@conference.example/nick');
      expect(got.id, 'm1');
      expect(got.type, 'groupchat');
      expect(got.child('body')?.innerText, 'hallo');
    });

    test('an iq with a namespaced payload survives', () {
      final sent = Stanza(
        kind: StanzaKind.iq,
        to: 'example.com',
        id: 'bind1',
        type: 'set',
        children: [
          xmppElement(
            'bind',
            namespace: 'urn:ietf:params:xml:ns:xmpp-bind',
            children: [xmppElement('resource', text: 'ocideck')],
          ),
        ],
      );
      final got = Stanza.parse(sent.toXmlString());
      expect(got.kind, StanzaKind.iq);
      expect(got.type, 'set');
      final bind = got.child('bind');
      expect(bind?.getAttribute('xmlns'), 'urn:ietf:params:xml:ns:xmpp-bind');
      expect(bind?.childElements.single.innerText, 'ocideck');
    });
  });

  group('parses real-world stanzas', () {
    test('a MUC occupant presence', () {
      const raw =
          '<presence from="room@conference.example/nick" '
          'to="user@example/res">'
          '<x xmlns="http://jabber.org/protocol/muc#user">'
          '<item affiliation="member" role="participant"/></x></presence>';
      final p = Stanza.parse(raw);
      expect(p.kind, StanzaKind.presence);
      expect(p.from, 'room@conference.example/nick');
      final x = p.child('x');
      expect(x?.getAttribute('xmlns'), 'http://jabber.org/protocol/muc#user');
      expect(x?.childElements.single.getAttribute('affiliation'), 'member');
    });

    test('an iq result with no payload', () {
      final p = Stanza.parse('<iq type="result" id="s1" from="example.com"/>');
      expect(p.kind, StanzaKind.iq);
      expect(p.type, 'result');
      expect(p.children, isEmpty);
      expect(p.child('anything'), isNull);
    });
  });

  group('rejects unsafe or non-stanza input', () {
    test('a DTD/doctype is refused (XMPP forbids it; XXE defence)', () {
      expect(
        () => Stanza.parse('<!DOCTYPE message><message/>'),
        throwsFormatException,
      );
    });

    test('an internal entity declaration is refused', () {
      expect(
        () => Stanza.parse(
          '<!DOCTYPE m [<!ENTITY x "y">]><message><body>&x;</body></message>',
        ),
        throwsFormatException,
      );
    });

    test('a non-stanza root element is refused', () {
      expect(() => Stanza.parse('<foo/>'), throwsFormatException);
    });

    test('malformed XML is refused', () {
      expect(() => Stanza.parse('<message>'), throwsFormatException);
    });
  });

  group('xmppElement helper', () {
    test('sets namespace, attributes and text', () {
      final e = xmppElement(
        'x',
        namespace: 'http://jabber.org/protocol/muc',
        attributes: {'a': '1'},
        text: 't',
      );
      expect(e.name.local, 'x');
      expect(e.getAttribute('xmlns'), 'http://jabber.org/protocol/muc');
      expect(e.getAttribute('a'), '1');
      expect(e.innerText, 't');
    });
  });
}
