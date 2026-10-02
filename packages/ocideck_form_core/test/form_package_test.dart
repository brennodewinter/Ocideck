import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:ocideck_form_core/ocideck_form_core.dart';
import 'package:test/test.dart';

import 'support/zip_fixtures.dart';

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

FormSpec get spec => (parseForm(template) as ParsedForm).spec;

final Uint8List photo = Uint8List.fromList(List.generate(300, (i) => i % 251));
const String sid = 'abcdefghijklmnopqrstuvwxyz'; // 26 characters of [a-z]

Uint8List build({
  String submission = filled,
  Map<String, Uint8List>? images,
  DateTime? created,
}) => buildFormPackage(
  submission: submission,
  template: template,
  spec: spec,
  images: images ?? {'images/foto-1.jpg': photo},
  submissionId: sid,
  created: created ?? DateTime.utc(2026, 10, 4, 21, 30),
  clientVersion: '0.4.9',
  clientRules: kFormRulesVersion,
);

FormPackageOpened opened(Uint8List bytes, {FormPackageLimits? limits}) {
  final result = readFormPackage(
    bytes,
    limits: limits ?? const FormPackageLimits(),
  );
  expect(
    result,
    isA<FormPackageOpened>(),
    reason: result is FormPackageRefused ? '${result.problems}' : '',
  );
  return result as FormPackageOpened;
}

List<FormPackageIssue> refusal(Uint8List bytes, {FormPackageLimits? limits}) {
  final result = readFormPackage(
    bytes,
    limits: limits ?? const FormPackageLimits(),
  );
  expect(result, isA<FormPackageRefused>(), reason: 'it was opened');
  return [for (final p in (result as FormPackageRefused).problems) p.issue];
}

/// The manifest of a valid package, as JSON, to change a field and write again.
Map<String, Object?> manifestOf(Uint8List package) {
  final zip = ZipDecoder().decodeBytes(package);
  return jsonDecode(utf8.decode(zip.findFile('manifest.json')!.content))
      as Map<String, Object?>;
}

/// A package with [manifest] and the given extra or replaced entries.
Uint8List packageWith(
  Map<String, Object?> manifest, {
  List<RawEntry> more = const [],
  bool withSubmission = true,
}) => rawZip([
  if (withSubmission) RawEntry('submission.md', utf8.encode(filled)),
  RawEntry('manifest.json', utf8.encode(jsonEncode(manifest))),
  ...more,
]);

void main() {
  group('identifiers and hashes', () {
    test('a form id is 26 characters of [a-z2-7]', () {
      final random = Random(1);
      final seen = <String>{};
      for (var i = 0; i < 200; i++) {
        final id = newFormId(random);
        expect(id, matches(RegExp(r'^[a-z2-7]{26}$')));
        expect(isValidFormId(id), isTrue);
        seen.add(id);
      }
      expect(seen, hasLength(200));
    });

    test('the same seed gives the same id; it carries no clock', () {
      expect(newFormId(Random(7)), newFormId(Random(7)));
      expect(newFormId(Random(7)), isNot(newFormId(Random(8))));
    });

    test('only 26 characters of the alphabet are an id', () {
      for (final bad in [
        '',
        'abc',
        'a' * 25,
        'a' * 27,
        'A' * 26,
        '1' * 26,
        '${'a' * 25}!',
        '${'a' * 25}0',
      ]) {
        expect(isValidFormId(bad), isFalse, reason: bad);
      }
      expect(isValidFormId('a' * 26), isTrue);
      expect(isValidFormId('2' * 26), isTrue);
      expect(isValidFormId('7' * 26), isTrue);
    });

    test('the template hash ignores a BOM and not a line ending', () {
      expect(formTemplateHash('﻿abc'), formTemplateHash('abc'));
      expect(formTemplateHash('a\nb'), isNot(formTemplateHash('a\r\nb')));
      expect(
        formTemplateHash('abc'),
        'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad',
      );
    });

    test('sha256Hex is the lower-case hex digest', () {
      expect(
        sha256Hex(utf8.encode('')),
        'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855',
      );
    });

    test('the consent text is the label, as LF, trimmed', () {
      final field = spec.fieldById('akkoord')!;
      expect(consentTextOf(template, field), 'Ik ga akkoord met publicatie.');
      final crlf = template.replaceAll('\n', '\r\n');
      final crlfField = (parseForm(crlf) as ParsedForm).spec.fieldById(
        'akkoord',
      )!;
      expect(consentTextOf(crlf, crlfField), 'Ik ga akkoord met publicatie.');
    });

    test('the day is UTC and day precision', () {
      expect(formDay(DateTime.utc(2026, 10, 4, 23, 59)), '2026-10-04');
      expect(formDay(DateTime.utc(2026, 1, 2)), '2026-01-02');
      expect(formDay(DateTime.utc(987, 3, 4)), '0987-03-04');
    });
  });

  group('buildFormPackage', () {
    test('a package opens again, with everything in it', () {
      final read = opened(build());
      expect(read.submission, filled);
      expect(read.images.keys, ['images/foto-1.jpg']);
      expect(read.images['images/foto-1.jpg'], photo);
      final m = read.manifest;
      expect(m.submissionId, sid);
      expect(m.formId, 'kookboek');
      expect(m.formVersion, 2);
      expect(m.formRules, 1);
      expect(m.templateSha256, formTemplateHash(template));
      expect(m.created, '2026-10-04');
      expect(m.clientName, 'OciDeck');
      expect(m.clientVersion, '0.4.9');
      expect(m.clientRules, kFormRulesVersion);
    });

    test(
      'the manifest lists every file with its hash and size, images sorted',
      () {
        final read = opened(
          build(
            images: {
              'images/zz-2.png': Uint8List.fromList([1, 2, 3]),
              'images/foto-1.jpg': photo,
            },
          ),
        );
        final files = read.manifest.files;
        expect(files.map((f) => f.path), [
          'submission.md',
          'images/foto-1.jpg',
          'images/zz-2.png',
        ]);
        expect(files[0].sha256, sha256Hex(utf8.encode(filled)));
        expect(files[0].bytes, utf8.encode(filled).length);
        expect(files[1].sha256, sha256Hex(photo));
        expect(files[2].bytes, 3);
      },
    );

    test('a consent that is ticked is recorded with the hash of its text', () {
      final consent = opened(build()).manifest.consent.single;
      expect(consent.field, 'akkoord');
      expect(consent.accepted, '2026-10-04');
      expect(
        consent.textSha256,
        sha256Hex(utf8.encode('Ik ga akkoord met publicatie.')),
      );
    });

    test('a consent that is not ticked is not recorded', () {
      final unticked = filled.replaceFirst('- [x]', '- [ ]');
      expect(opened(build(submission: unticked)).manifest.consent, isEmpty);
    });

    test('is deterministic: the same inputs give the same bytes', () {
      expect(build(), build());
    });

    test('says nothing about when it was made beyond the day', () {
      final a = build(created: DateTime.utc(2026, 10, 4, 1, 2, 3));
      final b = build(created: DateTime.utc(2026, 10, 4, 22, 59, 59));
      expect(a, b);
      // Every entry's time stamp is the earliest a zip can say: 1980-01-01 00:00.
      final zip = ZipDecoder().decodeBytes(a);
      for (final file in zip.files) {
        expect(file.lastModDateTime, DateTime.utc(1980, 1, 1));
      }
    });

    test('carries no more than the manifest says: no extra keys', () {
      final manifest = manifestOf(build());
      expect(manifest.keys, [
        'v',
        'submission_id',
        'form',
        'created',
        'client',
        'files',
        'consent',
      ]);
      expect((manifest['form'] as Map).keys, [
        'id',
        'version',
        'rules',
        'template_sha256',
      ]);
      expect((manifest['client'] as Map).keys, ['name', 'version', 'rules']);
    });

    test(
      'without a client version the key is left out; the rules may not be',
      () {
        final bytes = buildFormPackage(
          submission: filled,
          template: template,
          spec: spec,
          images: {'images/foto-1.jpg': photo},
          submissionId: sid,
          created: DateTime.utc(2026, 10, 4),
          clientRules: 1,
        );
        final client = manifestOf(bytes)['client'] as Map;
        expect(client.containsKey('version'), isFalse);
        expect(client['rules'], 1);
        expect(opened(bytes).manifest.clientVersion, isNull);
      },
    );

    test(
      'the entries are exactly the three kinds, photos stored and text deflated',
      () {
        final zip = ZipDecoder().decodeBytes(build());
        expect(zip.files.map((f) => f.name), [
          'submission.md',
          'manifest.json',
          'images/foto-1.jpg',
        ]);
        final byName = {for (final f in zip.files) f.name: f};
        expect(byName['submission.md']!.compression, CompressionType.deflate);
        expect(byName['images/foto-1.jpg']!.compression, CompressionType.none);
        expect(zip.files.every((f) => !f.isSymbolicLink && f.isFile), isTrue);
      },
    );

    test('a package without photos is a package', () {
      final read = opened(build(images: const {}));
      expect(read.images, isEmpty);
      expect(read.manifest.files.single.path, 'submission.md');
    });

    test('refuses to build what its own reader would refuse', () {
      expect(
        () => buildFormPackage(
          submission: filled,
          template: template,
          spec: spec,
          images: const {},
          submissionId: 'not-an-id',
          created: DateTime.utc(2026),
          clientRules: 1,
        ),
        throwsArgumentError,
      );
      for (final name in [
        'images/Foto-1.jpg',
        'images/../x.jpg',
        'images/foto-1.svg',
        'foto-1.jpg',
        'images/${'a' * 65}.jpg',
      ]) {
        expect(
          () => build(images: {name: photo}),
          throwsArgumentError,
          reason: name,
        );
      }
      expect(
        () => buildFormPackage(
          submission: filled,
          template: template,
          spec: spec,
          images: {'images/a-1.jpg': Uint8List(11)},
          submissionId: sid,
          created: DateTime.utc(2026),
          clientRules: 1,
          limits: const FormPackageLimits(maxImageBytes: 10),
        ),
        throwsArgumentError,
      );
      expect(
        () => buildFormPackage(
          submission: filled,
          template: template,
          spec: spec,
          images: {for (var i = 1; i <= 3; i++) 'images/a-$i.jpg': photo},
          submissionId: sid,
          created: DateTime.utc(2026),
          clientRules: 1,
          limits: const FormPackageLimits(maxFiles: 4),
        ),
        throwsArgumentError,
      );
    });
  });

  group('readFormPackage — a package that is a package', () {
    test(
      'a zip made by someone else with the same three kinds of entries opens',
      () {
        final honest = build();
        final manifest = manifestOf(honest);
        final theirs = rawZip([
          RawEntry('submission.md', utf8.encode(filled)),
          RawEntry('manifest.json', utf8.encode(jsonEncode(manifest))),
          RawEntry('images/foto-1.jpg', photo, method: 0),
        ]);
        expect(opened(theirs).submission, filled);
      },
    );

    test('a zip comment is tolerated', () {
      final manifest = manifestOf(build());
      final zip = rawZip([
        RawEntry('submission.md', utf8.encode(filled)),
        RawEntry('manifest.json', utf8.encode(jsonEncode(manifest))),
        RawEntry('images/foto-1.jpg', photo, method: 0),
      ], comment: utf8.encode('gemaakt met iets'));
      opened(zip);
    });
  });

  group('readFormPackage — refused, fail-closed', () {
    test('what is not a zip', () {
      expect(refusal(Uint8List(0)), [FormPackageIssue.badZip]);
      expect(refusal(Uint8List.fromList(utf8.encode('geen zip'))), [
        FormPackageIssue.badZip,
      ]);
      final good = build();
      expect(refusal(Uint8List.sublistView(good, 0, good.length - 10)), [
        FormPackageIssue.badZip,
      ]);
    });

    test('zip64 and multi-disk are not read', () {
      final entries = [RawEntry('submission.md', utf8.encode('x'))];
      expect(refusal(rawZip(entries, zip64: true)), [FormPackageIssue.badZip]);
      expect(refusal(rawZip(entries, disk: 1)), [FormPackageIssue.badZip]);
    });

    test('the package, an entry, and the sum of them have limits', () {
      final good = build();
      expect(
        refusal(
          good,
          limits: FormPackageLimits(maxPackageBytes: good.length - 1),
        ),
        [FormPackageIssue.tooLarge],
      );
      expect(
        refusal(good, limits: const FormPackageLimits(maxImageBytes: 100)),
        [FormPackageIssue.tooLarge],
      );
      expect(refusal(good, limits: const FormPackageLimits(maxTextBytes: 10)), [
        FormPackageIssue.tooLarge,
      ]);
      expect(
        refusal(good, limits: const FormPackageLimits(maxExtractedBytes: 500)),
        [FormPackageIssue.tooLarge],
      );
    });

    test('more entries than the limit', () {
      expect(refusal(build(), limits: const FormPackageLimits(maxFiles: 2)), [
        FormPackageIssue.tooManyFiles,
      ]);
    });

    test('names outside the grammar of §5.4 — every one is reported', () {
      final zip = rawZip([
        RawEntry('submission.md', utf8.encode(filled)),
        RawEntry('manifest.json', utf8.encode('{}')),
        RawEntry('../evil.md', [1]),
        RawEntry('/etc/passwd', [1]),
        RawEntry('images/A.jpg', [1]),
        RawEntry('images/x.svg', [1]),
        RawEntry('images/a/b.jpg', [1]),
        RawEntry('notes.txt', [1]),
        RawEntry('Submission.md', [1]),
        RawEntry('images/${'a' * 65}.jpg', [1]),
        RawEntry('images/é.jpg', [1]),
      ]);
      final result = readFormPackage(zip) as FormPackageRefused;
      expect(result.problems.map((p) => p.issue).toSet(), {
        FormPackageIssue.badEntry,
      });
      expect(result.problems.map((p) => p.path), [
        '../evil.md',
        '/etc/passwd',
        'images/A.jpg',
        'images/x.svg',
        'images/a/b.jpg',
        'notes.txt',
        'Submission.md',
        'images/${'a' * 65}.jpg',
        'images/é.jpg',
      ]);
    });

    test('the names Windows keeps for devices are refused', () {
      for (final name in ['con', 'prn', 'aux', 'nul', 'com1', 'lpt9', 'com0']) {
        final zip = rawZip([
          RawEntry('submission.md', utf8.encode(filled)),
          RawEntry('manifest.json', utf8.encode('{}')),
          RawEntry('images/$name.jpg', [1]),
        ]);
        final result = readFormPackage(zip) as FormPackageRefused;
        expect(result.problems.map((p) => p.path), [
          'images/$name.jpg',
        ], reason: name);
      }
    });

    test('and a client does not build one', () {
      expect(
        () => build(images: {'images/nul.jpg': photo}),
        throwsArgumentError,
      );
    });

    test('a directory entry is refused', () {
      expect(
        refusal(
          rawZip([
            RawEntry('images/', const [], method: 0),
            RawEntry('submission.md', utf8.encode(filled)),
          ]),
        ),
        [FormPackageIssue.badEntry],
      );
    });

    test(
      'two entries with one name — a library that keeps the first would hide it',
      () {
        final zip = rawZip([
          RawEntry('submission.md', utf8.encode(filled)),
          RawEntry('submission.md', utf8.encode('een andere inhoud')),
          RawEntry('manifest.json', utf8.encode('{}')),
        ]);
        expect(refusal(zip), [FormPackageIssue.duplicateEntry]);
      },
    );

    test('a symbolic link, an encrypted entry, an unknown compression', () {
      final link = rawZip([
        RawEntry(
          'images/a-1.jpg',
          utf8.encode('../../etc/passwd'),
          method: 0,
          madeBy: 3 << 8,
          externalAttributes: 0xA1FF << 16,
        ),
      ]);
      expect(refusal(link), [FormPackageIssue.badEntry]);
      expect(
        refusal(
          rawZip([
            RawEntry('submission.md', [1], flags: 1),
          ]),
        ),
        [FormPackageIssue.badEntry],
      );
      expect(
        refusal(
          rawZip([
            RawEntry('submission.md', [1], method: 99),
          ]),
        ),
        [FormPackageIssue.badEntry],
      );
    });

    test('a regular file made on Unix is not mistaken for a link', () {
      final manifest = manifestOf(build());
      final zip = rawZip([
        RawEntry(
          'submission.md',
          utf8.encode(filled),
          madeBy: 3 << 8,
          externalAttributes: 0x81A4 << 16,
        ),
        RawEntry('manifest.json', utf8.encode(jsonEncode(manifest))),
        RawEntry('images/foto-1.jpg', photo, method: 0),
      ]);
      opened(zip);
    });

    test('a local header that names another file than the directory does', () {
      final zip = rawZip([
        RawEntry(
          'submission.md',
          utf8.encode(filled),
          localName: 'manifest.json',
        ),
      ]);
      expect(refusal(zip), [FormPackageIssue.badEntry]);
    });

    test('entries that share bytes are refused', () {
      // B's local header and data sit inside A's stored data: one byte range read
      // as two files.
      const inner = 'images/a-1.jpg';
      final innerData = utf8.encode('verstopt');
      final nested = storedLocal(inner, innerData);
      const outer = 'submission.md';
      final outerLocal = storedLocal(outer, nested);
      final nestedOffset = outerLocal.length - nested.length;
      final central = [
        ...storedCentral(outer, nested, 0),
        ...storedCentral(inner, innerData, nestedOffset),
      ];
      final zip = Uint8List.fromList([
        ...outerLocal,
        ...central,
        ...endRecord(2, central.length, outerLocal.length),
      ]);
      expect(refusal(zip), [FormPackageIssue.overlappingEntries]);
    });

    test('an entry that points past the end of the zip', () {
      final good = build();
      // Make the first central record claim a compressed size beyond the file.
      final bytes = Uint8List.fromList(good);
      final cdOffset = ByteData.sublistView(
        bytes,
      ).getUint32(bytes.length - 22 + 16, Endian.little);
      ByteData.sublistView(
        bytes,
      ).setUint32(cdOffset + 20, 0x00FFFFFF, Endian.little);
      expect(refusal(bytes), [FormPackageIssue.overlappingEntries]);
    });

    test('a header that claims a size the data does not have', () {
      final manifest = manifestOf(build());
      final zip = rawZip([
        RawEntry('submission.md', utf8.encode(filled), claimedSize: 10),
        RawEntry('manifest.json', utf8.encode(jsonEncode(manifest))),
      ]);
      expect(refusal(zip), [FormPackageIssue.corruptEntry]);
    });

    test(
      'a bomb: a few bytes of deflate under a small claim never inflate past the claim',
      () {
        final bomb = deflateRaw(Uint8List(60 * 1024 * 1024));
        expect(bomb.length, lessThan(100 * 1024));
        final zip = rawZip([
          RawEntry(
            'submission.md',
            const [],
            rawCompressed: bomb,
            claimedSize: 1000,
            crc: 0,
          ),
        ]);
        final watch = Stopwatch()..start();
        expect(refusal(zip), [FormPackageIssue.corruptEntry]);
        // It stopped at the claim instead of producing 60 MB.
        expect(watch.elapsedMilliseconds, lessThan(5000));
      },
    );

    test('a stream one byte longer than its claim is stopped at the claim', () {
      final data = utf8.encode(filled);
      final zip = rawZip([
        RawEntry(
          'submission.md',
          const [],
          rawCompressed: deflateRaw([...data, 0x20]),
          claimedSize: data.length,
          crc: getCrc32(data),
        ),
      ]);
      final result = readFormPackage(zip) as FormPackageRefused;
      expect(result.problems.single.issue, FormPackageIssue.corruptEntry);
      expect(result.problems.single.detail, 'inflates past its size');
    });

    test('a bomb that claims the truth is stopped by the limits instead', () {
      final data = Uint8List(10 * 1024 * 1024);
      final zip = rawZip([RawEntry('submission.md', data)]);
      expect(
        refusal(
          zip,
          limits: const FormPackageLimits(maxTextBytes: 1024 * 1024),
        ),
        [FormPackageIssue.tooLarge],
      );
    });

    test('a wrong checksum', () {
      final zip = rawZip([
        RawEntry('submission.md', utf8.encode(filled), crc: 12345),
      ]);
      expect(refusal(zip), [FormPackageIssue.corruptEntry]);
    });

    test('a stored entry whose compressed size differs from its size', () {
      final zip = rawZip([
        RawEntry(
          'submission.md',
          utf8.encode(filled),
          method: 0,
          claimedSize: utf8.encode(filled).length + 5,
        ),
      ]);
      expect(refusal(zip), [FormPackageIssue.corruptEntry]);
    });

    test('a deflate stream that is garbage', () {
      final zip = rawZip([
        RawEntry(
          'submission.md',
          List.filled(40, 7),
          rawCompressed: List.filled(20, 0xFF),
        ),
      ]);
      expect(refusal(zip), [FormPackageIssue.corruptEntry]);
    });

    test('no submission, no manifest', () {
      final manifest = manifestOf(build());
      expect(
        refusal(
          rawZip([
            RawEntry('manifest.json', utf8.encode(jsonEncode(manifest))),
          ]),
        ),
        [FormPackageIssue.missingSubmission],
      );
      expect(
        refusal(rawZip([RawEntry('submission.md', utf8.encode(filled))])),
        [FormPackageIssue.missingManifest],
      );
    });

    test('a submission that is not UTF-8', () {
      final good = build();
      final manifest = manifestOf(good);
      final bad = Uint8List.fromList([0xFF, 0xFE, 0xFD]);
      (manifest['files'] as List)[0] = {
        'path': 'submission.md',
        'sha256': sha256Hex(bad),
        'bytes': 3,
      };
      (manifest['files'] as List).removeLast();
      final zip = rawZip([
        RawEntry('submission.md', bad),
        RawEntry('manifest.json', utf8.encode(jsonEncode(manifest))),
      ]);
      expect(refusal(zip), [FormPackageIssue.corruptEntry]);
    });
  });

  group('readFormPackage — the edges', () {
    test('a record count that is not the count on disk', () {
      final manifest = manifestOf(build());
      final entries = [
        RawEntry('submission.md', utf8.encode(filled)),
        RawEntry('manifest.json', utf8.encode(jsonEncode(manifest))),
      ];
      // The end record says 3 entries on this disk and 2 in total.
      final zip = Uint8List.fromList(rawZip(entries));
      final eocd = zip.length - 22;
      ByteData.sublistView(zip).setUint16(eocd + 8, 3, Endian.little);
      expect(refusal(zip), [FormPackageIssue.badZip]);
    });

    test('strong encryption is refused as well as plain encryption', () {
      expect(
        refusal(
          rawZip([
            RawEntry('submission.md', [1], flags: 0x40),
          ]),
        ),
        [FormPackageIssue.badEntry],
      );
    });

    test('an entry that runs past the end of its own data region', () {
      // The last entry of the file claims more compressed bytes than are left
      // before the directory: no later entry gets in the way, so only the check
      // against the directory itself catches it.
      final manifest = manifestOf(build());
      final zip = Uint8List.fromList(
        rawZip([
          RawEntry('submission.md', utf8.encode(filled)),
          RawEntry('manifest.json', utf8.encode(jsonEncode(manifest))),
          RawEntry('images/foto-1.jpg', photo, method: 0),
        ]),
      );
      final data = ByteData.sublistView(zip);
      final cdOffset = data.getUint32(zip.length - 22 + 16, Endian.little);
      var at = cdOffset;
      for (var i = 0; i < 2; i++) {
        at += 46 + data.getUint16(at + 28, Endian.little);
      }
      data.setUint32(
        at + 20,
        data.getUint32(at + 20, Endian.little) + 4,
        Endian.little,
      );
      expect(refusal(zip), [FormPackageIssue.overlappingEntries]);
    });

    test(
      'entries that share a single byte are refused, entries that touch are not',
      () {
        const inner = 'images/a-1.jpg';
        final innerData = [9, 8, 7];
        final innerHeader = storedLocal(
          inner,
          innerData,
        ).sublist(0, storedLocal(inner, innerData).length - innerData.length);
        const outer = 'submission.md';
        // A's data: five padding bytes, B's local header, then B's first data byte.
        final outerData = [1, 2, 3, 4, 5, ...innerHeader, innerData.first];
        final outerLocal = storedLocal(outer, outerData);
        final innerOffset = outerLocal.length - outerData.length + 5;
        final central = [
          ...storedCentral(outer, outerData, 0),
          ...storedCentral(inner, innerData, innerOffset),
        ];
        final body = [...outerLocal, ...innerData.sublist(1)];
        final zip = Uint8List.fromList([
          ...body,
          ...central,
          ...endRecord(2, central.length, body.length),
        ]);
        expect(refusal(zip), [FormPackageIssue.overlappingEntries]);

        // The same two entries laid end to end: nothing shared, nothing refused for it.
        final apart = rawZip([
          RawEntry(outer, outerData, method: 0),
          RawEntry(inner, innerData, method: 0),
        ]);
        final result = readFormPackage(apart);
        expect(
          result is FormPackageRefused &&
              result.problems.any(
                (p) => p.issue == FormPackageIssue.overlappingEntries,
              ),
          isFalse,
        );
      },
    );

    test(
      'a deflate stream that is shorter than its header says, with the right checksum',
      () {
        final short = utf8.encode('kort');
        final zip = rawZip([
          RawEntry('submission.md', short, claimedSize: 1000),
        ]);
        expect(refusal(zip), [FormPackageIssue.corruptEntry]);
      },
    );

    test(
      'the limits are inclusive: exactly at a limit opens, one over is refused',
      () {
        final good = build();
        final manifest = manifestOf(good);
        final sizes = [
          for (final f in (manifest['files'] as List))
            (f as Map)['bytes'] as int,
        ];
        final manifestBytes = utf8
            .encode(const JsonEncoder.withIndent('  ').convert(manifest))
            .length;
        final submissionLength = sizes.first;
        final photoLength = photo.length;
        // The image: exactly its size opens, one less is too large.
        opened(good, limits: FormPackageLimits(maxImageBytes: photoLength));
        expect(
          refusal(
            good,
            limits: FormPackageLimits(maxImageBytes: photoLength - 1),
          ),
          [FormPackageIssue.tooLarge],
        );
        // The text entries: the larger of the two.
        final text = submissionLength > manifestBytes
            ? submissionLength
            : manifestBytes;
        opened(good, limits: FormPackageLimits(maxTextBytes: text));
        expect(
          refusal(good, limits: FormPackageLimits(maxTextBytes: text - 1)),
          [FormPackageIssue.tooLarge],
        );
        // The sum.
        final total = submissionLength + manifestBytes + photoLength;
        opened(good, limits: FormPackageLimits(maxExtractedBytes: total));
        expect(
          refusal(
            good,
            limits: FormPackageLimits(maxExtractedBytes: total - 1),
          ),
          [FormPackageIssue.tooLarge],
        );
        // The package itself and the number of files.
        opened(good, limits: FormPackageLimits(maxPackageBytes: good.length));
        opened(good, limits: const FormPackageLimits(maxFiles: 3));
        expect(refusal(good, limits: const FormPackageLimits(maxFiles: 2)), [
          FormPackageIssue.tooManyFiles,
        ]);
      },
    );

    test('a photo is stored, not deflated again', () {
      final zip = ZipDecoder().decodeBytes(build());
      final entry = zip.files.firstWhere((f) => f.name == 'images/foto-1.jpg');
      expect(entry.compression, CompressionType.none);
    });
  });

  group('readFormPackage — what is received is kept as received', () {
    test('the manifest and the submission come back byte for byte', () {
      final zip = build();
      final read = opened(zip);
      final archive = ZipDecoder().decodeBytes(zip);
      expect(read.manifestBytes, archive.findFile('manifest.json')!.content);
      expect(read.submissionBytes, utf8.encode(filled));
    });

    test('a byte order mark is not dropped from the bytes', () {
      final read = opened(build(submission: '\u{FEFF}$filled'));
      expect(read.submissionBytes.sublist(0, 3), [0xEF, 0xBB, 0xBF]);
    });
  });

  group('readFormManifest', () {
    test('reads the manifest of a package on its own', () {
      final read = opened(build());
      final manifest = readFormManifest(read.manifestBytes)!;
      expect(manifest.submissionId, sid);
      expect(manifest.formId, 'kookboek');
      expect(manifest.templateSha256, read.manifest.templateSha256);
      expect(manifest.files.map((f) => f.path), contains('submission.md'));
    });

    test(
      'is null for what is not a manifest of this version, never a throw',
      () {
        expect(readFormManifest(Uint8List(0)), isNull);
        expect(readFormManifest(Uint8List.fromList(utf8.encode('{}'))), isNull);
        expect(
          readFormManifest(Uint8List.fromList(utf8.encode('[1]'))),
          isNull,
        );
        expect(readFormManifest(Uint8List.fromList([0xFF, 0xFE])), isNull);
        final other = jsonEncode({...manifestOf(build()), 'v': 2});
        expect(
          readFormManifest(Uint8List.fromList(utf8.encode(other))),
          isNull,
        );
      },
    );
  });

  group('readFormPackage — the manifest', () {
    late Map<String, Object?> good;
    late List<RawEntry> photoEntry;
    setUp(() {
      good = manifestOf(build());
      photoEntry = [RawEntry('images/foto-1.jpg', photo, method: 0)];
    });

    List<FormPackageIssue> with_(void Function(Map<String, Object?> m) edit) {
      final copy = jsonDecode(jsonEncode(good)) as Map<String, Object?>;
      edit(copy);
      return refusal(packageWith(copy, more: photoEntry));
    }

    test('the good one opens', () {
      opened(packageWith(good, more: photoEntry));
    });

    test('not JSON, not an object, the wrong version', () {
      expect(
        refusal(
          rawZip([
            RawEntry('submission.md', utf8.encode(filled)),
            RawEntry('manifest.json', utf8.encode('{niet json')),
            ...photoEntry,
          ]),
        ),
        [FormPackageIssue.badManifest],
      );
      expect(
        refusal(
          rawZip([
            RawEntry('submission.md', utf8.encode(filled)),
            RawEntry('manifest.json', utf8.encode('[1,2]')),
            ...photoEntry,
          ]),
        ),
        [FormPackageIssue.badManifest],
      );
      expect(with_((m) => m['v'] = 2), [FormPackageIssue.badManifest]);
      expect(with_((m) => m.remove('v')), [FormPackageIssue.badManifest]);
    });

    test('a submission id outside the grammar', () {
      for (final bad in ['', 'ABC', 'a' * 25, 'a' * 27, 5]) {
        expect(with_((m) => m['submission_id'] = bad), [
          FormPackageIssue.badManifest,
        ], reason: '$bad');
      }
    });

    test('a field of the wrong type or shape', () {
      expect(with_((m) => m['created'] = '4 oktober'), [
        FormPackageIssue.badManifest,
      ]);
      expect(with_((m) => m['form'] = 'x'), [FormPackageIssue.badManifest]);
      expect(with_((m) => (m['form'] as Map)['template_sha256'] = 'abc'), [
        FormPackageIssue.badManifest,
      ]);
      expect(with_((m) => (m['form'] as Map)['version'] = '2'), [
        FormPackageIssue.badManifest,
      ]);
      expect(with_((m) => (m['client'] as Map)['rules'] = null), [
        FormPackageIssue.badManifest,
      ]);
      expect(with_((m) => (m['client'] as Map)['version'] = 3), [
        FormPackageIssue.badManifest,
      ]);
      expect(with_((m) => m['files'] = 'x'), [FormPackageIssue.badManifest]);
      expect(with_((m) => m['consent'] = null), [FormPackageIssue.badManifest]);
      expect(with_((m) => (m['files'] as List)[0] = 'x'), [
        FormPackageIssue.badManifest,
      ]);
      expect(with_((m) => ((m['files'] as List)[0] as Map)['sha256'] = 'zz'), [
        FormPackageIssue.badManifest,
      ]);
      expect(
        with_(
          (m) => ((m['consent'] as List)[0] as Map)['accepted'] = 'gisteren',
        ),
        [FormPackageIssue.badManifest],
      );
      expect(
        with_(
          (m) => ((m['consent'] as List)[0] as Map)['text_sha256'] = 'nope',
        ),
        [FormPackageIssue.badManifest],
      );
    });

    test('a hash or a size that is not what the package holds', () {
      expect(
        with_((m) => ((m['files'] as List)[1] as Map)['sha256'] = '0' * 64),
        [FormPackageIssue.hashMismatch],
      );
      expect(with_((m) => ((m['files'] as List)[1] as Map)['bytes'] = 1), [
        FormPackageIssue.hashMismatch,
      ]);
    });

    test(
      'a file the package has and the manifest does not list, and the reverse',
      () {
        expect(with_((m) => (m['files'] as List).removeLast()), [
          FormPackageIssue.fileNotListed,
        ]);
        expect(refusal(packageWith(good)), [
          FormPackageIssue.fileMissing,
        ], reason: 'the photo is listed but not in the zip');
        expect(with_((m) => (m['files'] as List).removeAt(0)), [
          FormPackageIssue.fileNotListed,
        ], reason: 'the submission is in the zip but not listed');
      },
    );

    test('a file listed twice, and the manifest listing itself', () {
      expect(with_((m) => (m['files'] as List).add((m['files'] as List)[1])), [
        FormPackageIssue.badManifest,
      ]);
      expect(
        with_(
          (m) => (m['files'] as List).add({
            'path': 'manifest.json',
            'sha256': '0' * 64,
            'bytes': 1,
          }),
        ),
        [FormPackageIssue.fileMissing],
      );
    });

    test('a manifest can also say nothing about consent', () {
      final copy = jsonDecode(jsonEncode(good)) as Map<String, Object?>;
      copy['consent'] = [];
      expect(
        opened(packageWith(copy, more: photoEntry)).manifest.consent,
        isEmpty,
      );
    });
  });

  group('robustness', () {
    test('never throws, whatever is cut off or flipped', () {
      final random = Random(20261004);
      final good = build();
      for (var n = 0; n < good.length; n += 7) {
        readFormPackage(Uint8List.sublistView(good, 0, n));
      }
      for (var round = 0; round < 600; round++) {
        final copy = Uint8List.fromList(good);
        for (var k = 0; k <= random.nextInt(3); k++) {
          copy[random.nextInt(copy.length)] = random.nextInt(256);
        }
        final result = readFormPackage(copy);
        if (result is FormPackageOpened) {
          // Whatever opens is consistent: what the manifest lists is what is there.
          expect(result.manifest.files.map((f) => f.path).toSet(), {
            'submission.md',
            ...result.images.keys,
          });
        }
      }
    });
  });

  group('FormPackageIssue and FormPackageProblem', () {
    test('wire names are unique, kebab-case and stable', () {
      final names = FormPackageIssue.values.map((i) => i.wireName).toList();
      expect(names.toSet(), hasLength(names.length));
      for (final name in names) {
        expect(name, matches(RegExp(r'^[a-z]+(-[a-z]+)*$')));
      }
      expect(FormPackageIssue.badZip.wireName, 'bad-zip');
      expect(FormPackageIssue.hashMismatch.wireName, 'hash-mismatch');
    });

    test('toString names the issue, the entry and the reason', () {
      expect(
        const FormPackageProblem(
          FormPackageIssue.badEntry,
          path: 'x',
          detail: 'symlink',
        ).toString(),
        'bad-entry [x]: symlink',
      );
      expect(
        const FormPackageProblem(FormPackageIssue.badZip).toString(),
        'bad-zip',
      );
    });
  });
}
