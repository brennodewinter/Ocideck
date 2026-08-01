// A thin, pure-Dart Matrix client-server (CS) API client
// (`docs/design/SELF_ENCRYPTED_RELAY.md` §7.1, phase P-B). It speaks the parts of
// the CS API the self-encrypted relay needs — login/register, `/sync`, send
// timeline/state/to-device events, room create/invite/join, logout — as plain
// HTTP + JSON. It knows nothing about ops, crypto or authority: it is the
// carriage the `MatrixRelayTransport` (P-C) rides on, exactly as `MatrixClient`
// in the design.
//
// **Egress is injected, not opened here** (a refinement of the design's "one
// place that touches the network"). `MatrixClient` talks to a
// [MatrixHttpTransport], so the actual socket lives in a platform-specific
// transport — a NetGuard-pinned `dart:io` one on the desktop targets and a
// browser one on web (built at the wiring seam, P-D), mirroring the AI backend's
// `AiHttpTransport`. That keeps this file free of any network primitive (so it
// stays off `network_sink_guard_test.dart`) and fully unit-testable against an
// in-Dart fake homeserver with no server and no sockets. Being pure Dart, it runs
// identically under `flutter test`, on the desktop targets and on web.
//
// The client refuses to send its bearer token over plaintext to a non-loopback
// host (the `maySendReusableSecret` posture, done lexically here so it needs no
// `dart:io`), and the production transport additionally pins the socket and
// refuses redirects (§11). Response-size caps live in the transport.

import 'dart:convert';

/// A raw HTTP response: the status and the body text, before any JSON parsing.
/// The transport returns this; [MatrixClient] does all decoding and error
/// mapping, so the transport stays a dumb pipe.
class MatrixHttpResponse {
  const MatrixHttpResponse(this.status, this.body);

  final int status;
  final String body;
}

/// The egress seam. A production implementation opens the socket (pinned +
/// no-redirect on native, browser on web); the tests supply a fake homeserver.
abstract interface class MatrixHttpTransport {
  Future<MatrixHttpResponse> send({
    required String method,
    required Uri url,
    Map<String, String> headers,
    String? body,
  });
}

/// The machine-readable class of a Matrix failure. [errcode] carries the raw
/// Matrix `M_*` string when the server sent one.
enum MatrixErrorKind {
  /// Bad or missing credentials / access token (HTTP 401, or `M_UNKNOWN_TOKEN`).
  auth,

  /// The server refused the action (HTTP 403, `M_FORBIDDEN`).
  forbidden,

  /// The target does not exist (HTTP 404, `M_NOT_FOUND`).
  notFound,

  /// Rate limited (HTTP 429, `M_LIMIT_EXCEEDED`); see [MatrixException.retryAfter].
  rateLimited,

  /// A 3xx the client refused to follow — a redirect must not bypass the host
  /// check (§11). Surfaced as an error, never followed.
  redirect,

  /// A malformed URL, plaintext token target, or other local misuse.
  config,

  /// The server returned 5xx or an unparseable body.
  server,

  /// A transport-level failure before any HTTP status: TLS refusal, an
  /// unreachable or blocked host, a dropped connection. Produced by the
  /// production transport, not by the HTTP-status mapping.
  network,
}

/// A typed Matrix failure. [errcode] is the server's `M_*` code when present.
class MatrixException implements Exception {
  const MatrixException(
    this.kind,
    this.message, {
    this.errcode,
    this.retryAfter,
  });

  final MatrixErrorKind kind;
  final String message;
  final String? errcode;
  final Duration? retryAfter;

  @override
  String toString() =>
      'MatrixException($kind${errcode == null ? '' : ', $errcode'}): $message';
}

/// Thrown by [MatrixClient.register] when the homeserver requires User-
/// Interactive Auth: the caller drives the [flows] (recaptcha/terms/email/…),
/// carrying [session] back on each stage. Not an error — the expected multi-step
/// registration handshake (§8), surfaced typed so the onboarding UI (P-D) can
/// render it.
class MatrixUiaRequired implements Exception {
  const MatrixUiaRequired({
    required this.flows,
    required this.session,
    required this.params,
  });

  /// Each flow is an ordered list of stage type strings (e.g. `m.login.dummy`).
  final List<List<String>> flows;
  final String? session;
  final Map<String, Object?> params;

  @override
  String toString() => 'MatrixUiaRequired(flows: $flows)';
}

/// A logged-in session: what onboarding persists (token + device to the keychain,
/// the rest to preferences), per §8.
class MatrixSession {
  const MatrixSession({
    required this.userId,
    required this.deviceId,
    required this.accessToken,
  });

  final String userId;
  final String deviceId;
  final String accessToken;
}

/// The answer to `/account/whoami`: who an access token belongs to, and — when
/// the homeserver reports it — which device it is bound to. The device id matters
/// beyond display: the collaboration key-share is a to-device message addressed
/// to `userId:deviceId`, so the account must carry the *token's own* device id or
/// a co-author's key never arrives (SELF_ENCRYPTED_RELAY.md §4.3). This is why
/// the account form fills it from here rather than asking the user to guess it.
class MatrixWhoami {
  const MatrixWhoami({required this.userId, this.deviceId});

  final String userId;

  /// The token's device id, or null when the homeserver omits it (the field is
  /// optional in the CS spec).
  final String? deviceId;
}

/// One timeline event delivered by `/sync`, reduced to what the relay reads.
class MatrixTimelineEvent {
  const MatrixTimelineEvent({
    required this.roomId,
    required this.eventId,
    required this.type,
    required this.sender,
    required this.content,
    this.stateKey,
  });

  final String roomId;
  final String eventId;
  final String type;
  final String sender;
  final Map<String, Object?> content;

  /// Non-null for a state event (its state key), null for a timeline message.
  final String? stateKey;
}

/// One to-device message delivered by `/sync` (the key-share carrier, §4.3).
class MatrixToDeviceEvent {
  const MatrixToDeviceEvent({
    required this.type,
    required this.sender,
    required this.content,
  });

  final String type;
  final String sender;
  final Map<String, Object?> content;
}

/// The reduced result of one `/sync`: the next batch token and the new events.
class MatrixSyncResult {
  const MatrixSyncResult({
    required this.nextBatch,
    required this.timeline,
    required this.toDevice,
  });

  final String nextBatch;
  final List<MatrixTimelineEvent> timeline;
  final List<MatrixToDeviceEvent> toDevice;
}

/// The thin CS-API client. Construct with a [transport] and the [homeserver]
/// base URL; set [accessToken] after login (or pass it in to resume a session).
class MatrixClient {
  MatrixClient({
    required MatrixHttpTransport transport,
    required Uri homeserver,
    String? accessToken,
  }) : _http = transport,
       _homeserver = homeserver,
       _token = accessToken {
    if (!_maySendSecretTo(homeserver)) {
      throw const MatrixException(
        MatrixErrorKind.config,
        'homeserver must be https (or a loopback host for development)',
      );
    }
  }

  final MatrixHttpTransport _http;
  final Uri _homeserver;
  String? _token;

  /// A per-client monotonic transaction counter. Matrix requires transaction ids
  /// unique per access token; a counter is sufficient and deterministic, which is
  /// also what lets a test assert idempotent retries.
  int _txn = 0;

  String? get accessToken => _token;

  // --- authentication ------------------------------------------------------

  /// Log in with a password. Stores and returns the resulting session.
  Future<MatrixSession> login({
    required String user,
    required String password,
    String? deviceId,
  }) async {
    final json = await _request(
      'POST',
      _url(const ['login']),
      body: {
        'type': 'm.login.password',
        'identifier': {'type': 'm.id.user', 'user': user},
        'password': password,
        'device_id': ?deviceId,
      },
      requireAuth: false,
    );
    return _sessionFrom(json);
  }

  /// Register a new account. On success returns the session; when the homeserver
  /// demands User-Interactive Auth it throws [MatrixUiaRequired] carrying the
  /// flows for the onboarding UI to drive (pass the chosen stage back in [auth]).
  Future<MatrixSession> register({
    required String username,
    required String password,
    Map<String, Object?>? auth,
  }) async {
    final resp = await _send(
      'POST',
      _url(const ['register']),
      body: {'username': username, 'password': password, 'auth': ?auth},
      requireAuth: false,
    );
    final json = _bodyObject(resp);
    if (resp.status == 401 && json.containsKey('flows')) {
      throw MatrixUiaRequired(
        flows: _uiaFlows(json['flows']),
        session: json['session'] as String?,
        params: _asObject(json['params']) ?? const {},
      );
    }
    return _sessionFrom(_ok(resp, json));
  }

  /// Confirm who the current access token belongs to (`/account/whoami`) and,
  /// when the homeserver reports it, which device it is bound to.
  Future<MatrixWhoami> whoami() async {
    final json = await _request('GET', _url(const ['account', 'whoami']));
    final device = json['device_id'];
    return MatrixWhoami(
      userId: _string(json, 'user_id'),
      deviceId: device is String && device.isNotEmpty ? device : null,
    );
  }

  /// Invalidate the current access token server-side.
  Future<void> logout() async {
    await _request('POST', _url(const ['logout']));
    _token = null;
  }

  // --- sync ----------------------------------------------------------------

  /// One `/sync` round. Pass the previous [since] token to fetch only what is
  /// new (null for the first, initial sync). [timeout] is the long-poll wait the
  /// server holds the request open for when there is nothing new yet.
  Future<MatrixSyncResult> sync({
    String? since,
    Duration timeout = const Duration(seconds: 30),
  }) async {
    final json = await _request(
      'GET',
      _url(
        const ['sync'],
        {'since': ?since, 'timeout': '${timeout.inMilliseconds}'},
      ),
    );
    return _parseSync(json);
  }

  // --- sending -------------------------------------------------------------

  /// Send a timeline event; returns its event id. The transaction id is
  /// generated here and reused on a retry, so the server de-duplicates.
  Future<String> sendEvent({
    required String roomId,
    required String type,
    required Map<String, Object?> content,
    String? txnId,
  }) async {
    final id = txnId ?? _nextTxn();
    final json = await _request(
      'PUT',
      _url(['rooms', roomId, 'send', type, id]),
      body: content,
    );
    return _string(json, 'event_id');
  }

  /// Send (or replace) a state event keyed by [stateKey]; returns its event id.
  Future<String> sendStateEvent({
    required String roomId,
    required String type,
    required String stateKey,
    required Map<String, Object?> content,
  }) async {
    final json = await _request(
      'PUT',
      _url(['rooms', roomId, 'state', type, stateKey]),
      body: content,
    );
    return _string(json, 'event_id');
  }

  /// Send a to-device message to specific devices: `{userId: {deviceId: content}}`
  /// (the key-share carrier, §4.3). `*` as a device id targets all of a user's.
  Future<void> sendToDevice({
    required String type,
    required Map<String, Map<String, Map<String, Object?>>> messages,
    String? txnId,
  }) async {
    final id = txnId ?? _nextTxn();
    await _request(
      'PUT',
      _url(['sendToDevice', type, id]),
      body: {'messages': messages},
    );
  }

  // --- rooms ---------------------------------------------------------------

  /// Create a room; returns its id. [extra] carries any create options
  /// (preset, invites, initial state) verbatim.
  Future<String> createRoom({Map<String, Object?> extra = const {}}) async {
    final json = await _request(
      'POST',
      _url(const ['createRoom']),
      body: extra,
    );
    return _string(json, 'room_id');
  }

  /// Invite [userId] to [roomId].
  Future<void> invite({required String roomId, required String userId}) async {
    await _request(
      'POST',
      _url(['rooms', roomId, 'invite']),
      body: {'user_id': userId},
    );
  }

  /// Join a room by id or alias; returns the joined room id.
  Future<String> join(String roomIdOrAlias) async {
    final json = await _request('POST', _url(['join', roomIdOrAlias]));
    return _string(json, 'room_id');
  }

  // --- internals -----------------------------------------------------------

  String _nextTxn() => 'ocideck-${_txn++}';

  /// Build a CS-API v3 URL, percent-encoding each dynamic [segments] entry (room
  /// ids and event types contain `!`, `:` and `.`). Preserves any base path the
  /// homeserver URL already carries.
  Uri _url(List<String> segments, [Map<String, String>? query]) {
    return _homeserver.replace(
      pathSegments: [
        ..._homeserver.pathSegments.where((s) => s.isNotEmpty),
        '_matrix',
        'client',
        'v3',
        ...segments,
      ],
      queryParameters: query,
    );
  }

  Future<MatrixHttpResponse> _send(
    String method,
    Uri url, {
    Map<String, Object?>? body,
    bool requireAuth = true,
  }) {
    final token = _token;
    if (requireAuth && token == null) {
      throw const MatrixException(MatrixErrorKind.auth, 'no access token');
    }
    return _http.send(
      method: method,
      url: url,
      headers: {
        if (body != null) 'Content-Type': 'application/json',
        if (token != null) 'Authorization': 'Bearer $token',
      },
      body: body == null ? null : jsonEncode(body),
    );
  }

  /// Send and decode a success body, mapping any non-2xx to a [MatrixException].
  Future<Map<String, Object?>> _request(
    String method,
    Uri url, {
    Map<String, Object?>? body,
    bool requireAuth = true,
  }) async {
    final resp = await _send(method, url, body: body, requireAuth: requireAuth);
    return _ok(resp, _bodyObject(resp));
  }

  /// Return the parsed body on 2xx, else throw the mapped error.
  Map<String, Object?> _ok(MatrixHttpResponse resp, Map<String, Object?> json) {
    if (resp.status >= 200 && resp.status < 300) return json;
    throw _errorFor(resp, json);
  }

  MatrixException _errorFor(
    MatrixHttpResponse resp,
    Map<String, Object?> json,
  ) {
    final errcode = json['errcode'] as String?;
    final message = (json['error'] as String?) ?? 'HTTP ${resp.status}';
    final retryAfter = json['retry_after_ms'] is int
        ? Duration(milliseconds: json['retry_after_ms'] as int)
        : null;
    final kind = switch (resp.status) {
      401 => MatrixErrorKind.auth,
      403 => MatrixErrorKind.forbidden,
      404 => MatrixErrorKind.notFound,
      429 => MatrixErrorKind.rateLimited,
      >= 300 && < 400 => MatrixErrorKind.redirect,
      >= 500 => MatrixErrorKind.server,
      _ =>
        errcode == 'M_UNKNOWN_TOKEN'
            ? MatrixErrorKind.auth
            : MatrixErrorKind.server,
    };
    return MatrixException(
      kind,
      message,
      errcode: errcode,
      retryAfter: retryAfter,
    );
  }

  Map<String, Object?> _bodyObject(MatrixHttpResponse resp) {
    if (resp.body.isEmpty) return const {};
    final decoded = jsonDecode(resp.body);
    return _asObject(decoded) ??
        (throw const MatrixException(
          MatrixErrorKind.server,
          'response body is not a JSON object',
        ));
  }

  MatrixSession _sessionFrom(Map<String, Object?> json) => MatrixSession(
    userId: _string(json, 'user_id'),
    deviceId: _string(json, 'device_id'),
    accessToken: _storeToken(_string(json, 'access_token')),
  );

  String _storeToken(String token) {
    _token = token;
    return token;
  }

  MatrixSyncResult _parseSync(Map<String, Object?> json) {
    final timeline = <MatrixTimelineEvent>[];
    final joined = _asObject(_asObject(json['rooms'])?['join']) ?? const {};
    for (final entry in joined.entries) {
      final room = _asObject(entry.value) ?? const {};
      _collectRoomEvents(entry.key, room, timeline);
    }
    final toDevice = <MatrixToDeviceEvent>[];
    for (final e in _eventList(_asObject(json['to_device']))) {
      toDevice.add(
        MatrixToDeviceEvent(
          type: (e['type'] as String?) ?? '',
          sender: (e['sender'] as String?) ?? '',
          content: _asObject(e['content']) ?? const {},
        ),
      );
    }
    return MatrixSyncResult(
      nextBatch: _string(json, 'next_batch'),
      timeline: timeline,
      toDevice: toDevice,
    );
  }

  void _collectRoomEvents(
    String roomId,
    Map<String, Object?> room,
    List<MatrixTimelineEvent> out,
  ) {
    // Timeline messages and, for §6 state (locks, device keys, authority beacon),
    // the state block too — both carry the events the relay dispatches on.
    for (final section in const ['timeline', 'state']) {
      for (final e in _eventList(_asObject(room[section]))) {
        out.add(
          MatrixTimelineEvent(
            roomId: roomId,
            eventId: (e['event_id'] as String?) ?? '',
            type: (e['type'] as String?) ?? '',
            sender: (e['sender'] as String?) ?? '',
            content: _asObject(e['content']) ?? const {},
            stateKey: e['state_key'] as String?,
          ),
        );
      }
    }
  }

  List<Map<String, Object?>> _eventList(Map<String, Object?>? section) {
    final raw = section?['events'];
    if (raw is! List) return const [];
    return [for (final e in raw) ?_asObject(e)];
  }

  List<List<String>> _uiaFlows(Object? raw) {
    if (raw is! List) return const [];
    return [
      for (final flow in raw)
        if (_asObject(flow)?['stages'] case final List<Object?> stages)
          [for (final s in stages) '$s'],
    ];
  }

  bool _maySendSecretTo(Uri url) {
    if (url.scheme == 'https') return true;
    final host = url.host;
    // Lexical loopback allowance for development (no dart:io, so this works on
    // web too); the production transport still pins and refuses redirects.
    return host == 'localhost' ||
        host == '127.0.0.1' ||
        host.startsWith('127.') ||
        host == '::1' ||
        host == '[::1]';
  }

  static String _string(Map<String, Object?> json, String key) {
    final value = json[key];
    if (value is! String) {
      throw MatrixException(
        MatrixErrorKind.server,
        'expected string field "$key"',
      );
    }
    return value;
  }

  static Map<String, Object?>? _asObject(Object? value) {
    if (value is Map<String, Object?>) return value;
    if (value is Map) return value.map((k, v) => MapEntry('$k', v));
    return null;
  }
}
