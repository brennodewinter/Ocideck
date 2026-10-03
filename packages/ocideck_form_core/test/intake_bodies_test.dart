import 'dart:convert';

import 'package:ocideck_form_core/ocideck_form_core.dart';
import 'package:test/test.dart';

const String _fid = 'mfrggzdfmztwq2lknnwg23tpoa';
const String _sid = 'nvqwy3dpoixxg5dfonzgc3tjnq';
const String _kid = 'oruw2zlnmvzxi33sovzwk43fnz';
final String _secret = 'ma' * 26;

Map<String, Object?> _variant([String template = '# Form\n']) => {
  'bundle': {'v': 1, 'fid': _fid, 'sig': 'x'},
  'template': template,
};

String _form({
  Object? state = 'open',
  Object? variants,
  bool noState = false,
}) => jsonEncode({
  if (!noState) 'state': state,
  'variants': variants ?? [_variant()],
});

IntakeFormIssue? _issue(IntakeFormResult r) =>
    r is IntakeFormRefused ? r.issue : null;

void main() {
  group('a form as a server serves it', () {
    test('is read: its state, and each template with its bundle', () {
      final r = parseIntakeFormResponse(
        _form(state: 'closed', variants: [_variant('a'), _variant('b')]),
      );
      expect(r, isA<IntakeFormRead>());
      final form = (r as IntakeFormRead).form;
      expect(form.state, IntakeFormState.closed);
      expect(form.variants.map((v) => v.template), ['a', 'b']);
      expect(form.variants.first.bundle['fid'], _fid);
      expect(
        jsonDecode(form.variants.first.bundleText),
        form.variants.first.bundle,
      );
    });

    test('is written and read back', () {
      final form = (parseIntakeFormResponse(_form()) as IntakeFormRead).form;
      final again =
          (parseIntakeFormResponse(form.toJsonText()) as IntakeFormRead).form;
      expect(again.state, IntakeFormState.open);
      expect(again.variants.single.template, '# Form\n');
      expect(again.variants.single.bundle, form.variants.single.bundle);
    });

    test('keeps a template exactly, line endings and all', () {
      const t = '# A\r\n\r\nB C\n';
      final form =
          (parseIntakeFormResponse(_form(variants: [_variant(t)]))
                  as IntakeFormRead)
              .form;
      expect(form.variants.single.template, t);
    });

    test('ignores a member it does not know, in the form and in a variant', () {
      final text = jsonEncode({
        'state': 'open',
        'banner': 'hello',
        'variants': [
          {..._variant(), 'lang': 'nl'},
        ],
      });
      expect(parseIntakeFormResponse(text), isA<IntakeFormRead>());
    });

    test('has to say its state', () {
      expect(
        _issue(parseIntakeFormResponse(_form(noState: true))),
        IntakeFormIssue.badState,
      );
      for (final bad in [null, 5, 'OPEN', 'opened', '', true]) {
        expect(
          _issue(parseIntakeFormResponse(_form(state: bad))),
          IntakeFormIssue.badState,
          reason: '$bad',
        );
      }
    });

    test('has between one and 32 variants', () {
      for (final bad in [null, 'x', 5, <Object?>[], <String, Object?>{}]) {
        final text = jsonEncode({'state': 'open', 'variants': ?bad});
        expect(
          _issue(parseIntakeFormResponse(text)),
          IntakeFormIssue.noVariants,
          reason: '$bad',
        );
      }
      final ok = List.generate(32, (_) => _variant());
      expect(
        parseIntakeFormResponse(_form(variants: ok)),
        isA<IntakeFormRead>(),
      );
      expect(
        _issue(parseIntakeFormResponse(_form(variants: [...ok, _variant()]))),
        IntakeFormIssue.tooManyVariants,
      );
      expect(kIntakeMaxVariants, 32);
    });

    test(
      'refuses a variant that is not {bundle, template}, and says which',
      () {
        final bads = <Object?>[
          5,
          'x',
          null,
          <Object?>[],
          {'template': 't'},
          {'bundle': <String, Object?>{}},
          {'bundle': 'x', 'template': 't'},
          {'bundle': <Object?>[], 'template': 't'},
          {'bundle': <String, Object?>{}, 'template': 5},
          {'bundle': <String, Object?>{}, 'template': null},
        ];
        for (final bad in bads) {
          final r = parseIntakeFormResponse(_form(variants: [_variant(), bad]));
          expect(r, isA<IntakeFormRefused>(), reason: '$bad');
          r as IntakeFormRefused;
          expect(r.issue, IntakeFormIssue.badVariant, reason: '$bad');
          expect(r.index, 1, reason: '$bad');
        }
      },
    );

    test('takes a bundle of exactly 256 KiB and no more', () {
      Map<String, Object?> sized(int bytes) {
        final empty = utf8.encode(jsonEncode({'pad': ''})).length;
        return {
          'bundle': {'pad': 'x' * (bytes - empty)},
          'template': 't',
        };
      }

      expect(
        parseIntakeFormResponse(_form(variants: [sized(256 * 1024)])),
        isA<IntakeFormRead>(),
      );
      expect(
        _issue(
          parseIntakeFormResponse(_form(variants: [sized(256 * 1024 + 1)])),
        ),
        IntakeFormIssue.badVariant,
      );
    });

    test(
      'takes a template of exactly 1 MiB, counted in bytes, and no more',
      () {
        expect(
          parseIntakeFormResponse(
            _form(variants: [_variant('x' * (1024 * 1024))]),
          ),
          isA<IntakeFormRead>(),
        );
        final over = parseIntakeFormResponse(
          _form(variants: [_variant(), _variant('x' * (1024 * 1024 + 1))]),
        );
        expect(_issue(over), IntakeFormIssue.templateTooLarge);
        expect((over as IntakeFormRefused).index, 1);
        // Two bytes a character: 512 Ki characters fill it, one more does not.
        expect(
          parseIntakeFormResponse(
            _form(variants: [_variant('é' * (512 * 1024))]),
          ),
          isA<IntakeFormRead>(),
        );
        expect(
          _issue(
            parseIntakeFormResponse(
              _form(variants: [_variant('é' * (512 * 1024 + 1))]),
            ),
          ),
          IntakeFormIssue.templateTooLarge,
        );
        expect(kIntakeMaxTemplateBytes, 1048576);
      },
    );

    test('takes a document of exactly 8 MiB and no more', () {
      String padded(int bytes) {
        final empty = utf8
            .encode(
              jsonEncode({
                'state': 'open',
                'variants': [_variant()],
                'pad': '',
              }),
            )
            .length;
        return jsonEncode({
          'state': 'open',
          'variants': [_variant()],
          'pad': 'x' * (bytes - empty),
        });
      }

      const eight = 8 * 1024 * 1024;
      expect(utf8.encode(padded(eight)), hasLength(eight));
      expect(parseIntakeFormResponse(padded(eight)), isA<IntakeFormRead>());
      expect(
        _issue(parseIntakeFormResponse(padded(eight + 1))),
        IntakeFormIssue.notAForm,
      );
      expect(kIntakeMaxFormBytes, eight);
    });

    test('is not a form when it is not JSON, not an object', () {
      for (final bad in ['nope', '[]', '"x"', '5', '']) {
        expect(
          _issue(parseIntakeFormResponse(bad)),
          IntakeFormIssue.notAForm,
          reason: bad,
        );
      }
    });
  });

  group('a publication as the server reads it', () {
    test('may leave the state out: open', () {
      final r = parseIntakePublication(_form(noState: true));
      expect((r as IntakeFormRead).form.state, IntakeFormState.open);
    });

    test('reads a state when it is given', () {
      final r = parseIntakePublication(_form(state: 'closed'));
      expect((r as IntakeFormRead).form.state, IntakeFormState.closed);
      expect(
        _issue(parseIntakePublication(_form(state: 'shut'))),
        IntakeFormIssue.badState,
      );
      expect(
        _issue(parseIntakePublication(_form(state: null))),
        IntakeFormIssue.badState,
      );
    });

    test('refuses a member it does not know, in the body and in a variant', () {
      expect(
        _issue(
          parseIntakePublication(
            jsonEncode({
              'variants': [_variant()],
              'extra': 1,
            }),
          ),
        ),
        IntakeFormIssue.unknownMember,
      );
      final r = parseIntakePublication(
        _form(
          variants: [
            {..._variant(), 'lang': 'nl'},
          ],
        ),
      );
      expect(_issue(r), IntakeFormIssue.badVariant);
      expect((r as IntakeFormRefused).index, 0);
    });

    test('is judged like a response in everything else', () {
      expect(
        _issue(parseIntakePublication(_form(variants: []))),
        IntakeFormIssue.noVariants,
      );
      expect(
        _issue(
          parseIntakePublication(
            _form(variants: [_variant('x' * (1024 * 1024 + 1))]),
          ),
        ),
        IntakeFormIssue.templateTooLarge,
      );
      expect(_issue(parseIntakePublication('nope')), IntakeFormIssue.notAForm);
    });

    test('is written with its state and read back', () {
      const form = IntakeForm(
        state: IntakeFormState.closed,
        variants: [
          IntakeVariant(bundle: {'v': 1}, template: 't'),
        ],
      );
      final back =
          (parseIntakePublication(form.toJsonText()) as IntakeFormRead).form;
      expect(back.state, IntakeFormState.closed);
      expect(back.variants.single.template, 't');
      expect(IntakeFormState.fromWire('open'), IntakeFormState.open);
      expect(IntakeFormState.fromWire('closed'), IntakeFormState.closed);
      expect(IntakeFormState.fromWire('Open'), isNull);
    });
  });

  group('the result of publishing', () {
    test('is read and written back', () {
      const r = IntakePublishResult(fid: _fid, variants: 2, bundleSeq: 5);
      final back = parseIntakePublishResult(r.toJsonText())!;
      expect(back.fid, _fid);
      expect(back.variants, 2);
      expect(back.bundleSeq, 5);
    });

    test('is refused outside its grammar', () {
      Map<String, Object?> ok() => {
        'fid': _fid,
        'variants': 2,
        'bundle_seq': 5,
      };
      expect(parseIntakePublishResult(jsonEncode(ok())), isNotNull);
      final bad = <String, List<Object?>>{
        'fid': [null, 5, 'x', _fid.toUpperCase()],
        'variants': [null, '2', 0, -1, 33, 1.5],
        'bundle_seq': [null, '5', 0, -1, 1.5],
      };
      bad.forEach((member, values) {
        for (final v in values) {
          expect(
            parseIntakePublishResult(jsonEncode({...ok(), member: v})),
            isNull,
            reason: '$member $v',
          );
        }
      });
      expect(
        parseIntakePublishResult(jsonEncode({...ok(), 'variants': 1})),
        isNotNull,
      );
      expect(
        parseIntakePublishResult(jsonEncode({...ok(), 'variants': 32})),
        isNotNull,
      );
      expect(
        parseIntakePublishResult(jsonEncode({...ok(), 'bundle_seq': 1})),
        isNotNull,
      );
      expect(parseIntakePublishResult('nope'), isNull);
    });
  });

  group('the open token', () {
    final hash = 'a1' * 32;

    test('a request carries a hash, or null to revoke', () {
      expect(
        parseIntakeTokenRequest('{"token_sha256":"$hash"}')!.tokenSha256,
        hash,
      );
      expect(
        parseIntakeTokenRequest('{"token_sha256":null}')!.tokenSha256,
        isNull,
      );
      expect(IntakeTokenRequest(hash).toJsonText(), '{"token_sha256":"$hash"}');
      expect(
        const IntakeTokenRequest(null).toJsonText(),
        '{"token_sha256":null}',
      );
    });

    test('a request is the member and nothing else', () {
      for (final bad in [
        '{}',
        '{"token_sha256":"$hash","x":1}',
        '{"x":"$hash"}',
        '{"token_sha256":5}',
        '{"token_sha256":"${hash.toUpperCase()}"}',
        '{"token_sha256":"${hash.substring(1)}"}',
        '{"token_sha256":"${hash}0"}',
        '{"token_sha256":"${'g' * 64}"}',
        '[]',
        'nope',
      ]) {
        expect(parseIntakeTokenRequest(bad), isNull, reason: bad);
      }
    });

    test('the answer says whether a token is set', () {
      expect(parseIntakeTokenResult('{"token_set":true}')!.tokenSet, isTrue);
      expect(parseIntakeTokenResult('{"token_set":false}')!.tokenSet, isFalse);
      expect(
        const IntakeTokenResult(tokenSet: true).toJsonText(),
        '{"token_set":true}',
      );
      for (final bad in [
        '{}',
        '{"token_set":1}',
        '{"token_set":"true"}',
        '[]',
        'x',
      ]) {
        expect(parseIntakeTokenResult(bad), isNull, reason: bad);
      }
    });
  });

  group('withdrawing', () {
    test('a request carries the secret', () {
      final text = IntakeWithdrawRequest(_secret).toJsonText();
      expect(text, '{"secret":"$_secret"}');
      expect(parseIntakeWithdrawRequest(text)!.secret, _secret);
    });

    test('a request is the secret in its grammar and nothing else', () {
      for (final bad in [
        '{}',
        '{"secret":"$_secret","x":1}',
        '{"secret":5}',
        '{"secret":"${_secret.substring(1)}"}',
        '{"secret":"${_secret.toUpperCase()}"}',
        '{"secret":"${_secret.substring(0, 51)}b"}',
        '[]',
        'nope',
      ]) {
        expect(parseIntakeWithdrawRequest(bad), isNull, reason: bad);
      }
    });

    test('the answer is read and written back', () {
      const r = IntakeWithdrawResult(
        sid: _sid,
        at: '2026-10-05T18:02:44Z',
        deleted: true,
      );
      final back = parseIntakeWithdrawResult(r.toJsonText())!;
      expect(back.sid, _sid);
      expect(back.at, '2026-10-05T18:02:44Z');
      expect(back.deleted, isTrue);
      expect(
        parseIntakeWithdrawResult(
          '{"sid":"$_sid","at":"2026-10-05T18:02:44Z","deleted":false}',
        )!.deleted,
        isFalse,
      );
    });

    test('the answer is refused outside its grammar', () {
      Map<String, Object?> ok() => {
        'sid': _sid,
        'at': '2026-10-05T18:02:44Z',
        'deleted': true,
      };
      final bad = <String, List<Object?>>{
        'sid': [null, 5, 'x'],
        'at': [null, 5, '2026-10-05', '2026-10-05T24:00:00Z'],
        'deleted': [null, 1, 'true'],
      };
      bad.forEach((member, values) {
        for (final v in values) {
          expect(
            parseIntakeWithdrawResult(jsonEncode({...ok(), member: v})),
            isNull,
            reason: '$member $v',
          );
        }
      });
      expect(parseIntakeWithdrawResult('nope'), isNull);
    });
  });

  group('the paging cursor', () {
    test('is opaque, 1 to 64 characters of letters, digits, _ and -', () {
      for (final ok in ['a', 'A_-9', 'x' * 64]) {
        expect(isValidIntakeCursor(ok), isTrue, reason: ok);
      }
      for (final bad in ['', 'x' * 65, 'a b', 'a.b', 'a/b', 'a=', 'é', 'a\n']) {
        expect(isValidIntakeCursor(bad), isFalse, reason: bad);
      }
    });
  });

  group('a page of the listing', () {
    final hash = 'ab' * 32;
    Map<String, Object?> held({
      Object? acked = const [],
      Object? bytes = 1840221,
    }) => {
      'sid': _sid,
      'at': '2026-10-04T09:30:12Z',
      'bytes': bytes,
      'ciphertext_sha256': hash,
      'acked_by': acked,
    };
    String page(List<Object?> items, [Object? next]) =>
        jsonEncode({'items': items, 'next': next});

    test('is read: held submissions and tombstones', () {
      final p = parseIntakeSubmissionPage(
        page([
          held(acked: [_kid]),
          {'sid': _fid, 'at': '2026-10-05T18:02:44Z', 'withdrawn': true},
        ], 'abc_-'),
      )!;
      expect(p.next, 'abc_-');
      expect(p.items, hasLength(2));
      final a = p.items[0];
      expect(a.withdrawn, isFalse);
      expect(a.sid, _sid);
      expect(a.at, '2026-10-04T09:30:12Z');
      expect(a.bytes, 1840221);
      expect(a.ciphertextSha256, hash);
      expect(a.ackedBy, [_kid]);
      final b = p.items[1];
      expect(b.withdrawn, isTrue);
      expect(b.sid, _fid);
      expect(b.bytes, isNull);
      expect(b.ciphertextSha256, isNull);
      expect(b.ackedBy, isEmpty);
    });

    test('is written and read back', () {
      final p = IntakeSubmissionPage(
        items: [
          IntakeListedSubmission.held(
            sid: _sid,
            at: '2026-10-04T09:30:12Z',
            bytes: 5,
            ciphertextSha256: hash,
            ackedBy: const [_kid],
          ),
          const IntakeListedSubmission.withdrawn(
            sid: _fid,
            at: '2026-10-05T18:02:44Z',
          ),
        ],
        next: 'c1',
      );
      final back = parseIntakeSubmissionPage(p.toJsonText())!;
      expect(back.next, 'c1');
      expect(back.items[0].ackedBy, [_kid]);
      expect(back.items[0].bytes, 5);
      expect(back.items[1].withdrawn, isTrue);
      expect(jsonDecode(p.toJsonText()), {
        'items': [
          {
            'sid': _sid,
            'at': '2026-10-04T09:30:12Z',
            'bytes': 5,
            'ciphertext_sha256': hash,
            'acked_by': [_kid],
          },
          {'sid': _fid, 'at': '2026-10-05T18:02:44Z', 'withdrawn': true},
        ],
        'next': 'c1',
      });
    });

    test('the last page has no next, and an empty one is a page', () {
      expect(parseIntakeSubmissionPage(page([], null))!.next, isNull);
      expect(parseIntakeSubmissionPage(page([]))!.items, isEmpty);
      expect(parseIntakeSubmissionPage('{"items":[]}')!.next, isNull);
    });

    test('a cursor outside its grammar spoils the page', () {
      for (final bad in ['', 'a b', 'x' * 65, 5, true]) {
        expect(
          parseIntakeSubmissionPage(page([], bad)),
          isNull,
          reason: '$bad',
        );
      }
    });

    test('holds at most 100 items', () {
      expect(
        parseIntakeSubmissionPage(page(List.filled(100, held()))),
        isNotNull,
      );
      expect(parseIntakeSubmissionPage(page(List.filled(101, held()))), isNull);
      expect(kIntakeMaxPageItems, 100);
      expect(kIntakeDefaultPageItems, 50);
    });

    test('one bad line spoils the whole page', () {
      final bads = <Object?>[
        5,
        'x',
        null,
        {...held(), 'sid': 'x'},
        {...held(), 'sid': null},
        {...held(), 'at': '2026-10-04'},
        {...held(), 'at': null},
        {...held(), 'bytes': 0},
        {...held(), 'bytes': -1},
        {...held(), 'bytes': '5'},
        {...held(), 'bytes': 1.5},
        {...held(), 'bytes': null},
        {...held(), 'ciphertext_sha256': 'AB' * 32},
        {...held(), 'ciphertext_sha256': 'ab' * 31},
        {...held(), 'ciphertext_sha256': null},
        {...held(), 'acked_by': null},
        {...held(), 'acked_by': 'x'},
        {
          ...held(),
          'acked_by': ['x'],
        },
        {
          ...held(),
          'acked_by': [5],
        },
        {
          ...held(),
          'acked_by': [_kid, _kid],
        },
        {...held(), 'withdrawn': false, 'bytes': null},
        {'sid': _sid, 'at': '2026-10-04T09:30:12Z', 'withdrawn': 'yes'},
        {'sid': 'x', 'at': '2026-10-04T09:30:12Z', 'withdrawn': true},
        {'sid': _sid, 'at': 'x', 'withdrawn': true},
      ];
      for (final bad in bads) {
        expect(
          parseIntakeSubmissionPage(page([held(), bad])),
          isNull,
          reason: '$bad',
        );
      }
    });

    test('a held submission is at least one byte', () {
      expect(
        parseIntakeSubmissionPage(page([held(bytes: 1)]))!.items.single.bytes,
        1,
      );
      expect(
        parseIntakeSubmissionPage(page([held(bytes: 2)]))!.items.single.bytes,
        2,
      );
    });

    test('a line may name up to 64 organisers', () {
      // 64 distinct key ids of 26 characters of the base32 alphabet.
      final sixtyFour = [
        for (var i = 0; i < 64; i++)
          '${String.fromCharCode(97 + i ~/ 26)}${String.fromCharCode(97 + i % 26)}${'a' * 24}',
      ];
      expect(sixtyFour.toSet(), hasLength(64));
      expect(
        parseIntakeSubmissionPage(page([held(acked: sixtyFour)])),
        isNotNull,
      );
      expect(
        parseIntakeSubmissionPage(
          page([
            held(acked: [...sixtyFour, 'zz${'a' * 24}']),
          ]),
        ),
        isNull,
      );
    });

    test(
      'is not a page when it is not JSON, not an object or has no items',
      () {
        for (final bad in [
          'nope',
          '[]',
          '{}',
          '{"items":5}',
          '{"items":null}',
        ]) {
          expect(parseIntakeSubmissionPage(bad), isNull, reason: bad);
        }
      },
    );

    test('ignores a member it does not know', () {
      final text = jsonEncode({
        'items': [
          {...held(), 'note': 'x'},
        ],
        'next': null,
        'total': 1,
      });
      expect(parseIntakeSubmissionPage(text), isNotNull);
    });

    test('takes a document of exactly 1 MiB and no more', () {
      String padded(int bytes) {
        final empty = utf8
            .encode(jsonEncode({'items': <Object?>[], 'next': null, 'pad': ''}))
            .length;
        return jsonEncode({
          'items': <Object?>[],
          'next': null,
          'pad': 'x' * (bytes - empty),
        });
      }

      expect(parseIntakeSubmissionPage(padded(1024 * 1024)), isNotNull);
      expect(parseIntakeSubmissionPage(padded(1024 * 1024 + 1)), isNull);
    });
  });

  group('acknowledging', () {
    test('the answer is read and written back', () {
      final text = const IntakeAckResult(
        ackedBy: [_kid],
        purged: false,
      ).toJsonText();
      expect(text, '{"acked_by":["$_kid"],"purged":false}');
      final back = parseIntakeAckResult(text)!;
      expect(back.ackedBy, [_kid]);
      expect(back.purged, isFalse);
      expect(
        parseIntakeAckResult('{"acked_by":[],"purged":true}')!.purged,
        isTrue,
      );
    });

    test('is refused outside its grammar', () {
      for (final bad in [
        '{}',
        '{"acked_by":[],"purged":1}',
        '{"acked_by":[],"purged":null}',
        '{"acked_by":null,"purged":true}',
        '{"acked_by":["x"],"purged":true}',
        '{"acked_by":["$_kid","$_kid"],"purged":true}',
        '[]',
        'nope',
      ]) {
        expect(parseIntakeAckResult(bad), isNull, reason: bad);
      }
    });
  });
}
