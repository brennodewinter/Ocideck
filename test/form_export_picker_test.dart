// De bestandskiezer, het opslagvenster en de map van het document als wat de
// invulpagina voor het opslaan van een inzending nodig heeft (FormExportSupport).

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/services/download_delivery.dart';
import 'package:ocideck/widgets/forms/form_export_picker.dart';
import 'package:ocideck/widgets/forms/form_export_support.dart';
import 'package:ocideck/widgets/forms/form_text_helpers.dart';
import 'package:ocideck_form_core/ocideck_form_core.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

import 'support/form_photo_fixtures.dart';

FormSpec specOf(String id, int version) =>
    ((parseForm('<!-- form id=$id version=$version -->\n') as ParsedForm).spec);

void main() {
  late Directory dir;
  setUp(() async {
    dir = await Directory.systemTemp.createTemp('ocideck_formexport_');
    debugClearPublishedForms();
  });
  tearDown(() async {
    debugDeliversByDownload = null;
    debugDownloadSink = null;
    if (await dir.exists()) await dir.delete(recursive: true);
  });

  FormExportSupport support({
    String? projectPath,
    Future<String?> Function(String)? pick,
    FormExportDestination? destination,
    String? bundleTitle,
    Future<String?> Function(String)? pickBundle,
  }) => formExportSupportFor(
    projectPath: projectPath,
    frontMatter: '---\na: b\n---\n',
    pickTitle: 'Kies het formulier',
    saveTitle: 'Opslaan',
    bundleTitle: bundleTitle,
    pick: pick,
    pickBundle: pickBundle,
    destination: destination,
  );

  test('de front matter en de versie van OciDeck gaan mee', () {
    final s = support();
    expect(s.frontMatter, '---\na: b\n---\n');
    expect(s.clientVersion, matches(RegExp(r'^\d+\.\d+\.\d+')));
  });

  group('foto\'s lezen', () {
    test('een foto in de map van het document wordt gelezen', () async {
      final photo = jpegPhoto();
      await Directory(p.join(dir.path, 'images')).create();
      await File(p.join(dir.path, 'images', 'foto-1.jpg')).writeAsBytes(photo);
      final read = await support(
        projectPath: dir.path,
      ).readImage('images/foto-1.jpg');
      expect(read, photo);
    });

    test(
      'een foto die er niet is, of buiten de map ligt, wordt niet gelezen',
      () async {
        final s = support(projectPath: dir.path);
        expect(await s.readImage('images/weg.jpg'), isNull);
        expect(await s.readImage('../buiten.jpg'), isNull);
        expect(await s.readImage('/etc/hosts'), isNull);
      },
    );

    test('zonder map is er niets te lezen', () async {
      expect(await support().readImage('images/foto-1.jpg'), isNull);
    });
  });

  group('het gepubliceerde formulier', () {
    test('wordt per formulier en versie onthouden', () {
      final s = support();
      expect(s.recall(specOf('kook', 1)), isNull);
      s.remember(specOf('kook', 1), 'een');
      s.remember(specOf('kook', 2), 'twee');
      s.remember(specOf('ander', 1), 'drie');
      expect(s.recall(specOf('kook', 1)), 'een');
      expect(s.recall(specOf('kook', 2)), 'twee');
      expect(s.recall(specOf('ander', 1)), 'drie');
      expect(s.recall(specOf('kook', 3)), isNull);
    });

    test(
      'blijft onthouden over twee ondersteuningen heen (twee tabbladen)',
      () {
        support().remember(specOf('kook', 1), 'een');
        expect(support().recall(specOf('kook', 1)), 'een');
      },
    );

    test(
      'het gekozen bestand komt als tekst terug, met de kiezer als naad',
      () async {
        String? title;
        final text = await support(
          pick: (t) async {
            title = t;
            return 'tekst';
          },
        ).pickPublished();
        expect(text, 'tekst');
        expect(title, 'Kies het formulier');
      },
    );
  });

  group('opslaan', () {
    test('schrijft het pakket waar het opslagvenster naartoe wijst', () async {
      final target = p.join(dir.path, 'uit', 'kook-abc123.zip');
      await Directory(p.dirname(target)).create();
      String? seenTitle;
      String? seenName;
      String? seenDirectory;
      final bytes = Uint8List.fromList([1, 2, 3]);
      final name = await support(
        projectPath: dir.path,
        destination:
            ({
              required dialogTitle,
              required fileName,
              initialDirectory,
            }) async {
              seenTitle = dialogTitle;
              seenName = fileName;
              seenDirectory = initialDirectory;
              return target;
            },
      ).save('kook-abc123.zip', bytes);
      expect(name, 'kook-abc123.zip');
      expect(await File(target).readAsBytes(), bytes);
      expect(seenTitle, 'Opslaan');
      expect(seenName, 'kook-abc123.zip');
      expect(seenDirectory, dir.path);
    });

    test('annuleren schrijft niets en geeft geen naam', () async {
      final name = await support(
        destination:
            ({
              required dialogTitle,
              required fileName,
              initialDirectory,
            }) async => null,
      ).save('kook.zip', Uint8List(1));
      expect(name, isNull);
    });

    test('op het web is het een download', () async {
      debugDeliversByDownload = true;
      String? sentName;
      String? sentMime;
      debugDownloadSink = (name, bytes, mime) {
        sentName = name;
        sentMime = mime;
        return true;
      };
      final name = await support().save('kook.zip', Uint8List.fromList([9]));
      expect(name, 'kook.zip');
      expect(sentName, 'kook.zip');
      expect(sentMime, 'application/zip');
    });

    test('een download die niet wordt aangeboden geeft geen naam', () async {
      debugDeliversByDownload = true;
      debugDownloadSink = (_, _, _) => false;
      expect(await support().save('kook.zip', Uint8List(1)), isNull);
    });
  });

  group('verzegeld opslaan', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    test(
      'zonder titel voor de bundelkiezer is er geen verzegel-ondersteuning',
      () {
        expect(support().seal, isNull);
      },
    );

    test('met een titel is die er, en de kiezer krijgt hem mee', () async {
      String? asked;
      final seal = support(
        bundleTitle: 'Kies de bundel',
        pickBundle: (title) async {
          asked = title;
          return '{}';
        },
      ).seal!;
      expect(await seal.pickBundle(), '{}');
      expect(asked, 'Kies de bundel');
    });

    test('annuleren geeft geen bundel', () async {
      final seal = support(
        bundleTitle: 'Kies de bundel',
        pickBundle: (_) async => null,
      ).seal!;
      expect(await seal.pickBundle(), isNull);
    });

    test('bundel en vingerafdruk worden per formulier en versie onthouden', () {
      final seal = support(bundleTitle: 't').seal!;
      final v1 = specOf('kook', 1);
      final v2 = specOf('kook', 2);
      expect(seal.recall(v1), isNull);
      seal.remember(v1, 'bundel', 'afdruk');
      expect(seal.recall(v1), (bundle: 'bundel', fingerprint: 'afdruk'));
      expect(
        seal.recall(v2),
        isNull,
        reason: 'een andere versie is een ander formulier',
      );
      expect(
        support(bundleTitle: 't').seal!.recall(v1),
        isNotNull,
        reason: 'het geheugen hoort bij de sessie, niet bij één ondersteuning',
      );
      seal.forget(v1);
      expect(seal.recall(v1), isNull);
      seal.remember(v2, 'b2', 'a2');
      debugClearPublishedForms();
      expect(seal.recall(v2), isNull);
    });

    test('de pins blijven staan: schrijven en weer lezen', () async {
      final seal = support(bundleTitle: 't').seal!;
      expect((await seal.readPins()).seqFor('abc', 'fp'), isNull);
      await seal.writePins(FormBundlePins.fromJson({'abc@fp': 7}));
      final back = await seal.readPins();
      expect(back.seqFor('abc', 'fp'), 7);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString(kFormBundlePinsKey), '{"abc@fp":7}');
    });

    test(
      'pins die niet te lezen zijn: een lege lijst, geen uitzondering',
      () async {
        SharedPreferences.setMockInitialValues({
          kFormBundlePinsKey: 'geen json',
        });
        final pins = await support(bundleTitle: 't').seal!.readPins();
        expect(pins.toJson(), isEmpty);
      },
    );
  });

  test('een gekozen bestand is UTF-8 of het is geen formulier', () {
    expect(formTextOf(Uint8List.fromList(utf8.encode('Kook é'))), 'Kook é');
    expect(formTextOf(Uint8List.fromList([0xFF, 0xFE, 0x41])), isNull);
  });
}
