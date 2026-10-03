import 'dart:convert';
import 'dart:math';

import 'package:ocideck_form_core/ocideck_form_core.dart';
import 'package:test/test.dart';

/// A [Random] that records what it is asked for and answers the same every time.
class _Spy implements Random {
  final List<int> asked = [];

  @override
  int nextInt(int max) {
    asked.add(max);
    return 7;
  }

  @override
  bool nextBool() => throw UnimplementedError();

  @override
  double nextDouble() => throw UnimplementedError();
}

const String _fid = 'mfrggzdfmztwq2lknnwg23tpoa';
const String _invite = 'nvqwy3dpoixxg5dfonzgc3tjnq';
// 52 characters, 32 bytes.
const String _fp = 'mw3am46w5weex4a4fqrc3avnub2a6knmgnk5nkjfzaprp5d2e64a';

String _link({
  String scheme = 'https',
  String authority = 'forms.example.org',
  String path = '/f/$_fid',
  String? fragment,
}) =>
    '$scheme://$authority$path#${fragment ?? 'api=intake.example.org&fp=$_fp&t=$_invite'}';

InviteLinkIssue? _issue(String text) {
  final r = parseInviteLink(text);
  return r is InviteLinkRefused ? r.issue : null;
}

InviteLink _parsed(String text) {
  final r = parseInviteLink(text);
  expect(r, isA<InviteLinkParsed>(), reason: text);
  return (r as InviteLinkParsed).link;
}

void main() {
  group('an invite link (§6.4)', () {
    test('is read in full and written back as it came', () {
      final link = _parsed(_link());
      expect(link.shellBase, 'https://forms.example.org');
      expect(link.fid, _fid);
      expect(link.apiHost, 'intake.example.org');
      expect(link.fingerprint, _fp);
      expect(link.token, _invite);
      expect(link.text, _link());
    });

    test('ignores blanks around it', () {
      expect(_parsed('  \n${_link()}\t ').fid, _fid);
    });

    test(
      'keeps a path prefix and a port, and lets the form id end in a slash',
      () {
        final link = _parsed(
          _link(
            authority: 'forms.example.org:8443',
            path: '/shell/v2/f/$_fid/',
          ),
        );
        expect(link.shellBase, 'https://forms.example.org:8443/shell/v2');
        expect(
          link.text,
          startsWith('https://forms.example.org:8443/shell/v2/f/$_fid#'),
        );
      },
    );

    test('lower-cases the hosts, which have no case', () {
      final link = _parsed(
        _link(
          authority: 'Forms.Example.ORG',
          fragment: 'api=Intake.Example.ORG:8444&fp=$_fp&t=$_invite',
        ),
      );
      expect(link.shellBase, 'https://forms.example.org');
      expect(link.apiHost, 'intake.example.org:8444');
    });

    test('reads the fingerprint however it was written', () {
      final grouped = [
        for (var i = 0; i < 52; i += 4) _fp.substring(i, i + 4).toUpperCase(),
      ].join('-');
      final link = _parsed(
        _link(fragment: 'api=intake.example.org&fp=$grouped&t=$_invite'),
      );
      expect(link.fingerprint, _fp);
    });

    test(
      'takes the parameters in any order and ignores one it does not know',
      () {
        final link = _parsed(
          _link(
            fragment: 't=$_invite&x=1&fp=$_fp&&flag&api=intake.example.org',
          ),
        );
        expect(link.token, _invite);
        expect(link.apiHost, 'intake.example.org');
      },
    );

    final refused = <String, (String, InviteLinkIssue)>{
      'not an address': ('hello', InviteLinkIssue.notALink),
      'nothing': ('', InviteLinkIssue.notALink),
      'a scheme without a host': (
        'mailto:a@b.example',
        InviteLinkIssue.notALink,
      ),
      'an address with no host': ('https:///f/$_fid', InviteLinkIssue.notALink),
      'a user name in front of the host': (
        _link(authority: 'forms.example.org@evil.example'),
        InviteLinkIssue.notALink,
      ),
      'plain http': (_link(scheme: 'http'), InviteLinkIssue.notHttps),
      'another scheme': (_link(scheme: 'ftp'), InviteLinkIssue.notHttps),
      'no path': (_link(path: ''), InviteLinkIssue.noFormId),
      'the root': (_link(path: '/'), InviteLinkIssue.noFormId),
      'a path that is not /f/<id>': (
        _link(path: '/g/$_fid'),
        InviteLinkIssue.noFormId,
      ),
      'only /f': (_link(path: '/f'), InviteLinkIssue.noFormId),
      'an id of the wrong length': (
        _link(path: '/f/${_fid.substring(1)}'),
        InviteLinkIssue.badFormId,
      ),
      'an id in capitals': (
        _link(path: '/f/${_fid.toUpperCase()}'),
        InviteLinkIssue.badFormId,
      ),
      'no fragment': (
        'https://forms.example.org/f/$_fid',
        InviteLinkIssue.noApi,
      ),
      'api empty': (
        _link(fragment: 'api=&fp=$_fp&t=$_invite'),
        InviteLinkIssue.noApi,
      ),
      'api not a host': (
        _link(fragment: 'api=in_valid&fp=$_fp&t=$_invite'),
        InviteLinkIssue.badApi,
      ),
      'api with a path': (
        _link(fragment: 'api=intake.example.org/x&fp=$_fp&t=$_invite'),
        InviteLinkIssue.badApi,
      ),
      'no fingerprint': (
        _link(fragment: 'api=intake.example.org&t=$_invite'),
        InviteLinkIssue.noFingerprint,
      ),
      'fp empty': (
        _link(fragment: 'api=intake.example.org&fp=&t=$_invite'),
        InviteLinkIssue.noFingerprint,
      ),
      'a fingerprint one character short': (
        _link(
          fragment: 'api=intake.example.org&fp=${_fp.substring(1)}&t=$_invite',
        ),
        InviteLinkIssue.badFingerprint,
      ),
      'no token': (
        _link(fragment: 'api=intake.example.org&fp=$_fp'),
        InviteLinkIssue.noToken,
      ),
      't empty': (
        _link(fragment: 'api=intake.example.org&fp=$_fp&t='),
        InviteLinkIssue.noToken,
      ),
      'a token in capitals': (
        _link(
          fragment: 'api=intake.example.org&fp=$_fp&t=${_invite.toUpperCase()}',
        ),
        InviteLinkIssue.badToken,
      ),
      'api twice': (
        _link(fragment: 'api=a.example&api=b.example&fp=$_fp&t=$_invite'),
        InviteLinkIssue.repeatedParameter,
      ),
      'fp twice': (
        _link(fragment: 'api=intake.example.org&fp=$_fp&fp=$_fp&t=$_invite'),
        InviteLinkIssue.repeatedParameter,
      ),
      't twice': (
        _link(fragment: 'api=intake.example.org&fp=$_fp&t=$_invite&t=$_invite'),
        InviteLinkIssue.repeatedParameter,
      ),
    };
    refused.forEach((name, c) {
      test('is refused: $name', () => expect(_issue(c.$1), c.$2));
    });

    test(
      'a known parameter with two equals signs is not read, so it is missing',
      () {
        expect(
          _issue(
            _link(fragment: 'api=intake.example.org&fp=$_fp=x&t=$_invite'),
          ),
          InviteLinkIssue.noFingerprint,
        );
        expect(
          _issue(_link(fragment: 'api=intake.example.org&fp=$_fp&t')),
          InviteLinkIssue.noToken,
        );
      },
    );

    test('stops at the missing fingerprint even when the token is bad too', () {
      expect(
        _issue(_link(fragment: 'api=intake.example.org&t=bad')),
        InviteLinkIssue.noFingerprint,
      );
    });

    test(
      'a parameter only counts once it is known: a repeated unknown one is fine',
      () {
        expect(
          _issue(_link(fragment: 'x=1&x=2&api=a.example&fp=$_fp&t=$_invite')),
          isNull,
        );
      },
    );
  });

  group('invite tokens and withdrawal secrets', () {
    test('a token is 128 random bits in the grammar of an id', () {
      final a = newInviteToken(Random(1));
      final b = newInviteToken(Random(2));
      expect(a, isNot(b));
      expect(isValidInviteToken(a), isTrue);
      expect(a, hasLength(26));
      expect(isValidInviteToken(a.toUpperCase()), isFalse);
      expect(isValidInviteToken(a.substring(1)), isFalse);
      expect(isValidInviteToken(''), isFalse);
    });

    test('a token is hashed over its text', () {
      expect(
        inviteTokenHash(_invite),
        '588944edadbd274b82b2c4bbbe58d5bc60d6cc1eb141628322eff7fb394585f2',
      );
    });

    test('a secret is 256 random bits as 52 characters', () {
      final a = newWithdrawalSecret(Random(1));
      final b = newWithdrawalSecret(Random(2));
      expect(a, isNot(b));
      expect(a, hasLength(52));
      expect(isValidWithdrawalSecret(a), isTrue);
    });

    test('a secret takes 32 whole bytes from the generator it is given', () {
      final spy = _Spy();
      newWithdrawalSecret(spy);
      expect(spy.asked, List.filled(32, 256));
      final tokenSpy = _Spy();
      newInviteToken(tokenSpy);
      expect(tokenSpy.asked, List.filled(16, 256));
    });

    test('a secret is refused outside its grammar', () {
      final ok = 'ma' * 26;
      expect(isValidWithdrawalSecret(ok), isTrue);
      expect(isValidWithdrawalSecret(ok.substring(1)), isFalse);
      expect(isValidWithdrawalSecret('${ok}a'), isFalse);
      expect(isValidWithdrawalSecret(ok.toUpperCase()), isFalse);
      // Leftover bits that are not zero decode to the same bytes as another text.
      expect(isValidWithdrawalSecret('${ok.substring(0, 51)}b'), isFalse);
      expect(isValidWithdrawalSecret(''), isFalse);
      expect(isValidWithdrawalSecret('1' * 52), isFalse);
    });

    test('a secret is hashed over its text', () {
      expect(
        withdrawalSecretHash('ma' * 26),
        '46f03eac50c223fcfff497f9fedb13064a181c42d40b708ae6749ebf0aede0b3',
      );
    });
  });

  group('server information (GET /v1/info)', () {
    Map<String, Object?> info({
      Object? protocol = 1,
      Object? limits = const {'max_package_bytes': 62914560},
      Object? source = 'https://example.org/source',
      Object? contact = 'beheer@example.org',
    }) => {
      'protocol': protocol,
      'limits': limits,
      'source_url': source,
      'operator_contact': contact,
    };

    IntakeInfoIssue? issue(Object? json) {
      final r = parseIntakeInfo(json is String ? json : jsonEncode(json));
      return r is IntakeInfoRefused ? r.issue : null;
    }

    test('is read', () {
      final r = parseIntakeInfo(jsonEncode(info()));
      expect(r, isA<IntakeInfoRead>());
      final i = (r as IntakeInfoRead).info;
      expect(i.protocol, 1);
      expect(i.maxPackageBytes, 62914560);
      expect(i.sourceUrl, 'https://example.org/source');
      expect(i.operatorContact, 'beheer@example.org');
    });

    test(
      'ignores what it does not know, in the document and in the limits',
      () {
        final r = parseIntakeInfo(
          jsonEncode({
            ...info(limits: {'max_package_bytes': 5, 'per_day': 9}),
            'banner': 'hello',
          }),
        );
        expect(r, isA<IntakeInfoRead>());
      },
    );

    test(
      'lowers a limit above the client hard cap to it, and keeps one below',
      () {
        const hard = 120 * 1024 * 1024;
        int cap(int server) =>
            ((parseIntakeInfo(
                      jsonEncode(info(limits: {'max_package_bytes': server})),
                    )
                    as IntakeInfoRead)
                .info
                .maxPackageBytes);
        expect(cap(hard + 1), hard);
        expect(cap(hard), hard);
        expect(cap(hard - 1), hard - 1);
        expect(cap(1), 1);
      },
    );

    test('takes a document of exactly 64 KiB and no more', () {
      String padded(int bytes) {
        final empty = jsonEncode({...info(), 'pad': ''});
        return jsonEncode({
          ...info(),
          'pad': 'x' * (bytes - utf8.encode(empty).length),
        });
      }

      expect(utf8.encode(padded(65536)), hasLength(65536));
      expect(issue(padded(65536)), isNull);
      expect(issue(padded(65537)), IntakeInfoIssue.notInfo);
      expect(kIntakeMaxJsonBytes, 65536);
    });

    test('is too old or too new, never guessed at', () {
      expect(issue(info(protocol: 0)), IntakeInfoIssue.serverTooOld);
      expect(issue(info(protocol: 2)), IntakeInfoIssue.serverTooNew);
      expect(issue(info(protocol: 1)), isNull);
    });

    test('is not information', () {
      expect(issue('nope'), IntakeInfoIssue.notInfo);
      expect(issue('[1]'), IntakeInfoIssue.notInfo);
      expect(issue('"x"'), IntakeInfoIssue.notInfo);
      expect(issue(info(protocol: null)), IntakeInfoIssue.notInfo);
      expect(issue(info(protocol: '1')), IntakeInfoIssue.notInfo);
      expect(issue(info(protocol: 1.5)), IntakeInfoIssue.notInfo);
      expect(issue(info(protocol: -1)), IntakeInfoIssue.notInfo);
      expect(
        issue(info(contact: 'x' * kIntakeMaxJsonBytes)),
        IntakeInfoIssue.notInfo,
      );
    });

    test('has a limit that is not a positive whole number', () {
      expect(issue(info(limits: null)), IntakeInfoIssue.badLimits);
      expect(issue(info(limits: 5)), IntakeInfoIssue.badLimits);
      expect(
        issue(info(limits: const <String, Object?>{})),
        IntakeInfoIssue.badLimits,
      );
      expect(
        issue(info(limits: {'max_package_bytes': 0})),
        IntakeInfoIssue.badLimits,
      );
      expect(
        issue(info(limits: {'max_package_bytes': -5})),
        IntakeInfoIssue.badLimits,
      );
      expect(
        issue(info(limits: {'max_package_bytes': '5'})),
        IntakeInfoIssue.badLimits,
      );
      expect(
        issue(info(limits: {'max_package_bytes': 1.5})),
        IntakeInfoIssue.badLimits,
      );
    });

    test('has a source address that is not https', () {
      for (final bad in [
        null,
        5,
        'http://example.org/source',
        'https://',
        'https://u@example.org/x',
        'example.org/source',
        'https://example.org/\u0007',
        'https://example.org/${'x' * 200}',
        '',
      ]) {
        expect(
          issue(info(source: bad)),
          IntakeInfoIssue.badSourceUrl,
          reason: '$bad',
        );
      }
    });

    test(
      'has a contact line that is empty, too long or has control characters',
      () {
        for (final bad in [null, 5, '', '   ', 'a\nb', 'a\u007fb', 'x' * 201]) {
          expect(
            issue(info(contact: bad)),
            IntakeInfoIssue.badContact,
            reason: '$bad',
          );
        }
        expect(issue(info(contact: 'x' * 200)), isNull);
        expect(
          issue(info(contact: 'Team Kookboek (kookboek@example.org)')),
          isNull,
        );
      },
    );

    test('decides in this order: version, limits, source, contact', () {
      expect(
        issue(info(protocol: 2, limits: null, source: null, contact: null)),
        IntakeInfoIssue.serverTooNew,
      );
      expect(
        issue(info(limits: null, source: null, contact: null)),
        IntakeInfoIssue.badLimits,
      );
      expect(
        issue(info(source: null, contact: null)),
        IntakeInfoIssue.badSourceUrl,
      );
    });
  });

  group('the arrival note (§5.8)', () {
    final good = {
      'sid': _fid,
      'at': '2026-10-04T09:30:12Z',
      'ciphertext_sha256': 'a' * 64,
      'contact': 'redactie@example.org',
    };

    IntakeArrivalNote? read(Map<String, Object?> json) =>
        parseIntakeArrivalNote(jsonEncode(json));

    test('is read and written back', () {
      final note = read(good)!;
      expect(note.sid, _fid);
      expect(note.at, '2026-10-04T09:30:12Z');
      expect(note.ciphertextSha256, 'a' * 64);
      expect(note.contact, 'redactie@example.org');
      expect(jsonDecode(note.toJsonText()), good);
      expect(parseIntakeArrivalNote(note.toJsonText())!.sid, _fid);
    });

    test('ignores a member it does not know', () {
      expect(read({...good, 'sig': 'x'}), isNotNull);
    });

    test('is refused outside its grammar, member by member', () {
      final bad = <String, List<Object?>>{
        'sid': [null, 5, _fid.substring(1), _fid.toUpperCase()],
        'at': [
          null,
          5,
          '2026-10-04 09:30:12Z',
          '2026-10-04T09:30:12',
          '2026-10-04T09:30:12+00:00',
          '2026-10-04T09:30:12.5Z',
          '2027-02-29T09:30:12Z',
          '2026-10-04T24:00:00Z',
        ],
        'ciphertext_sha256': [null, 5, 'A' * 64, 'a' * 63, 'a' * 65, 'g' * 64],
        'contact': [null, 5, '', ' ', 'a\nb', 'x' * 201],
      };
      bad.forEach((member, values) {
        for (final value in values) {
          expect(
            read({...good, member: value}),
            isNull,
            reason: '$member: $value',
          );
        }
      });
      for (final member in good.keys) {
        expect(read({...good}..remove(member)), isNull, reason: 'no $member');
      }
    });

    test('is refused when it is not an object, not JSON or too long', () {
      expect(parseIntakeArrivalNote('nope'), isNull);
      expect(parseIntakeArrivalNote('[]'), isNull);
      expect(read({...good, 'contact': 'x' * kIntakeMaxJsonBytes}), isNull);
    });

    test('takes a time to the second that exists, and nothing else', () {
      for (final ok in [
        '2026-10-04T00:00:00Z',
        '2026-10-04T23:59:59Z',
        '2028-02-29T12:00:00Z',
      ]) {
        expect(isValidIntakeTime(ok), isTrue, reason: ok);
      }
      for (final bad in [
        '2026-10-04T24:00:00Z',
        '2026-10-04T12:60:00Z',
        '2026-10-04T12:00:60Z',
        '2027-02-29T12:00:00Z',
        '2026-13-01T12:00:00Z',
        ' 2026-10-04T12:00:00Z',
        '2026-10-04T12:00:00Z\n',
        '2026-10-04t12:00:00z',
        '',
      ]) {
        expect(isValidIntakeTime(bad), isFalse, reason: bad);
      }
    });
  });

  group('refusals (§6.3)', () {
    test('each has its own wire name and a status the protocol uses', () {
      final wires = IntakeErrorCode.values.map((c) => c.wire).toList();
      expect(wires.toSet(), hasLength(wires.length));
      for (final code in IntakeErrorCode.values) {
        expect(code.wire, matches(RegExp(r'^[a-z]+(-[a-z]+)*$')));
        expect(code.status, inInclusiveRange(400, 599));
        expect(IntakeErrorCode.fromWire(code.wire), code);
      }
    });

    test('the statuses the design names are the ones used', () {
      expect(IntakeErrorCode.submissionConflict.status, 409);
      expect(IntakeErrorCode.tooLarge.status, 413);
      expect(IntakeErrorCode.lengthRequired.status, 411);
      expect(IntakeErrorCode.rateLimited.status, 429);
      expect(IntakeErrorCode.inviteInvalid.status, 401);
      expect(IntakeErrorCode.signatureInvalid.status, 401);
      expect(IntakeErrorCode.requestExpired.status, 401);
      expect(IntakeErrorCode.requestReplayed.status, 401);
      expect(IntakeErrorCode.notAllowed.status, 403);
      expect(IntakeErrorCode.formClosed.status, 403);
      expect(IntakeErrorCode.notFound.status, 404);
      expect(IntakeErrorCode.methodNotAllowed.status, 405);
      expect(IntakeErrorCode.formUnknown.status, 404);
      expect(IntakeErrorCode.submissionUnknown.status, 404);
      expect(IntakeErrorCode.bundleRollback.status, 409);
      expect(IntakeErrorCode.bundleInvalid.status, 422);
      expect(IntakeErrorCode.bundleHostMismatch.status, 422);
      expect(IntakeErrorCode.badRequest.status, 400);
      expect(IntakeErrorCode.serverError.status, 500);
      expect(IntakeErrorCode.unavailable.status, 503);
    });

    test('a code this version does not know is not one', () {
      expect(IntakeErrorCode.fromWire('teapot'), isNull);
      expect(IntakeErrorCode.fromWire(''), isNull);
      expect(IntakeErrorCode.fromWire('FORM-CLOSED'), isNull);
    });

    test('a bare status stands for the first code that has it', () {
      expect(IntakeErrorCode.forStatus(401), IntakeErrorCode.inviteInvalid);
      expect(IntakeErrorCode.forStatus(403), IntakeErrorCode.notAllowed);
      expect(IntakeErrorCode.forStatus(404), IntakeErrorCode.notFound);
      expect(IntakeErrorCode.forStatus(405), IntakeErrorCode.methodNotAllowed);
      expect(
        IntakeErrorCode.forStatus(409),
        IntakeErrorCode.submissionConflict,
      );
      expect(IntakeErrorCode.forStatus(413), IntakeErrorCode.tooLarge);
      expect(IntakeErrorCode.forStatus(429), IntakeErrorCode.rateLimited);
      expect(IntakeErrorCode.forStatus(503), IntakeErrorCode.unavailable);
    });

    test(
      'a status nobody named is a server error from 500 up and a bad request below',
      () {
        expect(IntakeErrorCode.forStatus(501), IntakeErrorCode.serverError);
        expect(IntakeErrorCode.forStatus(502), IntakeErrorCode.serverError);
        expect(IntakeErrorCode.forStatus(599), IntakeErrorCode.serverError);
        expect(IntakeErrorCode.forStatus(418), IntakeErrorCode.badRequest);
        expect(IntakeErrorCode.forStatus(499), IntakeErrorCode.badRequest);
        expect(IntakeErrorCode.forStatus(302), IntakeErrorCode.badRequest);
      },
    );

    test('is read from a body, with the server\'s sentence', () {
      const e = IntakeError(IntakeErrorCode.formClosed, 'The form closed.');
      final read = parseIntakeError(403, e.toJsonText());
      expect(read.code, IntakeErrorCode.formClosed);
      expect(read.message, 'The form closed.');
      expect(jsonDecode(e.toJsonText()), {
        'error': {'code': 'form-closed', 'message': 'The form closed.'},
      });
    });

    test('the code in the body wins over the status', () {
      final read = parseIntakeError(
        403,
        const IntakeError(IntakeErrorCode.tooLarge, 'x').toJsonText(),
      );
      expect(read.code, IntakeErrorCode.tooLarge);
    });

    test(
      'a body that is not ours still gives the error its status stands for',
      () {
        final html = parseIntakeError(502, '<html>Bad gateway</html>');
        expect(html.code, IntakeErrorCode.serverError);
        expect(html.message, '');
        expect(parseIntakeError(404, '').code, IntakeErrorCode.notFound);
        expect(parseIntakeError(429, '[]').code, IntakeErrorCode.rateLimited);
        expect(
          parseIntakeError(429, '{"error":5}').code,
          IntakeErrorCode.rateLimited,
        );
        expect(parseIntakeError(429, '{}').code, IntakeErrorCode.rateLimited);
      },
    );

    test(
      'a code from a newer server falls back to the status, keeping the sentence',
      () {
        final read = parseIntakeError(
          403,
          '{"error":{"code":"quota-spent","message":"Used up."}}',
        );
        expect(read.code, IntakeErrorCode.notAllowed);
        expect(read.message, 'Used up.');
      },
    );

    test('a sentence that is not text, or too long, is dropped', () {
      expect(
        parseIntakeError(
          400,
          '{"error":{"code":"bad-request","message":5}}',
        ).message,
        '',
      );
      expect(
        parseIntakeError(
          400,
          jsonEncode({
            'error': {'code': 'bad-request', 'message': 'x' * 501},
          }),
        ).message,
        '',
      );
      expect(
        parseIntakeError(
          400,
          jsonEncode({
            'error': {'code': 'bad-request', 'message': 'x' * 500},
          }),
        ).message,
        hasLength(500),
      );
    });
  });
}
