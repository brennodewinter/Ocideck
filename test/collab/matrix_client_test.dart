// Tests for the thin CS-API client (`lib/collab/matrix_client.dart`,
// SELF_ENCRYPTED_RELAY.md phase P-B), driven entirely against an in-Dart fake
// homeserver — no server, no sockets (the client never opens one; egress is the
// injected transport's job). The fake implements just enough of the CS API to
// exercise the contracts that matter to the relay: login/UIA, `/sync` ordering
// and `since` resume, transaction-id idempotency, send/receive of timeline,
// state and to-device events, and the error mapping.

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/collab/matrix_client.dart';

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

// --- the fake homeserver ---------------------------------------------------

/// A minimal in-Dart Matrix homeserver. Routes on the CS-API path, holds a
/// monotonic event log so `/sync` can honour a `since` token, and de-duplicates
/// by transaction id. Test-only; lives here (not in `lib/`) so it never trips
/// the network-sink guard.
class FakeHomeserver implements MatrixHttpTransport {
  final Map<String, String> _passwords = {}; // username -> password
  final Map<String, String> _userIds = {}; // username -> user id
  final Map<String, String> _tokens = {}; // access token -> user id
  final List<_Item> _log = [];
  final Map<String, String> _txns = {}; // txnId -> event_id
  final Set<String> _rooms = {};
  int _seq = 0;
  int _uia = 0;

  // Inspection hooks + one-shot behaviours the tests drive.
  String? lastSendRoomId;
  String? lastSendType;
  Map<String, Map<String, Map<String, Object?>>>? lastToDevice;
  String? lastUiaSession;
  int? _rateLimitMs;
  bool _redirect = false;

  void addUser(String username, String password, {String? userId}) {
    _passwords[username] = password;
    _userIds[username] = userId ?? '@$username:hs.example';
  }

  void rateLimitNext({required int retryMs}) => _rateLimitMs = retryMs;
  void redirectNext() => _redirect = true;
  void revokeTokens() => _tokens.clear();

  void pushTimeline(
    String roomId, {
    required String type,
    required String sender,
    required Map<String, Object?> content,
  }) {
    _rooms.add(roomId);
    _log.add(
      _Item(++_seq, 'timeline', roomId, {
        'event_id': '\$e$_seq',
        'type': type,
        'sender': sender,
        'content': content,
      }),
    );
  }

  void pushState(
    String roomId, {
    required String type,
    required String stateKey,
    required String sender,
    required Map<String, Object?> content,
  }) {
    _rooms.add(roomId);
    _log.add(
      _Item(++_seq, 'state', roomId, {
        'event_id': '\$e$_seq',
        'type': type,
        'state_key': stateKey,
        'sender': sender,
        'content': content,
      }),
    );
  }

  void pushToDevice({
    required String type,
    required String sender,
    required Map<String, Object?> content,
  }) {
    _log.add(
      _Item(++_seq, 'todevice', null, {
        'type': type,
        'sender': sender,
        'content': content,
      }),
    );
  }

  @override
  Future<MatrixHttpResponse> send({
    required String method,
    required Uri url,
    Map<String, String> headers = const {},
    String? body,
  }) async {
    if (_redirect) {
      _redirect = false;
      return const MatrixHttpResponse(302, '');
    }
    if (_rateLimitMs != null) {
      final ms = _rateLimitMs!;
      _rateLimitMs = null;
      return _json(429, {
        'errcode': 'M_LIMIT_EXCEEDED',
        'error': 'slow down',
        'retry_after_ms': ms,
      });
    }
    final seg = url.pathSegments.sublist(
      url.pathSegments.indexOf('v3') + 1,
    ); // after /_matrix/client/v3
    final data = body == null ? const <String, Object?>{} : jsonDecode(body);
    final actor = _tokens[_bearer(headers)];
    return _route(method, seg, data as Map<String, Object?>, actor, url);
  }

  MatrixHttpResponse _route(
    String method,
    List<String> seg,
    Map<String, Object?> body,
    String? actor,
    Uri url,
  ) {
    switch (seg) {
      case ['login']:
        return _login(body);
      case ['register']:
        return _register(body);
      case ['logout']:
        return _json(200, const {});
    }
    // Everything below needs a valid token.
    if (actor == null) {
      return _json(401, {'errcode': 'M_UNKNOWN_TOKEN', 'error': 'bad token'});
    }
    switch (seg) {
      case ['account', 'whoami']:
        return _json(200, {'user_id': actor});
      case ['sync']:
        return _json(200, _sync(_parseSince(url.queryParameters['since'])));
      case ['createRoom']:
        final id = '!room${_rooms.length}:hs.example';
        _rooms.add(id);
        return _json(200, {'room_id': id});
      case ['rooms', final room, 'send', final type, final txn]:
        return _sendEvent(room, type, txn, body, actor);
      case ['rooms', final room, 'state', final type, final stateKey]:
        return _sendState(room, type, stateKey, body, actor);
      case ['sendToDevice', _, _]:
        lastToDevice = _asToDevice(body['messages']);
        return _json(200, const {});
      case ['rooms', final room, 'invite']:
        return _rooms.contains(room)
            ? _json(200, const {})
            : _json(404, {'errcode': 'M_NOT_FOUND', 'error': 'no room'});
      case ['join', final room]:
        if (!_rooms.contains(room)) {
          return _json(404, {'errcode': 'M_NOT_FOUND', 'error': 'no room'});
        }
        return _json(200, {'room_id': room});
    }
    return _json(404, {'errcode': 'M_UNRECOGNIZED', 'error': 'no route'});
  }

  int _parseSince(String? since) => (since != null && since.startsWith('s'))
      ? int.parse(since.substring(1))
      : 0;

  MatrixHttpResponse _login(Map<String, Object?> body) {
    final user = (body['identifier'] as Map?)?['user'] as String?;
    final pw = body['password'];
    if (user == null || _passwords[user] != pw) {
      return _json(403, {'errcode': 'M_FORBIDDEN', 'error': 'bad login'});
    }
    return _json(200, _issueToken(_userIds[user]!));
  }

  MatrixHttpResponse _register(Map<String, Object?> body) {
    final auth = body['auth'];
    if (auth == null) {
      lastUiaSession = 'uia${_uia++}';
      return _json(401, {
        'flows': [
          {
            'stages': ['m.login.dummy'],
          },
        ],
        'session': lastUiaSession,
        'params': const {},
      });
    }
    final username = body['username'] as String? ?? 'user';
    return _json(200, _issueToken('@$username:hs.example'));
  }

  Map<String, Object?> _issueToken(String userId) {
    final token = 'tok${_tokens.length}';
    _tokens[token] = userId;
    return {
      'user_id': userId,
      'device_id': 'DEV${_tokens.length}',
      'access_token': token,
    };
  }

  MatrixHttpResponse _sendEvent(
    String room,
    String type,
    String txn,
    Map<String, Object?> content,
    String actor,
  ) {
    lastSendRoomId = room;
    lastSendType = type;
    final existing = _txns[txn];
    if (existing != null) return _json(200, {'event_id': existing});
    _rooms.add(room);
    final id = '\$evt${++_seq}';
    _txns[txn] = id;
    _log.add(
      _Item(_seq, 'timeline', room, {
        'event_id': id,
        'type': type,
        'sender': actor,
        'content': content,
      }),
    );
    return _json(200, {'event_id': id});
  }

  MatrixHttpResponse _sendState(
    String room,
    String type,
    String stateKey,
    Map<String, Object?> content,
    String actor,
  ) {
    _rooms.add(room);
    final id = '\$evt${++_seq}';
    _log.add(
      _Item(_seq, 'state', room, {
        'event_id': id,
        'type': type,
        'state_key': stateKey,
        'sender': actor,
        'content': content,
      }),
    );
    return _json(200, {'event_id': id});
  }

  Map<String, Object?> _sync(int since) {
    final join = <String, Object?>{};
    final toDevice = <Map<String, Object?>>[];
    for (final item in _log.where((i) => i.seq > since)) {
      if (item.bucket == 'todevice') {
        toDevice.add(item.event);
        continue;
      }
      final room =
          join.putIfAbsent(
                item.roomId!,
                () => <String, Object?>{
                  'timeline': {'events': <Object?>[]},
                  'state': {'events': <Object?>[]},
                },
              )
              as Map<String, Object?>;
      ((room[item.bucket] as Map)['events'] as List).add(item.event);
    }
    return {
      'next_batch': 's$_seq',
      'rooms': {'join': join},
      'to_device': {'events': toDevice},
    };
  }

  String? _bearer(Map<String, String> headers) {
    final h = headers['Authorization'];
    return (h != null && h.startsWith('Bearer ')) ? h.substring(7) : null;
  }

  Map<String, Map<String, Map<String, Object?>>> _asToDevice(Object? raw) {
    final out = <String, Map<String, Map<String, Object?>>>{};
    (raw as Map).forEach((user, devs) {
      out['$user'] = {
        for (final e in (devs as Map).entries)
          '${e.key}': (e.value as Map).cast<String, Object?>(),
      };
    });
    return out;
  }

  MatrixHttpResponse _json(int status, Map<String, Object?> body) =>
      MatrixHttpResponse(status, jsonEncode(body));
}

class _Item {
  _Item(this.seq, this.bucket, this.roomId, this.event);
  final int seq;
  final String bucket; // 'timeline' | 'state' | 'todevice'
  final String? roomId;
  final Map<String, Object?> event;
}
