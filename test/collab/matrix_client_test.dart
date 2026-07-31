// Tests for the thin CS-API client (`lib/collab/matrix_client.dart`,
// SELF_ENCRYPTED_RELAY.md phase P-B), driven entirely against an in-Dart fake
// homeserver — no server, no sockets (the client never opens one; egress is the
// injected transport's job). The fake implements just enough of the CS API to
// exercise the contracts that matter to the relay: login/UIA, `/sync` ordering
// and `since` resume, transaction-id idempotency, send/receive of timeline,
// state and to-device events, and the error mapping.

import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/collab/matrix_client.dart';

import 'fake_homeserver.dart';

void main() {
  late FakeHomeserver hs;
  late MatrixClient client;

  setUp(() {
    hs = FakeHomeserver();
    client = MatrixClient(
      transport: hs,
      homeserver: Uri.parse('https://hs.example'),
    );
  });

  group('construction', () {
    test('a plaintext non-loopback homeserver is refused', () {
      expect(
        () => MatrixClient(
          transport: hs,
          homeserver: Uri.parse('http://hs.example'),
        ),
        throwsA(
          isA<MatrixException>().having(
            (e) => e.kind,
            'kind',
            MatrixErrorKind.config,
          ),
        ),
      );
    });

    test('a loopback http homeserver is allowed for development', () {
      expect(
        MatrixClient(
          transport: hs,
          homeserver: Uri.parse('http://localhost:8008'),
        ).accessToken,
        isNull,
      );
    });
  });

  group('authentication', () {
    test('login returns and stores a session', () async {
      hs.addUser('alice', 'pw', userId: '@alice:hs.example');
      final session = await client.login(user: 'alice', password: 'pw');
      expect(session.userId, '@alice:hs.example');
      expect(session.accessToken, isNotEmpty);
      expect(client.accessToken, session.accessToken);
      expect(await client.whoami(), '@alice:hs.example');
    });

    test('a wrong password maps to a forbidden error', () async {
      hs.addUser('alice', 'pw');
      await expectLater(
        () => client.login(user: 'alice', password: 'nope'),
        throwsA(
          isA<MatrixException>()
              .having((e) => e.kind, 'kind', MatrixErrorKind.forbidden)
              .having((e) => e.errcode, 'errcode', 'M_FORBIDDEN'),
        ),
      );
    });

    test('register surfaces UIA, then completes with a stage', () async {
      await expectLater(
        () => client.register(username: 'bob', password: 'pw'),
        throwsA(
          isA<MatrixUiaRequired>().having((e) => e.flows.first, 'first flow', [
            'm.login.dummy',
          ]),
        ),
      );
      final session = await client.register(
        username: 'bob',
        password: 'pw',
        auth: {'type': 'm.login.dummy', 'session': hs.lastUiaSession},
      );
      expect(session.userId, '@bob:hs.example');
      expect(client.accessToken, session.accessToken);
    });

    test('a call needing auth without a token fails fast', () async {
      await expectLater(
        () => client.whoami(),
        throwsA(
          isA<MatrixException>().having(
            (e) => e.kind,
            'kind',
            MatrixErrorKind.auth,
          ),
        ),
      );
    });

    test('logout clears the token', () async {
      hs.addUser('a', 'p');
      await client.login(user: 'a', password: 'p');
      await client.logout();
      expect(client.accessToken, isNull);
    });
  });

  group('sync — ordering and resume', () {
    setUp(() async {
      hs.addUser('a', 'p', userId: '@a:hs.example');
      await client.login(user: 'a', password: 'p');
    });

    test(
      'delivers events in order and resumes above the since token',
      () async {
        hs.pushTimeline(
          '!r:hs.example',
          type: 'nl.ocideck.op',
          sender: '@x:hs',
          content: {'n': 1},
        );
        hs.pushTimeline(
          '!r:hs.example',
          type: 'nl.ocideck.op',
          sender: '@x:hs',
          content: {'n': 2},
        );

        final first = await client.sync();
        expect(first.timeline.map((e) => e.content['n']), [1, 2]);
        expect(first.timeline.first.roomId, '!r:hs.example');
        expect(first.timeline.first.type, 'nl.ocideck.op');

        // Nothing new → empty, same-or-advanced token.
        final second = await client.sync(since: first.nextBatch);
        expect(second.timeline, isEmpty);

        // A new event → only that one, from the resumed token.
        hs.pushTimeline(
          '!r:hs.example',
          type: 'nl.ocideck.op',
          sender: '@x:hs',
          content: {'n': 3},
        );
        final third = await client.sync(since: second.nextBatch);
        expect(third.timeline.map((e) => e.content['n']), [3]);
      },
    );

    test('surfaces state events with their state key', () async {
      hs.pushState(
        '!r:hs.example',
        type: 'nl.ocideck.device',
        stateKey: '@a:hs.example:DEV',
        sender: '@a:hs',
        content: {'ik': 'k'},
      );
      final r = await client.sync();
      final ev = r.timeline.singleWhere((e) => e.type == 'nl.ocideck.device');
      expect(ev.stateKey, '@a:hs.example:DEV');
    });

    test('surfaces to-device events', () async {
      hs.pushToDevice(
        type: 'nl.ocideck.keyshare',
        sender: '@auth:hs',
        content: {'epoch': 0},
      );
      final r = await client.sync();
      expect(r.toDevice.single.type, 'nl.ocideck.keyshare');
      expect(r.toDevice.single.content['epoch'], 0);
    });
  });

  group('sending', () {
    setUp(() async {
      hs.addUser('a', 'p', userId: '@a:hs.example');
      await client.login(user: 'a', password: 'p');
    });

    test('a sent event round-trips through sync', () async {
      final id = await client.sendEvent(
        roomId: '!r:hs.example',
        type: 'nl.ocideck.op',
        content: {'kind': 'op'},
      );
      expect(id, isNotEmpty);
      final r = await client.sync();
      expect(r.timeline.single.eventId, id);
      expect(r.timeline.single.content, {'kind': 'op'});
    });

    test('the same transaction id is idempotent (no duplicate)', () async {
      final id1 = await client.sendEvent(
        roomId: '!r:hs.example',
        type: 'nl.ocideck.op',
        content: {'k': 1},
        txnId: 'fixed',
      );
      final id2 = await client.sendEvent(
        roomId: '!r:hs.example',
        type: 'nl.ocideck.op',
        content: {'k': 1},
        txnId: 'fixed',
      );
      expect(id2, id1);
      final r = await client.sync();
      expect(r.timeline.length, 1);
    });

    test('percent-encodes room ids and event types in the path', () async {
      await client.sendEvent(
        roomId: '!weird/room:hs.example',
        type: 'nl.ocideck.op',
        content: const {},
      );
      // The fake decoded the segments back to the originals — proving the client
      // encoded `!`, `/` and `:` rather than splitting the path on them.
      expect(hs.lastSendRoomId, '!weird/room:hs.example');
      expect(hs.lastSendType, 'nl.ocideck.op');
    });

    test('a state event and a to-device message are sent', () async {
      await client.sendStateEvent(
        roomId: '!r:hs.example',
        type: 'nl.ocideck.authority',
        stateKey: '',
        content: {'authority': '@a:hs'},
      );
      await client.sendToDevice(
        type: 'nl.ocideck.keyshare',
        messages: {
          '@b:hs.example': {
            'DEV': {'epoch': 0},
          },
        },
      );
      expect(hs.lastToDevice?['@b:hs.example']?['DEV']?['epoch'], 0);
      final r = await client.sync();
      expect(
        r.timeline.any(
          (e) => e.type == 'nl.ocideck.authority' && e.stateKey == '',
        ),
        isTrue,
      );
    });

    test('create, invite and join return/accept room ids', () async {
      final room = await client.createRoom(extra: {'preset': 'private_chat'});
      expect(room, startsWith('!'));
      await client.invite(roomId: room, userId: '@b:hs.example');
      expect(await client.join(room), room);
    });
  });

  group('error mapping', () {
    setUp(() async {
      hs.addUser('a', 'p');
      await client.login(user: 'a', password: 'p');
    });

    test('an unknown room join is a notFound', () async {
      await expectLater(
        () => client.join('!ghost:hs.example'),
        throwsA(
          isA<MatrixException>().having(
            (e) => e.kind,
            'kind',
            MatrixErrorKind.notFound,
          ),
        ),
      );
    });

    test('a rate limit carries retry-after', () async {
      hs.rateLimitNext(retryMs: 1500);
      await expectLater(
        () => client.sync(),
        throwsA(
          isA<MatrixException>()
              .having((e) => e.kind, 'kind', MatrixErrorKind.rateLimited)
              .having(
                (e) => e.retryAfter,
                'retryAfter',
                const Duration(milliseconds: 1500),
              ),
        ),
      );
    });

    test('a 3xx is refused, never followed', () async {
      hs.redirectNext();
      await expectLater(
        () => client.sync(),
        throwsA(
          isA<MatrixException>().having(
            (e) => e.kind,
            'kind',
            MatrixErrorKind.redirect,
          ),
        ),
      );
    });

    test('a stale/invalid token is an auth error', () async {
      hs.revokeTokens();
      await expectLater(
        () => client.whoami(),
        throwsA(
          isA<MatrixException>()
              .having((e) => e.kind, 'kind', MatrixErrorKind.auth)
              .having((e) => e.errcode, 'errcode', 'M_UNKNOWN_TOKEN'),
        ),
      );
    });
  });
}
