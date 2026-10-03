// Een inzendpakket binnenhalen in de werkmap (FORM_INTAKE.md §7.2): de keten van
// lezen, decoderen, beoordelen, landen en registreren, en wat er van elke schakel
// overblijft als hij weigert.

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/services/form/form_import.dart';
import 'package:ocideck/services/form/form_keys.dart';
import 'package:ocideck/services/form/form_workspace.dart';
import 'package:ocideck/services/secret_store.dart';
import 'package:ocideck_form_core/ocideck_form_core.dart';
import 'package:path/path.dart' as p;

import 'support/form_key_vault.dart';
import 'support/form_photo_fixtures.dart';
import 'support/temp_dir.dart';

const String kook = '''<!-- form id=kook version=1 overview="naam" -->
# Inzending

<!-- field id=naam type=text required -->
**Naam**
<!-- answer -->
<!-- /field id=naam -->

<!-- field id=foto type=image count=0..2 -->
**Foto**
<!-- answer -->
<!-- /field id=foto -->
''';

const String sid = 'abcdefghijklmnopqrstuvwxya';
final DateTime now = DateTime.utc(2026, 10, 6, 9);

Uint8List zipOf({
  String naam = 'Sari',
  List<String> fotos = const [],
  Map<String, Uint8List> images = const {},
  String id = sid,
  String template = kook,
}) {
  var text = template.replaceFirst(
    '<!-- answer -->\n<!-- /field id=naam -->',
    '<!-- answer -->\n$naam\n<!-- /field id=naam -->',
  );
  if (fotos.isNotEmpty) {
    text = text.replaceFirst(
      '<!-- answer -->\n<!-- /field id=foto',
      '<!-- answer -->\n${fotos.map((f) => '![]($f)').join('\n')}\n<!-- /field id=foto',
    );
  }
  return buildFormPackage(
    submission: text,
    template: template,
    spec: (parseForm(template) as ParsedForm).spec,
    images: images,
    submissionId: id,
    created: DateTime.utc(2026, 10, 4),
    clientRules: kFormRulesVersion,
  );
}

void main() {
  late Directory dir;
  late FormWorkspace workspace;
  setUp(() async {
    dir = await Directory.systemTemp.createTemp('ocideck_import_');
    workspace = FormWorkspace(p.join(dir.path, 'werkmap'));
    await workspace.publishForm(kook);
  });
  tearDown(() => deleteTempDir(dir));

  Future<FormRegister> register() async =>
      (await workspace.readRegister() as FormRegisterParsed).register;

  test('een goede inzending komt in de werkmap en in het register', () async {
    final outcome =
        await importFormPackage(workspace, zipOf(), now: now) as FormImported;
    expect(outcome.sid, sid);
    expect(outcome.needsFixing, isFalse);
    expect(outcome.registerSaved, isTrue);
    expect(await workspace.submissionIds(), [sid]);
    final row = (await register()).row(sid)!;
    expect(row.status, 'received');
    expect(row.valueOf('naam'), 'Sari');
    expect(row.received, '2026-10-06');
  });

  test('een inzending met een fout komt er wel in, als needs-fixing', () async {
    final outcome =
        await importFormPackage(workspace, zipOf(naam: ''), now: now)
            as FormImported;
    expect(outcome.needsFixing, isTrue);
    expect(outcome.review.problems.map((p) => p.code), [
      FormIssueCode.requiredEmpty,
    ]);
    expect(await workspace.submissionIds(), [sid]);
    expect((await register()).row(sid)!.status, kFormStateNeedsFixing);
  });

  test(
    'een formulier dat niet is toegevoegd: niets landt, niets in het register',
    () async {
      final other = FormWorkspace(p.join(dir.path, 'leeg'));
      final outcome = await importFormPackage(other, zipOf(), now: now);
      expect(outcome, isA<FormImportUnknownForm>());
      expect(
        (outcome as FormImportUnknownForm).review.problems.single.code,
        FormIssueCode.templateUnknown,
      );
      expect(await other.submissionIds(), isEmpty);
      expect(await other.readRegister(), isNull);
    },
  );

  test('wat geen pakket is, wordt gemeld met waarom', () async {
    final outcome = await importFormPackage(
      workspace,
      Uint8List.fromList([1, 2, 3, 4]),
      now: now,
    );
    expect(outcome, isA<FormImportNotAPackage>());
    expect(
      (outcome as FormImportNotAPackage).problems.single.issue,
      FormPackageIssue.badZip,
    );
    expect(await workspace.submissionIds(), isEmpty);
  });

  test('dezelfde inzending twee keer: de tweede overschrijft niets', () async {
    await importFormPackage(workspace, zipOf(), now: now);
    final again = await importFormPackage(
      workspace,
      zipOf(naam: 'Iemand anders'),
      now: now,
    );
    expect(again, isA<FormImportDuplicate>());
    expect((again as FormImportDuplicate).sid, sid);
    expect((await register()).rows, hasLength(1));
    expect((await register()).row(sid)!.valueOf('naam'), 'Sari');
  });

  test(
    'inzendingen komen in de volgorde van binnenkomst in het register',
    () async {
      for (final id in ['abcdefghijklmnopqrstuvwxyc', sid]) {
        await importFormPackage(workspace, zipOf(id: id), now: now);
      }
      expect(
        [for (final r in (await register()).rows) r.sid],
        ['abcdefghijklmnopqrstuvwxyc', sid],
      );
    },
  );

  group('de foto\'s', () {
    const path = 'images/foto-1.jpg';

    test('een echte foto landt, gezuiverd', () async {
      final outcome =
          await importFormPackage(
                workspace,
                zipOf(fotos: [path], images: {path: jpegPhoto(gps: true)}),
                now: now,
              )
              as FormImported;
      expect(outcome.needsFixing, isFalse);
      expect(outcome.review.strippedAgain[path]!.gps, isTrue);
      final onDisk = await File(
        p.join(workspace.submissionPath(sid), path),
      ).readAsBytes();
      expect(cleanImage(onDisk)!.removed.gps, isFalse);
    });

    test(
      'een bestand dat zich als foto voordoet maar niet decodeert: needs-fixing',
      () async {
        final outcome =
            await importFormPackage(
                  workspace,
                  zipOf(fotos: [path], images: {path: fakeJpeg()}),
                  now: now,
                )
                as FormImported;
        expect(outcome.needsFixing, isTrue);
        expect(outcome.review.problems.map((p) => p.code), [
          FormIssueCode.imageFormat,
        ]);
        expect((await register()).row(sid)!.status, kFormStateNeedsFixing);
      },
    );

    test('een HEIC wordt nooit gedecodeerd en alleen gewaarschuwd', () async {
      const heic = 'images/foto-1.heic';
      final outcome =
          await importFormPackage(
                workspace,
                zipOf(fotos: [heic], images: {heic: heicPhoto()}),
                now: now,
              )
              as FormImported;
      expect(outcome.needsFixing, isFalse);
      expect(outcome.review.problems.map((p) => p.code), [
        FormIssueCode.imageHeicUnverified,
      ]);
      expect(
        await File(p.join(workspace.submissionPath(sid), heic)).readAsBytes(),
        heicPhoto(),
      );
    });
  });

  group('het register', () {
    test(
      'dat niet te lezen is blijft zoals het was; de inzending staat er wel',
      () async {
        await Directory(workspace.root).create(recursive: true);
        await File(
          workspace.registerPath,
        ).writeAsString('Mijn aantekeningen.\n');
        final outcome =
            await importFormPackage(workspace, zipOf(), now: now)
                as FormImported;
        expect(outcome.registerSaved, isFalse);
        expect(await workspace.submissionIds(), [sid]);
        expect(
          await File(workspace.registerPath).readAsString(),
          'Mijn aantekeningen.\n',
        );
      },
    );

    test(
      'waar niet in te schrijven valt, meldt dat de rij niet is gezet',
      () async {
        await Directory(workspace.registerPath).create(recursive: true);
        final outcome =
            await importFormPackage(workspace, zipOf(), now: now)
                as FormImported;
        expect(outcome.registerSaved, isFalse);
        expect(await workspace.submissionIds(), [sid]);
      },
    );

    test(
      'een rij die er al stond (de map was weg) wordt niet dubbel gezet',
      () async {
        await importFormPackage(workspace, zipOf(), now: now);
        await Directory(workspace.submissionPath(sid)).delete(recursive: true);
        final outcome =
            await importFormPackage(workspace, zipOf(), now: now)
                as FormImported;
        expect(outcome.registerSaved, isTrue);
        expect((await register()).rows, hasLength(1));
      },
    );
  });

  test(
    'een werkmap waar niet te schrijven valt: niets blijft liggen',
    () async {
      await Directory(workspace.root).create(recursive: true);
      await File(
        p.join(workspace.root, 'submissions'),
      ).writeAsString('geen map');
      expect(
        await importFormPackage(workspace, zipOf(), now: now),
        isA<FormImportFailed>(),
      );
    },
  );

  group('verzegeld', () {
    late FormKeyVault vault;
    late FormKeyService keys;
    late FormKeyInfo mine;
    setUp(() async {
      vault = FormKeyVault();
      keys = FormKeyService(SecretStore(storage: vault, canStore: true));
      mine = ((await keys.create()) as FormKeyWritten).info;
    });

    Future<Uint8List> sealedFor(String recipient, {Uint8List? zip}) async =>
        (await sealFormPackage(zip ?? zipOf(), recipients: [recipient])
                as FormSealed)
            .bytes;

    Future<FormImportOutcome> import(Uint8List bytes, {FormKeyService? use}) =>
        importFormFile(workspace, bytes, now: now, keys: use ?? keys);

    test(
      'een pakket voor mijn sleutel opent en komt binnen als een gewoon',
      () async {
        final outcome =
            await import(await sealedFor(mine.recipient)) as FormImported;
        expect(outcome.wasSealed, isTrue);
        expect(outcome.sid, sid);
        expect(outcome.registerSaved, isTrue);
        expect(await workspace.submissionIds(), [sid]);
        final row = (await register()).row(sid)!;
        expect(row.status, 'received');
        expect(row.valueOf('naam'), 'Sari');
      },
    );

    test(
      'een gewone zip gaat langs de oude weg, zonder sleutel te vragen',
      () async {
        final nokey = FormKeyService(
          SecretStore(storage: FormKeyVault(), canStore: true),
        );
        final outcome = await import(zipOf(), use: nokey) as FormImported;
        expect(outcome.wasSealed, isFalse);
        expect(await workspace.submissionIds(), [sid]);
      },
    );

    test(
      'een verzegeld pakket met fouten komt er wel in, als needs-fixing',
      () async {
        final outcome =
            await import(await sealedFor(mine.recipient, zip: zipOf(naam: '')))
                as FormImported;
        expect(outcome.wasSealed, isTrue);
        expect(outcome.needsFixing, isTrue);
        expect((await register()).row(sid)!.status, kFormStateNeedsFixing);
      },
    );

    test(
      'verzegeld voor een ander: niets landt en het zegt dat het de verkeerde sleutel is',
      () async {
        final other =
            (await FormKeyService(
                      SecretStore(storage: FormKeyVault(), canStore: true),
                    ).create()
                    as FormKeyWritten)
                .info;
        final outcome = await import(await sealedFor(other.recipient));
        expect(
          (outcome as FormImportNotOpened).issue,
          FormUnsealIssue.noIdentityMatched,
        );
        expect(await workspace.submissionIds(), isEmpty);
        expect(await workspace.readRegister(), isNull);
      },
    );

    test('een veranderd pakket gaat niet open en laat niets achter', () async {
      final bytes = await sealedFor(mine.recipient);
      bytes[bytes.length - 1] ^= 1;
      final outcome = await import(bytes);
      expect((outcome as FormImportNotOpened).issue, FormUnsealIssue.tampered);
      expect(await workspace.submissionIds(), isEmpty);
    });

    test('een afgekapt pakket gaat niet open', () async {
      final bytes = await sealedFor(mine.recipient);
      final outcome = await import(bytes.sublist(0, bytes.length - 40));
      expect((outcome as FormImportNotOpened).issue, FormUnsealIssue.tampered);
    });

    test(
      'een age-bestand met pantser wordt als zodanig geweigerd, niet als zip',
      () async {
        final armored = Uint8List.fromList(
          '-----BEGIN AGE ENCRYPTED FILE-----\nAAAA\n-----END AGE ENCRYPTED FILE-----\n'
              .codeUnits,
        );
        final outcome = await import(armored);
        expect((outcome as FormImportNotOpened).issue, FormUnsealIssue.notAge);
      },
    );

    test(
      'een verzegeld bestand dat geen pakket bevat is geen inzendpakket',
      () async {
        // Het publieke testbestand van het age-project: voor een bekende sleutel, met als
        // inhoud geen zip. De sleutel erbij gaat via een herstelsleutel naar de sleutelhanger.
        final text = latin1.decode(
          File(
            'packages/ocideck_form_core/test/fixtures/age_testkit/x25519',
          ).readAsBytesSync(),
        );
        final identity = RegExp(
          r'^identity: (\S+)$',
          multiLine: true,
        ).firstMatch(text)!.group(1)!;
        final file = Uint8List.fromList(
          latin1.encode(text.substring(text.indexOf('\n\n') + 2)),
        );
        final known = FormKeyService(
          SecretStore(storage: FormKeyVault(), canStore: true),
        );
        await known.restore(
          encodeFormRecoveryKey(
            signingSeed: Uint8List(32),
            ageIdentity: identity,
          ),
        );
        final outcome = await import(file, use: known);
        expect(outcome, isA<FormImportNotAPackage>());
        expect((outcome as FormImportNotAPackage).problems, isNotEmpty);
        expect(await workspace.submissionIds(), isEmpty);
      },
    );

    group('zonder bruikbare sleutel is er niets geprobeerd', () {
      late Uint8List sealed;
      setUp(() async => sealed = await sealedFor(mine.recipient));

      Future<void> expectNeedsKey(
        FormKeyService use,
        FormImportKeyProblem problem,
      ) async {
        final outcome = await import(sealed, use: use);
        expect((outcome as FormImportNeedsKey).problem, problem);
        expect(await workspace.submissionIds(), isEmpty);
        expect(await workspace.readRegister(), isNull);
      }

      test('er is nog geen sleutel', () async {
        await expectNeedsKey(
          FormKeyService(SecretStore(storage: FormKeyVault(), canStore: true)),
          FormImportKeyProblem.absent,
        );
      });

      test('dit platform heeft geen sleutelhanger', () async {
        await expectNeedsKey(
          FormKeyService(SecretStore(storage: vault, canStore: false)),
          FormImportKeyProblem.unavailable,
        );
      });

      test('de sleutelhanger geeft geen antwoord', () async {
        vault.failRead = true;
        await expectNeedsKey(keys, FormImportKeyProblem.unreadable);
      });

      test('wat er staat is geen sleutel', () async {
        vault.data[SecretStore.formEditorialKeyKey] = 'geen sleutel';
        await expectNeedsKey(keys, FormImportKeyProblem.damaged);
      });
    });
  });
}
