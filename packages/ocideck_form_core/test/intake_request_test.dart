import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:ocideck_form_core/ocideck_form_core.dart';
import 'package:test/test.dart';

const String _host = 'intake.example.org';
const String _nonce = 'mfrggzdfmztwq2lknnwg23tpoa';
const int _ts = 1790000000;

Future<FormSigningKey> _key([int salt = 1]) => formSigningKeyFromSeed(
  Uint8List.fromList(List.generate(32, (i) => i + salt)),
);

Future<String> _sign({
  FormSigningKey? key,
  String host = _host,
  String method = 'GET',
  String target = '/v1/forms/$_nonce/submissions?after=x',
  List<int> body = const [],
  int ts = _ts,
  String nonce = _nonce,
}) async => signIntakeRequest(
  key: key ?? await _key(),
  host: host,
  method: method,
  target: target,
  ts: ts,
  nonce: nonce,
  body: body,
);

Future<IntakeRequestVerdict> _verify(
  String? header, {
  String host = _host,
  String method = 'GET',
  String target = '/v1/forms/$_nonce/submissions?after=x',
  List<int> body = const [],
  int now = _ts,
}) => verifyIntakeRequest(
  header: header,
  host: host,
  method: method,
  target: target,
  bodySha256: sha256Hex(body),
  nowSeconds: now,
);

IntakeRequestIssue? _issue(IntakeRequestVerdict v) =>
    v is IntakeRequestRefused ? v.issue : null;

void main() {
  group('a signed request (§6.3)', () {
    test('verifies, and says whose key signed it', () async {
      final key = await _key();
      final v = await _verify(await _sign(key: key));
      expect(v, isA<IntakeRequestVerified>());
      v as IntakeRequestVerified;
      expect(v.signKey, key.publicKeyText);
      expect(v.ts, _ts);
      expect(v.nonce, _nonce);
    });

    test('is signed over the canonical JSON of seven things, tag first', () {
      expect(
        intakeRequestPreimage(
          host: _host,
          method: 'PUT',
          target: '/v1/x?a=1',
          bodySha256: kIntakeEmptyBodySha256,
          ts: 5,
          nonce: _nonce,
        ),
        '["ocideck-intake-req-v1","$_host","PUT","/v1/x?a=1",'
        '"${sha256Hex(const [])}",5,"$_nonce"]',
      );
      expect(kIntakeRequestTag, 'ocideck-intake-req-v1');
    });

    test('the hash of no body is the hash of nothing', () {
      expect(
        kIntakeEmptyBodySha256,
        'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855',
      );
    });

    test('the header has the shape the protocol document gives', () async {
      final header = await _sign();
      expect(
        header,
        matches(
          RegExp(
            r'^OciIntake key=[a-z2-7]{52}, ts=1790000000, '
            r'nonce=[a-z2-7]{26}, sig=[a-z2-7]{103}$',
          ),
        ),
      );
    });

    test(
      'is deterministic: the same request signs to the same header',
      () async {
        expect(await _sign(), await _sign());
      },
    );

    test('takes the method in any case', () async {
      final lower = await _sign(method: 'get');
      expect(lower, await _sign(method: 'GET'));
      expect(await _verify(lower), isA<IntakeRequestVerified>());
    });

    test('signs a body, and a changed body no longer verifies', () async {
      final body = utf8.encode('{"token_sha256":null}');
      final header = await _sign(method: 'PUT', body: body);
      expect(
        await _verify(header, method: 'PUT', body: body),
        isA<IntakeRequestVerified>(),
      );
      expect(
        _issue(
          await _verify(
            header,
            method: 'PUT',
            body: utf8.encode('{"token_sha256":""}'),
          ),
        ),
        IntakeRequestIssue.badSignature,
      );
      expect(
        _issue(await _verify(header, method: 'PUT')),
        IntakeRequestIssue.badSignature,
      );
    });

    group('is tied to what the server knows the request to be', () {
      late String header;
      setUp(() async => header = await _sign());

      test('the host', () async {
        expect(
          _issue(await _verify(header, host: 'other.example.org')),
          IntakeRequestIssue.badSignature,
        );
      });

      test('the method', () async {
        expect(
          _issue(await _verify(header, method: 'DELETE')),
          IntakeRequestIssue.badSignature,
        );
      });

      test('the path', () async {
        expect(
          _issue(
            await _verify(header, target: '/v1/forms/$_nonce/token?after=x'),
          ),
          IntakeRequestIssue.badSignature,
        );
      });

      test(
        'the query, so a paging cursor cannot be changed in flight',
        () async {
          expect(
            _issue(
              await _verify(
                header,
                target: '/v1/forms/$_nonce/submissions?after=y',
              ),
            ),
            IntakeRequestIssue.badSignature,
          );
          expect(
            _issue(
              await _verify(header, target: '/v1/forms/$_nonce/submissions'),
            ),
            IntakeRequestIssue.badSignature,
          );
        },
      );

      test('the time written in the header', () async {
        final moved = header.replaceFirst('ts=$_ts', 'ts=${_ts + 1}');
        expect(_issue(await _verify(moved)), IntakeRequestIssue.badSignature);
      });

      test('the nonce written in the header', () async {
        final moved = header.replaceFirst(
          'nonce=$_nonce',
          'nonce=nvqwy3dpoixxg5dfonzgc3tjnq',
        );
        expect(_issue(await _verify(moved)), IntakeRequestIssue.badSignature);
      });

      test('the key written in the header', () async {
        final other = (await _key(9)).publicKeyText;
        final key = (await _key()).publicKeyText;
        final swapped = header.replaceFirst('key=$key', 'key=$other');
        expect(_issue(await _verify(swapped)), IntakeRequestIssue.badSignature);
      });

      test('the signature itself, in any one character', () async {
        final at = header.indexOf('sig=') + 4;
        for (final i in [0, 50, 100]) {
          final c = header[at + i] == 'a' ? 'b' : 'a';
          final bent = header.replaceRange(at + i, at + i + 1, c);
          final v = await _verify(bent);
          // A change in the last character can leave non-zero padding bits: malformed.
          expect(
            _issue(v),
            isIn([
              IntakeRequestIssue.badSignature,
              IntakeRequestIssue.malformed,
            ]),
          );
        }
      });
    });

    group('is read strictly', () {
      late String header;
      late Map<String, String> parts;
      setUp(() async {
        header = await _sign();
        parts = {
          for (final p in header.substring('OciIntake '.length).split(', '))
            p.split('=')[0]: p.split('=')[1],
        };
      });

      String build(
        Map<String, String> m, {
        String sep = ', ',
        String scheme = 'OciIntake',
      }) => '$scheme ${m.entries.map((e) => '${e.key}=${e.value}').join(sep)}';

      test('no header at all', () async {
        expect(_issue(await _verify(null)), IntakeRequestIssue.malformed);
        expect(_issue(await _verify('')), IntakeRequestIssue.malformed);
      });

      test('another scheme', () async {
        expect(
          _issue(await _verify('Bearer abc')),
          IntakeRequestIssue.malformed,
        );
        expect(
          _issue(await _verify(build(parts, scheme: 'ociintake'))),
          IntakeRequestIssue.malformed,
        );
        expect(
          _issue(await _verify('OciIntake')),
          IntakeRequestIssue.malformed,
        );
      });

      for (final name in ['key', 'ts', 'nonce', 'sig']) {
        test('without $name', () async {
          expect(
            _issue(await _verify(build({...parts}..remove(name)))),
            IntakeRequestIssue.malformed,
          );
        });
      }

      test(
        'with a member it does not know, in place of one or beside them',
        () async {
          expect(
            _issue(await _verify(build({...parts, 'extra': 'x'}))),
            IntakeRequestIssue.malformed,
          );
          final renamed = {...parts}..remove('nonce');
          expect(
            _issue(
              await _verify(build({...renamed, 'nonse': parts['nonce']!})),
            ),
            IntakeRequestIssue.malformed,
          );
        },
      );

      test('with a member twice', () async {
        expect(
          _issue(await _verify('$header, ts=${_ts + 1}')),
          IntakeRequestIssue.malformed,
        );
      });

      test('a part with no equals sign', () async {
        expect(
          _issue(await _verify('$header, flag')),
          IntakeRequestIssue.malformed,
        );
      });

      test(
        'takes the members in any order, and with or without blanks',
        () async {
          final reversed = Map.fromEntries(parts.entries.toList().reversed);
          expect(await _verify(build(reversed)), isA<IntakeRequestVerified>());
          expect(
            await _verify(build(parts, sep: ',')),
            isA<IntakeRequestVerified>(),
          );
          expect(
            await _verify(build(parts, sep: ' ,  ')),
            isA<IntakeRequestVerified>(),
          );
        },
      );

      test('a key that is not 32 bytes of canonical base32', () async {
        for (final bad in [
          '',
          parts['key']!.substring(1),
          '${parts['key']}a',
          parts['key']!.toUpperCase(),
          '${parts['key']!.substring(0, 51)}b',
          '1' * 52,
        ]) {
          expect(
            _issue(await _verify(build({...parts, 'key': bad}))),
            IntakeRequestIssue.malformed,
            reason: bad,
          );
        }
      });

      test('a signature that is not 64 bytes of canonical base32', () async {
        for (final bad in [
          '',
          parts['sig']!.substring(1),
          '${parts['sig']}a',
          '1' * 103,
        ]) {
          expect(
            _issue(await _verify(build({...parts, 'sig': bad}))),
            IntakeRequestIssue.malformed,
            reason: bad,
          );
        }
      });

      test('a time that is not whole seconds written plainly', () async {
        for (final bad in [
          '',
          '0',
          '01790000000',
          '-1',
          '1.5',
          '1e9',

          '1' * 13,
          'x',
        ]) {
          expect(
            _issue(await _verify(build({...parts, 'ts': bad}))),
            IntakeRequestIssue.malformed,
            reason: bad,
          );
        }
      });

      test('a nonce that is not an id', () async {
        for (final bad in [
          '',
          _nonce.substring(1),
          _nonce.toUpperCase(),
          '$_nonce$_nonce',
        ]) {
          expect(
            _issue(await _verify(build({...parts, 'nonce': bad}))),
            IntakeRequestIssue.malformed,
            reason: bad,
          );
        }
      });
    });

    group('has a window of five minutes either way', () {
      test('inside it, to the second', () async {
        final header = await _sign();
        expect(
          await _verify(header, now: _ts + 300),
          isA<IntakeRequestVerified>(),
        );
        expect(
          await _verify(header, now: _ts - 300),
          isA<IntakeRequestVerified>(),
        );
      });

      test('outside it, a second later', () async {
        final header = await _sign();
        expect(
          _issue(await _verify(header, now: _ts + 301)),
          IntakeRequestIssue.expired,
        );
        expect(
          _issue(await _verify(header, now: _ts - 301)),
          IntakeRequestIssue.expired,
        );
      });

      test('the window is five minutes', () {
        expect(kIntakeRequestWindow, const Duration(minutes: 5));
      });

      test(
        'a stale request is expired before its signature is looked at',
        () async {
          final header = await _sign();
          final bent = header.replaceFirst('sig=', 'sig=b');
          // One character longer: malformed. Stale and badly signed: expired, the cheaper verdict.
          expect(
            _issue(await _verify(bent, now: _ts + 1000)),
            IntakeRequestIssue.malformed,
          );
          final other = await _sign(key: await _key(9));
          final swapped = header.replaceFirst(
            RegExp(r'sig=\S+'),
            'sig=${other.split('sig=')[1]}',
          );
          expect(
            _issue(await _verify(swapped, now: _ts + 1000)),
            IntakeRequestIssue.expired,
          );
          expect(
            _issue(await _verify(swapped)),
            IntakeRequestIssue.badSignature,
          );
        },
      );
    });

    test('another organiser\'s key does not verify as this one', () async {
      final mine = await _key();
      final theirs = await _key(9);
      final header = await _sign(key: theirs);
      final v = await _verify(header) as IntakeRequestVerified;
      expect(v.signKey, theirs.publicKeyText);
      expect(v.signKey, isNot(mine.publicKeyText));
    });

    test('a nonce is a fresh id', () {
      final a = newIntakeNonce(Random(1));
      expect(isValidFormId(a), isTrue);
      expect(a, isNot(newIntakeNonce(Random(2))));
    });
  });

  group('the nonce cache', () {
    IntakeNonceVerdict take(
      IntakeNonceCache cache, {
      String key = 'k',
      String nonce = 'n',
      int ts = 1000,
      int now = 1000,
    }) => cache.accept(signKey: key, nonce: nonce, ts: ts, nowSeconds: now);

    test('lets a nonce through once', () {
      final cache = IntakeNonceCache();
      expect(take(cache), IntakeNonceVerdict.accepted);
      expect(take(cache), IntakeNonceVerdict.replayed);
      expect(cache.length, 1);
    });

    test('is per key: another organiser may use the same nonce', () {
      final cache = IntakeNonceCache();
      expect(take(cache, key: 'a'), IntakeNonceVerdict.accepted);
      expect(take(cache, key: 'b'), IntakeNonceVerdict.accepted);
      expect(take(cache, key: 'a'), IntakeNonceVerdict.replayed);
    });

    test('is per nonce', () {
      final cache = IntakeNonceCache();
      expect(take(cache, nonce: 'a'), IntakeNonceVerdict.accepted);
      expect(take(cache, nonce: 'b'), IntakeNonceVerdict.accepted);
    });

    test('keeps a nonce exactly as long as its request could still verify', () {
      final cache = IntakeNonceCache();
      expect(take(cache), IntakeNonceVerdict.accepted);
      // ts 1000 verifies until now = 1300: still held at 1300, forgotten at 1301.
      expect(take(cache, now: 1300), IntakeNonceVerdict.replayed);
      expect(take(cache, now: 1301), IntakeNonceVerdict.accepted);
    });

    test('forgets the old to make room for the new', () {
      final cache = IntakeNonceCache();
      for (var i = 0; i < 5; i++) {
        take(cache, nonce: 'n$i');
      }
      expect(cache.length, 5);
      take(cache, nonce: 'later', ts: 5000, now: 5000);
      expect(cache.length, 1);
    });

    test('says it is full rather than forget a nonce that still counts', () {
      final cache = IntakeNonceCache(maxEntries: 2);
      expect(take(cache, nonce: 'a'), IntakeNonceVerdict.accepted);
      expect(take(cache, nonce: 'b'), IntakeNonceVerdict.accepted);
      expect(take(cache, nonce: 'c'), IntakeNonceVerdict.full);
      expect(cache.length, 2);
      // A replay is still a replay when the cache is full.
      expect(take(cache, nonce: 'a'), IntakeNonceVerdict.replayed);
      // Room appears when the window moves on.
      expect(
        take(cache, nonce: 'c', ts: 2000, now: 2000),
        IntakeNonceVerdict.accepted,
      );
    });

    test('holds as many as it says', () {
      final cache = IntakeNonceCache(maxEntries: 3);
      for (var i = 0; i < 3; i++) {
        expect(take(cache, nonce: 'n$i'), IntakeNonceVerdict.accepted);
      }
      expect(take(cache, nonce: 'n3'), IntakeNonceVerdict.full);
      expect(IntakeNonceCache().maxEntries, 50000);
    });
  });
}
