// The editor card (FORM_INTAKE.md §5.1, §7.6): what the fingerprint covers, what a card may
// say, and what is refused. Platform-neutral — runs in a browser too.

import 'dart:convert';

import 'package:ocideck_form_core/ocideck_form_core.dart';
import 'package:test/test.dart';

late FormSigningKey signing;
late String age;
late String otherAge;

FormEditorCard make({String name = 'Tweede redacteur', String? recipient}) =>
    createFormEditorCard(
      name: name,
      age: recipient ?? age,
      signPublicKey: signing.publicKey,
    );

FormEditorCardIssue refused(String text) =>
    (parseFormEditorCard(text) as FormEditorCardRefused).issue;

FormEditorCard parsed(String text) =>
    (parseFormEditorCard(text) as FormEditorCardParsed).card;

/// The card as a map, with [changes] applied, as text.
String edited(Map<String, Object?> changes, {List<String> without = const []}) {
  final map = {...make().toJson(), ...changes};
  for (final key in without) {
    map.remove(key);
  }
  return jsonEncode(map);
}

void main() {
  setUpAll(() async {
    signing = await generateFormSigningKey();
    age = (await ageRecipientOf(generateAgeIdentity()))!;
    otherAge = (await ageRecipientOf(generateAgeIdentity()))!;
  });

  group('making a card', () {
    test('a card carries what the owner needs, with the kid derived', () {
      final card = make();
      expect(card.name, 'Tweede redacteur');
      expect(card.age, age);
      expect(card.sign, signing.publicKeyText);
      expect(card.kid, organiserKid(age));
    });

    test('the name is trimmed; what cannot be a name throws', () {
      expect(make(name: '  Team  ').name, 'Team');
      for (final bad in ['', '   ', 'x' * 81, 'a\u0000b', 'a\u007fb', 'a\nb']) {
        expect(() => make(name: bad), throwsArgumentError, reason: bad);
      }
      expect(make(name: 'x' * 80).name, hasLength(80));
    });

    test(
      'a recipient that is not one, and a key that is not 32 bytes, throw',
      () {
        expect(
          () => createFormEditorCard(
            name: 'x',
            age: age.toUpperCase(),
            signPublicKey: signing.publicKey,
          ),
          throwsArgumentError,
        );
        expect(
          () =>
              createFormEditorCard(name: 'x', age: age, signPublicKey: [1, 2]),
          throwsArgumentError,
        );
        expect(
          () => createFormEditorCard(
            name: 'x',
            age: age,
            signPublicKey: List.filled(33, 0),
          ),
          throwsArgumentError,
        );
      },
    );

    test(
      'the text is canonical JSON on one line, and reads back as the same card',
      () {
        final card = make();
        expect(card.toText(), isNot(contains('\n')));
        expect(
          card.toText().indexOf('"age"'),
          lessThan(card.toText().indexOf('"kid"')),
          reason: 'keys sorted',
        );
        final back = parsed(card.toText());
        expect(back.toText(), card.toText());
        expect(back.fingerprint, card.fingerprint);
      },
    );
  });

  group('the fingerprint', () {
    test('52 characters of base32, 32 bytes', () {
      final fp = make().fingerprint;
      expect(fp, hasLength(52));
      expect(base32Decode(fp), hasLength(32));
      expect(normalizeFingerprint(fp), fp);
    });

    test('it is not the fingerprint of the signing key', () {
      expect(make().fingerprint, isNot(signing.fingerprint));
    });

    test('it follows every field: swapping the recipient changes it', () {
      final base = make();
      expect(make(recipient: otherAge).fingerprint, isNot(base.fingerprint));
      expect(make(name: 'Anders').fingerprint, isNot(base.fingerprint));
      final otherKey = FormEditorCard(
        name: base.name,
        age: base.age,
        sign: base32Encode(List.filled(32, 7)),
        kid: base.kid,
      );
      expect(otherKey.fingerprint, isNot(base.fingerprint));
    });

    test('it does not depend on how the card was written down', () {
      final card = make();
      final pretty = const JsonEncoder.withIndent(
        '    ',
      ).convert(card.toJson());
      final shuffled = jsonEncode({
        'sign': card.sign,
        'v': 1,
        'kid': card.kid,
        'name': card.name,
        'age': card.age,
      });
      expect(parsed(pretty).fingerprint, card.fingerprint);
      expect(parsed(shuffled).fingerprint, card.fingerprint);
      expect(parsed('\n  $pretty  \n').fingerprint, card.fingerprint);
    });

    test('an upper-case key is not forgiven: the encoding is lower-case', () {
      final card = make();
      expect(
        refused(edited({'sign': card.sign.toUpperCase()})),
        FormEditorCardIssue.badSign,
      );
    });
  });

  group('the frozen card', () {
    // CC0 (D5): what version 1 produces, and what a second implementation checks itself
    // against — verified with Python's hashlib when it was made.
    const name = 'Tweede redacteur';
    const frozenAge =
        'age1xmwwc06ly3ee5rytxm9mflaz2u56jjj36s0mypdrwsvlul66mv4q47ryef';
    const frozenSign = 'pg2vmlup4zkpsqdywejorkmlu6ib7bj242k35v7a4oiqxlieszsa';
    const frozenKid = 't2opkkyz3ksutmups5g5e764pi';
    const frozenText =
        '{"age":"$frozenAge","kid":"$frozenKid","name":"$name","sign":"$frozenSign","v":1}';
    const frozenFingerprint =
        'hkbe5v2ofo4acsmaqr52szwkk454rz6emqt7gjih54uyrmnjwfqq';

    test('its text and fingerprint are exactly these', () {
      final card = createFormEditorCard(
        name: name,
        age: frozenAge,
        signPublicKey: base32Decode(frozenSign)!,
      );
      expect(card.kid, frozenKid);
      expect(card.toText(), frozenText);
      expect(card.fingerprint, frozenFingerprint);
    });

    test('and reads back from its text', () {
      final card = parsed(frozenText);
      expect(card.fingerprint, frozenFingerprint);
      expect(card.name, name);
    });
  });

  group('what a card may not be', () {
    test('not JSON, not an object, too long', () {
      for (final bad in ['', 'geen json', '[]', '"x"', '1', 'null', '{']) {
        expect(refused(bad), FormEditorCardIssue.notACard, reason: bad);
      }
      final long = edited({'name': 'x' * 5000});
      expect(refused(long), FormEditorCardIssue.notACard);
    });

    test('the limit is the one the document names', () {
      expect(kFormMaxEditorCardChars, 4096);
      expect(kFormEditorCardVersion, 1);
      expect(kEditorCardTag, 'ocideck-editor-card-v1\n');
    });

    test('text of exactly the limit is still read for what it says', () {
      final pad = ' ' * (kFormMaxEditorCardChars - make().toText().length);
      expect(
        parseFormEditorCard('${make().toText()}$pad'),
        isA<FormEditorCardParsed>(),
      );
      expect(refused('${make().toText()}$pad '), FormEditorCardIssue.notACard);
    });

    test('a key a card does not have', () {
      expect(refused(edited({'extra': 1})), FormEditorCardIssue.notACard);
    });

    test('a version it does not read', () {
      expect(refused(edited({'v': 2})), FormEditorCardIssue.unsupportedVersion);
      expect(refused(edited({'v': 0})), FormEditorCardIssue.unsupportedVersion);
      expect(refused(edited({'v': '1'})), FormEditorCardIssue.notACard);
      expect(refused(edited({}, without: ['v'])), FormEditorCardIssue.notACard);
    });

    test('a name that is not one — and no spaces round it', () {
      for (final bad in [
        '',
        '   ',
        'x' * 81,
        'a\u0000b',
        'a\u007fb',
        ' Team',
        'Team ',
        1,
        null,
      ]) {
        expect(
          refused(edited({'name': bad})),
          FormEditorCardIssue.badName,
          reason: '$bad',
        );
      }
      expect(
        refused(edited({}, without: ['name'])),
        FormEditorCardIssue.badName,
      );
      expect(
        parseFormEditorCard(edited({'name': 'x' * 80})),
        isA<FormEditorCardParsed>(),
      );
    });

    test('a recipient that is not one', () {
      for (final bad in [
        '',
        age.toUpperCase(),
        'age1',
        'AGE-SECRET-KEY-1X',
        7,
        null,
      ]) {
        expect(
          refused(edited({'age': bad})),
          FormEditorCardIssue.badAge,
          reason: '$bad',
        );
      }
      expect(refused(edited({}, without: ['age'])), FormEditorCardIssue.badAge);
    });

    test('a signing key that is not 32 bytes of base32', () {
      for (final bad in [
        '',
        'abc',
        '!!!',
        base32Encode(List.filled(31, 1)),
        base32Encode(List.filled(33, 1)),
        7,
        null,
      ]) {
        expect(
          refused(edited({'sign': bad})),
          FormEditorCardIssue.badSign,
          reason: '$bad',
        );
      }
      expect(
        refused(edited({}, without: ['sign'])),
        FormEditorCardIssue.badSign,
      );
    });

    test('a kid that is not the kid of its recipient', () {
      expect(
        refused(edited({'kid': organiserKid(otherAge)})),
        FormEditorCardIssue.badKid,
      );
      for (final bad in ['', 'abc', 7, null]) {
        expect(
          refused(edited({'kid': bad})),
          FormEditorCardIssue.badKid,
          reason: '$bad',
        );
      }
      expect(refused(edited({}, without: ['kid'])), FormEditorCardIssue.badKid);
    });

    test(
      'a recipient swapped under the same key is another card, not a forged one',
      () {
        // The attack the whole-card fingerprint exists for: keep the key, swap the recipient (and
        // its kid so the card still parses). The card is valid — and its fingerprint is different.
        final real = make();
        final forged = parsed(
          edited({'age': otherAge, 'kid': organiserKid(otherAge)}),
        );
        expect(forged.sign, real.sign);
        expect(forged.fingerprint, isNot(real.fingerprint));
      },
    );
  });

  test('isValidEditorName: the boundaries', () {
    expect(isValidEditorName('x'), isTrue);
    expect(isValidEditorName('x' * 80), isTrue);
    expect(isValidEditorName('x' * 81), isFalse);
    expect(isValidEditorName(''), isFalse);
    expect(isValidEditorName(' '), isFalse);
    expect(
      isValidEditorName('a b'),
      isTrue,
      reason: 'a space belongs inside a name',
    );
    expect(isValidEditorName('a\u001fb'), isFalse);
    expect(isValidEditorName('a b'), isTrue);
    expect(isValidEditorName('a\u007fb'), isFalse);
  });
}
