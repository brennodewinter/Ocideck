// Interoperability with the reference `age` implementation (FORM_INTAKE.md §5.6, §12, §17):
// a package sealed here opens there, and one sealed there opens here. Part of the phase 3
// gate. **When the binary is absent this reports "not run" — it does not pass silently.**
// Kept apart from `form_seal_test.dart` because it starts a process (`dart:io`), and that
// file runs in a browser too.

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

void main() {
  late String identity;
  late String recipient;
  setUpAll(() async {
    identity = generateAgeIdentity();
    recipient = (await ageRecipientOf(identity))!;
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
        ..writeAsStringSync('$identity\n');
      final zip = build(photoBytes: 200 * 1024);

      // Here -> there.
      final here =
          await sealFormPackage(zip, recipients: [recipient]) as FormSealed;
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
        recipient,
        '-o',
        '${dir.path}/there.age',
        '${dir.path}/plain.zip',
      ]);
      expect(theirSeal.exitCode, 0, reason: '${theirSeal.stderr}');
      final r = await openSealedPackage(
        File('${dir.path}/there.age').readAsBytesSync(),
        identities: [identity],
      );
      expect((r as FormUnsealed).zip, zip);
    });
  });
}
