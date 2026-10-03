// The bundle (FORM_INTAKE.md §5.1): signed by the owner, checked against a fingerprint
// that came by another road, bound to its template, fresh, and never rolled back.

import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:ocideck_form_core/ocideck_form_core.dart';
import 'package:test/test.dart';

const String template = '''<!-- form id=kookboek version=2 rules=1 -->
# Inzending

<!-- field id=naam type=text required -->
**Naam**
<!-- answer -->
<!-- /field id=naam -->

<!-- field id=akkoord type=consent required -->
Ik ga akkoord met publicatie.
<!-- answer -->
- [ ]
<!-- /field id=akkoord -->
''';

final DateTime now = DateTime.utc(2026, 11, 3);

Uint8List bytes(List<int> v) => Uint8List.fromList(v);

Uint8List unhex(String h) => bytes([
  for (var i = 0; i < h.length; i += 2)
    int.parse(h.substring(i, i + 2), radix: 16),
]);

late FormSigningKey alice;
late FormSigningKey bob;
late FormSigningKey mallory;
late String aliceAge;
late String bobAge;
const String fid = 'abcdefghijklmnopqrstuvwxyz';

/// A signed bundle for [template] by [owner], listing [alice] and [bob].
Future<FormBundle> make({
  FormSigningKey? owner,
  int seq = 3,
  String expires = '2027-03-01',
  FormBundlePolicy policy = const FormBundlePolicy(),
  String text = template,
  String id = fid,
}) async {
  final result = await createFormBundle(
    fid: id,
    template: text,
    organisers: [
      FormBundleOrganiserInput(
        name: 'Redactie',
        age: aliceAge,
        signPublicKey: alice.publicKey,
      ),
      FormBundleOrganiserInput(
        name: 'Penningmeester',
        age: bobAge,
        signPublicKey: bob.publicKey,
      ),
    ],
    owner: owner ?? alice,
    bundleSeq: seq,
    expires: expires,
    now: now,
    policy: policy,
  );
  return (result as FormBundleCreated).bundle;
}

Future<FormBundleResult> verify(
  Object bundle, {
  String? fingerprint,
  String text = template,
  DateTime? at,
  String? host,
  FormBundlePins pins = const FormBundlePins(),
}) => verifyFormBundle(
  bundle is FormBundle ? bundle.toJsonText() : bundle as String,
  templateText: text,
  fingerprint: fingerprint ?? alice.fingerprint,
  now: at ?? now,
  expectedApiHost: host,
  pins: pins,
);

FormBundleIssue refusedWith(FormBundleResult r) =>
    (r as FormBundleRefused).issue;

/// Signs [json] as the owner would — `ocideck-intake-bundle-v1\n` + JCS, Ed25519 — without
/// going through [createFormBundle], so a bundle with a field the builder would never make
/// can still carry a valid signature.
Future<String> signed(Map<String, Object?> json, FormSigningKey key) async {
  final body = {...json}..remove('sig');
  final pair = await Ed25519().newKeyPairFromSeed(key.seed);
  final signature = await Ed25519().sign(
    utf8.encode('$kBundleSignatureTag${canonicalJson(body)}'),
    keyPair: pair,
  );
  return jsonEncode({...body, 'sig': base32Encode(signature.bytes)});
}

Future<Map<String, Object?>> jsonOf(FormBundle b) async =>
    jsonDecode(b.toJsonText()) as Map<String, Object?>;

void main() {
  setUpAll(() async {
    alice = await generateFormSigningKey();
    bob = await generateFormSigningKey();
    mallory = await generateFormSigningKey();
    aliceAge = (await ageRecipientOf(generateAgeIdentity()))!;
    bobAge = (await ageRecipientOf(generateAgeIdentity()))!;
  });

  group('keys', () {
    test(
      'RFC 8032 section 7.1: a seed gives its public key (tests 1 and 2)',
      () async {
        const vectors = {
          '9d61b19deffd5a60ba844af492ec2cc44449c5697b326919703bac031cae7f60':
              'd75a980182b10ab7d54bfed3c964073a0ee172f3daa62325af021a68f707511a',
          '4ccd089b28ff96da9db6c346ec114e0f5b8a319f35aba624da8cf6ed4fb8a6fb':
              '3d4017c3e843895a92b70aa74d1b7ebc9c982ccf2ec4968cc0cd55f12af4660c',
        };
        for (final entry in vectors.entries) {
          final key = await formSigningKeyFromSeed(unhex(entry.key));
          expect(key.publicKey, unhex(entry.value), reason: entry.key);
        }
      },
    );

    test(
      'a key knows its text, its fingerprint and keeps its own copy of the seed',
      () async {
        final seed = bytes(List.generate(32, (i) => i));
        final key = await formSigningKeyFromSeed(seed);
        seed[0] = 99;
        expect(key.seed[0], 0, reason: 'a copy');
        expect(key.publicKeyText, base32Encode(key.publicKey));
        expect(key.publicKeyText, hasLength(52));
        expect(key.fingerprint, formKeyFingerprint(key.publicKey));
        expect(key.fingerprint, hasLength(52));
        expect(
          key.fingerprint,
          isNot(key.publicKeyText),
          reason: 'a hash of it, not it',
        );
      },
    );

    test('a seed is 32 bytes', () async {
      for (final n in [0, 31, 33, 64]) {
        await expectLater(
          formSigningKeyFromSeed(Uint8List(n)),
          throwsArgumentError,
          reason: '$n',
        );
      }
    });

    test('generated keys differ', () async {
      final a = await generateFormSigningKey();
      final b = await generateFormSigningKey();
      expect(a.publicKeyText, isNot(b.publicKeyText));
      expect(a.seed, hasLength(32));
    });

    test('the fingerprint is the base32 of the SHA-256 of the public key', () {
      final key = unhex(
        'd75a980182b10ab7d54bfed3c964073a0ee172f3daa62325af021a68f707511a',
      );
      expect(formKeyFingerprint(key), base32Encode(unhex(sha256Hex(key))));
    });

    test(
      'a fingerprint is written in groups of four and read back any way it is typed',
      () {
        final fp = alice.fingerprint;
        final grouped = formatFingerprint(fp);
        expect(grouped.split('-'), hasLength(13));
        expect(grouped.split('-').every((g) => g.length == 4), isTrue);
        expect(grouped.replaceAll('-', ''), fp);
        expect(normalizeFingerprint(grouped), fp);
        expect(normalizeFingerprint(grouped.toUpperCase()), fp);
        expect(normalizeFingerprint(' $fp\n'), fp);
        expect(normalizeFingerprint(grouped.replaceAll('-', ' ')), fp);
        expect(normalizeFingerprint(grouped.replaceAll('-', '\n')), fp);
      },
    );

    test('what is not a fingerprint is not read as one', () {
      final fp = alice.fingerprint;
      for (final bad in [
        '',
        'abc',
        fp.substring(1),
        '${fp}a',
        '${fp.substring(0, 51)}1',
        '${fp.substring(0, 51)}=',
        'é${fp.substring(1)}',
      ]) {
        expect(normalizeFingerprint(bad), isNull, reason: bad);
      }
      // Fifty-two characters whose last four bits are not zero are not any 32 bytes.
      expect(normalizeFingerprint('${'a' * 51}b'), isNull);
    });

    test('a short formatted fingerprint keeps its last, shorter group', () {
      expect(formatFingerprint('abcdefghij'), 'abcd-efgh-ij');
      expect(formatFingerprint('abcd'), 'abcd');
      expect(formatFingerprint(''), '');
    });

    test(
      'a kid is derived from the recipient, 26 characters, and nothing else',
      () {
        final kid = organiserKid(aliceAge);
        expect(kid, hasLength(26));
        expect(isValidFormId(kid), isTrue);
        expect(kid, organiserKid(aliceAge));
        expect(kid, isNot(organiserKid(bobAge)));
        expect(
          kid,
          base32Encode(unhex(sha256Hex(utf8.encode(aliceAge))).sublist(0, 16)),
        );
      },
    );

    test('a bundle file sits beside its template', () {
      expect(bundleFileNameFor('recept.nl.md'), 'recept.nl.bundle.json');
      expect(bundleFileNameFor('recept.md'), 'recept.bundle.json');
      expect(bundleFileNameFor('recept'), 'recept.bundle.json');
    });
  });

  group('a bundle the owner made', () {
    test(
      'verifies against the owner\'s fingerprint, and says who the owner is',
      () async {
        final bundle = await make();
        final r = await verify(bundle) as FormBundleVerified;
        expect(r.owner.name, 'Redactie');
        expect(r.fingerprint, alice.fingerprint);
        expect(r.bundle.fid, fid);
        expect(r.bundle.bundleSeq, 3);
        expect(r.bundle.organisers.map((o) => o.name), [
          'Redactie',
          'Penningmeester',
        ]);
        expect(r.pins.seqFor(fid, alice.fingerprint), 3);
      },
    );

    test('has the shape of section 5.1', () async {
      final json = await jsonOf(
        await make(
          policy: const FormBundlePolicy(
            apiHost: 'intake.example.org',
            closes: '2027-01-31',
            maxPackageBytes: 62914560,
            retainUnused: '6 maanden na sluiting',
          ),
        ),
      );
      expect(json['v'], 1);
      expect(json['fid'], fid);
      expect(json['form'], {'id': 'kookboek', 'version': 2, 'rules': 1});
      expect(json['template_sha256'], formTemplateHash(template));
      expect(json['bundle_seq'], 3);
      expect(json['expires'], '2027-03-01');
      expect(json['policy'], {
        'api_host': 'intake.example.org',
        'closes': '2027-01-31',
        'max_package_bytes': 62914560,
        'retain_unused': '6 maanden na sluiting',
      });
      final organisers = json['organisers']! as List;
      expect((organisers.first as Map).keys, ['name', 'age', 'sign', 'kid']);
      expect((json['sig']! as String), hasLength(103));
      expect(json.keys.toSet(), {
        'v',
        'fid',
        'form',
        'template_sha256',
        'organisers',
        'policy',
        'bundle_seq',
        'expires',
        'sig',
      });
    });

    test('its text is indented and ends with one newline', () async {
      final text = (await make()).toJsonText();
      expect(text, startsWith('{\n  "'));
      expect(text, endsWith('}\n'));
      expect(text.endsWith('\n\n'), isFalse);
    });

    test('is the same bytes every time: Ed25519 is deterministic', () async {
      expect((await make()).toJsonText(), (await make()).toJsonText());
    });

    test(
      'is signed over the tag and the canonical JSON, by anyone\'s Ed25519',
      () async {
        final bundle = await make();
        final message = utf8.encode(
          '$kBundleSignatureTag${canonicalJson(bundle.signedObject())}',
        );
        final ok = await Ed25519().verify(
          message,
          signature: Signature(
            base32Decode(bundle.signature)!,
            publicKey: SimplePublicKey(
              alice.publicKey,
              type: KeyPairType.ed25519,
            ),
          ),
        );
        expect(ok, isTrue);
      },
    );

    test('is the same bundle however its file is written', () async {
      final bundle = await make();
      final json = await jsonOf(bundle);
      final reversed = Map.fromEntries(json.entries.toList().reversed);
      for (final text in [
        jsonEncode(json),
        jsonEncode(reversed),
        const JsonEncoder.withIndent('\t').convert(json),
        bundle.toJsonText().replaceAll('\n', '\r\n'),
        '  \n${bundle.toJsonText()}  \n',
      ]) {
        expect(await verify(text), isA<FormBundleVerified>());
      }
    });

    test('can carry no policy at all (the file route)', () async {
      final bundle = await make();
      expect((await jsonOf(bundle))['policy'], isEmpty);
      expect(await verify(bundle), isA<FormBundleVerified>());
    });

    test('is bound to a template with a BOM no differently', () async {
      final bundle = await make();
      expect(
        await verify(bundle, text: '\u{FEFF}$template'),
        isA<FormBundleVerified>(),
      );
    });
  });

  group('the fingerprint comes from somewhere else', () {
    late FormBundle bundle;
    setUpAll(() async => bundle = await make());

    test('none at all: refused, not asked about', () async {
      for (final none in [null, '', '   ', '\n']) {
        final r = await verifyFormBundle(
          bundle.toJsonText(),
          templateText: template,
          fingerprint: none,
          now: now,
        );
        expect(
          refusedWith(r),
          FormBundleIssue.noFingerprint,
          reason: '"$none"',
        );
      }
    });

    test('one that is not a fingerprint', () async {
      for (final bad in ['abc', 'x' * 52, alice.fingerprint.substring(2)]) {
        expect(
          refusedWith(await verify(bundle, fingerprint: bad)),
          FormBundleIssue.badFingerprint,
          reason: bad,
        );
      }
    });

    test(
      'one that is a fingerprint of a key that is not in the bundle stops hard',
      () async {
        expect(
          refusedWith(await verify(bundle, fingerprint: mallory.fingerprint)),
          FormBundleIssue.fingerprintMismatch,
        );
      },
    );

    test(
      'a fingerprint of another listed organiser is not the owner: the signature fails',
      () async {
        expect(
          refusedWith(await verify(bundle, fingerprint: bob.fingerprint)),
          FormBundleIssue.badSignature,
        );
      },
    );

    test('any way of writing it is the same fingerprint', () async {
      expect(
        await verify(bundle, fingerprint: formatFingerprint(alice.fingerprint)),
        isA<FormBundleVerified>(),
      );
      expect(
        await verify(bundle, fingerprint: alice.fingerprint.toUpperCase()),
        isA<FormBundleVerified>(),
      );
    });

    test(
      'a bundle signed by another key than the one it lists as owner fails',
      () async {
        // The owner signs with the wrong key: listed as alice, signed by mallory.
        final json = await jsonOf(bundle);
        final text = await signed(json, mallory);
        expect(refusedWith(await verify(text)), FormBundleIssue.badSignature);
      },
    );

    test('the owner must be listed', () async {
      final r = await createFormBundle(
        fid: fid,
        template: template,
        organisers: [
          FormBundleOrganiserInput(
            name: 'Penningmeester',
            age: bobAge,
            signPublicKey: bob.publicKey,
          ),
        ],
        owner: alice,
        bundleSeq: 1,
        expires: '2027-03-01',
        now: now,
      );
      expect(
        (r as FormBundleCreateRefused).issue,
        FormBundleCreateIssue.signerNotListed,
      );
    });
  });

  group('every signed field is signed', () {
    test('changing any value, anywhere, one at a time, is refused', () async {
      final bundle = await make(
        policy: const FormBundlePolicy(
          apiHost: 'intake.example.org',
          closes: '2027-01-31',
          maxPackageBytes: 1000000,
          retainUnused: 'een half jaar',
        ),
      );
      final original = await jsonOf(bundle);
      final paths = <List<Object>>[];
      void collect(Object? node, List<Object> path) {
        if (node is Map) {
          node.forEach((k, v) => collect(v, [...path, k as Object]));
        } else if (node is List) {
          for (var i = 0; i < node.length; i++) {
            collect(node[i], [...path, i]);
          }
        } else {
          paths.add(path);
        }
      }

      collect(original, []);
      expect(paths.length, greaterThan(20));
      for (final path in paths) {
        final copy = jsonDecode(jsonEncode(original));
        dynamic holder = copy;
        for (final step in path.take(path.length - 1)) {
          holder = holder[step];
        }
        final value = holder[path.last];
        holder[path.last] = switch (value) {
          final String s => '${s}x',
          final int n => n + 1,
          _ => 'changed',
        };
        final r = await verify(jsonEncode(copy));
        expect(r, isA<FormBundleRefused>(), reason: path.join('.'));
      }
    });

    test('a member that is added, or one that is removed, breaks it', () async {
      final json = await jsonOf(await make());
      expect(
        await verify(jsonEncode({...json, 'extra': 1})),
        isA<FormBundleRefused>(),
      );
      for (final key in json.keys.where((k) => k != 'policy')) {
        final copy = {...json}..remove(key);
        expect(
          await verify(jsonEncode(copy)),
          isA<FormBundleRefused>(),
          reason: key,
        );
      }
    });

    test(
      'a signature over the JSON without the tag is not a bundle signature',
      () async {
        final json = await jsonOf(await make());
        final body = {...json}..remove('sig');
        final pair = await Ed25519().newKeyPairFromSeed(alice.seed);
        for (final prefix in [
          '',
          'ocideck-intake-req-v1\n',
          'ocideck-intake-bundle-v2\n',
          'ocideck-intake-bundle-v1',
        ]) {
          final sig = await Ed25519().sign(
            utf8.encode('$prefix${canonicalJson(body)}'),
            keyPair: pair,
          );
          final text = jsonEncode({...body, 'sig': base32Encode(sig.bytes)});
          expect(
            refusedWith(await verify(text)),
            FormBundleIssue.badSignature,
            reason: prefix,
          );
        }
      },
    );

    test(
      'a signature over the text rather than the canonical form is not one either',
      () async {
        final json = await jsonOf(await make());
        final body = {...json}..remove('sig');
        final pair = await Ed25519().newKeyPairFromSeed(alice.seed);
        final sig = await Ed25519().sign(
          utf8.encode('$kBundleSignatureTag${jsonEncode(body)}'),
          keyPair: pair,
        );
        // jsonEncode keeps insertion order, which is not sorted: the two texts differ.
        expect(jsonEncode(body), isNot(canonicalJson(body)));
        final text = jsonEncode({...body, 'sig': base32Encode(sig.bytes)});
        expect(refusedWith(await verify(text)), FormBundleIssue.badSignature);
      },
    );

    test('a signature that is not 64 bytes of base32', () async {
      final json = await jsonOf(await make());
      for (final bad in [
        '',
        'x',
        (json['sig']! as String).substring(1),
        '${json['sig']}aa',
        (json['sig']! as String).toUpperCase(),
        42,
        null,
      ]) {
        final text = jsonEncode({...json, 'sig': bad});
        expect(
          refusedWith(await verify(text)),
          FormBundleIssue.badSignature,
          reason: '$bad',
        );
      }
      final missing = {...json}..remove('sig');
      expect(
        refusedWith(await verify(jsonEncode(missing))),
        FormBundleIssue.badSignature,
      );
    });
  });

  group('not a bundle', () {
    late FormBundle bundle;
    setUpAll(() async => bundle = await make());

    test('text that is not JSON, or not an object', () async {
      for (final text in ['', 'hello', '[]', '"x"', '42', 'null', '{']) {
        expect(
          refusedWith(await verify(text)),
          FormBundleIssue.notABundle,
          reason: text,
        );
      }
    });

    test('the most bundle text read is a quarter of a megabyte', () {
      expect(kFormMaxBundleBytes, 256 * 1024);
    });

    test('too large', () async {
      final big = jsonEncode({'v': 1, 'pad': 'x' * kFormMaxBundleBytes});
      expect(refusedWith(await verify(big)), FormBundleIssue.notABundle);
      final fits =
          '${' ' * (kFormMaxBundleBytes - bundle.toJsonText().length)}${bundle.toJsonText()}';
      expect(utf8.encode(fits).length, kFormMaxBundleBytes);
      expect(await verify(fits), isA<FormBundleVerified>());
      expect(refusedWith(await verify(' $fits')), FormBundleIssue.notABundle);
    });

    test('a version it does not read', () async {
      final json = await jsonOf(bundle);
      for (final v in [0, 2, '1', null]) {
        expect(
          refusedWith(await verify(jsonEncode({...json, 'v': v}))),
          FormBundleIssue.unsupportedVersion,
          reason: '$v',
        );
      }
    });

    test('organisers that are not a list', () async {
      final json = await jsonOf(bundle);
      for (final bad in <Object?>[null, 'x', 1, <String, Object?>{}]) {
        expect(
          refusedWith(await verify(jsonEncode({...json, 'organisers': bad}))),
          FormBundleIssue.notABundle,
          reason: '$bad',
        );
      }
    });

    test('a number the signature cannot cover', () async {
      final json = await jsonOf(bundle);
      final text = jsonEncode({...json, 'bundle_seq': 1.5});
      expect(refusedWith(await verify(text)), FormBundleIssue.notABundle);
      // Written into the text: this number is not a Dart literal a browser can compile.
      final big = bundle.toJsonText().replaceFirst(
        '"bundle_seq": 3',
        '"bundle_seq": 9007199254740993',
      );
      expect(big, contains('9007199254740993'));
      expect(refusedWith(await verify(big)), FormBundleIssue.notABundle);
    });

    test(
      'an organiser without a usable key is not the signer, and the others still are',
      () async {
        final json = await jsonOf(bundle);
        final organisers = (json['organisers']! as List)
            .cast<Map<String, Object?>>();
        final mangled = [
          {...organisers[0], 'sign': 'not base32!'},
          organisers[1],
        ];
        expect(
          refusedWith(
            await verify(jsonEncode({...json, 'organisers': mangled})),
          ),
          FormBundleIssue.fingerprintMismatch,
        );
        final entries = <Object?>[
          'junk',
          42,
          null,
          {'name': 'x'},
          ...organisers,
        ];
        expect(
          refusedWith(
            await verify(jsonEncode({...json, 'organisers': entries})),
          ),
          FormBundleIssue.badSignature,
          reason:
              'the signer is found, and the signature is over a different object',
        );
      },
    );
  });

  group('signed, and still not allowed', () {
    late Map<String, Object?> good;
    setUpAll(() async => good = await jsonOf(await make()));

    Map<String, Object?> with_(Map<String, Object?> changes) => {
      ...good,
      ...changes,
    };
    List<Map<String, Object?>> organisers() => [
      for (final o in good['organisers']! as List)
        {...(o as Map).cast<String, Object?>()},
    ];

    Future<void> structure(String why, Map<String, Object?> json) async {
      final r = await verify(await signed(json, alice));
      expect(r, isA<FormBundleRefused>(), reason: why);
      expect(
        (r as FormBundleRefused).issue,
        FormBundleIssue.badStructure,
        reason: why,
      );
      expect(r.detail, isNotNull, reason: why);
    }

    test('a member nobody defined', () async {
      await structure('top level', with_({'extra': 1}));
      await structure(
        'form',
        with_({
          'form': {...good['form']! as Map, 'extra': 1},
        }),
      );
      await structure(
        'policy',
        with_({
          'policy': {'extra': 1},
        }),
      );
      final o = organisers()..[0]['extra'] = 1;
      await structure('organiser', with_({'organisers': o}));
    });

    test(
      'the first version of a form, and a name with spaces, are fine',
      () async {
        final one = template.replaceFirst('version=2', 'version=1');
        final json = await jsonOf(await make(text: one));
        expect((json['form']! as Map)['version'], 1);
        expect(
          await verify(jsonEncode(json), text: one),
          isA<FormBundleVerified>(),
        );
        final named = organisers()..[0]['name'] = 'Team Redactie Kookboek';
        final text = await signed(with_({'organisers': named}), alice);
        expect(await verify(text), isA<FormBundleVerified>());
      },
    );

    test('a fid, a form id, version or rules out of grammar', () async {
      for (final bad in [
        '',
        'short',
        'ABCDEFGHIJKLMNOPQRSTUVWXYZ',
        'abcdefghijklmnopqrstuvwxy1',
        'abcdefghijklmnopqrstuvwxyz2',
        7,
        null,
      ]) {
        await structure('fid $bad', with_({'fid': bad}));
      }
      final form = (good['form']! as Map).cast<String, Object?>();
      await structure('form not a map', with_({'form': 'x'}));
      for (final id in [
        '',
        'Kook',
        '1kook',
        'kook_book',
        'kook book',
        7,
        null,
      ]) {
        await structure(
          'form.id $id',
          with_({
            'form': {...form, 'id': id},
          }),
        );
      }
      for (final version in [0, -1, '2', null]) {
        await structure(
          'form.version $version',
          with_({
            'form': {...form, 'version': version},
          }),
        );
      }
      for (final rules in [0, -1, '1', null]) {
        await structure(
          'form.rules $rules',
          with_({
            'form': {...form, 'rules': rules},
          }),
        );
      }
    });

    test('a template hash that is not 64 lower-case hex digits', () async {
      final hash = good['template_sha256']! as String;
      for (final bad in [
        '',
        hash.substring(1),
        '${hash}0',
        hash.toUpperCase(),
        'g' * 64,
        7,
        null,
      ]) {
        await structure('hash $bad', with_({'template_sha256': bad}));
      }
    });

    test('organisers: none, or more than may be sealed to', () async {
      // With none listed there is no signer to find, so it ends before the structure.
      expect(
        refusedWith(
          await verify(await signed(with_({'organisers': <Object?>[]}), alice)),
        ),
        FormBundleIssue.fingerprintMismatch,
      );
      final many = <Map<String, Object?>>[];
      for (var i = 0; i < kFormMaxRecipients + 1; i++) {
        final k = await generateFormSigningKey();
        final age = (await ageRecipientOf(generateAgeIdentity()))!;
        many.add({
          'name': 'O$i',
          'age': age,
          'sign': k.publicKeyText,
          'kid': organiserKid(age),
        });
      }
      many[0] = organisers()[0];
      await structure('too many', with_({'organisers': many}));
      final atTheLimit = await signed(
        with_({'organisers': many.take(kFormMaxRecipients).toList()}),
        alice,
      );
      expect(await verify(atTheLimit), isA<FormBundleVerified>());
    });

    test('an organiser\'s name', () async {
      for (final bad in [
        '',
        '   ',
        'x' * 81,
        'tab\there',
        'line\nbreak',
        'del\u007f',
        7,
        null,
      ]) {
        final o = organisers()..[1]['name'] = bad;
        await structure('name $bad', with_({'organisers': o}));
      }
      final longest = organisers()..[1]['name'] = 'x' * 80;
      expect(
        await verify(await signed(with_({'organisers': longest}), alice)),
        isA<FormBundleVerified>(),
      );
    });

    test('an organiser\'s age recipient, signing key and kid', () async {
      for (final bad in [
        '',
        'age1',
        aliceAge.toUpperCase(),
        'AGE-SECRET-KEY-1X',
        7,
        null,
      ]) {
        final o = organisers()..[1]['age'] = bad;
        await structure('age $bad', with_({'organisers': o}));
      }
      for (final bad in ['', 'abc', 'a' * 51, 'a' * 53, 7, null]) {
        final o = organisers()..[1]['sign'] = bad;
        // The owner's key is intact, so the signer is found; the other key is not usable.
        await structure('sign $bad', with_({'organisers': o}));
      }
      for (final bad in [
        '',
        'a' * 26,
        organiserKid(aliceAge),
        organiserKid(bobAge).toUpperCase(),
        7,
        null,
      ]) {
        final o = organisers()..[1]['kid'] = bad;
        await structure('kid $bad', with_({'organisers': o}));
      }
    });

    test('an organiser listed twice: by recipient, key or kid', () async {
      final a = organisers()[0];
      final b = organisers()[1];
      await structure(
        'same age',
        with_({
          'organisers': [
            a,
            {...b, 'age': a['age'], 'kid': a['kid']},
          ],
        }),
      );
      await structure(
        'same key',
        with_({
          'organisers': [
            a,
            {...b, 'sign': a['sign']},
          ],
        }),
      );
      await structure(
        'same kid',
        with_({
          'organisers': [
            a,
            {...b, 'kid': a['kid']},
          ],
        }),
      );
      await structure(
        'same twice',
        with_({
          'organisers': [a, a],
        }),
      );
    });

    test('a policy: host, closing day, cap, retention', () async {
      for (final bad in [
        '',
        'Intake.Example.Org',
        'intake_example',
        '-x.org',
        'x.org-',
        'intake.example.org/path',
        'intake example',
        'x.org:',
        'x.org:123456',
        7,
      ]) {
        await structure(
          'host $bad',
          with_({
            'policy': {'api_host': bad},
          }),
        );
      }
      for (final bad in [
        '',
        '2027-02-30',
        '20270131',
        '2027-1-31',
        'morgen',
        7,
      ]) {
        await structure(
          'closes $bad',
          with_({
            'policy': {'closes': bad},
          }),
        );
      }
      for (final bad in [
        0,
        -1,
        const FormPackageLimits().maxPackageBytes + 1,
        '100',
        null,
      ]) {
        await structure(
          'cap $bad',
          with_({
            'policy': {'max_package_bytes': bad},
          }),
        );
      }
      for (final bad in ['', '   ', 'x' * 201, 'new\nline', 7, null]) {
        await structure(
          'retain $bad',
          with_({
            'policy': {'retain_unused': bad},
          }),
        );
      }
      for (final ok in [
        {'api_host': 'intake.example.org'},
        {'api_host': 'localhost:8080'},
        {'api_host': 'a'},
        {'closes': '2028-02-29'},
        {'max_package_bytes': 1},
        {'max_package_bytes': const FormPackageLimits().maxPackageBytes},
        {'retain_unused': 'x' * 200},
      ]) {
        expect(
          await verify(await signed(with_({'policy': ok}), alice)),
          isA<FormBundleVerified>(),
          reason: '$ok',
        );
      }
    });

    test('a sequence and an expiry', () async {
      for (final bad in [0, -1, '3', null]) {
        await structure('seq $bad', with_({'bundle_seq': bad}));
      }
      for (final bad in ['', '2027-02-30', '20270301', 'ooit', 7, null]) {
        await structure('expires $bad', with_({'expires': bad}));
      }
      expect(
        await verify(await signed(with_({'bundle_seq': 1}), alice)),
        isA<FormBundleVerified>(),
      );
    });

    test('a policy that is not an object', () async {
      for (final bad in [null, 'x', 1, <Object?>[]]) {
        await structure('policy $bad', with_({'policy': bad}));
      }
    });
  });

  group('bound to its template', () {
    test('a template that differs by one character', () async {
      final bundle = await make();
      expect(
        refusedWith(
          await verify(
            bundle,
            text: template.replaceFirst('publicatie', 'publicaties'),
          ),
        ),
        FormBundleIssue.templateMismatch,
      );
      expect(
        refusedWith(await verify(bundle, text: '$template ')),
        FormBundleIssue.templateMismatch,
      );
    });

    test('line endings are part of the text', () async {
      final bundle = await make();
      expect(
        refusedWith(
          await verify(bundle, text: template.replaceAll('\n', '\r\n')),
        ),
        FormBundleIssue.templateMismatch,
      );
    });

    test('a template that is not a form, with a hash that matches', () async {
      final json = await jsonOf(await make());
      const prose = '# Gewoon een document\n';
      final text = await signed({
        ...json,
        'template_sha256': formTemplateHash(prose),
      }, alice);
      final r = await verify(text, text: prose) as FormBundleRefused;
      expect(r.issue, FormBundleIssue.templateMismatch);
      expect(r.detail, contains('not the form'));
    });

    test(
      'another form id, version or rules version than the bundle names',
      () async {
        final json = await jsonOf(await make());
        final form = (json['form']! as Map).cast<String, Object?>();
        for (final changes in [
          {'id': 'ander'},
          {'version': 3},
          {'rules': 2},
        ]) {
          final text = await signed({
            ...json,
            'form': {...form, ...changes},
          }, alice);
          final r = await verify(text) as FormBundleRefused;
          expect(r.issue, FormBundleIssue.templateMismatch, reason: '$changes');
          expect(r.detail, contains('not the form'));
        }
      },
    );

    test('a form that needs rules this engine does not have', () async {
      final newer = template.replaceFirst('rules=1', 'rules=2');
      final json = await jsonOf(await make());
      final form = (json['form']! as Map).cast<String, Object?>();
      final text = await signed({
        ...json,
        'form': {...form, 'rules': 2},
        'template_sha256': formTemplateHash(newer),
      }, alice);
      expect(
        refusedWith(await verify(text, text: newer)),
        FormBundleIssue.rulesTooNew,
      );
    });

    test(
      'and one is not made for it either: it would not pass its own check',
      () async {
        final newer = template.replaceFirst('rules=1', 'rules=2');
        final r = await createFormBundle(
          fid: fid,
          template: newer,
          organisers: [
            FormBundleOrganiserInput(
              name: 'R',
              age: aliceAge,
              signPublicKey: alice.publicKey,
            ),
          ],
          owner: alice,
          bundleSeq: 1,
          expires: '2027-03-01',
          now: now,
        );
        expect(
          (r as FormBundleCreateRefused).issue,
          FormBundleCreateIssue.invalid,
        );
        expect(r.detail, 'rulesTooNew');
      },
    );

    test('a template that is not a form cannot be bundled', () async {
      final r = await createFormBundle(
        fid: fid,
        template: '# Gewoon een document\n',
        organisers: [
          FormBundleOrganiserInput(
            name: 'R',
            age: aliceAge,
            signPublicKey: alice.publicKey,
          ),
        ],
        owner: alice,
        bundleSeq: 1,
        expires: '2027-03-01',
        now: now,
      );
      expect(
        (r as FormBundleCreateRefused).issue,
        FormBundleCreateIssue.notAForm,
      );
    });
  });

  group('fresh', () {
    test('it is believed until the end of the day it names', () async {
      final bundle = await make(expires: '2026-11-03');
      expect(
        await verify(bundle, at: DateTime.utc(2026, 11, 3, 23, 59, 59)),
        isA<FormBundleVerified>(),
      );
      expect(
        await verify(bundle, at: DateTime.utc(2026, 11, 3)),
        isA<FormBundleVerified>(),
      );
      expect(
        refusedWith(await verify(bundle, at: DateTime.utc(2026, 11, 4))),
        FormBundleIssue.expired,
      );
      expect(
        await verify(bundle, at: DateTime.utc(2026, 11, 2)),
        isA<FormBundleVerified>(),
      );
    });

    test('the day is the UTC day', () async {
      final bundle = await make(expires: '2026-11-03');
      // 2026-11-04 00:30 in UTC+1 is 2026-11-03 23:30 UTC: still believed.
      expect(
        await verify(bundle, at: DateTime.parse('2026-11-04T00:30:00+01:00')),
        isA<FormBundleVerified>(),
      );
      expect(
        refusedWith(
          await verify(bundle, at: DateTime.parse('2026-11-04T01:30:00+01:00')),
        ),
        FormBundleIssue.expired,
      );
    });

    test(
      'a bundle that has expired is refused for that, once it is known to be genuine',
      () async {
        // Made by hand: the builder will not make a bundle that is already out of date.
        final json = await jsonOf(await make());
        final text = await signed({...json, 'expires': '2026-01-01'}, alice);
        expect(refusedWith(await verify(text)), FormBundleIssue.expired);
        expect(
          refusedWith(await verify(text, fingerprint: mallory.fingerprint)),
          FormBundleIssue.fingerprintMismatch,
        );
        expect(
          refusedWith(
            await verify(text.replaceFirst('2026-01-01', '2026-01-02')),
          ),
          FormBundleIssue.badSignature,
        );
      },
    );
  });

  group('the host it was made for', () {
    test('is the host the client called', () async {
      final bundle = await make(
        policy: const FormBundlePolicy(apiHost: 'intake.example.org'),
      );
      expect(
        await verify(bundle, host: 'intake.example.org'),
        isA<FormBundleVerified>(),
      );
      expect(
        await verify(bundle, host: 'Intake.Example.ORG'),
        isA<FormBundleVerified>(),
      );
      expect(
        refusedWith(await verify(bundle, host: 'evil.example.org')),
        FormBundleIssue.hostMismatch,
      );
      expect(
        refusedWith(await verify(bundle, host: 'intake.example.org:8443')),
        FormBundleIssue.hostMismatch,
      );
      expect(
        await verify(bundle),
        isA<FormBundleVerified>(),
        reason: 'no host called, none checked',
      );
    });

    test('a bundle without one is not for a server', () async {
      final bundle = await make();
      expect(
        refusedWith(await verify(bundle, host: 'intake.example.org')),
        FormBundleIssue.hostMismatch,
      );
    });
  });

  group('never rolled back', () {
    test(
      'a lower sequence than the highest seen is refused, the same or a higher one is not',
      () async {
        final v3 = await make(seq: 3);
        final v2 = await make(seq: 2);
        final v4 = await make(seq: 4);
        final first = await verify(v3) as FormBundleVerified;
        expect(
          refusedWith(await verify(v2, pins: first.pins)),
          FormBundleIssue.rollback,
        );
        expect(await verify(v3, pins: first.pins), isA<FormBundleVerified>());
        final later = await verify(v4, pins: first.pins) as FormBundleVerified;
        expect(later.pins.seqFor(fid, alice.fingerprint), 4);
        expect(
          refusedWith(await verify(v3, pins: later.pins)),
          FormBundleIssue.rollback,
        );
      },
    );

    test('a pin belongs to one form and one owner', () async {
      final v3 = await make(seq: 3);
      final first = await verify(v3) as FormBundleVerified;
      final otherForm = await make(seq: 1, id: 'zyxwvutsrqponmlkjihgfedcba');
      expect(
        await verify(otherForm, pins: first.pins),
        isA<FormBundleVerified>(),
        reason: 'another fid',
      );
      final otherOwner = await make(seq: 1, owner: bob);
      final r = await verify(
        otherOwner,
        fingerprint: bob.fingerprint,
        pins: first.pins,
      );
      expect(
        r,
        isA<FormBundleVerified>(),
        reason: 'another owner of the same fid',
      );
      expect((r as FormBundleVerified).pins.seqFor(fid, alice.fingerprint), 3);
      expect(r.pins.seqFor(fid, bob.fingerprint), 1);
    });

    test('pins are not changed by a refusal', () async {
      final v3 = await make(seq: 3);
      final first = await verify(v3) as FormBundleVerified;
      final v1 = await make(seq: 1);
      await verify(v1, pins: first.pins);
      expect(first.pins.seqFor(fid, alice.fingerprint), 3);
    });

    test(
      'accepting a lower sequence changes nothing; a higher one is the new pin',
      () async {
        final v3 = await make(seq: 3);
        final v5 = await make(seq: 5);
        final pins = const FormBundlePins().accepting(v3, alice.fingerprint);
        expect(
          identical(
            pins.accepting(await make(seq: 2), alice.fingerprint),
            pins,
          ),
          isTrue,
        );
        expect(identical(pins.accepting(v3, alice.fingerprint), pins), isTrue);
        expect(
          pins.accepting(v5, alice.fingerprint).seqFor(fid, alice.fingerprint),
          5,
        );
        expect(pins.seqFor(fid, alice.fingerprint), 3, reason: 'immutable');
      },
    );

    test('pins go to JSON and come back, and junk is dropped', () async {
      final v3 = await make(seq: 3);
      final pins = const FormBundlePins().accepting(v3, alice.fingerprint);
      final back = FormBundlePins.fromJson(
        jsonDecode(jsonEncode(pins.toJson())),
      );
      expect(back.seqFor(fid, alice.fingerprint), 3);
      for (final junk in [null, 'x', 5, <Object?>[]]) {
        expect(FormBundlePins.fromJson(junk).toJson(), isEmpty);
      }
      final mixed = FormBundlePins.fromJson({
        'k@l': 1,
        'a@b': 2,
        'c@d': 0,
        'e@f': -1,
        'g@h': 'x',
        'i@j': 1.5,
        3: 4,
      });
      expect(mixed.toJson(), {'k@l': 1, 'a@b': 2});
    });
  });

  group('making a bundle', () {
    FormBundleOrganiserInput person(
      String name,
      String age,
      FormSigningKey key,
    ) => FormBundleOrganiserInput(
      name: name,
      age: age,
      signPublicKey: key.publicKey,
    );

    Future<FormBundleCreateResult> create({
      List<FormBundleOrganiserInput>? organisers,
      String id = fid,
      int seq = 1,
      String expires = '2027-03-01',
      FormBundlePolicy policy = const FormBundlePolicy(),
      FormSigningKey? owner,
    }) => createFormBundle(
      fid: id,
      template: template,
      organisers: organisers ?? [person('Redactie', aliceAge, alice)],
      owner: owner ?? alice,
      bundleSeq: seq,
      expires: expires,
      now: now,
      policy: policy,
    );

    test(
      'a recipient that is not an age recipient, or a key that is not 32 bytes',
      () async {
        for (final bad in [
          FormBundleOrganiserInput(
            name: 'R',
            age: 'garbage',
            signPublicKey: alice.publicKey,
          ),
          FormBundleOrganiserInput(
            name: 'R',
            age: aliceAge.toUpperCase(),
            signPublicKey: alice.publicKey,
          ),
          FormBundleOrganiserInput(
            name: 'R',
            age: aliceAge,
            signPublicKey: Uint8List(31),
          ),
          FormBundleOrganiserInput(
            name: 'R',
            age: aliceAge,
            signPublicKey: Uint8List(33),
          ),
        ]) {
          expect(
            ((await create(organisers: [bad])) as FormBundleCreateRefused)
                .issue,
            FormBundleCreateIssue.badOrganiser,
          );
        }
      },
    );

    test(
      'an organiser named wrongly, one listed twice or too many are organiser problems',
      () async {
        final empty = await create(organisers: [person('', aliceAge, alice)]);
        expect(
          (empty as FormBundleCreateRefused).issue,
          FormBundleCreateIssue.badOrganiser,
        );
        expect(empty.detail, 'organiser.name');
        final twice = await create(
          organisers: [
            person('R', aliceAge, alice),
            person('S', aliceAge, bob),
          ],
        );
        expect(
          (twice as FormBundleCreateRefused).issue,
          FormBundleCreateIssue.badOrganiser,
        );
        final none = await create(organisers: []);
        expect(
          (none as FormBundleCreateRefused).issue,
          FormBundleCreateIssue.signerNotListed,
        );
      },
    );

    test(
      'a fid, dates, caps and hosts that a respondent would refuse are refused here first',
      () async {
        for (final (label, result) in [
          ('fid', await create(id: 'short')),
          ('expires', await create(expires: 'ooit')),
          ('seq', await create(seq: 0)),
          (
            'host',
            await create(policy: const FormBundlePolicy(apiHost: 'No Good')),
          ),
          (
            'closes',
            await create(policy: const FormBundlePolicy(closes: '2027-02-30')),
          ),
          (
            'cap',
            await create(policy: const FormBundlePolicy(maxPackageBytes: 0)),
          ),
          (
            'retain',
            await create(policy: const FormBundlePolicy(retainUnused: '')),
          ),
        ]) {
          final r = result as FormBundleCreateRefused;
          expect(r.issue, FormBundleCreateIssue.invalid, reason: label);
          expect(r.detail, isNotNull, reason: label);
        }
      },
    );

    test('a bundle that expired before it was made is not made', () async {
      final r = await create(expires: '2026-11-02');
      expect(
        (r as FormBundleCreateRefused).issue,
        FormBundleCreateIssue.invalid,
      );
      expect(r.detail, 'expired');
    });

    test('what it makes verifies, with the owner\'s own fingerprint', () async {
      final r =
          await create(
                organisers: [
                  person('Redactie', aliceAge, alice),
                  person('Bob', bobAge, bob),
                ],
                policy: const FormBundlePolicy(
                  apiHost: 'intake.example.org',
                  closes: '2027-01-31',
                ),
              )
              as FormBundleCreated;
      final v = await verifyFormBundle(
        r.text,
        templateText: template,
        fingerprint: alice.fingerprint,
        now: now,
        expectedApiHost: 'intake.example.org',
      );
      expect(v, isA<FormBundleVerified>());
      expect(r.text, r.bundle.toJsonText());
    });

    test('many organisers, the owner anywhere in the list', () async {
      final r =
          await create(
                organisers: [
                  person('Bob', bobAge, bob),
                  person('Redactie', aliceAge, alice),
                ],
              )
              as FormBundleCreated;
      final v = await verify(r.bundle) as FormBundleVerified;
      expect(v.owner.name, 'Redactie');
    });
  });
}
