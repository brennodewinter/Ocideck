// Het boek samenstellen (FORM_INTAKE.md §7.5): de gekozen inzendingen door een
// hoofdstuksjabloon tot één nieuw document in `book/`, met zijn foto's en zijn sidecar.

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/services/form/form_book.dart';
import 'package:ocideck/services/form/form_import.dart';
import 'package:ocideck/services/form/form_submission_actions.dart';
import 'package:ocideck/services/form/form_workspace.dart';
import 'package:ocideck_form_core/ocideck_form_core.dart';
import 'package:path/path.dart' as p;

import 'support/form_photo_fixtures.dart';
import 'support/temp_dir.dart';

const String kook =
    '''<!-- form id=kook version=1 states="received|maker-approved|laid-out" overview="naam" -->
# Inzending

<!-- field id=naam type=text required -->
**Naam**
<!-- answer -->
<!-- /field id=naam -->

<!-- field id=soort type=choice options="Zoet|Hartig" -->
**Soort**
<!-- answer -->
<!-- /field id=soort -->

<!-- field id=verhaal type=prose -->
**Verhaal**
<!-- answer -->
<!-- /field id=verhaal -->

<!-- field id=foto type=image count=0..2 -->
**Foto**
<!-- answer -->
<!-- /field id=foto -->

<!-- field id=akkoord type=consent required -->
Ik ga akkoord.
<!-- answer -->
- [ ]
<!-- /field id=akkoord -->
''';

const String template = '# {naam}\n*{soort}*\n\n{verhaal}\n\n{foto}';

String sidOf(int n) => 'abcdefghijklmnopqrstuvwxy${'abcdefg'[n]}';

FormSpec get spec => (parseForm(kook) as ParsedForm).spec;

Uint8List zipOf(
  int n, {
  String naam = 'Sari',
  String soort = 'Zoet',
  String verhaal = 'Een verhaal.',
  Map<String, Uint8List> images = const {},
  String form = kook,
}) {
  var text = form
      .replaceFirst(
        '<!-- answer -->\n<!-- /field id=naam',
        '<!-- answer -->\n$naam\n<!-- /field id=naam',
      )
      .replaceFirst(
        '<!-- answer -->\n<!-- /field id=soort',
        '<!-- answer -->\n$soort\n<!-- /field id=soort',
      )
      .replaceFirst(
        '<!-- answer -->\n<!-- /field id=verhaal',
        '<!-- answer -->\n$verhaal\n<!-- /field id=verhaal',
      )
      .replaceFirst(
        '- [ ]\n<!-- /field id=akkoord',
        '- [x]\n<!-- /field id=akkoord',
      );
  if (images.isNotEmpty) {
    text = text.replaceFirst(
      '<!-- answer -->\n<!-- /field id=foto',
      '<!-- answer -->\n${images.keys.map((k) => '![Beschrijving $k]($k "Foto: $naam")').join('\n')}\n<!-- /field id=foto',
    );
  }
  return buildFormPackage(
    submission: text,
    template: form,
    spec: (parseForm(form) as ParsedForm).spec,
    images: images,
    submissionId: sidOf(n),
    created: DateTime.utc(2026, 10, 4),
    clientRules: kFormRulesVersion,
  );
}

void main() {
  late Directory dir;
  late FormWorkspace workspace;
  final now = DateTime.utc(2026, 11, 3);
  setUp(() async {
    dir = await Directory.systemTemp.createTemp('ocideck_book_');
    workspace = FormWorkspace(p.join(dir.path, 'werkmap'));
    await workspace.publishForm(kook);
  });
  tearDown(() => deleteTempDir(dir));

  Future<void> land(
    int n, {
    String status = 'maker-approved',
    Uint8List? zip,
    bool withdrawn = false,
  }) async {
    await importFormPackage(
      workspace,
      zip ?? zipOf(n),
      now: DateTime.utc(2026, 10, 6),
    );
    if (status != 'received') {
      await setSubmissionStatus(workspace, sidOf(n), status, [
        'received',
        'maker-approved',
        'laid-out',
      ]);
    }
    if (withdrawn)
      await setSubmissionWithdrawal(workspace, sidOf(n), '2026-11-02');
  }

  Future<FormBookOutcome> compile({
    String t = template,
    Set<String> states = const {'maker-approved'},
    String name = 'boek',
    String? orderBy,
    String? groupBy,
    FormSpec? form,
  }) => compileFormBook(
    workspace,
    form: form ?? spec,
    template: t,
    states: states,
    name: name,
    now: now,
    orderBy: orderBy,
    groupBy: groupBy,
  );

  File book([String name = 'boek']) =>
      File(p.join(workspace.root, 'book', '$name.md'));

  test(
    'de gekozen inzendingen worden hoofdstukken, de rest blijft eruit',
    () async {
      await land(
        0,
        zip: zipOf(0, naam: 'Sari', soort: 'Zoet'),
      );
      await land(
        1,
        zip: zipOf(1, naam: 'Joe', soort: 'Hartig'),
        status: 'received',
      );
      await land(
        2,
        zip: zipOf(2, naam: 'Adi', soort: 'Zoet'),
      );
      final outcome = await compile() as FormBookWritten;
      expect(outcome.chapters, 2);
      expect(outcome.path, book().path);
      expect(
        await book().readAsString(),
        '# Sari\n*Zoet*\n\nEen verhaal.\n\n# Adi\n*Zoet*\n\nEen verhaal.\n',
      );
      expect(outcome.withdrawn, 0);
      expect(outcome.skipped, 0);
    },
  );

  test('een andere status in de keuze zet die inzendingen erbij', () async {
    await land(0);
    await land(
      1,
      zip: zipOf(1, naam: 'Joe'),
      status: 'received',
    );
    final outcome =
        await compile(states: {'maker-approved', 'received'})
            as FormBookWritten;
    expect(outcome.chapters, 2);
  });

  test('ordenen en groeperen komen door', () async {
    await land(
      0,
      zip: zipOf(0, naam: 'Zoë', soort: 'Zoet'),
    );
    await land(
      1,
      zip: zipOf(1, naam: 'Adi', soort: 'Hartig'),
    );
    await land(
      2,
      zip: zipOf(2, naam: 'Bo', soort: 'Zoet'),
    );
    await compile(t: '# {naam}', orderBy: 'soort', groupBy: 'soort');
    expect(
      await book().readAsString(),
      '## Hartig\n\n# Adi\n\n## Zoet\n\n# Zoë\n\n# Bo\n',
    );
  });

  test('wat ingetrokken is staat er niet in en wordt geteld', () async {
    await land(0);
    await land(1, zip: zipOf(1, naam: 'Joe'), withdrawn: true);
    final outcome = await compile() as FormBookWritten;
    expect(outcome.chapters, 1);
    expect(outcome.withdrawn, 1);
    expect(await book().readAsString(), isNot(contains('Joe')));
  });

  test(
    'een verwijderde inzending komt er nooit in, ook niet als haar status is gekozen',
    () async {
      await land(0);
      await land(1, zip: zipOf(1, naam: 'Joe'));
      await deleteSubmission(workspace, sidOf(1));
      final outcome =
          await compile(states: {'maker-approved', 'deleted'})
              as FormBookWritten;
      expect(outcome.chapters, 1);
      expect(
        outcome.skipped,
        0,
        reason: 'een verwijderde rij wordt niet eens geprobeerd',
      );
    },
  );

  test('de werkkopie gaat voor wat binnenkwam', () async {
    await land(0, zip: zipOf(0, naam: 'Sri'));
    await workspace.workingCopy(sidOf(0));
    final edit = File(
      p.join(workspace.submissionPath(sidOf(0)), 'submission.edit.md'),
    );
    await edit.writeAsString(
      (await edit.readAsString()).replaceFirst('Sri', 'Sari'),
    );
    await compile();
    expect(await book().readAsString(), startsWith('# Sari\n'));
    final received = File(
      p.join(workspace.submissionPath(sidOf(0)), 'submission.md'),
    );
    expect(await received.readAsString(), contains('Sri'));
  });

  group('de foto\'s', () {
    final photo = jpegPhoto();
    final other = jpegPhoto(width: 80, height: 40);

    test('komen naast het boek, onder het nummer van hun inzending', () async {
      await land(0, zip: zipOf(0, images: {'images/foto-1.jpg': photo}));
      await land(
        1,
        zip: zipOf(1, naam: 'Joe', images: {'images/foto-1.jpg': other}),
      );
      final outcome = await compile() as FormBookWritten;
      expect(outcome.images, 2);
      final a = File(
        p.join(workspace.root, 'book', 'images', '${sidOf(0)}-foto-1.jpg'),
      );
      final b = File(
        p.join(workspace.root, 'book', 'images', '${sidOf(1)}-foto-1.jpg'),
      );
      expect(await a.readAsBytes(), photo);
      expect(await b.readAsBytes(), other);
      final text = await book().readAsString();
      expect(
        text,
        contains(
          '![Beschrijving images/foto-1.jpg](images/${sidOf(0)}-foto-1.jpg "Foto: Sari")',
        ),
      );
    });

    test('een foto die er niet meer is wordt geteld, niet verzwegen', () async {
      await land(0, zip: zipOf(0, images: {'images/foto-1.jpg': photo}));
      await File(
        p.join(workspace.submissionPath(sidOf(0)), 'images', 'foto-1.jpg'),
      ).delete();
      final outcome = await compile() as FormBookWritten;
      expect(outcome.missingImages, 1);
      expect(outcome.images, 0);
    });

    test('een ingetrokken inzending laat geen foto achter', () async {
      await land(
        0,
        zip: zipOf(0, images: {'images/foto-1.jpg': photo}),
        withdrawn: true,
      );
      await land(1, zip: zipOf(1, naam: 'Joe'));
      await compile();
      expect(
        Directory(p.join(workspace.root, 'book', 'images')).existsSync(),
        isFalse,
      );
    });
  });

  group('de sidecar', () {
    test(
      'zegt welke inzendingen erin zitten, onder welke toestemming, en wie de foto maakte',
      () async {
        final photo = jpegPhoto();
        await land(0, zip: zipOf(0, images: {'images/foto-1.jpg': photo}));
        await land(1, zip: zipOf(1, naam: 'Joe'));
        await compile();
        final side =
            jsonDecode(
                  await File(
                    p.join(workspace.root, 'book', 'boek.compile.json'),
                  ).readAsString(),
                )
                as Map<String, Object?>;
        expect(side['v'], 1);
        expect(side['created'], '2026-11-03');
        expect(side['form'], {
          'id': 'kook',
          'version': 1,
          'template_sha256': formTemplateHash(template),
        });
        final chapters = side['chapters']! as List;
        expect(chapters.map((c) => (c as Map)['sid']), [sidOf(0), sidOf(1)]);
        final first = chapters.first as Map;
        expect(
          (first['consent']! as List).single,
          containsPair('field', 'akkoord'),
        );
        expect(first['form_sha256'], formTemplateHash(kook));
        expect(first['images'], [
          {'file': 'images/${sidOf(0)}-foto-1.jpg', 'creator': 'Foto: Sari'},
        ]);
        expect((chapters.last as Map)['images'], isEmpty);
      },
    );
  });

  group('wat wordt geweigerd', () {
    test(
      'een sjabloon met een veld dat het formulier niet heeft: niets wordt geschreven',
      () async {
        await land(0);
        final outcome = await compile(t: '# {naam} {fout}');
        expect(outcome, isA<FormBookUnknownFields>());
        expect((outcome as FormBookUnknownFields).ids, ['fout']);
        expect(Directory(p.join(workspace.root, 'book')).existsSync(), isFalse);
      },
    );

    test('een boek dat er al is wordt nooit overschreven', () async {
      await land(0);
      await compile();
      final before = await book().readAsString();
      await land(1, zip: zipOf(1, naam: 'Joe'));
      expect(await compile(), isA<FormBookNameTaken>());
      expect(await book().readAsString(), before);
      expect(await compile(name: 'boek-2'), isA<FormBookWritten>());
    });

    test('een naam die geen bestandsnaam kan zijn', () async {
      await land(0);
      for (final name in [
        '',
        '../x',
        'a b',
        'x.md',
        'é',
        '-x',
        'a/b',
        'x' * 65,
      ]) {
        expect(await compile(name: name), isA<FormBookBadName>(), reason: name);
      }
      expect(Directory(p.join(workspace.root, 'book')).existsSync(), isFalse);
    });

    test('zonder gekozen inzendingen is er geen boek', () async {
      await land(0, status: 'received');
      final outcome = await compile() as FormBookEmpty;
      expect(outcome.withdrawn, 0);
      expect(book().existsSync(), isFalse);
    });

    test('zonder register is er niets te kiezen', () async {
      expect(File(workspace.registerPath).existsSync(), isFalse);
      expect(await compile(), isA<FormBookEmpty>());
    });

    test('alles ingetrokken is ook geen boek, en het zegt waarom', () async {
      await land(0, withdrawn: true);
      final outcome = await compile() as FormBookEmpty;
      expect(outcome.withdrawn, 1);
    });

    test('een register dat stuk is wordt gemeld', () async {
      await land(0);
      await File(workspace.registerPath).writeAsString('Mijn aantekeningen.\n');
      expect(await compile(), isA<FormBookRegisterDamaged>());
    });

    test(
      'een inzending van een andere versie of die niet te lezen is wordt overgeslagen',
      () async {
        await land(0);
        final v2 = kook.replaceFirst('version=1', 'version=2');
        await workspace.publishForm(v2);
        await land(
          1,
          zip: zipOf(1, naam: 'Joe', form: v2),
        );
        await land(2, zip: zipOf(2, naam: 'Adi'));
        await File(
          p.join(workspace.submissionPath(sidOf(2)), 'manifest.json'),
        ).writeAsString('geen json');
        final outcome = await compile() as FormBookWritten;
        expect(outcome.chapters, 1);
        expect(outcome.skipped, 2);
      },
    );

    test('een inzending van een ander formulier komt er niet in', () async {
      await land(0);
      final ander = kook.replaceFirst('id=kook', 'id=ander');
      await workspace.publishForm(ander);
      await land(
        1,
        zip: zipOf(1, naam: 'Joe', form: ander),
      );
      final outcome = await compile() as FormBookWritten;
      expect(outcome.chapters, 1);
      expect(outcome.skipped, 1);
      expect(await book().readAsString(), isNot(contains('Joe')));
    });

    test('alles overgeslagen is ook geen boek', () async {
      await land(0);
      await File(
        p.join(workspace.submissionPath(sidOf(0)), 'manifest.json'),
      ).writeAsString('geen json');
      final outcome = await compile() as FormBookEmpty;
      expect(outcome.skipped, 1);
    });

    test('een schijf waar niet in te schrijven valt: geen boek', () async {
      if (Platform.isWindows) return;
      await land(0);
      await Process.run('chmod', ['555', workspace.root]);
      addTearDown(() => Process.run('chmod', ['755', workspace.root]));
      expect(await compile(), isA<FormBookFailed>());
      expect(book().existsSync(), isFalse);
    });
  });
}
