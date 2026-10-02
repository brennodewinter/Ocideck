import 'dart:typed_data';

import 'package:ocideck_form_core/ocideck_form_core.dart';
import 'package:test/test.dart';

import 'support/image_fixtures.dart';

const String published = '''<!-- form id=kookboek version=2 rules=1 -->
# Inzending

<!-- field id=naam type=text required max-chars=20 -->
**Naam**
<!-- answer -->
<!-- /field id=naam -->

<!-- field id=verhaal type=prose words=3..6 -->
**Verhaal**
<!-- answer -->
<!-- /field id=verhaal -->

<!-- field id=foto type=image count=0..2 min-width=2000 -->
**Foto's**
<!-- answer -->
<!-- /field id=foto -->

<!-- field id=akkoord type=consent required -->
Ik ga akkoord met publicatie.
<!-- answer -->
- [ ]
<!-- /field id=akkoord -->
''';

String fill({
  String naam = 'Sari',
  String verhaal = 'Een mooi verhaal hier',
  List<String> fotos = const [],
  bool akkoord = true,
  String from = published,
}) => from
    .replaceFirst(
      '<!-- answer -->\n<!-- /field id=naam -->',
      '<!-- answer -->\n$naam\n<!-- /field id=naam -->',
    )
    .replaceFirst(
      '<!-- answer -->\n<!-- /field id=verhaal -->',
      '<!-- answer -->\n$verhaal\n<!-- /field id=verhaal -->',
    )
    .replaceFirst(
      '<!-- answer -->\n<!-- /field id=foto -->',
      '<!-- answer -->\n${fotos.map((f) => '![]($f)').join('\n')}${fotos.isEmpty ? '' : '\n'}<!-- /field id=foto -->',
    )
    .replaceFirst('- [ ]', akkoord ? '- [x]' : '- [ ]');

FormSpec specOf(String text) => (parseForm(text) as ParsedForm).spec;

/// What a client builds, from the copy of the form it worked from ([client]).
FormPackageOpened received({
  String? submission,
  String? client,
  Map<String, Uint8List> images = const {},
}) {
  final copy = client ?? published;
  final bytes = buildFormPackage(
    submission: submission ?? fill(from: copy),
    template: copy,
    spec: specOf(copy),
    images: images,
    submissionId: 'abcdefghijklmnopqrstuvwxyz',
    created: DateTime.utc(2026, 10, 4),
    clientRules: kFormRulesVersion,
  );
  return readFormPackage(bytes) as FormPackageOpened;
}

FormPackageOpened withManifest(
  FormPackageOpened p, {
  List<FormManifestConsent>? consent,
  String? templateSha256,
}) {
  final m = p.manifest;
  return FormPackageOpened(
    manifest: FormPackageManifest(
      submissionId: m.submissionId,
      formId: m.formId,
      formVersion: m.formVersion,
      formRules: m.formRules,
      templateSha256: templateSha256 ?? m.templateSha256,
      created: m.created,
      clientName: m.clientName,
      clientVersion: m.clientVersion,
      clientRules: m.clientRules,
      files: m.files,
      consent: consent ?? m.consent,
    ),
    submission: p.submission,
    images: p.images,
  );
}

FormReview review(FormPackageOpened package, {List<String>? forms}) =>
    reviewFormPackage(package, forms ?? [published]);

Iterable<FormIssueCode> codes(FormReview r) => r.problems.map((p) => p.code);

void main() {
  group('a package that is what it says it is', () {
    test('is accepted, with nothing to report', () {
      final r = review(received());
      expect(r.problems, isEmpty);
      expect(r.acceptable, isTrue);
      expect(r.published, published);
      expect(r.spec!.id, 'kookboek');
      expect(r.answers!.byId['naam']!.text, 'Sari');
      expect(r.images, isEmpty);
      expect(r.strippedAgain, isEmpty);
      expect(r.unreferencedImages, isEmpty);
    });

    test('finds its form among several versions and languages by the hash', () {
      final english = published.replaceAll('Inzending', 'Submission');
      final older = published.replaceFirst('version=2', 'version=1');
      final r = review(
        received(client: english),
        forms: [published, older, english],
      );
      expect(r.published, english);
      expect(r.problems, isEmpty);
    });

    test('the photos it names are kept and measured', () {
      final photo = jpegClean(width: 2400, height: 1800);
      final r = review(
        received(
          submission: fill(fotos: ['images/foto-1.jpg']),
          images: {'images/foto-1.jpg': photo},
        ),
      );
      expect(r.problems, isEmpty);
      expect(r.images['images/foto-1.jpg'], photo);
      expect(r.strippedAgain, isEmpty);
    });
  });

  group('a form the organiser does not hold', () {
    test('is unknown, and nothing is judged', () {
      final r = review(
        received(),
        forms: [published.replaceAll('kookboek', 'ander')],
      );
      expect(codes(r), [FormIssueCode.templateUnknown]);
      expect(r.acceptable, isFalse);
      expect(r.spec, isNull);
      expect(r.published, isNull);
      expect(r.answers, isNull);
      final facts = r.problems.single.facts;
      expect(facts['form'], 'kookboek');
      expect(facts['version'], 2);
    });

    test('a known form with a version nobody published is unknown too', () {
      final r = review(
        received(),
        forms: [published.replaceFirst('version=2', 'version=3')],
      );
      expect(codes(r), [FormIssueCode.templateUnknown]);
    });

    test('with nothing published at all', () {
      expect(codes(review(received(), forms: [])), [
        FormIssueCode.templateUnknown,
      ]);
    });
  });

  group('the rules are the published ones, never the client\'s', () {
    test(
      'a client that weakened a rule in its own copy is judged by the real one',
      () {
        final weakened = published.replaceFirst('words=3..6', 'words=1..99');
        final r = review(
          received(
            client: weakened,
            submission: fill(verhaal: 'Eén', from: weakened),
          ),
        );
        expect(
          codes(r),
          containsAll([
            FormIssueCode.templateTextAltered,
            FormIssueCode.tooFewWords,
          ]),
        );
        expect(r.acceptable, isFalse);
        expect(
          r.problems
              .firstWhere((p) => p.code == FormIssueCode.tooFewWords)
              .fieldId,
          'verhaal',
        );
      },
    );

    test(
      'a copy that differs only inside an answer zone is a hash problem alone',
      () {
        final withPlaceholder = published.replaceFirst(
          '<!-- answer -->\n<!-- /field id=naam -->',
          '<!-- answer -->\nuw naam\n<!-- /field id=naam -->',
        );
        final r = review(received(client: withPlaceholder), forms: [published]);
        expect(codes(r), [FormIssueCode.templateTextAltered]);
        expect(r.problems.single.facts['reason'], 'hash');
      },
    );

    test('text outside the answers that was changed is named', () {
      final r = review(
        received(
          submission: fill().replaceFirst(
            '# Inzending',
            '# Inzending!\n\nExtra.',
          ),
        ),
      );
      expect(codes(r), [FormIssueCode.templateTextAltered]);
      expect(r.problems.single.facts['region'], 'outside-fields');
      expect(r.acceptable, isFalse);
    });

    test('a reworded consent text is found in the text, not the manifest', () {
      final r = review(
        received(
          submission: fill().replaceFirst(
            'Ik ga akkoord met publicatie.',
            'Ik ga akkoord met alles.',
          ),
        ),
      );
      expect(codes(r), [FormIssueCode.templateTextAltered]);
      expect(r.problems.single.fieldId, 'akkoord');
    });
  });

  group('the consent record is a cross-check', () {
    test('a recorded consent whose text hash is wrong is refused', () {
      final p = received();
      final r = review(
        withManifest(
          p,
          consent: [
            FormManifestConsent('akkoord', p.manifest.created, 'f' * 64),
          ],
        ),
      );
      expect(codes(r), [FormIssueCode.templateTextAltered]);
      expect(r.problems.single.facts['reason'], 'consent');
    });

    test(
      'a consent the answers give but the manifest does not record is refused',
      () {
        final r = review(withManifest(received(), consent: []));
        expect(codes(r), [FormIssueCode.templateTextAltered]);
      },
    );

    test(
      'a consent the manifest records but the answers do not give is refused',
      () {
        final honest = received();
        final r = review(
          withManifest(
            received(submission: fill(akkoord: false)),
            consent: honest.manifest.consent,
          ),
        );
        expect(codes(r), contains(FormIssueCode.templateTextAltered));
      },
    );

    test('an unticked consent that is not recorded is simply not given', () {
      final r = review(received(submission: fill(akkoord: false)));
      expect(codes(r), [FormIssueCode.consentNotGiven]);
    });
  });

  group('the answers', () {
    test('a required answer left empty needs fixing', () {
      final r = review(received(submission: fill(naam: '')));
      expect(codes(r), [FormIssueCode.requiredEmpty]);
      expect(r.problems.single.fieldId, 'naam');
      expect(r.acceptable, isFalse);
    });

    test('a warning does not block', () {
      final r = review(
        received(
          submission: fill(fotos: ['images/foto-1.jpg']),
          images: {'images/foto-1.jpg': jpegClean(width: 640)},
        ),
      );
      expect(codes(r), [FormIssueCode.imageTooSmall]);
      expect(r.acceptable, isTrue);
    });
  });

  group('the photos', () {
    const path = 'images/foto-1.jpg';

    test('are cleaned again, and what was still in them is reported', () {
      final dirty = jpeg(width: 2400, exif: tiff(gps: true));
      final r = review(
        received(
          submission: fill(fotos: [path]),
          images: {path: dirty},
        ),
      );
      expect(r.acceptable, isTrue);
      expect(r.strippedAgain[path]!.gps, isTrue);
      expect(cleanImage(r.images[path]!)!.removed.gps, isFalse);
      expect(r.images[path]!.length, lessThan(dirty.length));
    });

    test('anything cut off after the end of the picture is reported', () {
      final trailing = jpeg(width: 2400, trailer: [1, 2, 3, 4]);
      final r = review(
        received(
          submission: fill(fotos: [path]),
          images: {path: trailing},
        ),
      );
      expect(r.strippedAgain[path]!.trailerBytes, 4);
    });

    test('each kind of leftover counts as something removed', () {
      for (final photo in [
        jpeg(width: 2400, exif: tiff()),
        jpeg(width: 2400, xmp: true),
        jpeg(width: 2400, comment: true),
        jpeg(width: 2400, makerNote: true),
      ]) {
        final r = review(
          received(
            submission: fill(fotos: [path]),
            images: {path: photo},
          ),
        );
        expect(r.strippedAgain.keys, [path], reason: 'one of the segments');
      }
    });

    test('other formats are measured by what they are, not by their name', () {
      final r = review(
        received(
          submission: fill(fotos: ['images/foto-1.png', 'images/foto-2.webp']),
          images: {
            'images/foto-1.png': png(width: 2400, height: 1800),
            'images/foto-2.webp': webp(width: 2400, height: 1800),
          },
        ),
      );
      expect(r.problems, isEmpty);
      expect(r.strippedAgain, isEmpty);
    });

    test('a picture under its wrong extension is a format problem', () {
      final r = review(
        received(
          submission: fill(fotos: ['images/foto-1.png']),
          images: {'images/foto-1.png': jpegClean(width: 2400)},
        ),
      );
      expect(codes(r), [FormIssueCode.imageFormat]);
    });

    test('the size rule is judged on the picture as it is kept', () {
      // 3000 bytes of trailer: over the limit as received, well under it once cut.
      final padded = jpeg(width: 2400, trailer: List.filled(3000, 7));
      final cleaned = cleanImage(padded)!.bytes.length;
      final limited = published.replaceFirst(
        'min-width=2000',
        'min-width=2000 max-bytes=${cleaned + 10}',
      );
      final package = received(
        client: limited,
        submission: fill(from: limited, fotos: ['images/foto-1.jpg']),
        images: {'images/foto-1.jpg': padded},
      );
      expect(padded.length, greaterThan(cleaned + 10));
      expect(review(package, forms: [limited]).problems, isEmpty);

      final tighter = limited.replaceFirst(
        'max-bytes=${cleaned + 10}',
        'max-bytes=${cleaned - 1}',
      );
      final over = received(
        client: tighter,
        submission: fill(from: tighter, fotos: ['images/foto-1.jpg']),
        images: {'images/foto-1.jpg': padded},
      );
      expect(codes(review(over, forms: [tighter])), [
        FormIssueCode.imageTooLarge,
      ]);
    });

    test('a photo the answer names but the package lacks is missing', () {
      final r = review(received(submission: fill(fotos: [path])));
      expect(codes(r), [FormIssueCode.imageMissingFile]);
      expect(r.acceptable, isFalse);
    });

    test('a photo no answer names is listed, and blocks nothing', () {
      final r = review(
        received(images: {'images/los-1.jpg': jpegClean(width: 2400)}),
      );
      expect(r.problems, isEmpty);
      expect(r.unreferencedImages, ['images/los-1.jpg']);
      expect(r.images.keys, ['images/los-1.jpg']);
    });

    test(
      'a file that is no picture is a format problem, and is kept as received',
      () {
        final junk = Uint8List.fromList(List.generate(200, (i) => i));
        final r = review(
          received(
            submission: fill(fotos: [path]),
            images: {path: junk},
          ),
        );
        expect(codes(r), [FormIssueCode.imageFormat]);
        expect(r.images[path], junk);
        expect(r.strippedAgain, isEmpty);
      },
    );

    test('a picture a real decode refused is a format problem too', () {
      final package = received(
        submission: fill(fotos: [path]),
        images: {path: jpegClean(width: 2400)},
      );
      expect(review(package).problems, isEmpty);
      final refused = reviewFormPackage(
        package,
        [published],
        undecodable: {path},
      );
      expect(codes(refused), [FormIssueCode.imageFormat]);
      expect(refused.acceptable, isFalse);
    });

    test('a HEIC is kept as it is and only warned about', () {
      final r = review(
        received(
          submission: fill(fotos: ['images/foto-1.heic']),
          images: {'images/foto-1.heic': heic()},
        ),
      );
      expect(codes(r), [FormIssueCode.imageHeicUnverified]);
      expect(r.acceptable, isTrue);
      expect(r.images['images/foto-1.heic'], heic());
    });
  });

  group('a published form that cannot be used', () {
    FormReview against(String text) {
      final bytes = buildFormPackage(
        submission: fill(),
        template: text,
        spec: specOf(published),
        images: const {},
        submissionId: 'abcdefghijklmnopqrstuvwxyz',
        created: DateTime.utc(2026, 10, 4),
        clientRules: kFormRulesVersion,
      );
      return reviewFormPackage(readFormPackage(bytes) as FormPackageOpened, [
        text,
      ]);
    }

    test('one that is broken is reported, not judged against', () {
      final r = against(published.replaceFirst('words=3..6', 'words=6..3'));
      expect(codes(r), [FormIssueCode.structureDamaged]);
      expect(r.problems.single.facts['reason'], 'published-form');
      expect(r.published, isNotNull);
      expect(r.spec, isNull);
      expect(r.acceptable, isFalse);
    });

    test('one that needs newer rules is reported as such', () {
      final r = against(published.replaceFirst('rules=1', 'rules=99'));
      expect(codes(r), [FormIssueCode.rulesTooNew]);
      expect(r.problems.single.facts['rules'], 99);
      expect(r.acceptable, isFalse);
    });

    test('one that is no form at all is reported', () {
      const text = 'Gewoon tekst.';
      final r = reviewFormPackage(
        withManifest(received(), templateSha256: formTemplateHash(text)),
        [text],
      );
      expect(codes(r), [FormIssueCode.structureDamaged]);
      expect(r.problems.single.facts['reason'], 'published-form');
    });
  });
}
