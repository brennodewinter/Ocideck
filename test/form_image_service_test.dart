// De foto's van een formulier (FORM_INTAKE.md §5.5): wat er tussen kiezen en in het
// antwoord komen gebeurt — zuiveren, écht decoderen, opslaan onder een naam zonder
// persoonsgegevens — en wat de pagina van de foto's in een document weet.

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:ocideck/services/form/form_image_service.dart';
import 'package:ocideck_form_core/ocideck_form_core.dart';
import 'package:path/path.dart' as p;

List<int> u16(int v) => [(v >> 8) & 0xFF, v & 0xFF];
List<int> u32(int v) => [
  (v >> 24) & 0xFF,
  (v >> 16) & 0xFF,
  (v >> 8) & 0xFF,
  v & 0xFF,
];

/// Een TIFF met een draairichting en een verwijzing naar een GPS-blok.
List<int> tiff({int? orientation, bool gps = false}) {
  final entries = <List<int>>[
    if (orientation != null)
      [...u16(0x0112), ...u16(3), ...u32(1), ...u16(orientation), 0, 0],
    if (gps) [...u16(0x8825), ...u16(4), ...u32(1), ...u32(0x40)],
  ];
  return [
    ...'MM'.codeUnits,
    ...u16(42),
    ...u32(8),
    ...u16(entries.length),
    for (final e in entries) ...e,
    ...u32(0),
  ];
}

/// Een echte JPEG, met een EXIF-segment direct na het SOI.
Uint8List photo({
  int width = 40,
  int height = 20,
  List<int>? exif,
  List<int> trailer = const [],
}) {
  final image = img.Image(width: width, height: height);
  img.fill(image, color: img.ColorRgb8(200, 100, 50));
  final jpg = img.encodeJpg(image, quality: 90);
  final withExif = exif == null
      ? jpg
      : Uint8List.fromList([
          ...jpg.sublist(0, 2),
          0xFF,
          0xE1,
          ...u16(exif.length + 8),
          ...'Exif'.codeUnits,
          0,
          0,
          ...exif,
          ...jpg.sublist(2),
        ]);
  return Uint8List.fromList([...withExif, ...trailer]);
}

int crc32(List<int> data) {
  var c = 0xFFFFFFFF;
  for (final b in data) {
    c ^= b;
    for (var k = 0; k < 8; k++) {
      c = (c & 1) != 0 ? 0xEDB88320 ^ (c >> 1) : c >> 1;
    }
  }
  return c ^ 0xFFFFFFFF;
}

List<int> chunk(String type, List<int> body) {
  final typed = [...type.codeUnits, ...body];
  return [...u32(body.length), ...typed, ...u32(crc32(typed))];
}

/// Een PNG met een geldige opbouw en een gelogen kop: hij beweert [width]×[height]
/// en heeft geen beeldgegevens.
Uint8List claimedPng(int width, int height) => Uint8List.fromList([
  0x89,
  0x50,
  0x4E,
  0x47,
  0x0D,
  0x0A,
  0x1A,
  0x0A,
  ...chunk('IHDR', [...u32(width), ...u32(height), 8, 2, 0, 0, 0]),
  ...chunk('IDAT', [1, 2, 3]),
  ...chunk('IEND', []),
]);

Uint8List heic() => Uint8List.fromList([
  ...u32(24),
  ...'ftyp'.codeUnits,
  ...'heic'.codeUnits,
  ...u32(0),
  ...'mif1'.codeUnits,
  ...'heic'.codeUnits,
  1,
  2,
  3,
  4,
]);

void main() {
  late Directory dir;
  setUp(() async {
    dir = await Directory.systemTemp.createTemp('ocideck_formimg_');
  });
  tearDown(() async {
    if (await dir.exists()) await dir.delete(recursive: true);
  });

  group('intakeFormImage', () {
    test(
      'een foto met een positie komt schoon door en meldt wat eruit ging',
      () async {
        final result = await intakeFormImage(
          photo(exif: tiff(orientation: 1, gps: true)),
        );
        final intake = (result as FormImageAccepted).intake;
        expect(intake.report.removed.gps, isTrue);
        expect(intake.report.removed.exif, isTrue);
        expect(intake.fact.format, 'jpg');
        expect(intake.fact.displayedWidth, 40);
        expect(intake.fact.unverified, isFalse);
        // Wat er bewaard wordt heeft niets meer te verwijderen.
        expect(cleanImage(intake.report.bytes)!.removed.any, isFalse);
      },
    );

    test(
      'een gedraaide foto telt zijn getoonde breedte, en de decoder is het eens',
      () async {
        final result = await intakeFormImage(
          photo(width: 40, height: 20, exif: tiff(orientation: 6)),
        );
        final intake = (result as FormImageAccepted).intake;
        expect(intake.report.width, 40);
        expect(intake.fact.displayedWidth, 20);
      },
    );

    test('alles na het beeld gaat eruit', () async {
      final result = await intakeFormImage(
        photo(trailer: 'PK een zip achter de foto'.codeUnits),
      );
      final intake = (result as FormImageAccepted).intake;
      expect(
        intake.report.removed.trailerBytes,
        'PK een zip achter de foto'.length,
      );
      expect(intake.report.bytes.length, lessThan(photo().length + 1));
    });

    test('een PNG komt door met zijn bestandstype', () async {
      final image = img.Image(width: 8, height: 6);
      final result = await intakeFormImage(img.encodePng(image));
      expect((result as FormImageAccepted).intake.fact.format, 'png');
    });

    test(
      'een PNG met een draairichting komt door, ook al zet de decoder hem niet recht',
      () async {
        final base = img.encodePng(img.Image(width: 8, height: 4));
        final exif = chunk('eXIf', tiff(orientation: 6));
        final file = Uint8List.fromList([
          ...base.sublist(0, 33),
          ...exif,
          ...base.sublist(33),
        ]);
        final intake =
            (await intakeFormImage(file) as FormImageAccepted).intake;
        expect(intake.fact.displayedWidth, 4);
        expect(intake.report.orientation, 6);
      },
    );

    test('een WebP komt door', () async {
      // 1×1, verliesloos.
      final webp = base64Decode(
        'UklGRhoAAABXRUJQVlA4TA0AAAAvAAAAEAcQERGIiP4HAA==',
      );
      final result = await intakeFormImage(Uint8List.fromList(webp));
      expect(result, isA<FormImageAccepted>());
      expect((result as FormImageAccepted).intake.fact.format, 'webp');
    });

    test(
      'een HEIC blijft zoals hij is en heet niet gecontroleerd (D4)',
      () async {
        final file = heic();
        final intake =
            (await intakeFormImage(file) as FormImageAccepted).intake;
        expect(intake.report.bytes, file);
        expect(intake.fact.unverified, isTrue);
        expect(intake.fact.displayedWidth, isNull);
        expect(intake.fact.format, 'heic');
      },
    );

    test('tekst, een script en een leeg bestand zijn geen foto', () async {
      for (final bytes in [
        Uint8List(0),
        Uint8List.fromList('<script>alert(1)</script>'.codeUnits),
        Uint8List.fromList('gewoon woorden'.codeUnits),
      ]) {
        final result = await intakeFormImage(bytes);
        expect(
          (result as FormImageRejected).reason,
          FormImageRefusal.notAPhoto,
        );
      }
    });

    test('een afgebroken foto is geen foto', () async {
      final whole = photo();
      final cut = Uint8List.sublistView(whole, 0, whole.length ~/ 2);
      final result = await intakeFormImage(cut);
      expect((result as FormImageRejected).reason, FormImageRefusal.notAPhoto);
    });

    test(
      'een kop die 20000 × 20000 beeldpunten claimt wordt niet gedecodeerd',
      () async {
        final result = await intakeFormImage(claimedPng(20000, 20000));
        expect((result as FormImageRejected).reason, FormImageRefusal.tooLarge);
      },
    );

    test('een geldige kop zonder beeld is onleesbaar, niet geslaagd', () async {
      // Een polyglot-achtig bestand: de opbouw klopt, de beeldgegevens niet.
      final result = await intakeFormImage(claimedPng(30, 30));
      expect((result as FormImageRejected).reason, FormImageRefusal.unreadable);
    });

    test(
      'meer bytes dan het plafond is te groot, zonder te lezen wat erin zit',
      () async {
        final big = Uint8List(kFormMaxImageBytes + 1);
        big[0] = 0xFF;
        big[1] = 0xD8;
        big[2] = 0xFF;
        final result = await intakeFormImage(big);
        expect((result as FormImageRejected).reason, FormImageRefusal.tooLarge);
      },
    );
  });

  group('storeFormImage', () {
    Future<FormImageIntake> intake() async =>
        (await intakeFormImage(photo()) as FormImageAccepted).intake;

    test(
      'zet de foto in images/ onder veld en nummer, nooit onder zijn eigen naam',
      () async {
        final saved = await storeFormImage(
          projectPath: dir.path,
          fieldId: 'foto',
          intake: await intake(),
        );
        expect(saved!.path, 'images/foto-1.jpg');
        final stored = File(p.join(dir.path, 'images', 'foto-1.jpg'));
        expect(stored.existsSync(), isTrue);
        final schoon = await intake();
        expect(
          stored.readAsBytesSync(),
          schoon.report.bytes,
          reason: 'het schone bestand, niet het gekozen',
        );
      },
    );

    test('neemt het eerste vrije nummer en overschrijft niets', () async {
      final first = await storeFormImage(
        projectPath: dir.path,
        fieldId: 'foto',
        intake: await intake(),
      );
      final second = await storeFormImage(
        projectPath: dir.path,
        fieldId: 'foto',
        intake: await intake(),
      );
      expect(first!.path, 'images/foto-1.jpg');
      expect(second!.path, 'images/foto-2.jpg');
      final third = await storeFormImage(
        projectPath: dir.path,
        fieldId: 'foto',
        intake: await intake(),
        taken: {'images/foto-3.jpg'},
      );
      expect(
        third!.path,
        'images/foto-4.jpg',
        reason: 'een nummer dat al in het antwoord staat is bezet',
      );
    });

    test('een bestand dat er al staat wordt nooit overschreven', () async {
      await Directory(p.join(dir.path, 'images')).create();
      await File(
        p.join(dir.path, 'images', 'foto-1.jpg'),
      ).writeAsString('van een ander');
      final saved = await storeFormImage(
        projectPath: dir.path,
        fieldId: 'foto',
        intake: await intake(),
      );
      expect(saved!.path, 'images/foto-2.jpg');
      expect(
        File(p.join(dir.path, 'images', 'foto-1.jpg')).readAsStringSync(),
        'van een ander',
      );
    });

    test(
      'een heel lang veld-id blijft binnen de 64 tekens van de naamgrammatica',
      () async {
        final saved = await storeFormImage(
          projectPath: dir.path,
          fieldId: 'a' * 80,
          intake: await intake(),
        );
        final name = p.basenameWithoutExtension(saved!.path);
        expect(name.length, lessThanOrEqualTo(64));
        expect(kFormImagePath.hasMatch(saved.path), isTrue);
      },
    );

    test('de extensie komt uit het bestandstype, niet uit een naam', () async {
      final png =
          (await intakeFormImage(img.encodePng(img.Image(width: 4, height: 4)))
                  as FormImageAccepted)
              .intake;
      final saved = await storeFormImage(
        projectPath: dir.path,
        fieldId: 'foto',
        intake: png,
      );
      expect(saved!.path, 'images/foto-1.png');
    });

    test(
      'een projectmap die geen map kan zijn geeft null in plaats van een uitzondering',
      () async {
        final file = File(p.join(dir.path, 'bestand'))..writeAsStringSync('x');
        final saved = await storeFormImage(
          projectPath: file.path,
          fieldId: 'foto',
          intake: await intake(),
        );
        expect(saved, isNull);
      },
    );
  });

  group('addFormImages', () {
    test(
      'verwerkt een keuze: de goede erin, de rest geweigerd, in volgorde',
      () async {
        final batch = await addFormImages(
          projectPath: dir.path,
          fieldId: 'foto',
          readers: [
            () async => photo(exif: tiff(orientation: 1, gps: true)),
            () async => Uint8List.fromList('geen foto'.codeUnits),
            () async => photo(),
            () async => throw const FileSystemException('weg'),
          ],
        );
        expect(batch.stored.map((s) => s.path), [
          'images/foto-1.jpg',
          'images/foto-2.jpg',
        ]);
        expect(batch.refused, [
          FormImageRefusal.notAPhoto,
          FormImageRefusal.notAPhoto,
        ]);
        expect(batch.refs.map((r) => r.path), [
          'images/foto-1.jpg',
          'images/foto-2.jpg',
        ]);
        expect(
          batch.refs.every((r) => r.alt.isEmpty && r.credit == null),
          isTrue,
        );
        expect(batch.facts.keys, ['images/foto-1.jpg', 'images/foto-2.jpg']);
        expect(batch.scrubbedPaths, {'images/foto-1.jpg'});
      },
    );

    test('twee foto in één keuze krijgen twee nummers', () async {
      final batch = await addFormImages(
        projectPath: dir.path,
        fieldId: 'foto',
        readers: [() async => photo(), () async => photo()],
        taken: {'images/foto-1.jpg'},
      );
      expect(batch.stored.map((s) => s.path), [
        'images/foto-2.jpg',
        'images/foto-3.jpg',
      ]);
    });

    test('een onschrijfbare map is een geweigerde foto, geen crash', () async {
      final file = File(p.join(dir.path, 'bestand'))..writeAsStringSync('x');
      final batch = await addFormImages(
        projectPath: file.path,
        fieldId: 'foto',
        readers: [() async => photo()],
      );
      expect(batch.stored, isEmpty);
      expect(batch.refused, [FormImageRefusal.writeFailed]);
    });
  });

  group('probeFormImages', () {
    test('meet wat er staat: type, breedte zoals getoond, bytes', () async {
      await Directory(p.join(dir.path, 'images')).create();
      final file = photo(width: 40, height: 20, exif: tiff(orientation: 6));
      await File(p.join(dir.path, 'images', 'a-1.jpg')).writeAsBytes(file);
      final facts = await probeFormImages([
        'images/a-1.jpg',
      ], projectPath: dir.path);
      final fact = facts['images/a-1.jpg']!;
      expect(fact.exists, isTrue);
      expect(fact.format, 'jpg');
      expect(fact.displayedWidth, 20);
      expect(fact.bytes, file.length);
      expect(fact.unverified, isFalse);
    });

    test('een ontbrekend bestand bestaat niet', () async {
      final facts = await probeFormImages([
        'images/weg-1.jpg',
      ], projectPath: dir.path);
      expect(facts['images/weg-1.jpg']!.exists, isFalse);
    });

    test('een pad buiten de map van het document wordt niet gelezen', () async {
      await File(p.join(dir.parent.path, 'buiten.jpg')).writeAsBytes(photo());
      addTearDown(
        () => File(p.join(dir.parent.path, 'buiten.jpg')).deleteSync(),
      );
      final facts = await probeFormImages([
        '../buiten.jpg',
      ], projectPath: dir.path);
      expect(facts['../buiten.jpg']!.exists, isFalse);
    });

    test(
      'een bestand boven het plafond wordt niet gelezen en heet niet gecontroleerd',
      () async {
        await Directory(p.join(dir.path, 'images')).create();
        final big = File(p.join(dir.path, 'images', 'groot-1.jpg'));
        final raf = await big.open(mode: FileMode.write);
        await raf.truncate(
          kFormMaxImageBytes + 1,
        ); // een gat: geen 64 MB schrijven
        await raf.close();
        final facts = await probeFormImages([
          'images/groot-1.jpg',
        ], projectPath: dir.path);
        expect(facts['images/groot-1.jpg']!.unverified, isTrue);
        expect(facts['images/groot-1.jpg']!.bytes, kFormMaxImageBytes + 1);
      },
    );

    test(
      'een HEIC is niet gecontroleerd; iets dat geen foto is heeft een onbekend type',
      () async {
        await Directory(p.join(dir.path, 'images')).create();
        await File(p.join(dir.path, 'images', 'h-1.heic')).writeAsBytes(heic());
        await File(
          p.join(dir.path, 'images', 'x-1.jpg'),
        ).writeAsString('geen foto');
        final facts = await probeFormImages([
          'images/h-1.heic',
          'images/x-1.jpg',
        ], projectPath: dir.path);
        expect(facts['images/h-1.heic']!.unverified, isTrue);
        expect(facts['images/h-1.heic']!.format, 'heic');
        expect(facts['images/x-1.jpg']!.format, 'unknown');
        expect(facts['images/x-1.jpg']!.exists, isTrue);
      },
    );

    test(
      'de feiten laten de validator een foto van 1600 breed een waarschuwing geven',
      () async {
        await Directory(p.join(dir.path, 'images')).create();
        await File(
          p.join(dir.path, 'images', 'f-1.jpg'),
        ).writeAsBytes(photo(width: 40, height: 20));
        final facts = await probeFormImages([
          'images/f-1.jpg',
        ], projectPath: dir.path);
        const doc =
            '<!-- form id=f -->\n'
            '<!-- field id=f type=image min-width=2000 -->\nL\n<!-- answer -->\n'
            '![x](images/f-1.jpg)\n'
            '<!-- /field id=f -->\n';
        final fill =
            (FormFill.open(doc, imageFacts: facts) as FormFillReady).fill;
        expect(fill.problemsOf('f').map((p) => p.code), [
          FormIssueCode.imageTooSmall,
        ]);
      },
    );
  });
}
