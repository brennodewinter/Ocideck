import 'package:ocideck_form_core/ocideck_form_core.dart';
import 'package:test/test.dart';

const String _fid = 'mfrggzdfmztwq2lknnwg23tpoa';
const String _sid = 'nvqwy3dpoixxg5dfonzgc3tjnq';

IntakeRoute? _route(String method, String target) {
  final r = matchIntakeRoute(method, target);
  return r is IntakeRouteMatched ? r.route : null;
}

IntakeErrorCode? _refused(String method, String target) {
  final r = matchIntakeRoute(method, target);
  return r is IntakeRouteRefused ? r.code : null;
}

void main() {
  group('every operation has its method and path', () {
    test('GET /v1/info', () {
      final r = _route('GET', '/v1/info');
      expect(r, isA<IntakeInfoRoute>());
      expect(r!.isOrganiser, isFalse);
    });

    test('GET /v1/forms/{fid}', () {
      final r = _route('GET', '/v1/forms/$_fid');
      expect(r, isA<IntakeGetFormRoute>());
      expect((r! as IntakeGetFormRoute).fid, _fid);
      expect(r.isOrganiser, isFalse);
    });

    test('PUT /v1/forms/{fid} publishes, for an organiser', () {
      final r = _route('PUT', '/v1/forms/$_fid');
      expect(r, isA<IntakePublishFormRoute>());
      expect((r! as IntakePublishFormRoute).fid, _fid);
      expect(r.isOrganiser, isTrue);
    });

    test('PUT /v1/forms/{fid}/token, for an organiser', () {
      final r = _route('PUT', '/v1/forms/$_fid/token');
      expect(r, isA<IntakeTokenRoute>());
      expect((r! as IntakeTokenRoute).fid, _fid);
      expect(r.isOrganiser, isTrue);
    });

    test('GET /v1/forms/{fid}/submissions, for an organiser', () {
      final r = _route('GET', '/v1/forms/$_fid/submissions');
      expect(r, isA<IntakeListRoute>());
      r as IntakeListRoute;
      expect(r.fid, _fid);
      expect(r.after, isNull);
      expect(r.limit, 50);
      expect(r.isOrganiser, isTrue);
    });

    test('PUT /v1/submissions/{sid} uploads, for whoever holds the token', () {
      final r = _route('PUT', '/v1/submissions/$_sid');
      expect(r, isA<IntakeUploadRoute>());
      expect((r! as IntakeUploadRoute).sid, _sid);
      expect(r.isOrganiser, isFalse);
    });

    test('DELETE /v1/submissions/{sid}, for an organiser', () {
      final r = _route('DELETE', '/v1/submissions/$_sid');
      expect(r, isA<IntakeDeleteRoute>());
      expect((r! as IntakeDeleteRoute).sid, _sid);
      expect(r.isOrganiser, isTrue);
    });

    test(
      'POST /v1/submissions/{sid}/withdraw, for whoever holds the secret',
      () {
        final r = _route('POST', '/v1/submissions/$_sid/withdraw');
        expect(r, isA<IntakeWithdrawRoute>());
        expect((r! as IntakeWithdrawRoute).sid, _sid);
        expect(r.isOrganiser, isFalse);
      },
    );

    test('GET /v1/submissions/{sid}/blob, for an organiser', () {
      final r = _route('GET', '/v1/submissions/$_sid/blob');
      expect(r, isA<IntakeBlobRoute>());
      expect((r! as IntakeBlobRoute).sid, _sid);
      expect(r.isOrganiser, isTrue);
    });

    test('POST /v1/submissions/{sid}/ack, for an organiser', () {
      final r = _route('POST', '/v1/submissions/$_sid/ack');
      expect(r, isA<IntakeAckRoute>());
      expect((r! as IntakeAckRoute).sid, _sid);
      expect(r.isOrganiser, isTrue);
    });
  });

  group('the listing\'s query', () {
    IntakeListRoute list(String query) {
      final r = _route('GET', '/v1/forms/$_fid/submissions$query');
      expect(r, isA<IntakeListRoute>(), reason: query);
      return r! as IntakeListRoute;
    }

    test('takes a cursor and a page size, in either order', () {
      final a = list('?after=abc_-9&limit=7');
      expect(a.after, 'abc_-9');
      expect(a.limit, 7);
      final b = list('?limit=7&after=abc');
      expect(b.after, 'abc');
      expect(b.limit, 7);
    });

    test('takes one of them', () {
      expect(list('?after=abc').limit, 50);
      expect(list('?after=abc').after, 'abc');
      expect(list('?limit=3').after, isNull);
      expect(list('?limit=3').limit, 3);
    });

    test('a page is 1 to 100', () {
      expect(list('?limit=1').limit, 1);
      expect(list('?limit=100').limit, 100);
      for (final bad in [
        '0',
        '101',
        '1000',
        '-1',
        '01',
        'x',
        '',
        '1.5',
        '1 ',
        '+1',
      ]) {
        expect(
          _refused('GET', '/v1/forms/$_fid/submissions?limit=$bad'),
          IntakeErrorCode.badRequest,
          reason: bad,
        );
      }
    });

    test('a cursor is 1 to 64 characters of its grammar', () {
      expect(list('?after=${'x' * 64}').after, 'x' * 64);
      for (final bad in ['', 'x' * 65, 'a.b', 'a:b', 'a,b']) {
        expect(
          _refused('GET', '/v1/forms/$_fid/submissions?after=$bad'),
          IntakeErrorCode.badRequest,
          reason: bad,
        );
      }
    });

    test('anything else in it is refused', () {
      for (final bad in [
        '?',
        '?x=1',
        '?after=a&after=b',
        '?limit=1&limit=2',
        '?after',
        '?after=a=b',
        '?after=a&',
        '?&after=a',
        '?after=a&x=1',
      ]) {
        expect(
          _refused('GET', '/v1/forms/$_fid/submissions$bad'),
          IntakeErrorCode.badRequest,
          reason: bad,
        );
      }
    });
  });

  group('what is not a route', () {
    test('a path that has no shape of one is not found', () {
      for (final path in [
        '/',
        '/v1',
        '/v1/',
        '/v2/info',
        '/V1/info',
        '/info',
        '/v1/unknown',
        '/v1/forms',
        '/v1/submissions',
        '/v1/info/',
        '/v1/info/x',
        '/v1//info',
        '/v1/forms/$_fid/',
        '/v1/forms/$_fid/other',
        '/v1/forms/$_fid/token/x',
        '/v1/forms/$_fid/submissions/x',
        '/v1/submissions/$_sid/',
        '/v1/submissions/$_sid/other',
        '/v1/submissions/$_sid/blob/x',
        '/v1/forms/$_fid/withdraw',
        '/v1/submissions/$_sid/token',
        '/robots.txt',
      ]) {
        expect(_refused('GET', path), IntakeErrorCode.notFound, reason: path);
      }
    });

    test('a path that exists and does not answer the method', () {
      for (final c in <(String, String)>[
        ('POST', '/v1/info'),
        ('PUT', '/v1/info'),
        ('DELETE', '/v1/forms/$_fid'),
        ('POST', '/v1/forms/$_fid'),
        ('GET', '/v1/forms/$_fid/token'),
        ('POST', '/v1/forms/$_fid/submissions'),
        ('GET', '/v1/submissions/$_sid'),
        ('POST', '/v1/submissions/$_sid'),
        ('GET', '/v1/submissions/$_sid/withdraw'),
        ('PUT', '/v1/submissions/$_sid/blob'),
        ('GET', '/v1/submissions/$_sid/ack'),
        ('DELETE', '/v1/submissions/$_sid/ack'),
        ('get', '/v1/info'),
        ('HEAD', '/v1/info'),
        ('OPTIONS', '/v1/info'),
        ('', '/v1/info'),
      ]) {
        expect(
          _refused(c.$1, c.$2),
          IntakeErrorCode.methodNotAllowed,
          reason: '${c.$1} ${c.$2}',
        );
      }
    });

    test('an id that is not an id is a bad request', () {
      for (final id in [
        _fid.toUpperCase(),
        _fid.substring(1),
        '${_fid}a',
        '1' * 26,
        'x',
        '..',
      ]) {
        for (final c in <(String, String)>[
          ('GET', '/v1/forms/$id'),
          ('PUT', '/v1/forms/$id'),
          ('PUT', '/v1/forms/$id/token'),
          ('GET', '/v1/forms/$id/submissions'),
          ('PUT', '/v1/submissions/$id'),
          ('DELETE', '/v1/submissions/$id'),
          ('POST', '/v1/submissions/$id/withdraw'),
          ('GET', '/v1/submissions/$id/blob'),
          ('POST', '/v1/submissions/$id/ack'),
        ]) {
          expect(
            _refused(c.$1, c.$2),
            IntakeErrorCode.badRequest,
            reason: '${c.$1} ${c.$2}',
          );
        }
      }
    });

    test('is decided in order: shape, method, id, query', () {
      expect(
        _refused('DELETE', '/v1/forms/BAD/other'),
        IntakeErrorCode.notFound,
      );
      expect(
        _refused('DELETE', '/v1/forms/BAD'),
        IntakeErrorCode.methodNotAllowed,
      );
      expect(_refused('GET', '/v1/forms/BAD?x=1'), IntakeErrorCode.badRequest);
      expect(
        _refused('GET', '/v1/forms/BAD/submissions?x=1'),
        IntakeErrorCode.badRequest,
      );
    });

    test('a query where the route takes none is a bad request', () {
      for (final c in <(String, String)>[
        ('GET', '/v1/info?x=1'),
        ('GET', '/v1/info?'),
        ('GET', '/v1/forms/$_fid?after=a'),
        ('PUT', '/v1/forms/$_fid?x'),
        ('PUT', '/v1/forms/$_fid/token?x=1'),
        ('PUT', '/v1/submissions/$_sid?x=1'),
        ('POST', '/v1/submissions/$_sid/ack?x=1'),
      ]) {
        expect(_refused(c.$1, c.$2), IntakeErrorCode.badRequest, reason: c.$2);
      }
    });

    test(
      'a target that is not a path is a bad request, whatever it asks for',
      () {
        for (final target in [
          '',
          'v1/info',
          '//v1/info',
          'https://intake.example.org/v1/info',
          '/v1/info#x',
          '/v1/forms/%61',
          '/v1/forms/$_fid/submissions?after=%61',
          '/v1/info%2f',
          '*',
          '/v1/ info',
        ]) {
          expect(
            _refused('GET', target),
            IntakeErrorCode.badRequest,
            reason: target,
          );
        }
      },
    );
  });

  group('the targets a client builds are the ones the server reads', () {
    test('each, for its method', () {
      expect(_route('GET', intakeInfoTarget), isA<IntakeInfoRoute>());
      expect(_route('GET', intakeFormTarget(_fid)), isA<IntakeGetFormRoute>());
      expect(
        _route('PUT', intakeFormTarget(_fid)),
        isA<IntakePublishFormRoute>(),
      );
      expect(_route('PUT', intakeTokenTarget(_fid)), isA<IntakeTokenRoute>());
      expect(
        _route('GET', intakeSubmissionsTarget(_fid)),
        isA<IntakeListRoute>(),
      );
      expect(
        _route('PUT', intakeSubmissionTarget(_sid)),
        isA<IntakeUploadRoute>(),
      );
      expect(
        _route('DELETE', intakeSubmissionTarget(_sid)),
        isA<IntakeDeleteRoute>(),
      );
      expect(
        _route('POST', intakeWithdrawTarget(_sid)),
        isA<IntakeWithdrawRoute>(),
      );
      expect(_route('GET', intakeBlobTarget(_sid)), isA<IntakeBlobRoute>());
      expect(_route('POST', intakeAckTarget(_sid)), isA<IntakeAckRoute>());
    });

    test('are written as the protocol document gives them', () {
      expect(intakeInfoTarget, '/v1/info');
      expect(intakeFormTarget(_fid), '/v1/forms/$_fid');
      expect(intakeTokenTarget(_fid), '/v1/forms/$_fid/token');
      expect(intakeSubmissionsTarget(_fid), '/v1/forms/$_fid/submissions');
      expect(intakeSubmissionTarget(_sid), '/v1/submissions/$_sid');
      expect(intakeWithdrawTarget(_sid), '/v1/submissions/$_sid/withdraw');
      expect(intakeBlobTarget(_sid), '/v1/submissions/$_sid/blob');
      expect(intakeAckTarget(_sid), '/v1/submissions/$_sid/ack');
    });

    test('the listing\'s query, with a cursor and a size', () {
      expect(
        intakeSubmissionsTarget(_fid, after: 'abc'),
        '/v1/forms/$_fid/submissions?after=abc',
      );
      expect(
        intakeSubmissionsTarget(_fid, limit: 7),
        '/v1/forms/$_fid/submissions?limit=7',
      );
      final both = intakeSubmissionsTarget(_fid, after: 'abc', limit: 100);
      expect(both, '/v1/forms/$_fid/submissions?after=abc&limit=100');
      final r = _route('GET', both)! as IntakeListRoute;
      expect(r.after, 'abc');
      expect(r.limit, 100);
      expect(
        (_route('GET', intakeSubmissionsTarget(_fid, limit: 1))!
                as IntakeListRoute)
            .limit,
        1,
      );
    });

    test('refuse to build what the server would refuse', () {
      expect(() => intakeFormTarget('x'), throwsArgumentError);
      expect(() => intakeFormTarget(_fid.toUpperCase()), throwsArgumentError);
      expect(() => intakeTokenTarget('x'), throwsArgumentError);
      expect(() => intakeSubmissionTarget('x'), throwsArgumentError);
      expect(() => intakeWithdrawTarget('x'), throwsArgumentError);
      expect(() => intakeBlobTarget('x'), throwsArgumentError);
      expect(() => intakeAckTarget('x'), throwsArgumentError);
      expect(() => intakeSubmissionsTarget('x'), throwsArgumentError);
      expect(
        () => intakeSubmissionsTarget(_fid, after: 'a b'),
        throwsArgumentError,
      );
      expect(
        () => intakeSubmissionsTarget(_fid, after: ''),
        throwsArgumentError,
      );
      expect(
        () => intakeSubmissionsTarget(_fid, limit: 0),
        throwsArgumentError,
      );
      expect(
        () => intakeSubmissionsTarget(_fid, limit: 101),
        throwsArgumentError,
      );
    });
  });
}
