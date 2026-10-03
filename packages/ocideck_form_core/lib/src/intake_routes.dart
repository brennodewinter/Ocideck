/// The routes of the intake protocol v1 (`docs/design/INTAKE_PROTOCOL.md` §4–§5): which method and
/// path means which operation, in one place, so that the client builds a target and the server reads
/// one with the same grammar — and so that an id that is not an id never reaches a handler.
///
/// A request target is `path[?query]` exactly as it is sent and as a signed organiser request signs it
/// (`intakeRequestPreimage`). It is read **strictly**: an absolute address, a fragment, a `%` anywhere,
/// a trailing slash, an empty segment or a query where the route takes none is refused, so that there
/// is one spelling of every request and nothing for a cache, a proxy or a signature to disagree about.
///
/// **Decided in this order**, stopping at the first failure: the path has the shape of a route
/// ([IntakeErrorCode.notFound]) → the route answers the method ([IntakeErrorCode.methodNotAllowed]) →
/// its ids are ids ([IntakeErrorCode.badRequest]) → its query is the route's ([IntakeErrorCode.badRequest]).
library;

import 'form_package.dart' show isValidFormId;
import 'intake_bodies.dart'
    show isValidIntakeCursor, kIntakeDefaultPageItems, kIntakeMaxPageItems;
import 'intake_protocol.dart' show IntakeErrorCode;

/// What a request is for.
sealed class IntakeRoute {
  const IntakeRoute();

  /// Whether the request must be signed by an organiser (`INTAKE_PROTOCOL.md` §5.1). The others are
  /// answered to anyone (`info`, the form), or to whoever holds an invite token (the upload) or the
  /// withdrawal secret.
  bool get isOrganiser => false;
}

/// `GET /v1/info`
class IntakeInfoRoute extends IntakeRoute {
  const IntakeInfoRoute();
}

/// `GET /v1/forms/{fid}`
class IntakeGetFormRoute extends IntakeRoute {
  const IntakeGetFormRoute(this.fid);

  final String fid;
}

/// `PUT /v1/forms/{fid}` — publish
class IntakePublishFormRoute extends IntakeRoute {
  const IntakePublishFormRoute(this.fid);

  final String fid;

  @override
  bool get isOrganiser => true;
}

/// `PUT /v1/forms/{fid}/token`
class IntakeTokenRoute extends IntakeRoute {
  const IntakeTokenRoute(this.fid);

  final String fid;

  @override
  bool get isOrganiser => true;
}

/// `GET /v1/forms/{fid}/submissions?after=&limit=`
class IntakeListRoute extends IntakeRoute {
  const IntakeListRoute(this.fid, {this.after, required this.limit});

  final String fid;

  /// The cursor of the page to start after, or `null` for the first.
  final String? after;

  /// How many to return, 1–[kIntakeMaxPageItems]; [kIntakeDefaultPageItems] when not given.
  final int limit;

  @override
  bool get isOrganiser => true;
}

/// `PUT /v1/submissions/{sid}` — upload
class IntakeUploadRoute extends IntakeRoute {
  const IntakeUploadRoute(this.sid);

  final String sid;
}

/// `POST /v1/submissions/{sid}/withdraw`
class IntakeWithdrawRoute extends IntakeRoute {
  const IntakeWithdrawRoute(this.sid);

  final String sid;
}

/// `GET /v1/submissions/{sid}/blob`
class IntakeBlobRoute extends IntakeRoute {
  const IntakeBlobRoute(this.sid);

  final String sid;

  @override
  bool get isOrganiser => true;
}

/// `POST /v1/submissions/{sid}/ack`
class IntakeAckRoute extends IntakeRoute {
  const IntakeAckRoute(this.sid);

  final String sid;

  @override
  bool get isOrganiser => true;
}

/// `DELETE /v1/submissions/{sid}`
class IntakeDeleteRoute extends IntakeRoute {
  const IntakeDeleteRoute(this.sid);

  final String sid;

  @override
  bool get isOrganiser => true;
}

/// What [matchIntakeRoute] decided.
sealed class IntakeRouteResult {
  const IntakeRouteResult();
}

class IntakeRouteMatched extends IntakeRouteResult {
  const IntakeRouteMatched(this.route);

  final IntakeRoute route;
}

/// The request is not a route; the code is [IntakeErrorCode.notFound],
/// [IntakeErrorCode.methodNotAllowed] or [IntakeErrorCode.badRequest].
class IntakeRouteRefused extends IntakeRouteResult {
  const IntakeRouteRefused(this.code);

  final IntakeErrorCode code;
}

/// What a target may be made of: a slash first, then letters, digits and `. _ ~ - / ? = &`. A `%`, a
/// `#`, a blank, a control character or anything beyond ASCII is not part of any route's spelling.
final RegExp _targetChars = RegExp(r'^/[A-Za-z0-9._~/?=&-]*$');

const IntakeRouteRefused _notFound = IntakeRouteRefused(
  IntakeErrorCode.notFound,
);
const IntakeRouteRefused _wrongMethod = IntakeRouteRefused(
  IntakeErrorCode.methodNotAllowed,
);
const IntakeRouteRefused _badRequest = IntakeRouteRefused(
  IntakeErrorCode.badRequest,
);

/// The route of [method] (as received: upper case) on [target] (the request target, `path[?query]`).
IntakeRouteResult matchIntakeRoute(String method, String target) {
  if (!_targetChars.hasMatch(target) || target.startsWith('//')) {
    return _badRequest;
  }
  // Split by hand: `Uri` would resolve a `..` away, and then `/v1/forms/..` would read as `/v1`.
  final q = target.indexOf('?');
  final query = q == -1 ? null : target.substring(q + 1);
  final s = (q == -1 ? target : target.substring(0, q)).substring(1).split('/');
  if (s[0] != 'v1') return _notFound;

  // The shape decides which operations the path has; its id and the query are looked at last.
  final Map<String, _Make> byMethod;
  final String? id;
  if (s.length == 2 && s[1] == 'info') {
    id = null;
    byMethod = {'GET': _plain((_) => const IntakeInfoRoute())};
  } else if (s.length == 3 && s[1] == 'forms') {
    id = s[2];
    byMethod = {
      'GET': _plain(IntakeGetFormRoute.new),
      'PUT': _plain(IntakePublishFormRoute.new),
    };
  } else if (s.length == 4 && s[1] == 'forms' && s[3] == 'token') {
    id = s[2];
    byMethod = {'PUT': _plain(IntakeTokenRoute.new)};
  } else if (s.length == 4 && s[1] == 'forms' && s[3] == 'submissions') {
    id = s[2];
    byMethod = {'GET': _list};
  } else if (s.length == 3 && s[1] == 'submissions') {
    id = s[2];
    byMethod = {
      'PUT': _plain(IntakeUploadRoute.new),
      'DELETE': _plain(IntakeDeleteRoute.new),
    };
  } else if (s.length == 4 && s[1] == 'submissions' && s[3] == 'withdraw') {
    id = s[2];
    byMethod = {'POST': _plain(IntakeWithdrawRoute.new)};
  } else if (s.length == 4 && s[1] == 'submissions' && s[3] == 'blob') {
    id = s[2];
    byMethod = {'GET': _plain(IntakeBlobRoute.new)};
  } else if (s.length == 4 && s[1] == 'submissions' && s[3] == 'ack') {
    id = s[2];
    byMethod = {'POST': _plain(IntakeAckRoute.new)};
  } else {
    return _notFound;
  }

  final make = byMethod[method];
  if (make == null) return _wrongMethod;
  if (id != null && !isValidFormId(id)) return _badRequest;
  return make(id ?? '', query);
}

/// What makes a route from its id and its query, or refuses it.
typedef _Make = IntakeRouteResult Function(String id, String? query);

/// A route that takes no query.
_Make _plain(IntakeRoute Function(String id) route) =>
    (id, query) => query != null ? _badRequest : IntakeRouteMatched(route(id));

/// The listing, which takes `after` and `limit`.
IntakeRouteResult _list(String fid, String? query) {
  String? after;
  var limit = kIntakeDefaultPageItems;
  if (query != null) {
    final seen = <String>{};
    for (final part in query.split('&')) {
      final pair = part.split('=');
      if (pair.length != 2 || !seen.add(pair[0])) return _badRequest;
      switch (pair[0]) {
        case 'after':
          if (!isValidIntakeCursor(pair[1])) return _badRequest;
          after = pair[1];
        case 'limit':
          final n = RegExp(r'^[1-9][0-9]{0,2}$').hasMatch(pair[1])
              ? int.parse(pair[1])
              : 0;
          if (n < 1 || n > kIntakeMaxPageItems) return _badRequest;
          limit = n;
        default:
          return _badRequest;
      }
    }
  }
  return IntakeRouteMatched(IntakeListRoute(fid, after: after, limit: limit));
}

// ── targets, for the client ─────────────────────────────────────────────────

/// `GET /v1/info`
const String intakeInfoTarget = '/v1/info';

/// The target of a form: `GET` it, or `PUT` it to publish.
String intakeFormTarget(String fid) => '/v1/forms/${_id(fid)}';

/// The target of a form's open token.
String intakeTokenTarget(String fid) => '${intakeFormTarget(fid)}/token';

/// The target of a form's listing, with the cursor of the page to start after and a page size when
/// they are given.
String intakeSubmissionsTarget(String fid, {String? after, int? limit}) {
  final query = [
    if (after != null)
      'after=${isValidIntakeCursor(after) ? after : throw ArgumentError.value(after, 'after')}',
    if (limit != null)
      'limit=${limit >= 1 && limit <= kIntakeMaxPageItems ? limit : throw ArgumentError.value(limit, 'limit')}',
  ];
  return '${intakeFormTarget(fid)}/submissions'
      '${query.isEmpty ? '' : '?${query.join('&')}'}';
}

/// The target of a submission: `PUT` it to upload, `DELETE` it to remove the server's copy.
String intakeSubmissionTarget(String sid) => '/v1/submissions/${_id(sid)}';

/// The target of a withdrawal.
String intakeWithdrawTarget(String sid) =>
    '${intakeSubmissionTarget(sid)}/withdraw';

/// The target of a submission's ciphertext.
String intakeBlobTarget(String sid) => '${intakeSubmissionTarget(sid)}/blob';

/// The target of an acknowledgement.
String intakeAckTarget(String sid) => '${intakeSubmissionTarget(sid)}/ack';

String _id(String id) =>
    isValidFormId(id) ? id : throw ArgumentError.value(id, 'id', 'not an id');
