import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';

import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/models/deck.dart';
import 'package:ocideck/models/settings.dart';
import 'package:ocideck/models/slide.dart';
import 'package:ocideck/services/file_service.dart';
import 'package:ocideck/services/image_service.dart';
import 'package:ocideck/services/markdown_service.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory tmp;
  late FileService file;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('ocideck_pkg_test');
    file = FileService(
      MarkdownService(),
      ImageService(),
      () => const ThemeProfile(),
    );
  });

  tearDown(() {
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  test(
    'export then import a package round-trips slides and bundles the image',
    () async {
      // Bron-afbeelding (absoluut pad, zoals net geplakt/gekozen).
      final srcImg = File(p.join(tmp.path, 'pic.png'))
        ..writeAsBytesSync([1, 2, 3, 4]);

      final deck = Deck(
        title: 'Mijn Deck',
        slides: [
          Slide.create(
            SlideType.image,
          ).copyWith(title: 'Foto', imagePath: srcImg.path),
          Slide.create(
            SlideType.bullets,
          ).copyWith(title: 'Punten', bullets: ['een', 'twee']),
        ],
      );

      // Exporteren naar een .ocideck-zip.
      final zipPath = p.join(tmp.path, 'deck.ocideck');
      await file.exportPackage(deck, zipPath);
      expect(File(zipPath).existsSync(), isTrue);

      // Importeren in een verse map.
      final out = Directory(p.join(tmp.path, 'out'))..createSync();
      final bytes = File(zipPath).readAsBytesSync();
      final mdPath = await file.importPackageBytes(bytes, out.path);
      expect(mdPath, isNotNull);
      expect(File(mdPath!).existsSync(), isTrue);

      // Het uitgepakte deck moet identiek zijn en de afbeelding meebrengen.
      final imported = await file.openDeck(mdPath);
      expect(imported, isNotNull);
      expect(imported!.slides, hasLength(2));
      expect(imported.slides[0].type, SlideType.image);
      expect(imported.slides[0].imagePath, 'images/pic.png');
      expect(imported.slides[1].bullets, ['een', 'twee']);

      final extracted = File(
        p.join(imported.projectPath!, 'images', 'pic.png'),
      );
      expect(extracted.existsSync(), isTrue);
      expect(extracted.readAsBytesSync(), [1, 2, 3, 4]);
    },
  );

  test('export then import round-trips user notes sidecar', () async {
    final slide = Slide.create(SlideType.bullets).copyWith(title: 'Een');
    final deck = Deck(
      title: 'Mijn Deck',
      slides: [slide],
      userNotes: {slide.id: 'Cursusnotitie'},
    );

    final zipPath = p.join(tmp.path, 'notes.ocideck');
    await file.exportPackage(deck, zipPath);

    final out = Directory(p.join(tmp.path, 'out_notes'))..createSync();
    final mdPath = await file.importPackageBytes(
      File(zipPath).readAsBytesSync(),
      out.path,
    );
    expect(mdPath, isNotNull);

    final imported = await file.openDeck(mdPath!);
    expect(imported, isNotNull);
    expect(imported!.userNotes.values, contains('Cursusnotitie'));
  });

  group('encrypted packages', () {
    Deck sampleDeck() => Deck(
      title: 'Geheim Deck',
      slides: [
        Slide.create(
          SlideType.bullets,
        ).copyWith(title: 'Punten', bullets: ['een', 'twee']),
      ],
    );

    test('versleuteld pakket is detecteerbaar; onversleuteld niet', () async {
      final encPath = p.join(tmp.path, 'enc.ocideck');
      await file.exportPackage(sampleDeck(), encPath, password: 'geheim123!');
      final plainPath = p.join(tmp.path, 'plain.ocideck');
      await file.exportPackage(sampleDeck(), plainPath);

      expect(
        FileService.isEncryptedPackage(File(encPath).readAsBytesSync()),
        isTrue,
      );
      expect(
        FileService.isEncryptedPackage(File(plainPath).readAsBytesSync()),
        isFalse,
      );
    });

    test('round-trip met juist wachtwoord via de resolver', () async {
      final zipPath = p.join(tmp.path, 'enc.ocideck');
      await file.exportPackage(
        sampleDeck(),
        zipPath,
        password: 'correct-paard',
      );
      final bytes = File(zipPath).readAsBytesSync();
      final out = Directory(p.join(tmp.path, 'out_enc'))..createSync();

      final outcome = await file.importPackageBytesDetailed(
        bytes,
        out.path,
        onPassword: ({required bool retry}) async => 'correct-paard',
      );
      expect(outcome.mdPath, isNotNull);
      final imported = await file.openDeck(outcome.mdPath!);
      expect(imported!.slides.single.bullets, ['een', 'twee']);
    });

    test('retry: eerst fout, dan juist wachtwoord', () async {
      final zipPath = p.join(tmp.path, 'enc.ocideck');
      await file.exportPackage(sampleDeck(), zipPath, password: 's3cret');
      final bytes = File(zipPath).readAsBytesSync();
      final out = Directory(p.join(tmp.path, 'out_retry'))..createSync();

      var attempts = 0;
      final outcome = await file.importPackageBytesDetailed(
        bytes,
        out.path,
        onPassword: ({required bool retry}) async {
          attempts++;
          expect(retry, attempts > 1);
          return attempts == 1 ? 'fout' : 's3cret';
        },
      );
      expect(attempts, 2);
      expect(outcome.mdPath, isNotNull);
    });

    test('afbreken → encryptedCancelled (geen fout)', () async {
      final zipPath = p.join(tmp.path, 'enc.ocideck');
      await file.exportPackage(sampleDeck(), zipPath, password: 'x');
      final bytes = File(zipPath).readAsBytesSync();
      final out = Directory(p.join(tmp.path, 'out_cancel'))..createSync();

      final outcome = await file.importPackageBytesDetailed(
        bytes,
        out.path,
        onPassword: ({required bool retry}) async => null,
      );
      expect(outcome.mdPath, isNull);
      expect(outcome.failure, ImportFailure.encryptedCancelled);
    });

    test('geen resolver → needsPassword', () async {
      final zipPath = p.join(tmp.path, 'enc.ocideck');
      await file.exportPackage(sampleDeck(), zipPath, password: 'x');
      final bytes = File(zipPath).readAsBytesSync();
      final out = Directory(p.join(tmp.path, 'out_none'))..createSync();

      final outcome = await file.importPackageBytesDetailed(bytes, out.path);
      expect(outcome.failure, ImportFailure.needsPassword);
    });

    test('onversleuteld pakket importeert zonder resolver', () async {
      final zipPath = p.join(tmp.path, 'plain.ocideck');
      await file.exportPackage(sampleDeck(), zipPath);
      final bytes = File(zipPath).readAsBytesSync();
      final out = Directory(p.join(tmp.path, 'out_plain'))..createSync();

      final mdPath = await file.importPackageBytes(bytes, out.path);
      expect(mdPath, isNotNull);
    });

    // WinZip-AES draagt per lid een HMAC. Klopt die niet, dan is er ná het
    // versleutelen aan het pakket gezeten. Dat lid overslaan en de rest
    // doorlaten leverde stil een pakket op waar precies het gewijzigde
    // bestand uit verdwenen was — in een bewijsdossier de verkeerde kant op.
    group('gemanipuleerd pakket', () {
      /// Een versleuteld pakket met twee leden, zodat het wegvallen van één
      /// lid ook werkelijk zichtbaar is: bij één lid is "alles weg" en
      /// "stil ingekort" hetzelfde resultaat.
      List<int> twoMemberPackage() {
        final archive = Archive();
        final md = utf8.encode('# Geheim\n\nregel\n');
        final asset = List<int>.generate(400, (i) => (i * 7) % 251);
        archive
          ..addFile(ArchiveFile('deck.md', md.length, md))
          ..addFile(ArchiveFile('images/a.bin', asset.length, asset));
        return ZipEncoder(password: 'pw').encode(archive);
      }

      /// Eén byte omklappen in de versleutelde inhoud van het éérste lid.
      ///
      /// De plek wordt uit de local file header gelezen in plaats van geteld:
      /// na de vaste 30 bytes volgen de bestandsnaam (lengte op 26) en het
      /// extra veld (lengte op 28), en daarna begint de WinZip-AES-lading met
      /// 16 bytes salt plus 2 bytes wachtwoordverificatie. Twintig bytes verder
      /// zit dus cijfertekst — een wijziging die het wachtwoord ongemoeid laat
      /// en precies de HMAC laat vallen.
      Uint8List tamperFirstMember(List<int> bytes) {
        final nameLength = bytes[26] | (bytes[27] << 8);
        final extraLength = bytes[28] | (bytes[29] << 8);
        final payload = 30 + nameLength + extraLength;
        return Uint8List.fromList(bytes)..[payload + 20] ^= 0xFF;
      }

      test('een gewijzigd lid laat het hele pakket vallen', () {
        final bytes = twoMemberPackage();
        expect(
          file.decodePackageEntries(bytes, password: 'pw')?.map((e) => e.name),
          containsAll(<String>['deck.md', 'images/a.bin']),
          reason: 'het ongeschonden pakket moet beide leden opleveren',
        );

        final entries = file.decodePackageEntries(
          tamperFirstMember(bytes),
          password: 'pw',
        );
        // De fail-open die hier zat gaf `[images/a.bin]` terug: het pakket
        // kwam er compleet uitziend uit, mét het gewijzigde lid eruit gevallen.
        expect(
          entries,
          isNull,
          reason: entries == null
              ? ''
              : 'het pakket kwam er stil ingekort uit: '
                    '${entries.map((e) => e.name).toList()}',
        );
      });

      test('de import als geheel weigert een gemanipuleerd pakket', () async {
        final tampered = tamperFirstMember(twoMemberPackage());
        final out = Directory(p.join(tmp.path, 'out_tampered'))..createSync();

        final outcome = await file.importPackageBytesDetailed(
          tampered,
          out.path,
          onPassword: ({required bool retry}) async => 'pw',
        );
        expect(outcome.mdPath, isNull);
      });
    });
  });

  test('importing the same package twice never loses local edits', () async {
    final deck = Deck(
      title: 'Deck',
      slides: [
        Slide.create(SlideType.bullets).copyWith(bullets: ['x']),
      ],
    );
    final zipPath = p.join(tmp.path, 'deck.ocideck');
    await file.exportPackage(deck, zipPath);
    final bytes = File(zipPath).readAsBytesSync();
    final out = Directory(p.join(tmp.path, 'out'))..createSync();

    final first = await file.importPackageBytes(bytes, out.path);
    // Ongewijzigde kopie: dezelfde import wordt hergebruikt (geen "map (2)"
    // en dus geen dubbele vermelding in recente presentaties).
    final second = await file.importPackageBytes(bytes, out.path);
    expect(second, first);

    // Maar een lokaal bewerkte kopie wordt nooit overschreven: de derde
    // import krijgt een eigen map.
    await File(first!).writeAsString('---\nmarp: true\n---\n# Bewerkt');
    final third = await file.importPackageBytes(bytes, out.path);
    expect(third, isNotNull);
    expect(p.dirname(third!), isNot(p.dirname(first))); // aparte mappen
    expect(await File(first).readAsString(), '---\nmarp: true\n---\n# Bewerkt');
  });

  group('achtergehouden dia\'s', () {
    test(
      'een overgeslagen of strenger geclassificeerde dia zit niet in het pakket',
      () async {
        // Een pakket is de meest complete uitvoer die de app kent. Dit pad
        // serialiseerde `deck.slides` rechtstreeks, dus een dia die in de
        // presenter, op het zaalscherm én in de PDF wordt achtergehouden ging hier
        // gewoon mee — zonder dat er ook maar een instelling voor nodig was.
        final deck = Deck(
          title: 'Rapport',
          tlp: TlpLevel.none,
          slides: [
            Slide.create(
              SlideType.bullets,
            ).copyWith(title: 'PUBLIEK', bullets: ['zichtbaar']),
            Slide.create(SlideType.bullets).copyWith(
              title: 'ROOD-INTERN',
              bullets: ['klantnaam'],
              tlp: TlpLevel.red,
            ),
            Slide.create(SlideType.bullets).copyWith(
              title: 'OVERGESLAGEN',
              bullets: ['concept'],
              skipped: true,
            ),
          ],
        );
        final zipPath = p.join(tmp.path, 'pakket.ocideck');
        await file.exportPackage(deck, zipPath);
        final markdown = await _markdownFromPackage(zipPath);

        expect(markdown, contains('PUBLIEK'));
        expect(
          markdown,
          isNot(contains('ROOD-INTERN')),
          reason: 'strenger dan het deck: wordt overal elders achtergehouden',
        );
        expect(
          markdown,
          isNot(contains('OVERGESLAGEN')),
          reason: 'de auteur zette hem op overslaan',
        );
      },
    );
  });
}

/// De markdown uit een pakket, zonder aannames over de bestandsnaam.
Future<String> _markdownFromPackage(String zipPath) async {
  final archive = ZipDecoder().decodeBytes(File(zipPath).readAsBytesSync());
  final md = archive.files.firstWhere((f) => f.name.endsWith('.md'));
  return utf8.decode(md.content as List<int>);
}
