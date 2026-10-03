// Het team van de redactie (FORM_INTAKE.md §7.6): `team.json` in de werkmap, een redacteur
// toevoegen met zijn kaart en de teruggetypte vingerafdruk, en weer verwijderen.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/services/form/form_keys.dart';
import 'package:ocideck/services/form/form_team_actions.dart';
import 'package:ocideck/services/form/form_workspace.dart';
import 'package:ocideck/services/secret_store.dart';
import 'package:ocideck_form_core/ocideck_form_core.dart';
import 'package:path/path.dart' as p;

import 'support/form_key_vault.dart';
import 'support/temp_dir.dart';

void main() {
  late Directory dir;
  late FormWorkspace workspace;
  late FormKeyService owner;
  late FormKeyInfo ownerInfo;

  Future<FormKeyService> keyService() async {
    final service = FormKeyService(
      SecretStore(storage: FormKeyVault(), canStore: true),
    );
    await service.create();
    return service;
  }

  Future<FormEditorCard> cardOf(String name) async {
    final service = await keyService();
    final info = (await service.read() as FormKeyPresent).info;
    return editorCardOf(info, name);
  }

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('ocideck_team_');
    workspace = FormWorkspace(p.join(dir.path, 'werkmap'));
    owner = await keyService();
    ownerInfo = (await owner.read() as FormKeyPresent).info;
  });
  tearDown(() => deleteTempDir(dir));

  Future<FormTeamEdit> add(
    FormEditorCard card, {
    String? fingerprint,
    String? text,
    FormKeyService? keys,
  }) => addFormEditor(
    workspace,
    keys ?? owner,
    cardText: text ?? card.toText(),
    fingerprintText: fingerprint ?? formatFingerprint(card.fingerprint),
  );

  Future<List<String>> names() async => [
    for (final e
        in ((await workspace.readTeam()) as FormTeamStored).team.editors)
      e.name,
  ];

  group('team.json in de werkmap', () {
    test(
      'zonder bestand is het team leeg, en dat maakt geen bestand',
      () async {
        final read = await workspace.readTeam() as FormTeamStored;
        expect(read.team.editors, isEmpty);
        expect(File(workspace.teamPath).existsSync(), isFalse);
        expect(workspace.teamPath, p.join(workspace.root, 'team.json'));
      },
    );

    test('bewaren maakt de werkmap en leest terug', () async {
      final a = await cardOf('A');
      expect(await workspace.saveTeam(FormTeam([a])), isTrue);
      expect(await names(), ['A']);
      expect(File(workspace.teamPath).readAsStringSync(), endsWith('\n'));
    });

    test(
      'wat niet te lezen is, is beschadigd en wordt niet overschreven',
      () async {
        Directory(workspace.root).createSync(recursive: true);
        for (final bad in [
          () => File(workspace.teamPath).writeAsStringSync('geen team'),
          () => File(workspace.teamPath).writeAsBytesSync([0xff, 0xfe, 0x00]),
          () => File(
            workspace.teamPath,
          ).writeAsStringSync('{"v":2,"editors":[]}'),
        ]) {
          bad();
          final before = File(workspace.teamPath).readAsBytesSync();
          expect(await workspace.readTeam(), isA<FormTeamDamaged>());
          expect(await workspace.saveTeam(const FormTeam()), isFalse);
          expect(File(workspace.teamPath).readAsBytesSync(), before);
        }
      },
    );

    test('een map met die naam: niet te bewaren, geen uitzondering', () async {
      Directory(workspace.teamPath).createSync(recursive: true);
      expect(await workspace.saveTeam(const FormTeam()), isFalse);
    });
  });

  group('een redacteur toevoegen', () {
    test('met zijn kaart en de vingerafdruk die hij gaf', () async {
      final card = await cardOf('Tweede redacteur');
      final done = await add(card) as FormEditorAdded;
      expect(done.card.name, 'Tweede redacteur');
      expect([for (final e in done.team.editors) e.name], ['Tweede redacteur']);
      expect(await names(), ['Tweede redacteur']);
    });

    test(
      'hoofdletters, streepjes en witruimte in de vingerafdruk maken niet uit',
      () async {
        final card = await cardOf('A');
        for (final typed in [
          card.fingerprint,
          formatFingerprint(card.fingerprint).toUpperCase(),
          ' ${formatFingerprint(card.fingerprint)}\n',
        ]) {
          await workspace.saveTeam(const FormTeam());
          expect(
            await add(card, fingerprint: typed),
            isA<FormEditorAdded>(),
            reason: typed,
          );
        }
      },
    );

    test('de kaart mag opgemaakt zijn: wat telt is wat erin staat', () async {
      final card = await cardOf('A');
      final pretty = const JsonEncoder.withIndent('  ').convert(card.toJson());
      expect(await add(card, text: '\n$pretty\n'), isA<FormEditorAdded>());
    });

    test('de vingerafdruk van een andere kaart: niets verandert', () async {
      final card = await cardOf('A');
      final other = await cardOf('B');
      final outcome = await add(
        card,
        fingerprint: formatFingerprint(other.fingerprint),
      );
      expect(outcome, isA<FormTeamFingerprintWrong>());
      expect(await names(), isEmpty);
    });

    test(
      'de vingerafdruk van de ondertekeningssleutel is niet die van de kaart',
      () async {
        final service = await keyService();
        final info = (await service.read() as FormKeyPresent).info;
        final card = editorCardOf(info, 'A');
        expect(
          await add(card, fingerprint: info.fingerprint),
          isA<FormTeamFingerprintWrong>(),
        );
      },
    );

    test(
      'een kaart met een verwisseld adres heeft een andere vingerafdruk',
      () async {
        final card = await cardOf('A');
        final swapped = await cardOf('A');
        final forged = FormEditorCard(
          name: card.name,
          age: swapped.age,
          sign: card.sign,
          kid: swapped.kid,
        );
        expect(
          await add(card, text: forged.toText()),
          isA<FormTeamFingerprintWrong>(),
          reason:
              'de vingerafdruk van de echte kaart past niet bij de vervalste',
        );
        expect(await names(), isEmpty);
      },
    );

    test('wat ingetikt is geen vingerafdruk', () async {
      final card = await cardOf('A');
      for (final bad in ['', 'abcd', 'geen vingerafdruk']) {
        expect(
          await add(card, fingerprint: bad),
          isA<FormTeamBadFingerprint>(),
          reason: bad,
        );
      }
    });

    test('een tekst die geen kaart is, met de reden', () async {
      final card = await cardOf('A');
      final outcome = await add(card, text: 'geen kaart');
      expect(
        (outcome as FormTeamCardRefused).issue,
        FormEditorCardIssue.notACard,
      );
      final newer = await add(
        card,
        text: card.toText().replaceFirst('"v":1', '"v":2'),
      );
      expect(
        (newer as FormTeamCardRefused).issue,
        FormEditorCardIssue.unsupportedVersion,
      );
    });

    test('de eigen kaart van de eigenaar', () async {
      final own = editorCardOf(ownerInfo, 'Ik');
      final outcome = await add(own);
      expect((outcome as FormTeamNotAdded).issue, FormTeamAddIssue.owner);
      expect(await names(), isEmpty);
    });

    test(
      'een kaart met alleen het adres, of alleen de sleutel van de eigenaar',
      () async {
        final other = await cardOf('Anders');
        final ownAddress = FormEditorCard(
          name: 'Adres',
          age: ownerInfo.recipient,
          sign: other.sign,
          kid: ownerInfo.kid,
        );
        final ownKey = FormEditorCard(
          name: 'Sleutel',
          age: other.age,
          sign: ownerInfo.signPublicKey,
          kid: other.kid,
        );
        for (final card in [ownAddress, ownKey]) {
          final outcome = await add(card);
          expect(
            (outcome as FormTeamNotAdded).issue,
            FormTeamAddIssue.owner,
            reason: card.name,
          );
        }
        expect(await names(), isEmpty);
      },
    );

    test('dezelfde redacteur twee keer', () async {
      final card = await cardOf('A');
      await add(card);
      final again = await add(card);
      expect((again as FormTeamNotAdded).issue, FormTeamAddIssue.duplicate);
      expect(await names(), ['A']);
    });

    test(
      'een verkeerde vingerafdruk wordt gemeld vóór een dubbele kaart',
      () async {
        final card = await cardOf('A');
        await add(card);
        final other = await cardOf('B');
        expect(
          await add(card, fingerprint: formatFingerprint(other.fingerprint)),
          isA<FormTeamFingerprintWrong>(),
        );
      },
    );

    test('een vol team', () async {
      final cards = [
        for (var i = 0; i < kFormMaxEditors; i++) await cardOf('E$i'),
      ];
      await workspace.saveTeam(FormTeam(cards));
      final one = await cardOf('te veel');
      final outcome = await add(one);
      expect((outcome as FormTeamNotAdded).issue, FormTeamAddIssue.full);
    });

    test(
      'zonder bruikbare sleutel is er geen eigenaar om bij te voegen',
      () async {
        final card = await cardOf('A');
        final none = FormKeyService(
          SecretStore(storage: FormKeyVault(), canStore: true),
        );
        expect(
          (await add(card, keys: none) as FormTeamNeedsKey).problem,
          FormKeyProblem.absent,
        );
        final noStore = FormKeyService(
          SecretStore(storage: FormKeyVault(), canStore: false),
        );
        expect(
          (await add(card, keys: noStore) as FormTeamNeedsKey).problem,
          FormKeyProblem.unavailable,
        );
        expect(await names(), isEmpty);
      },
    );

    test('een team dat niet te lezen is wordt met rust gelaten', () async {
      Directory(workspace.root).createSync(recursive: true);
      File(workspace.teamPath).writeAsStringSync('geen team');
      final card = await cardOf('A');
      expect(await add(card), isA<FormTeamUnreadable>());
      expect(File(workspace.teamPath).readAsStringSync(), 'geen team');
    });

    test('een plek waar niet te schrijven valt', () async {
      Directory(workspace.teamPath).createSync(recursive: true);
      final card = await cardOf('A');
      expect(await add(card), isA<FormTeamNotSaved>());
    });
  });

  group('een redacteur verwijderen', () {
    test('op key id; de rest blijft', () async {
      final a = await cardOf('A');
      final b = await cardOf('B');
      await add(a);
      await add(b);
      final done =
          await removeFormEditor(workspace, a.kid) as FormEditorRemoved;
      expect(done.card.name, 'A');
      expect([for (final e in done.team.editors) e.name], ['B']);
      expect(await names(), ['B']);
    });

    test('een key id die er niet is', () async {
      final a = await cardOf('A');
      await add(a);
      expect(
        await removeFormEditor(workspace, 'nietbestaand'),
        isA<FormEditorUnknown>(),
      );
      expect(await names(), ['A']);
    });

    test('een team dat niet te lezen is wordt met rust gelaten', () async {
      Directory(workspace.root).createSync(recursive: true);
      File(workspace.teamPath).writeAsStringSync('geen team');
      expect(await removeFormEditor(workspace, 'x'), isA<FormTeamUnreadable>());
      expect(File(workspace.teamPath).readAsStringSync(), 'geen team');
    });

    test('een plek waar niet te schrijven valt', () async {
      final a = await cardOf('A');
      await add(a);
      File(workspace.teamPath)
        ..deleteSync()
        ..createSync();
      // Een geldig team met één redacteur, maar de map is dicht.
      File(workspace.teamPath).writeAsStringSync(FormTeam([a]).toJsonText());
      await Process.run('chmod', ['555', workspace.root]);
      addTearDown(() => Process.run('chmod', ['755', workspace.root]));
      if (Platform.isWindows) return;
      expect(await removeFormEditor(workspace, a.kid), isA<FormTeamNotSaved>());
    });
  });
}
