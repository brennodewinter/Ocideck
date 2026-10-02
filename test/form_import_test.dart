// Een inzendpakket binnenhalen in de werkmap (FORM_INTAKE.md §7.2): de keten van
// lezen, decoderen, beoordelen, landen en registreren, en wat er van elke schakel
// overblijft als hij weigert.

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/services/form/form_import.dart';
import 'package:ocideck/services/form/form_workspace.dart';
import 'package:ocideck_form_core/ocideck_form_core.dart';
import 'package:path/path.dart' as p;

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
}
