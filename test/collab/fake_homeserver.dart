// A shared in-Dart fake Matrix homeserver for the collaboration tests
// (`matrix_client_test.dart`, `matrix_relay_transport_test.dart`). It implements
// just enough of the CS API — login/register, `/sync` with a `since` token,
// send timeline/state/to-device, room create/invite/join, logout — to drive the
// client and the relay transport with no server and no sockets. Test-only; lives
// under `test/` (never `lib/`) so it never trips the network-sink guard.

import 'dart:convert';

import 'package:ocideck/collab/matrix_client.dart';

/// A minimal in-Dart Matrix homeserver. Routes on the CS-API path, holds a
/// monotonic event log so `/sync` can honour a `since` token, and de-duplicates
/// by transaction id. Test-only; lives here (not in `lib/`) so it never trips
/// the network-sink guard.
class FakeHomeserver implements MatrixHttpTransport {
  final Map<String, String> _passwords = {}; // username -> password
  final Map<String, String> _userIds = {}; // username -> user id
  final Map<String, String> _tokens = {}; // access token -> user id
  final Map<String, String> _tokenDevices = {}; // access token -> device id
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
  void revokeTokens() {
    _tokens.clear();
    _tokenDevices.clear();
  }

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
    final bearer = _bearer(headers);
    final actor = _tokens[bearer];
    return _route(
      method,
      seg,
      data as Map<String, Object?>,
      actor,
      _tokenDevices[bearer],
      url,
    );
  }

  MatrixHttpResponse _route(
    String method,
    List<String> seg,
    Map<String, Object?> body,
    String? actor,
    String? actorDevice,
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
        return _json(200, {'user_id': actor, 'device_id': ?actorDevice});
      case ['sync']:
        return _json(
          200,
          _sync(_parseSince(url.queryParameters['since']), actor),
        );
      case ['createRoom']:
        final id = '!room${_rooms.length}:hs.example';
        _rooms.add(id);
        return _json(200, {'room_id': id});
      case ['rooms', final room, 'send', final type, final txn]:
        return _sendEvent(room, type, txn, body, actor);
      case ['rooms', final room, 'state', final type, final stateKey]:
        return _sendState(room, type, stateKey, body, actor);
      case ['sendToDevice', final type, _]:
        return _sendToDevice(type, body, actor);
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
    final device = 'DEV${_tokens.length}';
    _tokens[token] = userId;
    _tokenDevices[token] = device;
    return {'user_id': userId, 'device_id': device, 'access_token': token};
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
    // Transaction ids are unique *per access token* in Matrix, so two different
    // clients may legitimately both use 'ocideck-0'. Key the dedup by actor so a
    // second client's send is not mistaken for the first's retry.
    final txnKey = '$actor|$txn';
    final existing = _txns[txnKey];
    if (existing != null) return _json(200, {'event_id': existing});
    _rooms.add(room);
    final id = '\$evt${++_seq}';
    _txns[txnKey] = id;
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

  MatrixHttpResponse _sendToDevice(
    String type,
    Map<String, Object?> body,
    String actor,
  ) {
    final messages = _asToDevice(body['messages']);
    lastToDevice = messages;
    messages.forEach((user, devices) {
      devices.forEach((device, content) {
        _log.add(
          _Item(++_seq, 'todevice', null, {
            'type': type,
            'sender': actor,
            'content': content,
          }, recipient: user),
        );
      });
    });
    return _json(200, const {});
  }

  Map<String, Object?> _sync(int since, String actor) {
    final join = <String, Object?>{};
    final toDevice = <Map<String, Object?>>[];
    for (final item in _log.where((i) => i.seq > since)) {
      if (item.bucket == 'todevice') {
        if (item.recipient == null || item.recipient == actor) {
          toDevice.add(item.event);
        }
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
  _Item(this.seq, this.bucket, this.roomId, this.event, {this.recipient});
  final int seq;
  final String bucket; // 'timeline' | 'state' | 'todevice'
  final String? roomId;
  final Map<String, Object?> event;

  /// For a to-device item: the user id it is addressed to (`null` = broadcast to
  /// every syncing user, which the `pushToDevice` test helper uses). Ignored for
  /// timeline/state items.
  final String? recipient;
}
