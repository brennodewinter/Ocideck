// De redactiesleutel (FORM_INTAKE.md §5.9): onvervangbaar, dus nooit overschreven, nooit
// aangenomen dat hij er niet is als de sleutelhanger niet te lezen was, en altijd teruggelezen.

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/services/form/form_keys.dart';
import 'package:ocideck/services/secret_store.dart';
import 'package:ocideck_form_core/ocideck_form_core.dart';

import 'support/form_key_vault.dart';

const String _slot = SecretStore.formEditorialKeyKey;

void main() {
  late FormKeyVault vault;
  late FormKeyService service;
  final day = DateTime.utc(2026, 11, 3);

  setUp(() {
    vault = FormKeyVault();
    service = FormKeyService(
      SecretStore(storage: vault, canStore: true),
      now: () => day,
    );
  });

  Future<FormKeyPresent> created() async {
    final r = await service.create() as FormKeyWritten;
    return FormKeyPresent(r.key, r.info);
  }

  group('lezen', () {
    test('zonder sleutelhanger: er kan hier geen sleutel zijn', () async {
      final none = FormKeyService(SecretStore(storage: vault, canStore: false));
      expect(await none.read(), isA<FormKeyUnavailable>());
      expect(vault.writes, isEmpty);
    });

    test('een lege sleutelhanger is leeg', () async {
      expect(await service.read(), isA<FormKeyAbsent>());
    });

    test('een sleutelhanger die niet te lezen is, is niet leeg', () async {
      vault.failRead = true;
      expect(await service.read(), isA<FormKeyUnreadable>());
    });

    test('wat erin staat en geen sleutel is, is beschadigd', () async {
      final good =
          jsonDecode((await created()).key.toJsonText())
              as Map<String, Object?>;
      for (final bad in <Object?>[
        'geen json',
        '[]',
        '{}',
        {...good, 'v': 2},
        {...good, 'v': '1'},
        {...good, 'identity': 'garbage'},
        {...good, 'identity': (good['identity']! as String).toLowerCase()},
        {...good, 'identity': null},
        {...good, 'signing_seed': 'abc'},
        {...good, 'signing_seed': base32Encode(Uint8List(31))},
        {...good, 'signing_seed': base32Encode(Uint8List(33))},
        {...good, 'signing_seed': 7},
        {...good, 'created': '2026-02-30'},
        {...good, 'created': 5},
        {...good, 'recovery_verified': 'ja'},
        {...good, 'recovery_verified': null},
      ]) {
        vault.data[_slot] = bad is String ? bad : jsonEncode(bad);
        expect(await service.read(), isA<FormKeyDamaged>(), reason: '$bad');
      }
    });

    test('een sleutel heeft een publieke kant die klopt', () async {
      final present = await created();
      final info = present.info;
      expect(info.recipient, await ageRecipientOf(present.key.ageIdentity));
      expect(info.kid, organiserKid(info.recipient));
      expect(info.kid, hasLength(26));
      final signing = await formSigningKeyFromSeed(present.key.signingSeed);
      expect(info.signPublicKey, signing.publicKeyText);
      expect(info.fingerprint, signing.fingerprint);
      expect(info.fingerprint, hasLength(52));
      expect(info.created, '2026-11-03');
      expect(info.recoveryVerified, isFalse);
    });

    test('het zaad is een eigen kopie', () {
      final seed = Uint8List(32);
      final key = FormEditorialKey(
        ageIdentity: generateAgeIdentity(),
        signingSeed: seed,
        created: '2026-11-03',
      );
      seed[0] = 9;
      expect(key.signingSeed[0], 0);
    });

    test(
      'de opgeslagen tekst heeft versie 1 en de velden die erin horen',
      () async {
        final key = (await created()).key;
        final json = jsonDecode(key.toJsonText()) as Map<String, Object?>;
        expect(kFormEditorialKeyVersion, 1);
        expect(json['v'], 1);
        expect(json.keys.toSet(), {
          'v',
          'identity',
          'signing_seed',
          'created',
          'recovery_verified',
        });
        expect(json['recovery_verified'], isFalse);
        expect(base32Decode(json['signing_seed']! as String), key.signingSeed);
      },
    );

    test('de opgeslagen tekst gaat heen en weer', () async {
      final key = (await created()).key;
      final back = FormEditorialKey.fromJsonText(key.toJsonText())!;
      expect(back.ageIdentity, key.ageIdentity);
      expect(back.signingSeed, key.signingSeed);
      expect(back.created, key.created);
      expect(back.recoveryVerified, key.recoveryVerified);
      final verified = FormEditorialKey.fromJsonText(
        key.withRecoveryVerified().toJsonText(),
      )!;
      expect(verified.recoveryVerified, isTrue);
    });
  });

  group('aanmaken', () {
    test('maakt een sleutel, bewaart hem en leest hem terug', () async {
      final r = await service.create() as FormKeyWritten;
      expect(vault.writes, [_slot]);
      expect(isAgeIdentity(r.key.ageIdentity), isTrue);
      expect(r.key.signingSeed, hasLength(32));
      expect(r.key.created, '2026-11-03');
      expect(r.key.recoveryVerified, isFalse);
      final read = await service.read() as FormKeyPresent;
      expect(read.key.ageIdentity, r.key.ageIdentity);
      expect(read.info.fingerprint, r.info.fingerprint);
    });

    test('twee keer: de tweede overschrijft niets', () async {
      final first = await created();
      final again = await service.create();
      expect((again as FormKeyNotWritten).state, isA<FormKeyPresent>());
      expect(vault.writes, hasLength(1));
      expect(
        ((await service.read()) as FormKeyPresent).key.ageIdentity,
        first.key.ageIdentity,
      );
    });

    test(
      'met een sleutelhanger die niet te lezen is wordt er niets aangemaakt',
      () async {
        vault.failRead = true;
        final r = await service.create();
        expect((r as FormKeyNotWritten).state, isA<FormKeyUnreadable>());
        expect(vault.writes, isEmpty);
      },
    );

    test('met iets beschadigds erin wordt het niet overschreven', () async {
      vault.data[_slot] = 'rommel';
      final r = await service.create();
      expect((r as FormKeyNotWritten).state, isA<FormKeyDamaged>());
      expect(vault.data[_slot], 'rommel');
      expect(vault.writes, isEmpty);
    });

    test('zonder sleutelhanger wordt er niets aangemaakt', () async {
      final none = FormKeyService(SecretStore(storage: vault, canStore: false));
      expect(
        (await none.create() as FormKeyNotWritten).state,
        isA<FormKeyUnavailable>(),
      );
      expect(vault.writes, isEmpty);
    });

    test('een sleutelhanger die schrijven weigert meldt dat', () async {
      vault.failWrite = true;
      expect(await service.create(), isA<FormKeyWriteFailed>());
    });

    test(
      'een sleutelhanger die stil niets bewaart meldt dat ook: er is niets om op te schrijven',
      () async {
        vault.dropWrites = true;
        expect(await service.create(), isA<FormKeyWriteFailed>());
        expect(await service.read(), isA<FormKeyAbsent>());
      },
    );

    test('twee sleutels zijn nooit dezelfde', () async {
      final a = (await created()).key;
      await service.delete();
      final b = (await created()).key;
      expect(a.ageIdentity, isNot(b.ageIdentity));
      expect(a.signingSeed, isNot(b.signingSeed));
    });
  });

  group('de herstelsleutel', () {
    test('is die van de bewaarde sleutel, en geeft hem terug', () async {
      final present = await created();
      final text = (await service.recoveryKey())!;
      final decoded = decodeFormRecoveryKey(text) as FormRecoveredKey;
      expect(decoded.ageIdentity, present.key.ageIdentity);
      expect(decoded.signingSeed, present.key.signingSeed);
    });

    test('is er niet als er geen sleutel is of hij niet te lezen is', () async {
      expect(await service.recoveryKey(), isNull);
      vault.data[_slot] = 'rommel';
      expect(await service.recoveryKey(), isNull);
      vault.failRead = true;
      expect(await service.recoveryKey(), isNull);
    });
  });

  group('herstellen', () {
    late String recovery;
    late FormKeyPresent original;
    setUp(() async {
      original = await created();
      recovery = (await service.recoveryKey())!;
      await service.delete();
      vault.writes.clear();
    });

    test('zet dezelfde sleutel terug, als gecontroleerd', () async {
      final r = await service.restore(recovery) as FormKeyWritten;
      expect(r.key.ageIdentity, original.key.ageIdentity);
      expect(r.key.signingSeed, original.key.signingSeed);
      expect(r.key.recoveryVerified, isTrue);
      expect(r.info.fingerprint, original.info.fingerprint);
      expect(r.info.recipient, original.info.recipient);
    });

    test('begrijpt de herstelsleutel zoals hij werd overgetypt', () async {
      final typed = recovery.toLowerCase().replaceAll('-', ' ');
      expect(await service.restore(typed), isA<FormKeyWritten>());
    });

    test('weigert als er al een sleutel is, en raakt hem niet aan', () async {
      final other = await created();
      vault.writes.clear();
      final r = await service.restore(recovery);
      expect((r as FormKeyNotWritten).state, isA<FormKeyPresent>());
      expect(vault.writes, isEmpty);
      expect(
        ((await service.read()) as FormKeyPresent).key.ageIdentity,
        other.key.ageIdentity,
      );
    });

    test(
      'weigert bij een sleutelhanger die niet te lezen is of beschadigd, of ontbreekt',
      () async {
        vault.failRead = true;
        expect(
          ((await service.restore(recovery)) as FormKeyNotWritten).state,
          isA<FormKeyUnreadable>(),
        );
        vault.failRead = false;
        vault.data[_slot] = 'rommel';
        expect(
          ((await service.restore(recovery)) as FormKeyNotWritten).state,
          isA<FormKeyDamaged>(),
        );
        final none = FormKeyService(
          SecretStore(storage: vault, canStore: false),
        );
        expect(
          ((await none.restore(recovery)) as FormKeyNotWritten).state,
          isA<FormKeyUnavailable>(),
        );
        expect(vault.writes, isEmpty);
      },
    );

    test(
      'zegt waarom een herstelsleutel niet gelezen wordt, en schrijft niets',
      () async {
        final plain = recovery.replaceAll('-', '');
        final typo = plain.replaceRange(10, 11, plain[10] == '2' ? '3' : '2');
        for (final (text, issue) in [
          ('', FormRecoveryIssue.format),
          ('onzin', FormRecoveryIssue.format),
          (typo, FormRecoveryIssue.checksum),
        ]) {
          final r = await service.restore(text);
          expect((r as FormKeyRestoreRefused).issue, issue, reason: text);
        }
        expect(vault.writes, isEmpty);
        expect(await service.read(), isA<FormKeyAbsent>());
      },
    );

    test('een sleutelhanger die schrijven weigert meldt dat', () async {
      vault.failWrite = true;
      expect(await service.restore(recovery), isA<FormKeyWriteFailed>());
    });
  });

  group('de herstelsleutel terugtypen', () {
    late FormKeyPresent present;
    late String recovery;
    setUp(() async {
      present = await created();
      recovery = (await service.recoveryKey())!;
      vault.writes.clear();
    });

    test('klopt: de sleutel is gecontroleerd en blijft het', () async {
      expect(await service.verifyRecovery(recovery), isA<FormKeyVerified>());
      final read = await service.read() as FormKeyPresent;
      expect(read.info.recoveryVerified, isTrue);
      expect(
        read.key.ageIdentity,
        present.key.ageIdentity,
        reason: 'de sleutel zelf ongewijzigd',
      );
      expect(read.key.signingSeed, present.key.signingSeed);
      expect(read.key.created, present.key.created);
    });

    test('opnieuw controleren schrijft niets meer', () async {
      await service.verifyRecovery(recovery);
      vault.writes.clear();
      expect(await service.verifyRecovery(recovery), isA<FormKeyVerified>());
      expect(vault.writes, isEmpty);
    });

    test(
      'een andere sleutel is een andere sleutel, en de vlag blijft uit',
      () async {
        final other = encodeFormRecoveryKey(
          signingSeed: present.key.signingSeed,
          ageIdentity: generateAgeIdentity(),
        );
        expect(await service.verifyRecovery(other), isA<FormKeyDifferent>());
        final otherSeed = encodeFormRecoveryKey(
          signingSeed: Uint8List(32),
          ageIdentity: present.key.ageIdentity,
        );
        expect(
          await service.verifyRecovery(otherSeed),
          isA<FormKeyDifferent>(),
        );
        // Een zaad dat alleen in de eerste of de laatste byte verschilt is ook een ander zaad.
        for (final index in [0, 31]) {
          final almost = Uint8List.fromList(present.key.signingSeed)
            ..[index] ^= 1;
          final text = encodeFormRecoveryKey(
            signingSeed: almost,
            ageIdentity: present.key.ageIdentity,
          );
          expect(
            await service.verifyRecovery(text),
            isA<FormKeyDifferent>(),
            reason: 'byte $index',
          );
        }
        expect(
          ((await service.read()) as FormKeyPresent).info.recoveryVerified,
          isFalse,
        );
        expect(vault.writes, isEmpty);
      },
    );

    test(
      'een typefout, onzin of een samenwerkingssleutel wordt niet gelezen',
      () async {
        final plain = recovery.replaceAll('-', '');
        final typo = plain.replaceRange(20, 21, plain[20] == '2' ? '3' : '2');
        var r = await service.verifyRecovery(typo);
        expect(
          (r as FormKeyUnreadableRecovery).issue,
          FormRecoveryIssue.checksum,
        );
        r = await service.verifyRecovery('onzin');
        expect(
          (r as FormKeyUnreadableRecovery).issue,
          FormRecoveryIssue.format,
        );
        expect(
          ((await service.read()) as FormKeyPresent).info.recoveryVerified,
          isFalse,
        );
      },
    );

    test(
      'zonder sleutel, met een onleesbare sleutelhanger of een beschadigde sleutel is er niets om te controleren',
      () async {
        await service.delete();
        expect(
          await service.verifyRecovery(recovery),
          isA<FormKeyNothingToCheck>(),
        );
        vault.data[_slot] = 'rommel';
        expect(
          await service.verifyRecovery(recovery),
          isA<FormKeyNothingToCheck>(),
        );
        vault.data.remove(_slot);
        vault.failRead = true;
        expect(
          await service.verifyRecovery(recovery),
          isA<FormKeyNothingToCheck>(),
        );
      },
    );

    test('een controle die niet kon worden bewaard zegt dat', () async {
      vault.failWrite = true;
      expect(
        await service.verifyRecovery(recovery),
        isA<FormKeyVerifyNotSaved>(),
      );
    });
  });

  group('wissen', () {
    test('haalt de sleutel weg, ook een die niet te lezen is', () async {
      await created();
      await service.delete();
      expect(await service.read(), isA<FormKeyAbsent>());
      vault.data[_slot] = 'rommel';
      await service.delete();
      expect(await service.read(), isA<FormKeyAbsent>());
    });

    test('als er niets is, gaat het stil goed', () async {
      await service.delete();
      expect(await service.read(), isA<FormKeyAbsent>());
    });
  });

  group('het age-sleutelbestand', () {
    test(
      'is zoals age-keygen het schrijft: twee commentaarregels en de identiteit',
      () async {
        final present = await created();
        final text = service.identityFileText(present.key, present.info);
        final lines = text.split('\n');
        expect(lines, hasLength(4));
        expect(lines[0], '# created: 2026-11-03');
        expect(lines[1], '# public key: ${present.info.recipient}');
        expect(lines[2], present.key.ageIdentity);
        expect(lines[3], isEmpty);
        expect(isAgeIdentity(lines[2]), isTrue);
        expect(
          isAgeRecipient(lines[1].substring('# public key: '.length)),
          isTrue,
        );
      },
    );
  });
}
