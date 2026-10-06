// De werkmap van een organisator (FORM_INTAKE.md §7.1): gepubliceerde formulieren,
// inzendingen die er in één stap komen en nooit over een bestaande heen, het
// minimale record bij verwijderen, en een register dat niet wordt overschreven als
// het niet te lezen is.

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/services/form/form_workspace.dart';
import 'package:ocideck_form_core/ocideck_form_core.dart';
import 'package:path/path.dart' as p;

import 'support/chmod_lock.dart';
import 'support/form_photo_fixtures.dart';
import 'support/temp_dir.dart';

const String kook = '''<!-- form id=kook version=2 lang=nl overview="naam" -->
# Inzending

<!-- field id=naam type=text required -->
**Naam**
<!-- answer -->
<!-- /field id=naam -->
''';

const String sid = 'abcdefghijklmnopqrstuvwxya';

String filled(String text, String naam) => text.replaceFirst(
  '<!-- answer -->\n<!-- /field id=naam -->',
  '<!-- answer -->\n$naam\n<!-- /field id=naam -->',
);

FormPackageOpened packageOf(
  String template, {
  String id = sid,
  String naam = 'Sari',
  Map<String, Uint8List> images = const {},
}) =>
    readFormPackage(
          buildFormPackage(
            submission: filled(template, naam),
            template: template,
            spec: (parseForm(template) as ParsedForm).spec,
            images: images,
            submissionId: id,
            created: DateTime.utc(2026, 10, 4),
            clientRules: kFormRulesVersion,
          ),
        )
        as FormPackageOpened;

FormReview reviewOf(FormPackageOpened package, String template) =>
    reviewFormPackage(package, [template]);

void main() {
  late Directory dir;
  late FormWorkspace workspace;
  setUp(() async {
    dir = await Directory.systemTemp.createTemp('ocideck_workspace_');
    workspace = FormWorkspace(p.join(dir.path, 'werkmap'));
  });
  tearDown(() => deleteTempDir(dir));

  group('formulieren publiceren', () {
    test('een formulier komt onder zijn id, versie en taal', () async {
      final outcome = await workspace.publishForm(kook) as FormPublished;
      expect(
        outcome.form.path,
        p.join(workspace.root, 'forms', 'kook', 'v2', 'template.nl.md'),
      );
      expect(await File(outcome.form.path).readAsString(), kook);
      expect(outcome.form.id, 'kook');
      expect(outcome.form.version, 2);
      expect(outcome.form.lang, 'nl');
    });

    test('zonder taal heet het bestand template.md', () async {
      final text = kook.replaceFirst(' lang=nl', '');
      final outcome = await workspace.publishForm(text) as FormPublished;
      expect(p.basename(outcome.form.path), 'template.md');
      expect(outcome.form.lang, isNull);
    });

    test('een taal in hoofdletters wordt kleine letters', () async {
      final outcome =
          await workspace.publishForm(
                kook.replaceFirst('lang=nl', 'lang=PT-BR'),
              )
              as FormPublished;
      expect(p.basename(outcome.form.path), 'template.pt-br.md');
    });

    test('dezelfde tekst nog eens is niets nieuws', () async {
      await workspace.publishForm(kook);
      expect(await workspace.publishForm(kook), isA<FormPublishedAlready>());
    });

    test(
      'een andere tekst voor dezelfde versie wordt niet geaccepteerd',
      () async {
        final first = await workspace.publishForm(kook) as FormPublished;
        final outcome = await workspace.publishForm(
          kook.replaceAll('Inzending', 'Anders'),
        );
        expect(outcome, isA<FormPublishConflict>());
        expect((outcome as FormPublishConflict).existing.text, kook);
        expect(
          await File(first.form.path).readAsString(),
          kook,
          reason: 'ongemoeid',
        );
      },
    );

    test('een nieuwe versie is wel welkom, naast de oude', () async {
      await workspace.publishForm(kook);
      expect(
        await workspace.publishForm(
          kook.replaceFirst('version=2', 'version=3'),
        ),
        isA<FormPublished>(),
      );
      expect((await workspace.publishedForms()).forms.map((f) => f.version), [
        2,
        3,
      ]);
    });

    test(
      'wat geen formulier is, een kapot formulier of een te nieuw formulier wordt geweigerd',
      () async {
        for (final text in [
          'Gewoon tekst.',
          kook.replaceFirst('type=text required', 'type=prose words=5..3'),
          kook.replaceFirst('version=2', 'version=2 rules=99'),
          kook.replaceFirst('lang=nl', 'lang=Nederlands'),
          kook.replaceFirst('lang=nl', 'lang=../x'),
        ]) {
          expect(
            await workspace.publishForm(text),
            isA<FormPublishRefused>(),
            reason: text,
          );
        }
        expect(
          Directory(p.join(workspace.root, 'forms')).existsSync(),
          isFalse,
        );
      },
    );

    test('een werkmap waar niet in te schrijven valt, meldt het', () async {
      await Directory(workspace.root).create(recursive: true);
      await File(p.join(workspace.root, 'forms')).writeAsString('geen map');
      expect(await workspace.publishForm(kook), isA<FormPublishFailed>());
    });
  });

  group('de gepubliceerde formulieren lezen', () {
    test('zonder map is er niets', () async {
      final read = await workspace.publishedForms();
      expect(read.forms, isEmpty);
      expect(read.unreadable, isEmpty);
    });

    test('alles wat er staat, in vaste volgorde', () async {
      await workspace.publishForm(kook.replaceFirst('version=2', 'version=3'));
      await workspace.publishForm(kook.replaceFirst('lang=nl', 'lang=en'));
      await workspace.publishForm(kook);
      final read = await workspace.publishedForms();
      expect(
        [for (final f in read.forms) '${f.id} v${f.version} ${f.lang}'],
        ['kook v2 en', 'kook v2 nl', 'kook v3 nl'],
      );
      expect(read.forms[1].text, kook);
    });

    test('wat er staat maar niet klopt, verdwijnt niet stil', () async {
      await workspace.publishForm(kook);
      final root = p.join(workspace.root, 'forms');
      Future<String> put(String path, List<int> bytes) async {
        final file = File(p.join(root, path));
        await file.parent.create(recursive: true);
        await file.writeAsBytes(bytes);
        return file.path;
      }

      final unreadable = [
        await put('kook/v9/template.nl.md', const [0xFF, 0xFE, 0x41]),
        await put('kook/v8/template.nl.md', utf8.encode('Geen formulier.')),
        // Een formulier dat in de map van een andere versie is gezet.
        await put('kook/v7/template.nl.md', utf8.encode(kook)),
        // Een formulier in de map van een ander id.
        await put('ander/v2/template.nl.md', utf8.encode(kook)),
      ];
      // Dit hoort er niet bij en wordt niet eens bekeken.
      await put('kook/v2/notities.md', utf8.encode('x'));
      await put('kook/versie2/template.nl.md', utf8.encode(kook));
      await put('9kook/v2/template.nl.md', utf8.encode(kook));
      await put('los.md', utf8.encode(kook));
      final read = await workspace.publishedForms();
      expect(read.forms, hasLength(1));
      expect(read.unreadable..sort(), unreadable..sort());
    });

    test('een verwijzing wordt niet gevolgd', () async {
      await workspace.publishForm(kook);
      final outside = Directory(p.join(dir.path, 'buiten', 'v2'));
      await outside.create(recursive: true);
      await File(p.join(outside.path, 'template.nl.md')).writeAsString(kook);
      try {
        await Link(
          p.join(workspace.root, 'forms', 'ander'),
        ).create(outside.parent.path);
      } on FileSystemException {
        return; // Windows zonder rechten om te koppelen
      }
      expect((await workspace.publishedForms()).forms, hasLength(1));
    });
  });

  group('inzendingen landen', () {
    test('in één stap: zoals ontvangen, met foto\'s, zonder rommel', () async {
      final photo = jpegPhoto();
      final template = kook.replaceFirst(
        '<!-- field id=naam',
        '<!-- field id=foto type=image count=0..2 -->\n**Foto**\n<!-- answer -->\n<!-- /field id=foto -->\n\n<!-- field id=naam',
      );
      final package =
          readFormPackage(
                buildFormPackage(
                  submission: filled(template, 'Sari').replaceFirst(
                    '<!-- answer -->\n<!-- /field id=foto',
                    '<!-- answer -->\n![](images/foto-1.jpg)\n<!-- /field id=foto',
                  ),
                  template: template,
                  spec: (parseForm(template) as ParsedForm).spec,
                  images: {'images/foto-1.jpg': photo},
                  submissionId: sid,
                  created: DateTime.utc(2026, 10, 4),
                  clientRules: kFormRulesVersion,
                ),
              )
              as FormPackageOpened;
      final review = reviewFormPackage(package, [template]);
      expect(await workspace.land(package, review), FormLandOutcome.landed);
      final folder = workspace.submissionPath(sid);
      expect(
        await File(p.join(folder, 'submission.md')).readAsBytes(),
        package.submissionBytes,
      );
      expect(
        await File(p.join(folder, 'manifest.json')).readAsBytes(),
        package.manifestBytes,
      );
      expect(
        await File(p.join(folder, 'images', 'foto-1.jpg')).readAsBytes(),
        photo,
      );
      expect(
        Directory(p.dirname(folder)).listSync().map((e) => p.basename(e.path)),
        [sid],
        reason: 'geen tijdelijke map blijft staan',
      );
    });

    test(
      'een foto komt gezuiverd op schijf, zoals de beoordeling hem bewaart',
      () async {
        final dirty = jpegPhoto(gps: true);
        final template = kook.replaceFirst(
          '<!-- field id=naam',
          '<!-- field id=foto type=image count=0..2 -->\n**Foto**\n<!-- answer -->\n<!-- /field id=foto -->\n\n<!-- field id=naam',
        );
        final package =
            readFormPackage(
                  buildFormPackage(
                    submission: filled(template, 'Sari').replaceFirst(
                      '<!-- answer -->\n<!-- /field id=foto',
                      '<!-- answer -->\n![](images/foto-1.jpg)\n<!-- /field id=foto',
                    ),
                    template: template,
                    spec: (parseForm(template) as ParsedForm).spec,
                    images: {'images/foto-1.jpg': dirty},
                    submissionId: sid,
                    created: DateTime.utc(2026, 10, 4),
                    clientRules: kFormRulesVersion,
                  ),
                )
                as FormPackageOpened;
        final review = reviewFormPackage(package, [template]);
        await workspace.land(package, review);
        final onDisk = await File(
          p.join(workspace.submissionPath(sid), 'images', 'foto-1.jpg'),
        ).readAsBytes();
        expect(onDisk, review.images['images/foto-1.jpg']);
        expect(cleanImage(onDisk)!.removed.gps, isFalse);
      },
    );

    test('nooit over een bestaande inzending heen', () async {
      final package = packageOf(kook);
      final review = reviewOf(package, kook);
      await workspace.land(package, review);
      final other = packageOf(kook, naam: 'Iemand anders');
      expect(
        await workspace.land(other, reviewOf(other, kook)),
        FormLandOutcome.exists,
      );
      expect(
        await File(
          p.join(workspace.submissionPath(sid), 'submission.md'),
        ).readAsBytes(),
        package.submissionBytes,
      );
      expect(
        await Directory(p.dirname(workspace.submissionPath(sid))).list().length,
        1,
      );
    });

    test(
      'twee tegelijk onder één nummer: één landt, de ander ziet dat',
      () async {
        final a = packageOf(kook);
        final b = packageOf(kook, naam: 'Iemand anders');
        final results = await Future.wait([
          workspace.land(a, reviewOf(a, kook)),
          workspace.land(b, reviewOf(b, kook)),
        ]);
        expect(results..sort((x, y) => x.index.compareTo(y.index)), [
          FormLandOutcome.landed,
          FormLandOutcome.exists,
        ]);
        expect(
          Directory(p.dirname(workspace.submissionPath(sid))).listSync().length,
          1,
          reason: 'geen tijdelijke map blijft staan',
        );
      },
    );

    test('een beoordeling zonder formulier landt niet', () async {
      final package = packageOf(kook);
      expect(
        await workspace.land(package, reviewFormPackage(package, const [])),
        FormLandOutcome.refused,
      );
      expect(await workspace.submissionIds(), isEmpty);
    });

    test('een bestandsnaam buiten de grammatica landt niet', () async {
      final package = packageOf(kook);
      final real = reviewOf(package, kook);
      final bad = FormReview(
        manifest: real.manifest,
        problems: real.problems,
        published: real.published,
        spec: real.spec,
        answers: real.answers,
        images: {'../buiten.jpg': Uint8List(3)},
      );
      expect(await workspace.land(package, bad), FormLandOutcome.refused);
      expect(File(p.join(dir.path, 'buiten.jpg')).existsSync(), isFalse);
      expect(await workspace.submissionIds(), isEmpty);
    });

    test('een nummer buiten de grammatica landt niet', () async {
      final package = packageOf(kook);
      final real = reviewOf(package, kook);
      final m = real.manifest;
      final hostile = FormPackageOpened(
        manifest: FormPackageManifest(
          submissionId: '../../etc',
          formId: m.formId,
          formVersion: m.formVersion,
          formRules: m.formRules,
          templateSha256: m.templateSha256,
          created: m.created,
          clientName: m.clientName,
          clientRules: m.clientRules,
          files: m.files,
          consent: m.consent,
        ),
        manifestBytes: package.manifestBytes,
        submission: package.submission,
        submissionBytes: package.submissionBytes,
        images: package.images,
      );
      expect(await workspace.land(hostile, real), FormLandOutcome.refused);
    });

    test(
      'een schijf waar niet in te schrijven valt, laat niets achter',
      () async {
        await Directory(workspace.root).create(recursive: true);
        await File(
          p.join(workspace.root, 'submissions'),
        ).writeAsString('geen map');
        final package = packageOf(kook);
        expect(
          await workspace.land(package, reviewOf(package, kook)),
          FormLandOutcome.failed,
        );
      },
    );

    test('de nummers, gesorteerd, zonder wat onderbroken is', () async {
      for (final id in [
        'abcdefghijklmnopqrstuvwxyc',
        'abcdefghijklmnopqrstuvwxya',
      ]) {
        final package = packageOf(kook, id: id);
        await workspace.land(package, reviewOf(package, kook));
      }
      final folder = p.join(workspace.root, 'submissions');
      await Directory(p.join(folder, '.landing-abc-0')).create();
      await Directory(p.join(folder, 'geen-nummer')).create();
      await File(
        p.join(folder, 'abcdefghijklmnopqrstuvwxyb'),
      ).writeAsString('x');
      expect(await workspace.submissionIds(), [
        'abcdefghijklmnopqrstuvwxya',
        'abcdefghijklmnopqrstuvwxyc',
      ]);
    });

    test('zonder map zijn er geen nummers', () async {
      expect(await workspace.submissionIds(), isEmpty);
    });

    test('een pad naar een inzending vraagt een geldig nummer', () {
      expect(() => workspace.submissionPath('../x'), throwsArgumentError);
      expect(
        () => workspace.submissionPath(sid.toUpperCase()),
        throwsArgumentError,
      );
      expect(
        workspace.submissionPath(sid),
        p.join(workspace.root, 'submissions', sid),
      );
    });
  });

  group('de werkkopie', () {
    Future<File> landed() async {
      final package = packageOf(kook);
      await workspace.land(package, reviewOf(package, kook));
      return File(p.join(workspace.submissionPath(sid), 'submission.md'));
    }

    File copyFile() =>
        File(p.join(workspace.submissionPath(sid), 'submission.edit.md'));

    test(
      'is een letterlijke kopie van wat binnenkwam, en ze is nieuw',
      () async {
        final received = await landed();
        final result = await workspace.workingCopy(sid) as FormWorkingCopy;
        expect(result.created, isTrue);
        expect(result.path, copyFile().path);
        expect(await copyFile().readAsBytes(), await received.readAsBytes());
      },
    );

    test(
      'een tweede keer laat de kopie met rust, ook als er in is gewerkt',
      () async {
        await landed();
        await workspace.workingCopy(sid);
        await copyFile().writeAsString('Verbeterd door de redactie.');
        final again = await workspace.workingCopy(sid) as FormWorkingCopy;
        expect(again.created, isFalse);
        expect(await copyFile().readAsString(), 'Verbeterd door de redactie.');
      },
    );

    test('wat binnenkwam blijft ongewijzigd', () async {
      final received = await landed();
      final before = await received.readAsBytes();
      await workspace.workingCopy(sid);
      await copyFile().writeAsString('anders');
      expect(await received.readAsBytes(), before);
    });

    test(
      'een verwijderde of ontbrekende inzending heeft niets om te kopiëren',
      () async {
        await landed();
        await workspace.deleteSubmissionFiles(sid);
        expect(
          await workspace.workingCopy(sid),
          isA<FormWorkingCopyUnavailable>(),
        );
        expect(copyFile().existsSync(), isFalse);
        expect(
          await workspace.workingCopy('abcdefghijklmnopqrstuvwxyz'),
          isA<FormWorkingCopyUnavailable>(),
        );
      },
    );

    test(
      'een schijf waar niet in te schrijven valt meldt dat het mislukte',
      () async {
        if (Platform.isWindows) return;
        await landed();
        final folder = workspace.submissionPath(sid);
        await Process.run('chmod', ['555', folder]);
        addTearDown(() => Process.run('chmod', ['755', folder]));
        if (!chmodLockHoudt(folder)) {
          // `chmod` houdt root niet tegen; de CI-container draait als root.
          // Dan is dit scenario niet toetsbaar — overslaan i.p.v. vals-rood.
          markTestSkipped('chmod heeft geen effect als root (CI-container)');
          return;
        }
        expect(await workspace.workingCopy(sid), isA<FormWorkingCopyFailed>());
      },
    );

    test('een nummer buiten de grammatica is een programmeerfout', () {
      expect(() => workspace.workingCopy('../x'), throwsArgumentError);
    });

    group('weggooien', () {
      test('verwijdert alleen de werkkopie', () async {
        final received = await landed();
        final before = await received.readAsBytes();
        await workspace.workingCopy(sid);
        await copyFile().writeAsString('Verbeterd door de redactie.');
        expect(
          await workspace.discardWorkingCopy(sid),
          FormDiscardResult.discarded,
        );
        expect(copyFile().existsSync(), isFalse);
        expect(await received.readAsBytes(), before);
        expect(
          File(
            p.join(workspace.submissionPath(sid), 'manifest.json'),
          ).existsSync(),
          isTrue,
        );
      });

      test('de beoordeling gaat daarna weer over wat binnenkwam', () async {
        await landed();
        await workspace.workingCopy(sid);
        expect(
          ((await workspace.reviewStored(sid)) as FormStoredReview).edited,
          isTrue,
        );
        await workspace.discardWorkingCopy(sid);
        expect(
          ((await workspace.reviewStored(sid)) as FormStoredReview).edited,
          isFalse,
        );
      });

      test('zonder werkkopie is er niets te doen', () async {
        await landed();
        expect(await workspace.discardWorkingCopy(sid), FormDiscardResult.none);
        await workspace.workingCopy(sid);
        await workspace.discardWorkingCopy(sid);
        expect(await workspace.discardWorkingCopy(sid), FormDiscardResult.none);
      });

      test('een verwijzing naar niets is geen werkkopie', () async {
        if (Platform.isWindows) return;
        await landed();
        Link(copyFile().path).createSync(p.join(dir.path, 'bestaat-niet'));
        expect(await workspace.discardWorkingCopy(sid), FormDiscardResult.none);
        expect(
          ((await workspace.reviewStored(sid)) as FormStoredReview).edited,
          isFalse,
        );
      });

      test('een map met die naam is geen werkkopie en blijft staan', () async {
        await landed();
        final folder = Directory(copyFile().path)..createSync();
        expect(await workspace.discardWorkingCopy(sid), FormDiscardResult.none);
        expect(folder.existsSync(), isTrue);
      });

      test(
        'een verwijzing wordt zelf verwijderd, wat erachter ligt blijft',
        () async {
          if (Platform.isWindows) return;
          await landed();
          final outside = File(p.join(dir.path, 'buiten.md'))
            ..writeAsStringSync('niet van de werkmap');
          Link(copyFile().path).createSync(outside.path);
          expect(
            await workspace.discardWorkingCopy(sid),
            FormDiscardResult.discarded,
          );
          expect(
            FileSystemEntity.typeSync(copyFile().path, followLinks: false),
            FileSystemEntityType.notFound,
          );
          expect(outside.readAsStringSync(), 'niet van de werkmap');
        },
      );

      test(
        'een schijf waar niet in te schrijven valt meldt dat het mislukte',
        () async {
          if (Platform.isWindows) return;
          await landed();
          await workspace.workingCopy(sid);
          final folder = workspace.submissionPath(sid);
          await Process.run('chmod', ['555', folder]);
          addTearDown(() => Process.run('chmod', ['755', folder]));
          if (!chmodLockHoudt(folder)) {
            // `chmod` houdt root niet tegen; de CI-container draait als root.
            // Dan is dit scenario niet toetsbaar — overslaan i.p.v. vals-rood.
            markTestSkipped('chmod heeft geen effect als root (CI-container)');
            return;
          }
          expect(
            await workspace.discardWorkingCopy(sid),
            FormDiscardResult.failed,
          );
          expect(copyFile().existsSync(), isTrue);
        },
      );

      test(
        'een werkkopie die niet te lezen is staat als bewerkt in de uitkomst',
        () async {
          await landed();
          await workspace.workingCopy(sid);
          await copyFile().writeAsBytes([0xff, 0xfe, 0x00]);
          final result =
              await workspace.reviewStored(sid) as FormStoredUnavailable;
          expect(result.edited, isTrue);
          expect(result.deleted, isFalse);
        },
      );

      test('een nummer buiten de grammatica is een programmeerfout', () {
        expect(() => workspace.discardWorkingCopy('../x'), throwsArgumentError);
      });
    });

    test('de beoordeling gaat daarna over de kopie', () async {
      await workspace.publishForm(kook);
      final package = packageOf(kook, naam: '');
      await workspace.land(package, reviewOf(package, kook));
      await workspace.workingCopy(sid);
      final same = await workspace.reviewStored(sid) as FormStoredReview;
      expect(same.edited, isTrue);
      expect(same.review.problems.map((p) => p.code), [
        FormIssueCode.requiredEmpty,
      ]);
      await copyFile().writeAsString(filled(kook, 'Sari'));
      final fixed = await workspace.reviewStored(sid) as FormStoredReview;
      expect(fixed.review.problems, isEmpty);
    });
  });

  group('verwijderen laat het minimale record', () {
    Future<String> landed() async {
      final package = packageOf(kook);
      await workspace.land(package, reviewOf(package, kook));
      final folder = workspace.submissionPath(sid);
      await File(
        p.join(folder, 'submission.edit.md'),
      ).writeAsString('werkkopie');
      await Directory(p.join(folder, 'images')).create(recursive: true);
      await File(
        p.join(folder, 'images', 'foto-1.jpg'),
      ).writeAsBytes([1, 2, 3]);
      return folder;
    }

    test(
      'submission, werkkopie en foto\'s gaan; het manifest blijft',
      () async {
        final folder = await landed();
        expect(await workspace.deleteSubmissionFiles(sid), isTrue);
        expect(File(p.join(folder, 'submission.md')).existsSync(), isFalse);
        expect(
          File(p.join(folder, 'submission.edit.md')).existsSync(),
          isFalse,
        );
        expect(Directory(p.join(folder, 'images')).existsSync(), isFalse);
        expect(File(p.join(folder, 'manifest.json')).existsSync(), isTrue);
        expect(await workspace.submissionIds(), [sid]);
      },
    );

    test('nog eens verwijderen mag, en is niets', () async {
      await landed();
      await workspace.deleteSubmissionFiles(sid);
      expect(await workspace.deleteSubmissionFiles(sid), isTrue);
    });

    test('een inzending die er niet is, is er niet', () async {
      expect(await workspace.deleteSubmissionFiles(sid), isFalse);
    });

    test('een verwijzing naar elders wordt niet gevolgd', () async {
      final folder = await landed();
      final elsewhere = Directory(p.join(dir.path, 'elders'));
      await elsewhere.create();
      await File(p.join(elsewhere.path, 'blijft.txt')).writeAsString('x');
      await Directory(p.join(folder, 'images')).delete(recursive: true);
      try {
        await Link(p.join(folder, 'images')).create(elsewhere.path);
      } on FileSystemException {
        return; // Windows zonder rechten om te koppelen
      }
      await workspace.deleteSubmissionFiles(sid);
      expect(File(p.join(elsewhere.path, 'blijft.txt')).existsSync(), isTrue);
      expect(Link(p.join(folder, 'images')).existsSync(), isFalse);
    });
  });

  group('een inzending opnieuw beoordelen', () {
    const photoPath = 'images/foto-1.jpg';
    final withPhoto = kook.replaceFirst(
      '<!-- field id=naam',
      '<!-- field id=foto type=image count=0..2 -->\n**Foto**\n<!-- answer -->\n<!-- /field id=foto -->\n\n<!-- field id=naam',
    );

    Future<FormStoredReview> reviewed(String id) async =>
        await workspace.reviewStored(id) as FormStoredReview;

    Future<void> landIn(
      FormWorkspace target,
      FormPackageOpened package,
      String template,
    ) async {
      await target.publishForm(template);
      final review = reviewFormPackage(package, [template]);
      expect(await target.land(package, review), FormLandOutcome.landed);
    }

    test('een goede inzending heeft niets om na te lopen', () async {
      await landIn(workspace, packageOf(kook), kook);
      final result = await reviewed(sid);
      expect(result.edited, isFalse);
      expect(result.review.problems, isEmpty);
      expect(result.review.acceptable, isTrue);
      expect(result.review.answers!.byId['naam']!.text, 'Sari');
    });

    test('een fout blijft een fout, tot de werkkopie hem herstelt', () async {
      await landIn(workspace, packageOf(kook, naam: ''), kook);
      final first = await reviewed(sid);
      expect(first.review.problems.map((p) => p.code), [
        FormIssueCode.requiredEmpty,
      ]);
      final folder = workspace.submissionPath(sid);
      await File(
        p.join(folder, 'submission.edit.md'),
      ).writeAsString(filled(kook, 'Sari'));
      final fixed = await reviewed(sid);
      expect(fixed.edited, isTrue);
      expect(fixed.review.problems, isEmpty);
      expect(
        await File(p.join(folder, 'submission.md')).readAsString(),
        filled(kook, ''),
        reason: 'wat binnenkwam is niet aangeraakt',
      );
    });

    test(
      'een werkkopie waarin de tekst van het formulier is veranderd, valt op',
      () async {
        await landIn(workspace, packageOf(kook), kook);
        await File(
          p.join(workspace.submissionPath(sid), 'submission.edit.md'),
        ).writeAsString(
          filled(kook.replaceFirst('# Inzending', '# Anders'), 'Sari'),
        );
        final result = await reviewed(sid);
        expect(result.review.problems.map((p) => p.code), [
          FormIssueCode.templateTextAltered,
        ]);
      },
    );

    test('een verwijderde inzending laat alleen het record over', () async {
      await landIn(workspace, packageOf(kook), kook);
      await workspace.deleteSubmissionFiles(sid);
      final result = await workspace.reviewStored(sid);
      expect(result, isA<FormStoredUnavailable>());
      expect((result as FormStoredUnavailable).deleted, isTrue);
    });

    test(
      'bestanden die er niet meer of niet kloppen zijn niet te beoordelen',
      () async {
        await landIn(workspace, packageOf(kook), kook);
        final folder = workspace.submissionPath(sid);

        Future<void> expectUnavailable(String why) async {
          final result = await workspace.reviewStored(sid);
          expect(result, isA<FormStoredUnavailable>(), reason: why);
          expect(
            (result as FormStoredUnavailable).deleted,
            isFalse,
            reason: why,
          );
        }

        final submission = File(p.join(folder, 'submission.md'));
        final good = await submission.readAsBytes();
        await submission.writeAsBytes([0xFF, 0xFE, 0x41]);
        await expectUnavailable('geen UTF-8');
        await submission.writeAsBytes(good);

        final edit = File(p.join(folder, 'submission.edit.md'));
        await edit.writeAsBytes([0xFF, 0xFE, 0x41]);
        await expectUnavailable('werkkopie geen UTF-8');
        await edit.delete();

        final manifest = File(p.join(folder, 'manifest.json'));
        final manifestGood = await manifest.readAsBytes();
        await manifest.writeAsString('geen json');
        await expectUnavailable('manifest kapot');
        await manifest.writeAsBytes(manifestGood);
        expect(await workspace.reviewStored(sid), isA<FormStoredReview>());

        await manifest.delete();
        await expectUnavailable('geen manifest');
      },
    );

    test('een werkkopie die niet te lezen is, is niet "verwijderd"', () async {
      if (Platform.isWindows) return; // geen chmod
      await landIn(workspace, packageOf(kook), kook);
      final edit = File(
        p.join(workspace.submissionPath(sid), 'submission.edit.md'),
      );
      await edit.writeAsString('werkkopie');
      await Process.run('chmod', ['000', edit.path]);
      addTearDown(() => Process.run('chmod', ['644', edit.path]));
      if (!chmodLockHoudt(edit.path, schrijven: false)) {
        // `chmod` houdt root niet tegen; de CI-container draait als root.
        // Dan is dit scenario niet toetsbaar — overslaan i.p.v. vals-rood.
        markTestSkipped('chmod heeft geen effect als root (CI-container)');
        return;
      }
      final result = await workspace.reviewStored(sid);
      expect(result, isA<FormStoredUnavailable>());
      expect((result as FormStoredUnavailable).deleted, isFalse);
    });

    test(
      'een manifest van een andere inzending hoort niet in deze map',
      () async {
        await landIn(workspace, packageOf(kook), kook);
        final other = 'abcdefghijklmnopqrstuvwxyb';
        await Directory(
          workspace.submissionPath(sid),
        ).rename(workspace.submissionPath(other));
        final result = await workspace.reviewStored(other);
        expect(result, isA<FormStoredUnavailable>());
      },
    );

    test(
      'zonder het formulier in de werkmap is het formulier onbekend',
      () async {
        final elsewhere = FormWorkspace(p.join(dir.path, 'elders'));
        await landIn(elsewhere, packageOf(kook), kook);
        await Directory(
          p.join(elsewhere.root, 'forms'),
        ).delete(recursive: true);
        final result = await elsewhere.reviewStored(sid) as FormStoredReview;
        expect(result.review.problems.map((p) => p.code), [
          FormIssueCode.templateUnknown,
        ]);
        expect(result.review.acceptable, isFalse);
      },
    );

    test(
      'de foto\'s komen mee, en een foto die ontbreekt wordt gemeld',
      () async {
        final photo = jpegPhoto();
        final package =
            readFormPackage(
                  buildFormPackage(
                    submission: filled(withPhoto, 'Sari').replaceFirst(
                      '<!-- answer -->\n<!-- /field id=foto',
                      '<!-- answer -->\n![]($photoPath)\n<!-- /field id=foto',
                    ),
                    template: withPhoto,
                    spec: (parseForm(withPhoto) as ParsedForm).spec,
                    images: {photoPath: photo},
                    submissionId: sid,
                    created: DateTime.utc(2026, 10, 4),
                    clientRules: kFormRulesVersion,
                  ),
                )
                as FormPackageOpened;
        await landIn(workspace, package, withPhoto);
        final ok = await reviewed(sid);
        expect(ok.review.problems, isEmpty);
        expect(ok.review.images.keys, [photoPath]);

        final folder = workspace.submissionPath(sid);
        // Wat niet in de naamgrammatica past, telt niet mee.
        await File(p.join(folder, 'images', 'nul.jpg')).writeAsBytes([1]);
        await File(p.join(folder, 'images', 'x y.jpg')).writeAsBytes([1]);
        await File(p.join(folder, photoPath)).delete();
        final missing = await reviewed(sid);
        expect(missing.review.images, isEmpty);
        expect(missing.review.problems.map((p) => p.code), [
          FormIssueCode.imageMissingFile,
        ]);
      },
    );

    test('een verwijzing in images/ wordt niet gevolgd', () async {
      await landIn(workspace, packageOf(kook), kook);
      final folder = workspace.submissionPath(sid);
      final outside = File(p.join(dir.path, 'buiten.jpg'))
        ..writeAsBytesSync([1, 2]);
      await Directory(p.join(folder, 'images')).create(recursive: true);
      try {
        await Link(p.join(folder, 'images', 'foto-9.jpg')).create(outside.path);
      } on FileSystemException {
        return; // Windows zonder rechten om te koppelen
      }
      expect((await reviewed(sid)).review.images, isEmpty);
    });

    test('een nummer buiten de grammatica is een programmeerfout', () {
      expect(() => workspace.reviewStored('../x'), throwsArgumentError);
    });
  });

  group('het register', () {
    FormRegister fresh() =>
        FormRegister.empty((parseForm(kook) as ParsedForm).spec);

    test('zonder bestand is er geen register', () async {
      expect(await workspace.readRegister(), isNull);
    });

    test('wordt bewaard in de werkmap en leest terug', () async {
      expect(await workspace.saveRegister(fresh()), isTrue);
      expect(workspace.registerPath, p.join(workspace.root, 'overview.md'));
      final read = await workspace.readRegister() as FormRegisterParsed;
      expect(read.register.columns, fresh().columns);
    });

    test('een register dat niet te lezen is wordt niet overschreven', () async {
      await Directory(workspace.root).create(recursive: true);
      await File(
        workspace.registerPath,
      ).writeAsString('Mijn eigen aantekeningen.\n');
      expect(await workspace.readRegister(), isA<FormRegisterDamaged>());
      expect(await workspace.saveRegister(fresh()), isFalse);
      expect(
        await File(workspace.registerPath).readAsString(),
        'Mijn eigen aantekeningen.\n',
      );
    });

    test('een register dat geen UTF-8 is, is beschadigd', () async {
      await Directory(workspace.root).create(recursive: true);
      await File(workspace.registerPath).writeAsBytes([0xFF, 0xFE, 0x41]);
      final read = await workspace.readRegister() as FormRegisterDamaged;
      expect(read.reason, 'not UTF-8');
    });

    test('een register waar niet in te schrijven valt, meldt het', () async {
      await Directory(workspace.registerPath).create(recursive: true);
      // Een map met de naam van het register: lezen geeft "bestaat niet als bestand".
      expect(await workspace.saveRegister(fresh()), isFalse);
    });
  });
}
