// The team of a form's organisers (FORM_INTAKE.md §7.6): who may be added, in what order, and how
// the team file is read back. Platform-neutral — runs in a browser too.

import 'dart:convert';

import 'package:ocideck_form_core/ocideck_form_core.dart';
import 'package:test/test.dart';

late FormSigningKey ownerKey;
late String ownerAge;

Future<FormEditorCard> card(String name) async {
  final signing = await generateFormSigningKey();
  final recipient = (await ageRecipientOf(generateAgeIdentity()))!;
  return createFormEditorCard(
    name: name,
    age: recipient,
    signPublicKey: signing.publicKey,
  );
}

FormTeam added(FormTeamAdd result) => (result as FormTeamAdded).team;

FormTeamAddIssue refusedAdd(FormTeamAdd result) =>
    (result as FormTeamAddRefused).issue;

FormTeamAdd add(FormTeam team, FormEditorCard c) =>
    team.withEditor(c, ownerAge: ownerAge, ownerSign: ownerKey.publicKeyText);

FormTeamIssue refused(String text) =>
    (parseFormTeam(text) as FormTeamRefused).issue;

FormTeam parsed(String text) => (parseFormTeam(text) as FormTeamParsed).team;

void main() {
  setUpAll(() async {
    ownerKey = await generateFormSigningKey();
    ownerAge = (await ageRecipientOf(generateAgeIdentity()))!;
  });

  test('the limits are the ones a bundle carries', () {
    expect(kFormMaxEditors, kFormMaxRecipients - 1);
    expect(kFormMaxEditors, 63);
    expect(kFormTeamVersion, 1);
  });

  group('adding an editor', () {
    test('goes last, and leaves the team it came from alone', () async {
      final a = await card('A');
      final b = await card('B');
      final one = added(add(const FormTeam(), a));
      final two = added(add(one, b));
      expect([for (final e in two.editors) e.name], ['A', 'B']);
      expect(one.editors, hasLength(1));
    });

    test('not the owner: by recipient, by signing key, by key id', () async {
      final other = await card('Anders');
      final sameAge = createFormEditorCard(
        name: 'X',
        age: ownerAge,
        signPublicKey: (await generateFormSigningKey()).publicKey,
      );
      final sameSign = createFormEditorCard(
        name: 'X',
        age: other.age,
        signPublicKey: ownerKey.publicKey,
      );
      expect(
        refusedAdd(add(const FormTeam(), sameAge)),
        FormTeamAddIssue.owner,
      );
      expect(
        refusedAdd(add(const FormTeam(), sameSign)),
        FormTeamAddIssue.owner,
      );
      // A key id that is the owner's while the recipient is not cannot be made by the card maker (the
      // kid follows from the recipient); a hand-made card object can carry it.
      final sameKid = FormEditorCard(
        name: 'X',
        age: other.age,
        sign: other.sign,
        kid: organiserKid(ownerAge),
      );
      expect(
        refusedAdd(add(const FormTeam(), sameKid)),
        FormTeamAddIssue.owner,
      );
    });

    test('not twice: the same recipient, signing key or key id', () async {
      final a = await card('A');
      final team = added(add(const FormTeam(), a));
      final sameAge = createFormEditorCard(
        name: 'B',
        age: a.age,
        signPublicKey: (await generateFormSigningKey()).publicKey,
      );
      final other = await card('C');
      final sameSign = createFormEditorCard(
        name: 'D',
        age: other.age,
        signPublicKey: base32Decode(a.sign)!,
      );
      final sameKid = FormEditorCard(
        name: 'E',
        age: other.age,
        sign: other.sign,
        kid: a.kid,
      );
      for (final dup in [a, sameAge, sameSign, sameKid]) {
        expect(
          refusedAdd(add(team, dup)),
          FormTeamAddIssue.duplicate,
          reason: dup.name,
        );
      }
    });

    test('not more than a bundle can carry', () async {
      var team = const FormTeam();
      for (var i = 0; i < kFormMaxEditors; i++) {
        team = added(add(team, await card('E$i')));
      }
      expect(team.editors, hasLength(63));
      expect(
        refusedAdd(add(team, await card('een te veel'))),
        FormTeamAddIssue.full,
      );
      expect(
        add(team.without(team.editors.first.kid), await card('past')),
        isA<FormTeamAdded>(),
      );
    });
  });

  group('removing an editor', () {
    test('by key id; another id changes nothing', () async {
      final a = await card('A');
      final b = await card('B');
      final team = added(add(added(add(const FormTeam(), a)), b));
      expect([for (final e in team.without(a.kid).editors) e.name], ['B']);
      expect(team.without('nietbestaand').editors, hasLength(2));
      expect(team.editors, hasLength(2), reason: 'immutable');
    });
  });

  group('the team file', () {
    test('writes and reads back the same team, in order', () async {
      final a = await card('A');
      final b = await card('B');
      final team = added(add(added(add(const FormTeam(), a)), b));
      final text = team.toJsonText();
      expect(text, endsWith('\n'));
      final back = parsed(text);
      expect(
        [for (final e in back.editors) e.fingerprint],
        [a.fingerprint, b.fingerprint],
      );
      expect(jsonDecode(text), containsPair('v', 1));
    });

    test('an empty team is a file too', () {
      expect(parsed(const FormTeam().toJsonText()).editors, isEmpty);
    });

    test('not JSON, not an object, a key it does not have', () {
      for (final bad in ['', 'geen json', '[]', '"x"', 'null', '{']) {
        expect(refused(bad), FormTeamIssue.notATeam, reason: bad);
      }
      expect(refused('{"v":1,"editors":[],"extra":1}'), FormTeamIssue.notATeam);
    });

    test('a version it does not read', () {
      expect(refused('{"v":2,"editors":[]}'), FormTeamIssue.unsupportedVersion);
      expect(refused('{"v":"1","editors":[]}'), FormTeamIssue.notATeam);
      expect(refused('{"editors":[]}'), FormTeamIssue.notATeam);
    });

    test(
      'editors that are not a list, or not cards, with the card named',
      () async {
        expect(refused('{"v":1,"editors":{}}'), FormTeamIssue.badEditor);
        expect(refused('{"v":1}'), FormTeamIssue.badEditor);
        expect(refused('{"v":1,"editors":["x"]}'), FormTeamIssue.badEditor);
        final c = await card('A');
        final broken = {...c.toJson(), 'kid': 'abc'};
        final result = parseFormTeam(
          jsonEncode({
            'v': 1,
            'editors': [broken],
          }),
        );
        expect((result as FormTeamRefused).issue, FormTeamIssue.badEditor);
        expect(result.card, FormEditorCardIssue.badKid);
        final noCard =
            parseFormTeam('{"v":1,"editors":[7]}') as FormTeamRefused;
        expect(noCard.card, FormEditorCardIssue.notACard);
      },
    );

    test('two entries that clash', () async {
      final a = await card('A');
      final text = jsonEncode({
        'v': 1,
        'editors': [a.toJson(), a.toJson()],
      });
      expect(refused(text), FormTeamIssue.duplicate);
    });

    test('one too many; exactly the limit is fine', () async {
      final cards = [
        for (var i = 0; i < kFormMaxEditors + 1; i++) await card('E$i'),
      ];
      String file(int n) => jsonEncode({
        'v': 1,
        'editors': [for (final c in cards.take(n)) c.toJson()],
      });
      expect(parsed(file(kFormMaxEditors)).editors, hasLength(kFormMaxEditors));
      expect(refused(file(kFormMaxEditors + 1)), FormTeamIssue.tooMany);
    });
  });
}
