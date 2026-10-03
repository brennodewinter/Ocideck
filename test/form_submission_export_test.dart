// Van een ingevuld formulier naar het inzendpakket (FORM_INTAKE.md §5.2): de
// controle vlak vóór het opslaan en wat er in de zip terechtkomt.

import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/services/form/form_submission_export.dart';
import 'package:ocideck_form_core/ocideck_form_core.dart';

import 'support/form_photo_fixtures.dart';

const String frontMatter = '---\ntitle: Kookboek\n---\n';

const String leeg = '''<!-- form id=kook version=2 rules=1 -->
Welkom.

<!-- field id=naam type=text required max-chars=40 -->
**Naam**
<!-- answer -->
<!-- /field id=naam -->

<!-- field id=foto type=image count=0..70 -->
**Foto's**
<!-- answer -->
<!-- /field id=foto -->
''';

String gevuld({List<String> fotos = const []}) => leeg
    .replaceFirst(
      '<!-- answer -->\n<!-- /field id=naam -->',
      '<!-- answer -->\nSari\n<!-- /field id=naam -->',
    )
    .replaceFirst(
      '<!-- answer -->\n<!-- /field id=foto -->',
      '<!-- answer -->\n${fotos.map((f) => '![]($f)').join('\n')}${fotos.isEmpty ? '' : '\n'}<!-- /field id=foto -->',
    );

FormFill fillOf(String text, {Iterable<String> photos = const []}) {
  final open = FormFill.open(
    text,
    imageFacts: {
      for (final path in photos)
        path: const FormImageFact(
          displayedWidth: 3000,
          bytes: 1000,
          format: 'jpg',
        ),
    },
  );
  return (open as FormFillReady).fill;
}

Future<FormSubmissionResult> build(
  FormFill fill, {
  String? published,
  Map<String, Uint8List?> files = const {},
  Random? random,
}) => buildFormSubmission(
  fill: fill,
  frontMatter: frontMatter,
  published: published ?? frontMatter + leeg,
  readImage: (path) async => files[path],
  now: DateTime.utc(2026, 10, 4),
  random: random ?? Random(7),
  clientVersion: '0.6.13',
);

FormPackageOpened open(FormSubmissionBuilt built) =>
    readFormPackage(built.bytes) as FormPackageOpened;

void main() {
  test(
    'een ingevuld formulier wordt een pakket dat de eigen lezer opent',
    () async {
      final result = await build(fillOf(gevuld()));
      final built = result as FormSubmissionBuilt;
      final opened = open(built);
      expect(opened.submission, frontMatter + gevuld());
      expect(opened.manifest.formId, 'kook');
      expect(opened.manifest.formVersion, 2);
      expect(opened.manifest.created, '2026-10-04');
      expect(opened.manifest.clientVersion, '0.6.13');
      expect(opened.manifest.clientRules, kFormRulesVersion);
      expect(
        opened.manifest.templateSha256,
        formTemplateHash(frontMatter + leeg),
      );
      expect(built.photos, 0);
      expect(built.fileName, matches(RegExp(r'^kook-[a-z2-7]{6}\.zip$')));
      expect(
        built.fileName,
        'kook-${opened.manifest.submissionId.substring(0, 6)}.zip',
      );
      // Het nummer waaronder de server de inzending kent is het nummer in het manifest.
      expect(built.sid, opened.manifest.submissionId);
    },
  );

  test('met dezelfde dobbelsteen komt dezelfde zip uit', () async {
    final a = await build(fillOf(gevuld()), random: Random(3));
    final b = await build(fillOf(gevuld()), random: Random(3));
    final c = await build(fillOf(gevuld()), random: Random(4));
    expect((a as FormSubmissionBuilt).bytes, (b as FormSubmissionBuilt).bytes);
    expect(a.bytes, isNot((c as FormSubmissionBuilt).bytes));
  });

  test('een open fout houdt het pakket tegen', () async {
    final result = await build(fillOf(leeg));
    expect(result, isA<FormSubmissionBlocked>());
    expect(
      (result as FormSubmissionBlocked).problems.map((p) => p.code),
      contains(FormIssueCode.requiredEmpty),
    );
  });

  test(
    'een formulier waarvan de tekst is veranderd is niet het gepubliceerde',
    () async {
      final result = await build(
        fillOf(gevuld()),
        published:
            frontMatter + leeg.replaceFirst('Welkom.', 'Welkom allemaal.'),
      );
      expect(result, isA<FormSubmissionWrongForm>());
      expect(
        (result as FormSubmissionWrongForm).problem.code,
        FormIssueCode.templateTextAltered,
      );
    },
  );

  test('een andere front matter is ook een ander formulier', () async {
    final result = await build(
      fillOf(gevuld()),
      published: '---\ntitle: Anders\n---\n$leeg',
    );
    expect(result, isA<FormSubmissionWrongForm>());
  });

  test(
    'een gepubliceerd formulier dat geen formulier is, wordt gemeld',
    () async {
      final result = await build(fillOf(gevuld()), published: 'Gewoon tekst.');
      expect(result, isA<FormSubmissionWrongForm>());
      expect(
        (result as FormSubmissionWrongForm).problem.code,
        FormIssueCode.structureDamaged,
      );
    },
  );

  test('een foto gaat mee onder zijn eigen pad', () async {
    const path = 'images/foto-1.jpg';
    final fill = fillOf(gevuld(fotos: [path]), photos: [path]);
    final built =
        await build(fill, files: {path: jpegPhoto()}) as FormSubmissionBuilt;
    expect(built.photos, 1);
    expect(open(built).images.keys, [path]);
  });

  test(
    'een foto die met de hand een positie draagt, vertrekt zonder',
    () async {
      const path = 'images/foto-1.jpg';
      final fill = fillOf(gevuld(fotos: [path]), photos: [path]);
      final onDisk = jpegPhoto(gps: true);
      expect(cleanImage(onDisk)!.removed.gps, isTrue);
      final built =
          await build(fill, files: {path: onDisk}) as FormSubmissionBuilt;
      final sent = open(built).images[path]!;
      expect(cleanImage(sent)!.removed.gps, isFalse);
      expect(sent.length, lessThan(onDisk.length));
    },
  );

  test('een foto die er niet meer is, wordt bij naam genoemd', () async {
    const path = 'images/foto-1.jpg';
    final fill = fillOf(gevuld(fotos: [path]), photos: [path]);
    final result = await build(fill);
    expect(result, isA<FormSubmissionPhotoUnreadable>());
    expect((result as FormSubmissionPhotoUnreadable).path, path);
  });

  test('een bestand dat geen foto is, gaat niet mee', () async {
    const path = 'images/foto-1.jpg';
    final fill = fillOf(gevuld(fotos: [path]), photos: [path]);
    final result = await build(
      fill,
      files: {
        path: Uint8List.fromList([1, 2, 3, 4]),
      },
    );
    expect(result, isA<FormSubmissionPhotoUnreadable>());
  });

  test(
    'een pakket dat de eigen lezer zou weigeren, wordt niet gebouwd',
    () async {
      final paths = [for (var i = 1; i <= 63; i++) 'images/foto-$i.jpg'];
      final fill = fillOf(gevuld(fotos: paths), photos: paths);
      final photo = jpegPhoto();
      final result = await build(
        fill,
        files: {for (final p in paths) p: photo},
      );
      expect(result, isA<FormSubmissionRefused>());
      expect(
        (result as FormSubmissionRefused).reason,
        contains('too many files'),
      );
    },
  );

  test('64 bestanden is de rand: 62 foto\'s passen, 63 niet', () async {
    final paths = [for (var i = 1; i <= 62; i++) 'images/foto-$i.jpg'];
    final fill = fillOf(gevuld(fotos: paths), photos: paths);
    final photo = jpegPhoto();
    final result = await build(fill, files: {for (final p in paths) p: photo});
    expect((result as FormSubmissionBuilt).photos, 62);
  });
}
