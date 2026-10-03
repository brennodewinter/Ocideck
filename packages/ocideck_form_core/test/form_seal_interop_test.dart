// Interoperability with the reference `age` implementation (FORM_INTAKE.md §5.6, §12, §17):
// a package sealed here opens there, and one sealed there opens here. Part of the phase 3
// gate. **When the binary is absent this reports "not run" — it does not pass silently.**
// Kept apart from `form_seal_test.dart` because it starts a process (`dart:io`), and that
// file runs in a browser too.

import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

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

Uint8List build({int photoBytes = 300}) {
  final random = Random(7);
  return buildFormPackage(
    submission: filled,
    template: template,
    spec: (parseForm(template) as ParsedForm).spec,
    images: {
      'images/foto-1.jpg': Uint8List.fromList(
        List.generate(photoBytes, (_) => random.nextInt(256)),
      ),
    },
    submissionId: 'abcdefghijklmnopqrstuvwxyz',
    created: DateTime.utc(2026, 10, 4),
    clientRules: kFormRulesVersion,
  );
}

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

/// Runs [body] with the reference binary and a scratch directory, or reports "not run".
Future<void> withReference(
  Future<void> Function(String binary, Directory dir) body,
) async {
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
  await body(binary, dir);
}

/// The reference opening [sealed] with [identity]: its exit code, and the plaintext when it
/// opened.
Future<({int exitCode, Uint8List? plain})> referenceOpens(
  String binary,
  Directory dir,
  Uint8List sealed,
  String identity,
) async {
  final id = File('${dir.path}/id-${identity.hashCode}.txt')
    ..writeAsStringSync('$identity\n');
  final input = File('${dir.path}/in-${sealed.hashCode}.age')
    ..writeAsBytesSync(sealed);
  final out = File('${dir.path}/out-${sealed.hashCode}-${identity.hashCode}');
  final r = await Process.run(binary, [
    '-d',
    '-i',
    id.path,
    '-o',
    out.path,
    input.path,
  ]);
  return (
    exitCode: r.exitCode,
    plain: r.exitCode == 0 ? out.readAsBytesSync() : null,
  );
}

/// The reference sealing [plain] to [recipients].
Future<Uint8List> referenceSeals(
  String binary,
  Directory dir,
  Uint8List plain,
  List<String> recipients,
) async {
  final input = File(
    '${dir.path}/plain-${plain.length}-${recipients.join().hashCode}',
  )..writeAsBytesSync(plain);
  final out = File('${input.path}.age');
  final r = await Process.run(binary, [
    for (final recipient in recipients) ...['-r', recipient],
    '-o',
    out.path,
    input.path,
  ]);
  expect(r.exitCode, 0, reason: '${r.stderr}');
  return out.readAsBytesSync();
}

void main() {
  late String identity;
  late String recipient;
  late String otherIdentity;
  late String otherRecipient;
  setUpAll(() async {
    identity = generateAgeIdentity();
    recipient = (await ageRecipientOf(identity))!;
    otherIdentity = generateAgeIdentity();
    otherRecipient = (await ageRecipientOf(otherIdentity))!;
  });

  group('the reference implementation', () {
    test('seals here, opens there, and the other way round', () async {
      await withReference((binary, dir) async {
        final zip = build(photoBytes: 200 * 1024);

        // Here -> there.
        final here =
            await sealFormPackage(zip, recipients: [recipient]) as FormSealed;
        final theirs = await referenceOpens(binary, dir, here.bytes, identity);
        expect(theirs.exitCode, 0);
        expect(theirs.plain, zip);

        // There -> here.
        final there = await referenceSeals(binary, dir, zip, [recipient]);
        final r = await openSealedPackage(there, identities: [identity]);
        expect((r as FormUnsealed).zip, zip);
      });
    });

    test('several recipients: each of them opens it, here and there', () async {
      await withReference((binary, dir) async {
        final zip = build(photoBytes: 70 * 1024);
        final here =
            await sealFormPackage(zip, recipients: [recipient, otherRecipient])
                as FormSealed;
        for (final who in [identity, otherIdentity]) {
          final theirs = await referenceOpens(binary, dir, here.bytes, who);
          expect(
            theirs.plain,
            zip,
            reason: 'the reference opens it as one of two',
          );
          final ours = await openSealedPackage(here.bytes, identities: [who]);
          expect((ours as FormUnsealed).zip, zip);
        }
        final there = await referenceSeals(binary, dir, zip, [
          recipient,
          otherRecipient,
        ]);
        for (final who in [identity, otherIdentity]) {
          final ours = await openSealedPackage(there, identities: [who]);
          expect((ours as FormUnsealed).zip, zip);
        }
      });
    });

    test(
      'a key that is not a recipient opens nothing, on either side',
      () async {
        await withReference((binary, dir) async {
          final zip = build();
          final here =
              await sealFormPackage(zip, recipients: [recipient]) as FormSealed;
          final theirs = await referenceOpens(
            binary,
            dir,
            here.bytes,
            otherIdentity,
          );
          expect(
            theirs.exitCode,
            isNot(0),
            reason: 'the reference refuses our file for a stranger',
          );
          expect(
            (await openSealedPackage(here.bytes, identities: [otherIdentity])
                    as FormUnsealRefused)
                .issue,
            FormUnsealIssue.noIdentityMatched,
          );
          final there = await referenceSeals(binary, dir, zip, [recipient]);
          expect(
            (await openSealedPackage(there, identities: [otherIdentity])
                    as FormUnsealRefused)
                .issue,
            FormUnsealIssue.noIdentityMatched,
          );
        });
      },
    );

    test('a changed or cut-short file is refused by both', () async {
      await withReference((binary, dir) async {
        final zip = build(photoBytes: 130 * 1024);
        final good =
            (await sealFormPackage(zip, recipients: [recipient]) as FormSealed)
                .bytes;
        // Where the header ends: after the line that starts with `--- ` (the MAC), then a 16-byte
        // nonce, then the chunks of 64 KiB plus a 16-byte tag each.
        final macLine = latin1.decode(good.sublist(0, 400)).indexOf('\n--- ');
        final headerEnd =
            macLine +
            latin1
                .decode(good.sublist(macLine + 1, macLine + 120))
                .indexOf('\n') +
            2;
        final cases = <String, Uint8List>{
          // One bit in the payload (past the header), one in the header MAC area, the last
          // byte, and a file cut short at a chunk boundary and inside a chunk.
          'payload bit': Uint8List.fromList(good)..[good.length ~/ 2] ^= 1,
          'last byte': Uint8List.fromList(good)..[good.length - 1] ^= 1,
          'header bit': Uint8List.fromList(good)..[headerEnd - 10] ^= 1,
          'cut short': good.sublist(0, good.length - 100),
          'cut at a chunk': good.sublist(0, headerEnd + 16 + 65536 + 16),
        };
        for (final entry in cases.entries) {
          final theirs = await referenceOpens(
            binary,
            dir,
            entry.value,
            identity,
          );
          expect(
            theirs.exitCode,
            isNot(0),
            reason: 'the reference refuses: ${entry.key}',
          );
          final ours = await openSealedPackage(
            entry.value,
            identities: [identity],
          );
          expect(
            ours,
            isA<FormUnsealRefused>(),
            reason: 'we refuse: ${entry.key}',
          );
        }
      });
    });

    test(
      'what the reference seals, at every edge of a 64 KiB chunk, opens here',
      () async {
        await withReference((binary, dir) async {
          for (final size in [
            0,
            1,
            65535,
            65536,
            65537,
            131071,
            131072,
            131073,
          ]) {
            final random = Random(size);
            final plain = Uint8List.fromList(
              List.generate(size, (_) => random.nextInt(256)),
            );
            final sealed = await referenceSeals(binary, dir, plain, [
              recipient,
            ]);
            final opened = await openAge(sealed, [identity]);
            expect(
              (opened as FormAgeOpened).plaintext,
              plain,
              reason: 'a plaintext of $size bytes',
            );
          }
        });
      },
    );
  });
}
