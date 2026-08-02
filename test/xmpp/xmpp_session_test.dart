import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/models/xmpp_settings.dart';
import 'package:ocideck/xmpp/xmpp_frame_transport.dart';
import 'package:ocideck/xmpp/xmpp_session.dart';
import 'package:ocideck/xmpp/xmpp_stanza.dart';
import 'package:xml/xml.dart';

/// A scriptable server: for each frame the client sends, [respond] returns the
/// frames to push back. [inject] pushes a server-initiated frame (used to test
/// the live inbound dispatch after the session is up).
class FakeXmppTransport implements XmppFrameTransport {
  FakeXmppTransport(this.respond);

  final List<String> Function(String frame) respond;
  final _inbound = StreamController<String>();
  final sent = <String>[];
  bool closed = false;

  @override
  Stream<String> get inbound => _inbound.stream;

  @override
  void send(String frame) {
    sent.add(frame);
    for (final reply in respond(frame)) {
      if (!_inbound.isClosed) _inbound.add(reply);
    }
  }

  void inject(String frame) {
    if (!_inbound.isClosed) _inbound.add(frame);
  }

  /// Simulate the server ending the stream (EOF) without the client closing.
  void dropStream() {
    if (!_inbound.isClosed) _inbound.close();
  }

  @override
  Future<void> close() async {
    if (closed) return;
    closed = true;
    await _inbound.close();
  }
}

const _sasl = 'urn:ietf:params:xml:ns:xmpp-sasl';
const _bind = 'urn:ietf:params:xml:ns:xmpp-bind';
const _openReply = '<open xmlns="urn:ietf:params:xml:ns:xmpp-framing"/>';

String _features(List<String> mechanisms) =>
    '<stream:features xmlns:stream="http://etherx.jabber.org/streams">'
    '<mechanisms xmlns="$_sasl">'
    '${mechanisms.map((m) => '<mechanism>$m</mechanism>').join()}'
    '</mechanisms></stream:features>';

const _bindFeatures =
    '<stream:features xmlns:stream="http://etherx.jabber.org/streams">'
    '<bind xmlns="$_bind"/></stream:features>';

String _bindResult(String jid) =>
    '<iq type="result" id="bind-1"><bind xmlns="$_bind">'
    '<jid>$jid</jid></bind></iq>';

String _b64(String s) => base64.encode(utf8.encode(s));

/// A server that authenticates, then restarts + offers bind, then binds [jid].
/// [sasl] answers the `<auth>`/`<response>` frames; when it emits `<success>`
/// the server flips to the post-auth (bind) features on the next `<open>`.
FakeXmppTransport happyServer({
  required List<String> mechanisms,
  required List<String> Function(String frame) sasl,
  String jid = 'user@example.org/ocideck-abc',
}) {
  var authed = false;
  return FakeXmppTransport((frame) {
    if (frame.contains('<open')) {
      return authed
          ? [_openReply, _bindFeatures]
          : [_openReply, _features(mechanisms)];
    }
    if (frame.contains('<auth') || frame.contains('<response')) {
      final out = sasl(frame);
      if (out.any((f) => f.contains('<success'))) authed = true;
      return out;
    }
    if (frame.contains('<iq') && frame.contains('bind')) {
      return [_bindResult(jid)];
    }
    return const [];
  });
}

void main() {
  XmppSettings account({String jid = 'user@example.org'}) =>
      XmppSettings(serverUrl: 'wss://example.org/xmpp-websocket', jid: jid);

  test('ANONYMOUS authenticates and binds a resource', () async {
    final t = happyServer(
      mechanisms: ['ANONYMOUS'],
      sasl: (_) => ['<success xmlns="$_sasl"/>'],
      jid: 'anon@example.org/x1',
    );
    final result = await XmppSession(
      transport: t,
      settings: account(jid: ''), // no localpart -> anonymous
    ).connect();
    expect(result.ok, isTrue);
    expect(result.mechanism, 'ANONYMOUS');
    expect(result.boundJid, 'anon@example.org/x1');
  });

  test('PLAIN binds and sends the NUL-delimited password', () async {
    final t = happyServer(
      mechanisms: ['PLAIN'],
      sasl: (_) => ['<success xmlns="$_sasl"/>'],
    );
    final result = await XmppSession(
      transport: t,
      settings: account(),
      password: 'pencil',
    ).connect();
    expect(result.ok, isTrue);
    expect(result.mechanism, 'PLAIN');
    expect(result.boundJid, 'user@example.org/ocideck-abc');
    final auth = t.sent.firstWhere((f) => f.contains('<auth'));
    expect(auth, contains('mechanism="PLAIN"'));
    expect(auth, contains(_b64('\u0000user\u0000pencil')));
  });

  group('SCRAM-SHA-1 end to end (RFC 5802 §5 vectors)', () {
    const serverFirst =
        'r=fyko+d2lbbFgONRv9qkxdawL3rfcNHYJY1ZVvWVs7j,'
        's=QSXCR+Q6sek8bf92,i=4096';
    const serverFinalOk = 'v=rmF9pqV8S7suAoZWja4dJRkFsKQ=';

    XmppSession scramSession(FakeXmppTransport t) => XmppSession(
      transport: t,
      settings: account(),
      password: 'pencil',
      nonceFactory: () => 'fyko+d2lbbFgONRv9qkxdawL',
    );

    test('succeeds, verifies the server signature, and binds', () async {
      final t = happyServer(
        mechanisms: ['SCRAM-SHA-1'],
        sasl: (frame) => frame.contains('<auth')
            ? ['<challenge xmlns="$_sasl">${_b64(serverFirst)}</challenge>']
            : ['<success xmlns="$_sasl">${_b64(serverFinalOk)}</success>'],
      );
      final result = await scramSession(t).connect();
      expect(result.ok, isTrue);
      expect(result.mechanism, 'SCRAM-SHA-1');
      expect(result.boundJid, 'user@example.org/ocideck-abc');
      final auth = t.sent.firstWhere((f) => f.contains('<auth'));
      expect(auth, contains(_b64('n,,n=user,r=fyko+d2lbbFgONRv9qkxdawL')));
    });

    test('refuses login when the server signature is wrong', () async {
      final t = happyServer(
        mechanisms: ['SCRAM-SHA-1'],
        sasl: (frame) => frame.contains('<auth')
            ? ['<challenge xmlns="$_sasl">${_b64(serverFirst)}</challenge>']
            : [
                '<success xmlns="$_sasl">'
                    '${_b64('v=AAAAAAAAAAAAAAAAAAAAAAAAAAA=')}</success>',
              ],
      );
      final result = await scramSession(t).connect();
      expect(result.ok, isFalse);
      expect(result.failure, XmppSessionFailure.mutualAuthFailed);
    });
  });

  test('prefers SCRAM over PLAIN when both are offered', () async {
    final t = FakeXmppTransport((frame) {
      if (frame.contains('<open')) {
        return [
          _openReply,
          _features(['PLAIN', 'SCRAM-SHA-1']),
        ];
      }
      if (frame.contains('<auth')) {
        return [
          '<challenge xmlns="$_sasl">'
              '${_b64('r=x3rfcNHYJY1ZVvWVs7j,s=QSXCR+Q6sek8bf92,i=4096')}'
              '</challenge>',
        ];
      }
      // The proof will not verify (nonce mismatch), but we only assert which
      // mechanism was chosen.
      if (frame.contains('<response')) {
        return ['<failure xmlns="$_sasl"><not-authorized/></failure>'];
      }
      return const [];
    });
    await XmppSession(
      transport: t,
      settings: account(),
      password: 'pencil',
      nonceFactory: () => 'x',
    ).connect();
    final auth = t.sent.firstWhere((f) => f.contains('<auth'));
    expect(auth, contains('mechanism="SCRAM-SHA-1"'));
  });

  test(
    'the default client nonce is fresh each run (no injected factory)',
    () async {
      final nonces = <String>{};
      for (var i = 0; i < 2; i++) {
        final t = FakeXmppTransport((frame) {
          if (frame.contains('<open')) {
            return [
              _openReply,
              _features(['SCRAM-SHA-1']),
            ];
          }
          if (frame.contains('<auth')) {
            return ['<failure xmlns="$_sasl"><not-authorized/></failure>'];
          }
          return const [];
        });
        await XmppSession(
          transport: t,
          settings: account(),
          password: 'pencil',
        ).connect();
        final auth = t.sent.firstWhere((f) => f.contains('<auth'));
        final payload = RegExp(r'>([^<]+)<').firstMatch(auth)!.group(1)!;
        final clientFirst = utf8.decode(base64.decode(payload));
        final nonce = RegExp(r'r=([^,]+)').firstMatch(clientFirst)!.group(1)!;
        expect(nonce.length, greaterThan(20));
        nonces.add(nonce);
      }
      expect(nonces.length, 2);
    },
  );

  test('reports a not-authorized failure as bad credentials', () async {
    final t = FakeXmppTransport((frame) {
      if (frame.contains('<open')) {
        return [
          _openReply,
          _features(['PLAIN']),
        ];
      }
      if (frame.contains('<auth')) {
        return ['<failure xmlns="$_sasl"><not-authorized/></failure>'];
      }
      return const [];
    });
    final result = await XmppSession(
      transport: t,
      settings: account(),
      password: 'wrong',
    ).connect();
    expect(result.ok, isFalse);
    expect(result.failure, XmppSessionFailure.badCredentials);
  });

  test('refuses a see-other-host stream redirect (fail closed)', () async {
    final t = FakeXmppTransport((frame) {
      if (frame.contains('<open')) {
        return [
          _openReply,
          '<stream:error xmlns:stream="http://etherx.jabber.org/streams">'
              '<see-other-host>10.0.0.1:5222</see-other-host></stream:error>',
        ];
      }
      return const [];
    });
    final result = await XmppSession(
      transport: t,
      settings: account(),
      password: 'p',
    ).connect();
    expect(result.ok, isFalse);
    expect(result.failure, XmppSessionFailure.serverRedirect);
  });

  test('fails when no usable mechanism is offered', () async {
    final t = FakeXmppTransport((frame) {
      if (frame.contains('<open')) {
        return [
          _openReply,
          _features(['DIGEST-MD5']),
        ];
      }
      return const [];
    });
    final result = await XmppSession(
      transport: t,
      settings: account(),
      password: 'p',
    ).connect();
    expect(result.ok, isFalse);
    expect(result.failure, XmppSessionFailure.noUsableMechanism);
  });

  test('reports resourceBindFailed when the server refuses the bind', () async {
    var authed = false;
    final t = FakeXmppTransport((frame) {
      if (frame.contains('<open')) {
        return authed
            ? [_openReply, _bindFeatures]
            : [
                _openReply,
                _features(['PLAIN']),
              ];
      }
      if (frame.contains('<auth')) {
        authed = true;
        return ['<success xmlns="$_sasl"/>'];
      }
      if (frame.contains('<iq') && frame.contains('bind')) {
        return [
          '<iq type="error" id="bind-1"><error type="cancel">'
              '<not-allowed/></error></iq>',
        ];
      }
      return const [];
    });
    final result = await XmppSession(
      transport: t,
      settings: account(),
      password: 'pencil',
    ).connect();
    expect(result.ok, isFalse);
    expect(result.failure, XmppSessionFailure.resourceBindFailed);
  });

  test('a live session dispatches inbound stanzas and sends stanzas', () async {
    final t = happyServer(
      mechanisms: ['PLAIN'],
      sasl: (_) => ['<success xmlns="$_sasl"/>'],
    );
    final session = XmppSession(
      transport: t,
      settings: account(),
      password: 'pencil',
    );
    final result = await session.connect();
    expect(result.ok, isTrue);

    // Inbound: a server-pushed message reaches the stanzas stream.
    final inbound = <Stanza>[];
    session.stanzas.listen(inbound.add);
    t.inject(
      '<message from="room@conf.example.org" type="groupchat">'
      '<body>hi</body></message>',
    );
    await Future<void>.delayed(Duration.zero);
    expect(inbound, hasLength(1));
    expect(inbound.single.kind, StanzaKind.message);
    expect(inbound.single.child('body')?.innerText, 'hi');

    // Outbound: sendStanza reaches the transport.
    session.sendStanza(
      Stanza(kind: StanzaKind.presence, to: 'room@conf.example.org'),
    );
    expect(t.sent.any((f) => f.contains('<presence')), isTrue);

    await session.close();
    expect(t.closed, isTrue);
  });

  test('a server stream drop ends the stanzas stream', () async {
    final t = happyServer(
      mechanisms: ['PLAIN'],
      sasl: (_) => ['<success xmlns="$_sasl"/>'],
    );
    final session = XmppSession(
      transport: t,
      settings: account(),
      password: 'pencil',
    );
    await session.connect();
    var done = false;
    session.stanzas.listen((_) {}, onDone: () => done = true);

    t.dropStream(); // the server hangs up
    await Future<void>.delayed(Duration.zero);

    // The MUC layer rides this signal to learn the room is gone.
    expect(done, isTrue);
    // A send on the dead session is a no-op, not a throw.
    session.sendStanza(Stanza(kind: StanzaKind.presence));
  });

  test(
    'a DTD-bearing inbound frame is dropped; the session stays live',
    () async {
      final t = happyServer(
        mechanisms: ['PLAIN'],
        sasl: (_) => ['<success xmlns="$_sasl"/>'],
      );
      final session = XmppSession(
        transport: t,
        settings: account(),
        password: 'pencil',
      );
      await session.connect();
      final inbound = <Stanza>[];
      session.stanzas.listen(inbound.add);

      // A DOCTYPE on the live path (XXE probe) must be dropped, not crash the
      // session — and a valid stanza right after it must still get through.
      t.inject(
        '<!DOCTYPE message [<!ENTITY x "boom">]>'
        '<message><body>&x;</body></message>',
      );
      t.inject('<message from="r@conf.example.org"><body>ok</body></message>');
      await Future<void>.delayed(Duration.zero);

      expect(inbound, hasLength(1));
      expect(inbound.single.child('body')?.innerText, 'ok');

      await session.close();
    },
  );
}
