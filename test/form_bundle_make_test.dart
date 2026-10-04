// Een bundel publiceren (FORM_INTAKE.md §5.1, §7.6): wat er ondertekend wordt, hoe het volgnummer
// loopt, en elke reden waarom er niets ondertekend wordt.

import 'dart:io';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/services/form/form_bundle_make.dart';
import 'package:ocideck/services/form/form_keys.dart';
import 'package:ocideck/services/form/form_workspace.dart';
import 'package:ocideck/services/secret_store.dart';
import 'package:ocideck_form_core/ocideck_form_core.dart';
import 'package:path/path.dart' as p;

import 'support/form_key_vault.dart';
import 'support/temp_dir.dart';

String formText({
  String id = 'kook',
  String lang = 'nl',
  String controller = 'Indo IT Kookboek-team',
  String closes = '2026-12-01',
}) =>
    '''<!-- form id=$id version=1 lang=$lang controller="$controller" contact="kook@example.org" retain-unused="6 maanden" closes="$closes" overview="naam" -->
# Inzending

<!-- field id=naam type=text required -->
**Naam**
<!-- answer -->
<!-- /field id=naam -->
''';

final DateTime now = DateTime.utc(2026, 10, 6, 9);

void main() {
  late Directory dir;
  late FormWorkspace workspace;
  late FormKeyVault vault;
  late FormKeyService keys;
  late FormKeyInfo mine;
  late PublishedForm form;
  var seed = 0;

  Future<PublishedForm> add(String text) async {
    final outcome = await workspace.publishForm(text) as FormPublished;
    return outcome.form;
  }

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('ocideck_bundle_');
    workspace = FormWorkspace(p.join(dir.path, 'werkmap'));
    vault = FormKeyVault();
    keys = FormKeyService(SecretStore(storage: vault, canStore: true));
    mine = ((await keys.create()) as FormKeyWritten).info;
    expect(
      await keys.verifyRecovery((await keys.recoveryKey())!),
      isA<FormKeyVerified>(),
    );
    form = await add(formText());
    seed = 0;
  });
  tearDown(() => deleteTempDir(dir));

  Future<FormBundleOutcome> publish({
    PublishedForm? target,
    String name = 'Indo IT Kookboek-team',
    String expires = '2026-12-15',
    FormKeyService? use,
    Random? random,
  }) => makeFormBundle(
    workspace,
    target ?? form,
    keys: use ?? keys,
    organiserName: name,
    expires: expires,
    now: now,
    random: random ?? Random(++seed),
  );

  FormBundleMade published(FormBundleOutcome o) => o as FormBundleMade;

  Future<FormBundle> verified(FormBundleMade done, PublishedForm of) async {
    final text = File(done.path).readAsStringSync();
    final result = await verifyFormBundle(
      text,
      templateText: of.text,
      fingerprint: mine.fingerprint,
      now: now,
    );
    return (result as FormBundleVerified).bundle;
  }

  group('wat er wordt ondertekend', () {
    test('een bundel die een invuller met de vingerafdruk gelooft', () async {
      final done = published(await publish());
      expect(
        done.path,
        p.join(
          workspace.root,
          'forms',
          'kook',
          'v1',
          'template.nl.bundle.json',
        ),
      );
      expect(done.fingerprint, formatFingerprint(mine.fingerprint));
      final bundle = await verified(done, form);
      expect(bundle.bundleSeq, 1);
      expect(bundle.formId, 'kook');
      expect(bundle.expires, '2026-12-15');
      expect(bundle.organisers.single.name, 'Indo IT Kookboek-team');
      expect(bundle.organisers.single.age, mine.recipient);
      expect(bundle.organisers.single.sign, mine.signPublicKey);
      expect(bundle.organisers.single.kid, mine.kid);
      expect(bundle.templateSha256, formTemplateHash(form.text));
    });

    test(
      'sluitingsdag en bewaartermijn komen uit het formulier zelf',
      () async {
        final bundle = await verified(published(await publish()), form);
        expect(bundle.policy.closes, '2026-12-01');
        expect(bundle.policy.retainUnused, '6 maanden');
      },
    );

    test('een andere vingerafdruk geloofde de bundel niet', () async {
      final done = published(await publish());
      final other = await generateFormSigningKey();
      final result = await verifyFormBundle(
        File(done.path).readAsStringSync(),
        templateText: form.text,
        fingerprint: other.fingerprint,
        now: now,
      );
      expect(result, isA<FormBundleRefused>());
    });

    test('de naam wordt bijgesneden, niet doorgelaten met witruimte', () async {
      final bundle = await verified(
        published(await publish(name: '  Redactie  ')),
        form,
      );
      expect(bundle.organisers.single.name, 'Redactie');
    });

    test('een spatie hoort bij een naam, ook binnenin', () async {
      final bundle = await verified(
        published(await publish(name: 'Het Kookboek Team')),
        form,
      );
      expect(bundle.organisers.single.name, 'Het Kookboek Team');
    });

    test('de naam mag 80 tekens zijn', () async {
      final bundle = await verified(
        published(await publish(name: 'x' * 80)),
        form,
      );
      expect(bundle.organisers.single.name, hasLength(80));
    });
  });

  group('volgnummer en fid', () {
    test(
      'elke nieuwe bundel heeft een hoger volgnummer en hetzelfde fid',
      () async {
        final first = published(await publish());
        final second = published(await publish());
        final a = await verified(first, form);
        expect(second.path, first.path, reason: 'de nieuwe vervangt de oude');
        final b = await verified(second, form);
        expect(b.bundleSeq, 2);
        expect(b.fid, a.fid);
        expect(isValidFormId(a.fid), isTrue);
      },
    );

    test(
      'een andere taal heeft zijn eigen bundel, maar telt door op hetzelfde fid',
      () async {
        final nl = published(await publish());
        final en = await add(formText(lang: 'en'));
        final done = published(await publish(target: en));
        expect(done.path, endsWith('template.en.bundle.json'));
        expect(done.path, isNot(nl.path));
        final a = await verified(nl, form);
        final b = await verified(done, en);
        expect(b.fid, a.fid);
        expect(
          b.bundleSeq,
          2,
          reason: 'een invuller die 1 zag, gelooft 1 niet meer onder 2',
        );
      },
    );

    test('een andere versie van het formulier telt ook door', () async {
      published(await publish());
      final v2 = await add(formText().replaceFirst('version=1', 'version=2'));
      final done = published(await publish(target: v2));
      expect(done.path, contains('v2'));
      expect((await verified(done, v2)).bundleSeq, 2);
    });

    test('een ander formulier heeft een eigen fid en begint bij 1', () async {
      final a = await verified(published(await publish()), form);
      final other = await add(formText(id: 'soep'));
      final b = await verified(
        published(await publish(target: other, random: Random(2))),
        other,
      );
      expect(b.fid, isNot(a.fid));
      expect(b.bundleSeq, 1);
    });

    test(
      'het hoogste volgnummer van alle bundels telt, niet het laatste dat de map noemt',
      () async {
        final en = await add(formText(lang: 'en'));
        const fid = 'abcdefghijklmnopqrstuvwxyz';
        File(
          workspace.bundlePathOf(en),
        ).writeAsStringSync('{"fid": "$fid", "bundle_seq": 7}');
        File(
          workspace.bundlePathOf(form),
        ).writeAsStringSync('{"fid": "$fid", "bundle_seq": 2}');
        final bundle = await verified(published(await publish()), form);
        expect(bundle.bundleSeq, 8);
        expect(bundle.fid, fid);
      },
    );

    test(
      'een bundel die niet te lezen is: niets wordt ondertekend of overschreven',
      () async {
        final path = workspace.bundlePathOf(form);
        File(path).writeAsStringSync('geen bundel');
        final outcome = await publish();
        expect((outcome as FormBundleExistingUnreadable).paths, [path]);
        expect(File(path).readAsStringSync(), 'geen bundel');
      },
    );

    test('een bundel die geen UTF-8 is telt ook als onleesbaar', () async {
      final path = workspace.bundlePathOf(form);
      File(path).writeAsBytesSync([0xff, 0xfe, 0x00]);
      expect(await publish(), isA<FormBundleExistingUnreadable>());
    });

    test(
      'een bundel zonder bruikbaar volgnummer of fid is geen bundel',
      () async {
        final path = workspace.bundlePathOf(form);
        for (final text in [
          '[]',
          '{}',
          '{"fid": "abcdefghijklmnopqrstuvwxyz", "bundle_seq": 0}',
          '{"fid": "abcdefghijklmnopqrstuvwxyz", "bundle_seq": "1"}',
          '{"fid": "te kort", "bundle_seq": 1}',
        ]) {
          File(path).writeAsStringSync(text);
          expect(
            await publish(),
            isA<FormBundleExistingUnreadable>(),
            reason: text,
          );
        }
      },
    );

    test(
      'twee bundels die het oneens zijn over het fid: er wordt niets ondertekend',
      () async {
        published(await publish());
        final en = await add(formText(lang: 'en'));
        File(workspace.bundlePathOf(en)).writeAsStringSync(
          '{"fid": "abcdefghijklmnopqrstuvwxyz", "bundle_seq": 9}',
        );
        final outcome = await publish();
        expect(outcome, isA<FormBundleExistingUnreadable>());
        expect((outcome as FormBundleExistingUnreadable).paths, hasLength(1));
      },
    );
  });

  group('welke bestanden een bundel zijn', () {
    test('alleen *.bundle.json onder v<n>, van dit formulier', () async {
      final versionDir = p.dirname(form.path);
      File(p.join(versionDir, 'notities.json')).writeAsStringSync('rommel');
      File(
        p.join(versionDir, 'template.nl.bundle.bak'),
      ).writeAsStringSync('rommel');
      final draft = Directory(
        p.join(workspace.root, 'forms', 'kook', 'concept'),
      )..createSync(recursive: true);
      File(p.join(draft.path, 'x.bundle.json')).writeAsStringSync('rommel');
      final other = await add(formText(id: 'soep'));
      File(workspace.bundlePathOf(other)).writeAsStringSync('rommel');
      final found = await workspace.bundlesOf('kook');
      expect(found.bundles, isEmpty);
      expect(found.unreadable, isEmpty);
      expect(await publish(), isA<FormBundleMade>());
    });

    test('een map met een bundelnaam is geen bundel', () async {
      Directory(workspace.bundlePathOf(form)).createSync();
      final found = await workspace.bundlesOf('kook');
      expect(found.bundles, isEmpty);
      expect(found.unreadable, isEmpty);
    });

    test('een formulier-id dat geen id is, opent geen enkele map', () async {
      for (final id in ['', '..', '../kook', 'Kook', 'koo/k']) {
        final found = await workspace.bundlesOf(id);
        expect(found.bundles, isEmpty, reason: id);
        expect(found.unreadable, isEmpty, reason: id);
      }
    });

    test('een formulier zonder map is geen fout maar niets', () async {
      final found = await workspace.bundlesOf('onbekend');
      expect(found.bundles, isEmpty);
      expect(found.unreadable, isEmpty);
    });

    test('een pad naar buiten forms/ komt er niet doorheen', () async {
      final outside = Directory(
        p.join(workspace.root, 'forms', '..', 'verstopt', 'v1'),
      )..createSync(recursive: true);
      File(p.join(outside.path, 'x.bundle.json')).writeAsStringSync('rommel');
      final found = await workspace.bundlesOf('../verstopt');
      expect(found.bundles, isEmpty);
      expect(found.unreadable, isEmpty);
    });

    test('de bundels komen gesorteerd op pad', () async {
      final en = await add(formText(lang: 'en'));
      published(await publish());
      published(await publish(target: en));
      final paths = [
        for (final b in (await workspace.bundlesOf('kook')).bundles) b.path,
      ];
      expect(paths, [...paths]..sort());
      expect(paths, hasLength(2));
    });
  });

  group('zonder bruikbare sleutel wordt er niets ondertekend', () {
    Future<void> expectNeedsKey(
      FormKeyService use,
      FormKeyProblem problem,
    ) async {
      final outcome = await publish(use: use);
      expect((outcome as FormBundleNeedsKey).problem, problem);
      expect(File(workspace.bundlePathOf(form)).existsSync(), isFalse);
    }

    test('er is nog geen sleutel', () async {
      await expectNeedsKey(
        FormKeyService(SecretStore(storage: FormKeyVault(), canStore: true)),
        FormKeyProblem.absent,
      );
    });

    test('dit platform heeft geen sleutelhanger', () async {
      await expectNeedsKey(
        FormKeyService(SecretStore(storage: vault, canStore: false)),
        FormKeyProblem.unavailable,
      );
    });

    test('de sleutelhanger geeft geen antwoord', () async {
      vault.failRead = true;
      await expectNeedsKey(keys, FormKeyProblem.unreadable);
    });

    test('wat er staat is geen sleutel', () async {
      vault.data[SecretStore.formEditorialKeyKey] = 'geen sleutel';
      await expectNeedsKey(keys, FormKeyProblem.damaged);
    });
  });

  test(
    'een herstelsleutel die niet is teruggetypt houdt de bundel tegen',
    () async {
      final fresh = FormKeyService(
        SecretStore(storage: FormKeyVault(), canStore: true),
      );
      await fresh.create();
      final outcome = await publish(use: fresh);
      expect(outcome, isA<FormBundleRecoveryNotChecked>());
      expect(File(workspace.bundlePathOf(form)).existsSync(), isFalse);
      expect(
        await fresh.verifyRecovery((await fresh.recoveryKey())!),
        isA<FormKeyVerified>(),
      );
      expect(await publish(use: fresh), isA<FormBundleMade>());
    },
  );

  group('het team', () {
    Future<FormEditorCard> editor(String name) async {
      final other = FormKeyService(
        SecretStore(storage: FormKeyVault(), canStore: true),
      );
      await other.create();
      return editorCardOf((await other.read() as FormKeyPresent).info, name);
    }

    test(
      'de redacteurs staan na de eigenaar in de bundel, in volgorde',
      () async {
        final a = await editor('Eerste');
        final b = await editor('Tweede');
        await workspace.saveTeam(FormTeam([a, b]));
        final bundle = await verified(published(await publish()), form);
        expect(
          [for (final o in bundle.organisers) o.name],
          ['Indo IT Kookboek-team', 'Eerste', 'Tweede'],
        );
        expect(bundle.organisers[1].age, a.age);
        expect(bundle.organisers[1].sign, a.sign);
        expect(bundle.organisers[1].kid, a.kid);
        expect(bundle.organisers[0].age, mine.recipient);
      },
    );

    test(
      'een tweede sleutel is een herstelweg: de herstelsleutel hoeft niet terug',
      () async {
        final fresh = FormKeyService(
          SecretStore(storage: FormKeyVault(), canStore: true),
        );
        final info = ((await fresh.create()) as FormKeyWritten).info;
        expect(await publish(use: fresh), isA<FormBundleRecoveryNotChecked>());
        await workspace.saveTeam(FormTeam([await editor('Tweede')]));
        final done = published(await publish(use: fresh));
        final text = File(done.path).readAsStringSync();
        final result = await verifyFormBundle(
          text,
          templateText: form.text,
          fingerprint: info.fingerprint,
          now: now,
        );
        expect((result as FormBundleVerified).bundle.organisers, hasLength(2));
      },
    );

    test('zonder team blijft het de eigenaar alleen', () async {
      final bundle = await verified(published(await publish()), form);
      expect(bundle.organisers, hasLength(1));
    });

    test('een team dat niet te lezen is: niets wordt ondertekend', () async {
      Directory(workspace.root).createSync(recursive: true);
      File(workspace.teamPath).writeAsStringSync('geen team');
      expect(await publish(), isA<FormBundleTeamUnreadable>());
      expect(File(workspace.bundlePathOf(form)).existsSync(), isFalse);
      expect(File(workspace.teamPath).readAsStringSync(), 'geen team');
    });
  });

  group('wat de redacteur invult', () {
    Future<void> expectBad(
      FormBundleInputField field, {
      String name = 'Redactie',
      String expires = '2026-12-15',
    }) async {
      final outcome = await publish(name: name, expires: expires);
      expect((outcome as FormBundleBadInput).field, field);
      expect(File(workspace.bundlePathOf(form)).existsSync(), isFalse);
    }

    test(
      'een naam is niet leeg, hooguit 80 tekens en zonder stuurtekens',
      () async {
        await expectBad(FormBundleInputField.name, name: '');
        await expectBad(FormBundleInputField.name, name: '   ');
        await expectBad(FormBundleInputField.name, name: 'x' * 81);
        await expectBad(FormBundleInputField.name, name: 'Re\u0000dactie');
        await expectBad(FormBundleInputField.name, name: 'Re\u007fdactie');
        await expectBad(FormBundleInputField.name, name: 'Re\u001fdactie');
      },
    );

    test('een geldigheid is een datum die bestaat', () async {
      for (final bad in [
        '',
        '2026-13-01',
        '2026-02-30',
        '15-12-2026',
        'morgen',
      ]) {
        await expectBad(FormBundleInputField.expires, expires: bad);
      }
    });

    test(
      'een geldigheid eindigt niet vóór de sluitingsdag, op de dag zelf mag het',
      () async {
        await expectBad(
          FormBundleInputField.expiresBeforeCloses,
          expires: '2026-11-30',
        );
        expect(await publish(expires: '2026-12-01'), isA<FormBundleMade>());
      },
    );
  });

  group('wat de kern weigert', () {
    test('een formulier dat geen formulier meer is', () async {
      final broken = PublishedForm(
        id: form.id,
        version: form.version,
        lang: form.lang,
        text: 'geen formulier',
        path: form.path,
      );
      final outcome = await publish(target: broken);
      expect(
        (outcome as FormBundleRefusedByCore).issue,
        FormBundleCreateIssue.notAForm,
      );
    });

    test('een bewaartermijn die de bundel niet draagt', () async {
      final long = await add(
        formText(id: 'lang').replaceFirst('"6 maanden"', '"${'x' * 201}"'),
      );
      final outcome = await publish(target: long);
      expect(outcome, isA<FormBundleRefusedByCore>());
      expect(
        (outcome as FormBundleRefusedByCore).issue,
        FormBundleCreateIssue.invalid,
      );
      expect(File(workspace.bundlePathOf(long)).existsSync(), isFalse);
    });
  });

  test(
    'een plek waar niet te schrijven valt: niet bewaard, en dat staat er',
    () async {
      Directory(workspace.bundlePathOf(form)).createSync();
      expect(await publish(), isA<FormBundleNotWritten>());
    },
  );

  group('beginwaarden', () {
    test('geldig tot is de sluitingsdag, of anders een jaar verder', () {
      expect(defaultBundleExpiry(now, '2027-01-31'), '2027-01-31');
      expect(defaultBundleExpiry(now, null), '2027-10-06');
      expect(defaultBundleExpiry(now, 'geen datum'), '2027-10-06');
      expect(defaultBundleExpiry(now, '2027-02-30'), '2027-10-06');
    });

    test('de naam is wie het formulier verwerkt, anders Redactie', () {
      FormSpec spec(String text) => (parseForm(text) as ParsedForm).spec;
      expect(
        defaultBundleOrganiserName(spec(formText())),
        'Indo IT Kookboek-team',
      );
      expect(
        defaultBundleOrganiserName(spec(formText(controller: ' Team '))),
        'Team',
        reason: 'witruimte rond de naam hoort er niet bij',
      );
      expect(
        defaultBundleOrganiserName(
          spec(
            formText().replaceFirst(' controller="Indo IT Kookboek-team"', ''),
          ),
        ),
        'Redactie',
      );
    });
  });
}
