// Sealing (FORM_INTAKE.md §5.6, §17): a package in an age file, opened only by the
// organisers it was sealed to, and only as the package that was asked for.

import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:dartage/dartage.dart' as age;
import 'package:ocideck_form_core/ocideck_form_core.dart';
import 'package:test/test.dart';

const String template = '''<!-- form id=kookboek version=2 rules=1 -->
# Inzending

<!-- field id=naam type=text required -->
**Naam**
<!-- answer -->
<!-- /field id=naam -->

<!-- field id=foto type=image count=1..3 -->
**Foto's**
<!-- answer -->
<!-- /field id=foto -->

<!-- field id=akkoord type=consent required -->
Ik ga akkoord met publicatie.
<!-- answer -->
- [ ]
<!-- /field id=akkoord -->
''';

const String filled = '''<!-- form id=kookboek version=2 rules=1 -->
# Inzending

<!-- field id=naam type=text required -->
**Naam**
<!-- answer -->
Sari
<!-- /field id=naam -->

<!-- field id=foto type=image count=1..3 -->
**Foto's**
<!-- answer -->
![](images/foto-1.jpg)
<!-- /field id=foto -->

<!-- field id=akkoord type=consent required -->
Ik ga akkoord met publicatie.
<!-- answer -->
- [x]
<!-- /field id=akkoord -->
''';

const String sid = 'abcdefghijklmnopqrstuvwxyz';

FormSpec get spec => (parseForm(template) as ParsedForm).spec;

/// A package whose photo is [photoBytes] long — enough of them and the sealed file has
/// several chunks of 64 KiB.
Uint8List build({
  int photoBytes = 300,
  String id = sid,
  String form = template,
}) {
  final random = Random(7);
  final photo = Uint8List.fromList(
    List.generate(photoBytes, (_) => random.nextInt(256)),
  );
  return buildFormPackage(
    submission: filled,
    template: form,
    spec: (parseForm(form) as ParsedForm).spec,
    images: {'images/foto-1.jpg': photo},
    submissionId: id,
    created: DateTime.utc(2026, 10, 4),
    clientRules: kFormRulesVersion,
  );
}

class Organiser {
  Organiser(this.identity, this.recipient);

  final String identity;
  final String recipient;
}

Future<Organiser> organiser() async {
  final identity = generateAgeIdentity();
  return Organiser(identity, (await ageRecipientOf(identity))!);
}

FormSealed sealed(FormSealResult r) => r as FormSealed;

FormUnsealIssue refused(FormUnsealResult r) => (r as FormUnsealRefused).issue;

void main() {
  late Organiser alice;
  late Organiser bob;
  late Organiser carol;
  setUpAll(() async {
    alice = await organiser();
    bob = await organiser();
    carol = await organiser();
  });

  group('keys', () {
    test(
      'an identity is a canonical age secret key with its own recipient',
      () async {
        final a = generateAgeIdentity();
        final b = generateAgeIdentity();
        expect(a, startsWith('AGE-SECRET-KEY-1'));
        expect(a, a.toUpperCase());
        expect(a, isNot(b));
        final recipient = (await ageRecipientOf(a))!;
        expect(recipient, startsWith('age1'));
        expect(recipient, recipient.toLowerCase());
        expect(await ageRecipientOf(a), recipient, reason: 'deterministic');
        expect(await ageRecipientOf(b), isNot(recipient));
        expect(isAgeIdentity(a), isTrue);
        expect(isAgeRecipient(recipient), isTrue);
      },
    );

    test(
      'a recipient is not an identity and an identity is not a recipient',
      () {
        expect(isAgeRecipient(alice.identity), isFalse);
        expect(isAgeIdentity(alice.recipient), isFalse);
      },
    );

    test('the form must be canonical: case is part of it', () {
      expect(isAgeRecipient(alice.recipient.toUpperCase()), isFalse);
      expect(isAgeIdentity(alice.identity.toLowerCase()), isFalse);
    });

    test('garbage is neither', () async {
      for (final text in ['', 'age1', 'AGE-SECRET-KEY-1', 'hello', 'age1 x']) {
        expect(isAgeRecipient(text), isFalse, reason: text);
        expect(isAgeIdentity(text), isFalse, reason: text);
      }
      expect(await ageRecipientOf('garbage'), isNull);
      expect(await ageRecipientOf(alice.recipient), isNull);
      expect(await ageRecipientOf(alice.identity.toLowerCase()), isNull);
    });
  });

  group('sealing', () {
    test(
      'an age file for X25519 recipients, named after the submission',
      () async {
        final zip = build();
        final result = sealed(
          await sealFormPackage(zip, recipients: [alice.recipient]),
        );
        final text = latin1.decode(result.bytes.sublist(0, 60));
        expect(text, startsWith('age-encryption.org/v1\n-> X25519 '));
        expect(result.fileName, '$sid.zip.age');
        expect(result.fileName, endsWith(kSealedSuffix));
        expect(result.submissionId, sid);
      },
    );

    test('the same package sealed twice is two different files', () async {
      final zip = build();
      final a = sealed(
        await sealFormPackage(zip, recipients: [alice.recipient]),
      );
      final b = sealed(
        await sealFormPackage(zip, recipients: [alice.recipient]),
      );
      expect(a.bytes, isNot(b.bytes));
      expect(a.sha256, isNot(b.sha256));
    });

    test('the hash is that of the file', () async {
      final result = sealed(
        await sealFormPackage(build(), recipients: [alice.recipient]),
      );
      expect(result.sha256, sha256Hex(result.bytes));
      expect(result.sha256, matches(RegExp(r'^[0-9a-f]{64}$')));
    });

    test('the most recipients a package is sealed to is 64', () {
      expect(kFormMaxRecipients, 64);
    });

    test('a recipient given twice is sealed to once', () async {
      final result = sealed(
        await sealFormPackage(
          build(),
          recipients: [alice.recipient, alice.recipient],
        ),
      );
      final stanzas = '-> X25519 '.allMatches(
        latin1.decode(result.bytes.sublist(0, 400)),
      );
      expect(stanzas, hasLength(1));
    });

    test('no recipient is refused', () async {
      final r = await sealFormPackage(build(), recipients: const []);
      expect((r as FormSealRefused).issue, FormSealIssue.noRecipients);
    });

    test(
      'a recipient that is not an age X25519 recipient is refused',
      () async {
        for (final bad in [
          'garbage',
          alice.identity,
          alice.recipient.toUpperCase(),
          '',
        ]) {
          final r = await sealFormPackage(
            build(),
            recipients: [alice.recipient, bad],
          );
          expect(
            (r as FormSealRefused).issue,
            FormSealIssue.badRecipient,
            reason: bad,
          );
        }
      },
    );

    test(
      'too many recipients are refused, at the limit they are not',
      () async {
        final many = <String>[];
        for (var i = 0; i < kFormMaxRecipients + 1; i++) {
          many.add((await ageRecipientOf(generateAgeIdentity()))!);
        }
        final zip = build();
        final over = await sealFormPackage(zip, recipients: many);
        expect(
          (over as FormSealRefused).issue,
          FormSealIssue.tooManyRecipients,
        );
        final at = await sealFormPackage(
          zip,
          recipients: many.take(kFormMaxRecipients).toList(),
        );
        expect(at, isA<FormSealed>());
      },
    );

    test('what is not a package is not sealed', () async {
      final r = await sealFormPackage(
        Uint8List.fromList(utf8.encode('geen zip')),
        recipients: [alice.recipient],
      );
      expect((r as FormSealRefused).issue, FormSealIssue.notAPackage);
      expect(r.detail, isNotNull);
    });

    test('a package over the limit is not sealed', () async {
      final r = await sealFormPackage(
        build(),
        recipients: [alice.recipient],
        limits: const FormPackageLimits(maxPackageBytes: 100),
      );
      expect((r as FormSealRefused).issue, FormSealIssue.notAPackage);
      expect(r.detail, contains('too-large'));
    });

    test('a package refused for several reasons names them', () async {
      // A zip that is a zip but whose manifest is gone is refused with its reasons.
      final r = await sealFormPackage(
        Uint8List.fromList([0x50, 0x4b, 0x05, 0x06, ...List.filled(18, 0)]),
        recipients: [alice.recipient],
      );
      expect((r as FormSealRefused).detail, isNotEmpty);
    });
  });

  group('opening', () {
    test(
      'gives back the plain zip, read, and the hash of what was opened',
      () async {
        final zip = build();
        final file = sealed(
          await sealFormPackage(zip, recipients: [alice.recipient]),
        );
        final r = await openSealedPackage(
          file.bytes,
          identities: [alice.identity],
        );
        final opened = r as FormUnsealed;
        expect(opened.zip, zip);
        expect(opened.package.manifest.submissionId, sid);
        expect(opened.package.submission, filled);
        expect(opened.sha256, file.sha256);
      },
    );

    test(
      'every organiser it was sealed to opens it, no one else does',
      () async {
        final file = sealed(
          await sealFormPackage(
            build(),
            recipients: [alice.recipient, bob.recipient],
          ),
        );
        for (final who in [alice, bob]) {
          expect(
            await openSealedPackage(file.bytes, identities: [who.identity]),
            isA<FormUnsealed>(),
          );
        }
        expect(
          refused(
            await openSealedPackage(file.bytes, identities: [carol.identity]),
          ),
          FormUnsealIssue.noIdentityMatched,
        );
      },
    );

    test('the right identity among wrong ones opens it', () async {
      final file = sealed(
        await sealFormPackage(build(), recipients: [bob.recipient]),
      );
      expect(
        await openSealedPackage(
          file.bytes,
          identities: [alice.identity, carol.identity, bob.identity],
        ),
        isA<FormUnsealed>(),
      );
    });

    test(
      'an identity that is not one is the caller\'s problem, said so',
      () async {
        final file = sealed(
          await sealFormPackage(build(), recipients: [alice.recipient]),
        );
        for (final identities in [
          <String>[],
          ['garbage'],
          [alice.recipient],
          [alice.identity, 'garbage'],
        ]) {
          expect(
            refused(
              await openSealedPackage(file.bytes, identities: identities),
            ),
            FormUnsealIssue.badIdentity,
            reason: '$identities',
          );
        }
      },
    );

    test('a file that is not an age file is not one', () async {
      final file = sealed(
        await sealFormPackage(build(), recipients: [alice.recipient]),
      );
      final armored = Uint8List.fromList(
        utf8.encode(
          '-----BEGIN AGE ENCRYPTED FILE-----\n${base64Encode(file.bytes)}\n-----END AGE ENCRYPTED FILE-----\n',
        ),
      );
      for (final bytes in [
        Uint8List(0),
        Uint8List.fromList(utf8.encode('hello')),
        Uint8List.fromList(utf8.encode('age-encryption.org/v1\n')),
        file.bytes.sublist(0, 30),
        armored,
      ]) {
        expect(
          refused(await openSealedPackage(bytes, identities: [alice.identity])),
          FormUnsealIssue.notAge,
        );
      }
    });

    test(
      'a file over the limit is refused before anything is decrypted',
      () async {
        const limits = FormPackageLimits(maxPackageBytes: 1000);
        final big = Uint8List(maxSealedBytes(limits) + 1);
        expect(
          refused(
            await openSealedPackage(
              big,
              identities: [alice.identity],
              limits: limits,
            ),
          ),
          FormUnsealIssue.tooLarge,
        );
        final edge = Uint8List(maxSealedBytes(limits));
        expect(
          refused(
            await openSealedPackage(
              edge,
              identities: [alice.identity],
              limits: limits,
            ),
          ),
          FormUnsealIssue.notAge,
          reason: 'at the limit it is read, and is not an age file',
        );
      },
    );

    test(
      'the largest sealed file is the cap, its nonce, its tags and its header',
      () {
        const limits = FormPackageLimits(maxPackageBytes: 65536);
        expect(
          maxSealedBytes(limits),
          kFormMaxAgeHeaderBytes + 16 + 65536 + 2 * 16,
        );
        const odd = FormPackageLimits(maxPackageBytes: 65537);
        expect(
          maxSealedBytes(odd),
          kFormMaxAgeHeaderBytes + 16 + 65537 + 3 * 16,
        );
        expect(
          maxSealedBytes(),
          greaterThan(const FormPackageLimits().maxPackageBytes),
        );
      },
    );

    test(
      'a header larger than the limit is refused for its size, not read',
      () async {
        final line = 'A' * 64;
        final body = List.filled(1100, line).join('\n'); // 70 KB of stanza body
        final header =
            'age-encryption.org/v1\n-> grease x\n$body\nAAAA\n--- ${'A' * 43}\n';
        expect(header.length, greaterThan(kFormMaxAgeHeaderBytes));
        final file = Uint8List.fromList([
          ...latin1.encode(header),
          ...List.filled(64, 0),
        ]);
        expect(
          refused(await openSealedPackage(file, identities: [alice.identity])),
          FormUnsealIssue.notAge,
        );
        // The same stanza within the limit parses, and nobody it was sealed for is found.
        final small =
            'age-encryption.org/v1\n-> grease x\nAAAA\n--- ${'A' * 43}\n';
        final fits = Uint8List.fromList([
          ...latin1.encode(small),
          ...List.filled(64, 0),
        ]);
        expect(
          refused(await openSealedPackage(fits, identities: [alice.identity])),
          FormUnsealIssue.noIdentityMatched,
        );
      },
    );

    test(
      'what opens and is not a package is said so, with the reasons',
      () async {
        final junk = await age.AgeEncrypter(
          recipients: [age.X25519Recipient.parse(alice.recipient)],
        ).encrypt(Uint8List.fromList(utf8.encode('not a zip')));
        final r = await openSealedPackage(junk, identities: [alice.identity]);
        expect((r as FormUnsealRefused).issue, FormUnsealIssue.notAPackage);
        expect(r.problems, isNotEmpty);
      },
    );
  });

  group('binding to what was asked for', () {
    late Uint8List file;
    setUpAll(() async {
      file = sealed(
        await sealFormPackage(build(), recipients: [alice.recipient]),
      ).bytes;
    });

    Future<FormUnsealResult> open({
      String? sidWanted,
      String? formWanted,
      int? versionWanted,
    }) => openSealedPackage(
      file,
      identities: [alice.identity],
      expectedSid: sidWanted,
      expectedFormId: formWanted,
      expectedFormVersion: versionWanted,
    );

    test('what is asked for and what is inside agree', () async {
      expect(
        await open(sidWanted: sid, formWanted: 'kookboek', versionWanted: 2),
        isA<FormUnsealed>(),
      );
    });

    test('nothing asked is nothing checked', () async {
      expect(await open(), isA<FormUnsealed>());
    });

    test('each one asked for is checked on its own', () async {
      expect(await open(sidWanted: sid), isA<FormUnsealed>());
      expect(await open(formWanted: 'kookboek'), isA<FormUnsealed>());
      expect(await open(versionWanted: 2), isA<FormUnsealed>());
      expect(
        refused(await open(sidWanted: 'zyxwvutsrqponmlkjihgfedcba')),
        FormUnsealIssue.wrongSubmission,
      );
      expect(
        refused(await open(formWanted: 'andere')),
        FormUnsealIssue.wrongForm,
      );
      expect(refused(await open(versionWanted: 3)), FormUnsealIssue.wrongForm);
    });

    test(
      'a ciphertext moved to another form of the same organiser opens, and fails here',
      () async {
        // The server hands form B's client a file sealed for form A: it opens (same
        // organiser key), and the manifest says A.
        expect(
          refused(
            await open(
              sidWanted: sid,
              formWanted: 'recepten',
              versionWanted: 2,
            ),
          ),
          FormUnsealIssue.wrongForm,
        );
        expect(
          refused(
            await open(
              sidWanted: sid,
              formWanted: 'kookboek',
              versionWanted: 1,
            ),
          ),
          FormUnsealIssue.wrongForm,
        );
      },
    );

    test('the submission is checked before the form', () async {
      expect(
        refused(
          await open(
            sidWanted: 'zyxwvutsrqponmlkjihgfedcba',
            formWanted: 'andere',
          ),
        ),
        FormUnsealIssue.wrongSubmission,
      );
    });
  });

  group('tampering fails closed', () {
    late Uint8List file;
    late int headerEnd;
    setUpAll(() async {
      // Three chunks: 200 KB of photo.
      file = sealed(
        await sealFormPackage(
          build(photoBytes: 200 * 1024),
          recipients: [alice.recipient, bob.recipient],
        ),
      ).bytes;
      headerEnd = _headerEnd(file);
    });

    Future<FormUnsealIssue> opens(Uint8List bytes, [Organiser? who]) async {
      final r = await openSealedPackage(
        bytes,
        identities: [(who ?? alice).identity],
      );
      expect(r, isA<FormUnsealRefused>(), reason: 'nothing tampered opens');
      return refused(r);
    }

    Uint8List flipped(int at) => Uint8List.fromList(file)..[at] ^= 0x01;

    test(
      'the untouched file opens (so the tests below mean something)',
      () async {
        expect(
          await openSealedPackage(file, identities: [alice.identity]),
          isA<FormUnsealed>(),
        );
        expect(
          await openSealedPackage(file, identities: [bob.identity]),
          isA<FormUnsealed>(),
        );
        expect(file.length, greaterThan(headerEnd + 16 + 3 * 65536));
      },
    );

    test(
      'a changed byte in the header, in every position, never opens',
      () async {
        for (var i = 0; i < headerEnd; i++) {
          final issue = await opens(flipped(i));
          expect(
            {
              FormUnsealIssue.notAge,
              FormUnsealIssue.tampered,
              FormUnsealIssue.noIdentityMatched,
            },
            contains(issue),
            reason: 'byte $i',
          );
        }
      },
    );

    test(
      'a changed byte in the MAC is a MAC failure, not something else',
      () async {
        final macStart = _macStart(file);
        for (var i = macStart; i < macStart + 6; i++) {
          // Another letter that is still base64: a byte that is not base64 at all would
          // fail earlier, as a header that does not parse.
          final other = Uint8List.fromList(file)
            ..[i] = file[i] == 0x41 ? 0x42 : 0x41;
          expect(
            await opens(other),
            FormUnsealIssue.tampered,
            reason: 'byte $i',
          );
        }
      },
    );

    test(
      'a changed byte in the nonce, a chunk, the last chunk or its tag never opens',
      () async {
        final positions = <int>[
          headerEnd,
          headerEnd + 15,
          headerEnd + 16,
          headerEnd + 16 + 100,
          headerEnd + 16 + 65536 + 15,
          headerEnd + 16 + 65536 + 16,
          headerEnd + 16 + 2 * (65536 + 16),
          file.length - 17,
          file.length - 16,
          file.length - 1,
        ];
        for (final i in positions) {
          expect(
            await opens(flipped(i)),
            FormUnsealIssue.tampered,
            reason: 'byte $i',
          );
        }
      },
    );

    test(
      'a file cut at every chunk boundary, and inside a chunk, never opens',
      () async {
        final body = headerEnd + 16;
        const chunk = 65536 + 16;
        final cuts = <int>[
          body,
          body + 1,
          body + chunk - 1,
          body + chunk,
          body + chunk + 1,
          body + 2 * chunk,
          body + 2 * chunk + 15,
          file.length - 1,
          file.length - 16,
          file.length - 17,
        ];
        for (final cut in cuts) {
          expect(
            await opens(file.sublist(0, cut)),
            FormUnsealIssue.tampered,
            reason: 'cut at $cut',
          );
        }
      },
    );

    test('a file with something after it never opens', () async {
      for (final extra in [1, 16, 17, 65552]) {
        final longer = Uint8List(file.length + extra)..setAll(0, file);
        expect(
          await opens(longer),
          FormUnsealIssue.tampered,
          reason: '+$extra',
        );
      }
    });

    test('chunks swapped never open', () async {
      final body = headerEnd + 16;
      const chunk = 65536 + 16;
      final swapped = Uint8List.fromList(file);
      swapped.setRange(body, body + chunk, file, body + chunk);
      swapped.setRange(body + chunk, body + 2 * chunk, file, body);
      expect(await opens(swapped), FormUnsealIssue.tampered);
    });

    test(
      'a recipient stanza dropped fails the header MAC for the one that is left',
      () async {
        final lines = latin1.decode(file.sublist(0, headerEnd)).split('\n');
        // age-encryption.org/v1, then per recipient `-> X25519 …` and its body line, then `--- mac`.
        final starts = [
          for (var i = 0; i < lines.length; i++)
            if (lines[i].startsWith('-> ')) i,
        ];
        expect(starts, hasLength(2));
        for (final drop in starts) {
          final kept = [...lines]..removeRange(drop, drop + 2);
          final cut = Uint8List.fromList([
            ...latin1.encode(kept.join('\n')),
            ...file.sublist(headerEnd),
          ]);
          // The one whose stanza is left can still unwrap — and the MAC, over a header it was
          // not made for, refuses.
          final who = drop == starts.first ? bob : alice;
          expect(
            await opens(cut, who),
            FormUnsealIssue.tampered,
            reason: 'dropped line $drop',
          );
        }
      },
    );

    test('a stanza from another file does not pass for this one', () async {
      final other = sealed(
        await sealFormPackage(
          build(photoBytes: 200 * 1024, id: 'zyxwvutsrqponmlkjihgfedcba'),
          recipients: [alice.recipient, bob.recipient],
        ),
      ).bytes;
      final mine = latin1.decode(file.sublist(0, headerEnd)).split('\n');
      final theirs = latin1
          .decode(other.sublist(0, _headerEnd(other)))
          .split('\n');
      final swapped = [...mine];
      final i = swapped.indexWhere((l) => l.startsWith('-> '));
      final j = theirs.indexWhere((l) => l.startsWith('-> '));
      swapped[i] = theirs[j];
      swapped[i + 1] = theirs[j + 1];
      final bytes = Uint8List.fromList([
        ...latin1.encode(swapped.join('\n')),
        ...file.sublist(headerEnd),
      ]);
      expect(await opens(bytes), FormUnsealIssue.tampered);
    });

    test('random bytes and random damage never throw and never open', () async {
      final random = Random(11);
      for (var round = 0; round < 150; round++) {
        final length = random.nextInt(3000);
        final junk = Uint8List.fromList(
          List.generate(length, (_) => random.nextInt(256)),
        );
        expect(
          await openSealedPackage(junk, identities: [alice.identity]),
          isA<FormUnsealRefused>(),
        );
      }
      for (var round = 0; round < 60; round++) {
        final damaged = Uint8List.fromList(
          file.sublist(0, headerEnd + 16 + 200),
        );
        for (var k = 0; k < 1 + random.nextInt(5); k++) {
          damaged[random.nextInt(damaged.length)] = random.nextInt(256);
        }
        if (damaged.equals(file.sublist(0, damaged.length))) continue;
        final r = await openSealedPackage(
          damaged,
          identities: [alice.identity],
        );
        expect(r, isA<FormUnsealRefused>());
      }
    });
  });

  group('the reference implementation', () {
    Future<String?> reference() async {
      final candidates = [
        Platform.environment['AGE_BIN'],
        'age',
      ].whereType<String>();
      for (final binary in candidates) {
        try {
          final r = await Process.run(binary, ['--version']);
          if (r.exitCode == 0) return binary;
        } on ProcessException {
          continue;
        }
      }
      return null;
    }

    test('seals here, opens there, and the other way round', () async {
      final binary = await reference();
      if (binary == null) {
        markTestSkipped(
          'NOT RUN: the reference `age` binary is not on the PATH (set AGE_BIN to use one). '
          'Interoperability with the reference implementation is part of the phase 3 gate (§12).',
        );
        return;
      }
      final dir = Directory.systemTemp.createTempSync('ocideck_age_interop_');
      addTearDown(() => dir.deleteSync(recursive: true));
      final identityFile = File('${dir.path}/key.txt')
        ..writeAsStringSync('${alice.identity}\n');
      final zip = build(photoBytes: 200 * 1024);

      // Here -> there.
      final here = sealed(
        await sealFormPackage(zip, recipients: [alice.recipient]),
      );
      final sealedFile = File('${dir.path}/here.age')
        ..writeAsBytesSync(here.bytes);
      final theirOpen = await Process.run(binary, [
        '-d',
        '-i',
        identityFile.path,
        '-o',
        '${dir.path}/there.zip',
        sealedFile.path,
      ]);
      expect(theirOpen.exitCode, 0, reason: '${theirOpen.stderr}');
      expect(File('${dir.path}/there.zip').readAsBytesSync(), zip);

      // There -> here.
      File('${dir.path}/plain.zip').writeAsBytesSync(zip);
      final theirSeal = await Process.run(binary, [
        '-r',
        alice.recipient,
        '-o',
        '${dir.path}/there.age',
        '${dir.path}/plain.zip',
      ]);
      expect(theirSeal.exitCode, 0, reason: '${theirSeal.stderr}');
      final r = await openSealedPackage(
        File('${dir.path}/there.age').readAsBytesSync(),
        identities: [alice.identity],
      );
      expect((r as FormUnsealed).zip, zip);
    });
  });
}

/// Where the header of [file] ends: after the `--- <mac>` line.
int _headerEnd(Uint8List file) {
  final start = _macStart(file);
  return file.indexOf(0x0a, start) + 1;
}

/// Where the base64 of the header MAC begins.
int _macStart(Uint8List file) {
  final text = latin1.decode(file.sublist(0, min(file.length, 70000)));
  return text.indexOf('\n--- ') + 5;
}

extension on Uint8List {
  bool equals(Uint8List other) {
    if (length != other.length) return false;
    for (var i = 0; i < length; i++) {
      if (this[i] != other[i]) return false;
    }
    return true;
  }
}
