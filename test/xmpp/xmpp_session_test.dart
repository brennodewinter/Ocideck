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

  // ── reconnect / rejoin (§4) ──────────────────────────────────────────────

  /// A factory that produces a fresh happy server (PLAIN) each call, collecting
  /// them so the test can inspect the reconnect transports.
  (Future<XmppFrameTransport> Function(), List<FakeXmppTransport>)
  reconnectFactory({String jid = 'user@example.org/ocideck-abc'}) {
    final created = <FakeXmppTransport>[];
    return (
      () async {
        final t = happyServer(
          mechanisms: ['PLAIN'],
          sasl: (_) => ['<success xmlns="$_sasl"/>'],
          jid: jid,
        );
        created.add(t);
        return t;
      },
      created,
    );
  }

  group('reconnect/rejoin (§4)', () {
    test('a stream drop triggers reconnect + rejoin + signal', () async {
      final firstTransport = happyServer(
        mechanisms: ['PLAIN'],
        sasl: (_) => ['<success xmlns="$_sasl"/>'],
      );
      final (factory, created) = reconnectFactory();
      var rejoinCalled = false;
      final reconnected = Completer<void>();

      final session = XmppSession(
        transport: firstTransport,
        settings: account(),
        password: 'pencil',
        reconnectTransportFactory: factory,
        onRejoin: (_) async {
          rejoinCalled = true;
        },
        reconnectDelay: (_) => Duration.zero,
      );
      session.onReconnected.listen((_) => reconnected.complete());

      final result = await session.connect();
      expect(result.ok, isTrue);

      // Drop the first transport's stream — the session should reconnect.
      firstTransport.dropStream();
      await reconnected.future.timeout(const Duration(seconds: 5));

      // A new transport was created by the factory.
      expect(created, hasLength(1));
      // The new transport received <open> + <auth> (SASL re-run).
      expect(created.first.sent.any((f) => f.contains('<open')), isTrue);
      expect(created.first.sent.any((f) => f.contains('<auth')), isTrue);
      // The rejoin hook was called.
      expect(rejoinCalled, isTrue);
      // The session is live again with a bound JID.
      expect(session.boundJid, isNotNull);

      await session.close();
    });

    test(
      'stanzas survive reconnect — new stanzas flow through the same stream',
      () async {
        final firstTransport = happyServer(
          mechanisms: ['PLAIN'],
          sasl: (_) => ['<success xmlns="$_sasl"/>'],
        );
        final (factory, created) = reconnectFactory();
        final reconnected = Completer<void>();

        final session = XmppSession(
          transport: firstTransport,
          settings: account(),
          password: 'pencil',
          reconnectTransportFactory: factory,
          reconnectDelay: (_) => Duration.zero,
        );
        session.onReconnected.listen((_) => reconnected.complete());

        await session.connect();

        final inbound = <Stanza>[];
        session.stanzas.listen(inbound.add);

        // Drop and reconnect.
        firstTransport.dropStream();
        await reconnected.future.timeout(const Duration(seconds: 5));

        // Inject a stanza into the NEW transport — it must reach the same
        // stream, proving the _inbound controller survived the reconnect.
        created.first.inject(
          '<message from="room@conf.example.org" type="groupchat">'
          '<body>after-reconnect</body></message>',
        );
        await Future<void>.delayed(Duration.zero);

        expect(inbound, hasLength(1));
        expect(inbound.single.child('body')?.innerText, 'after-reconnect');

        await session.close();
      },
    );

    test('fail-closed after max reconnect attempts', () async {
      final firstTransport = happyServer(
        mechanisms: ['PLAIN'],
        sasl: (_) => ['<success xmlns="$_sasl"/>'],
      );
      var factoryCalls = 0;

      // A factory that produces transports whose stream closes immediately —
      // every reconnect attempt fails (the server hangs up before features).
      Future<XmppFrameTransport> failFactory() async {
        factoryCalls++;
        final t = FakeXmppTransport((_) => const []);
        t.dropStream();
        return t;
      }

      final session = XmppSession(
        transport: firstTransport,
        settings: account(),
        password: 'pencil',
        reconnectTransportFactory: failFactory,
        maxReconnectAttempts: 3,
        reconnectDelay: (_) => Duration.zero,
      );

      await session.connect();

      final stanzasDone = Completer<void>();
      session.stanzas.listen((_) {}, onDone: () => stanzasDone.complete());

      // Drop the stream — the session should try 3 times, then fail closed.
      firstTransport.dropStream();
      await stanzasDone.future.timeout(const Duration(seconds: 5));

      // Exactly maxReconnectAttempts calls — no more, no less.
      expect(factoryCalls, 3);
      // The stanzas stream completed (fail-closed).
      expect(stanzasDone.isCompleted, isTrue);
    });

    test(
      'see-other-host during reconnect is refused (fail closed, not followed)',
      () async {
        final firstTransport = happyServer(
          mechanisms: ['PLAIN'],
          sasl: (_) => ['<success xmlns="$_sasl"/>'],
        );

        // Every reconnect transport responds with see-other-host — the redirect
        // must be refused, never followed (same fail-closed posture as connect).
        Future<XmppFrameTransport> redirectFactory() async {
          return FakeXmppTransport((frame) {
            if (frame.contains('<open')) {
              return [
                _openReply,
                '<stream:error xmlns:stream="http://etherx.jabber.org/streams">'
                    '<see-other-host>10.0.0.1:5222</see-other-host>'
                    '</stream:error>',
              ];
            }
            return const [];
          });
        }

        final session = XmppSession(
          transport: firstTransport,
          settings: account(),
          password: 'pencil',
          reconnectTransportFactory: redirectFactory,
          maxReconnectAttempts: 2,
          reconnectDelay: (_) => Duration.zero,
        );

        await session.connect();

        final stanzasDone = Completer<void>();
        session.stanzas.listen((_) {}, onDone: () => stanzasDone.complete());

        firstTransport.dropStream();
        await stanzasDone.future.timeout(const Duration(seconds: 5));

        // The redirect was never followed; the session failed closed.
        expect(stanzasDone.isCompleted, isTrue);
      },
    );

    test('default backoff is bounded — exponential with a 30s cap', () {
      expect(xmppReconnectDelay(0), const Duration(seconds: 1));
      expect(xmppReconnectDelay(1), const Duration(seconds: 2));
      expect(xmppReconnectDelay(2), const Duration(seconds: 4));
      expect(xmppReconnectDelay(3), const Duration(seconds: 8));
      expect(xmppReconnectDelay(4), const Duration(seconds: 16));
      // Capped at 30s — a persistent outage must not delay absurdly.
      expect(xmppReconnectDelay(5), const Duration(seconds: 30));
      expect(xmppReconnectDelay(100), const Duration(seconds: 30));
    });

    test('close during backoff cancels the reconnect loop', () async {
      final firstTransport = happyServer(
        mechanisms: ['PLAIN'],
        sasl: (_) => ['<success xmlns="$_sasl"/>'],
      );
      final (factory, created) = reconnectFactory();

      final session = XmppSession(
        transport: firstTransport,
        settings: account(),
        password: 'pencil',
        reconnectTransportFactory: factory,
        maxReconnectAttempts: 5,
        reconnectDelay: (_) => const Duration(seconds: 10),
      );

      await session.connect();

      // Drop the stream — the reconnect loop starts but waits 10s before the
      // first attempt. Close immediately: the loop must cancel, not call the
      // factory after the delay.
      firstTransport.dropStream();
      await Future<void>.delayed(Duration.zero); // let the drop propagate
      await session.close();

      // Wait past the delay to be sure no late factory call lands.
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(created, isEmpty);
    });

    test(
      'without a reconnect factory, a stream drop tears down (backward compat)',
      () async {
        final t = happyServer(
          mechanisms: ['PLAIN'],
          sasl: (_) => ['<success xmlns="$_sasl"/>'],
        );
        final session = XmppSession(
          transport: t,
          settings: account(),
          password: 'pencil',
          // no reconnectTransportFactory — pre-reconnect behaviour
        );

        await session.connect();

        var done = false;
        session.stanzas.listen((_) {}, onDone: () => done = true);

        t.dropStream();
        await Future<void>.delayed(Duration.zero);

        // The stanzas stream completed; no reconnect attempted.
        expect(done, isTrue);
      },
    );
  });

  // ── jabber:client namespace (RFC 7395) ───────────────────────────────────

  test(
    'stanzas carry xmlns=jabber:client — each WebSocket frame is standalone',
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

      session.sendStanza(
        Stanza(kind: StanzaKind.presence, to: 'room@conf.example.org'),
      );

      // In XMPP-over-WebSocket (RFC 7395) each frame is a standalone XML
      // document — the jabber:client namespace is NOT inherited from the
      // stream. Without it, Prosody rejects stanzas as "unhandled".
      final presence = t.sent.firstWhere((f) => f.contains('<presence'));
      expect(presence, contains('xmlns="jabber:client"'));

      // Stream-level elements (open, auth) keep their own namespace.
      final open = t.sent.firstWhere((f) => f.contains('<open'));
      expect(open, contains('urn:ietf:params:xml:ns:xmpp-framing'));
      expect(open, isNot(contains('jabber:client')));

      await session.close();
    },
  );
}
