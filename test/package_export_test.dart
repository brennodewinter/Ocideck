import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';

import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/models/deck.dart';
import 'package:ocideck/models/marp_style.dart';
import 'package:ocideck/models/settings.dart';
import 'package:ocideck/models/slide.dart';
import 'package:ocideck/services/file_service.dart';
import 'package:ocideck/services/image_service.dart';
import 'package:ocideck/services/asset_staging.dart';
import 'package:ocideck/services/markdown_service.dart';
import 'package:ocideck/services/pdf_evidence_service.dart';
import 'package:ocideck/utils/archive_limits.dart';
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
    AssetStaging.overrideRootForTest(p.join(tmp.path, 'staging'));
  });

  tearDown(() {
    AssetStaging.overrideRootForTest(null);
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  test(
    'export then import a package round-trips slides and bundles the image',
    () async {
      // Bron-afbeelding (absoluut pad, zoals net geplakt/gekozen).
      final srcImg = File(p.join(tmp.path, 'pic.png'))
        ..writeAsBytesSync([1, 2, 3, 4]);

      final staged = await AssetStaging.stage(srcImg.path, subdir: 'images');
      expect(staged, isNotNull);
      final stagedPath = staged!;
      final deck = Deck(
        title: 'Mijn Deck',
        slides: [
          Slide.create(
            SlideType.image,
          ).copyWith(title: 'Foto', imagePath: stagedPath),
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

  test('project package refuses absolute and symlink escapes', () async {
    final project = Directory(p.join(tmp.path, 'project'))..createSync();
    final images = Directory(p.join(project.path, 'images'))..createSync();
    final outside = File(p.join(tmp.path, 'secret.txt'))
      ..writeAsStringSync('outside');
    final sneaky = Link(p.join(images.path, 'sneaky.png'))
      ..createSync(outside.path);
    final deck = Deck(
      title: 'Containment',
      projectPath: project.path,
      slides: [
        Slide.create(SlideType.image).copyWith(imagePath: outside.path),
        Slide.create(SlideType.image).copyWith(imagePath: sneaky.path),
      ],
    );

    final members = await file.buildPackageMembers(deck);
    expect(members.keys.where((name) => name.startsWith('images/')), isEmpty);
    final markdown = utf8.decode(members['Containment.md']!);
    expect(markdown, isNot(contains(outside.path)));
    expect(markdown, isNot(contains(sneaky.path)));
  });

  test('unsaved package refuses untrusted local image paths', () async {
    final outside = File(p.join(tmp.path, 'secret.png'))
      ..writeAsBytesSync([1, 2, 3]);
    final deck = Deck(
      title: 'Unsaved',
      slides: [
        Slide.create(SlideType.image).copyWith(imagePath: outside.path),
        Slide.create(SlideType.image).copyWith(imagePath: 'images/local.png'),
      ],
    );

    final members = await file.buildPackageMembers(deck);
    expect(members.keys.where((name) => name.startsWith('images/')), isEmpty);
    final markdown = utf8.decode(members['Unsaved.md']!);
    expect(markdown, isNot(contains(outside.path)));
    expect(markdown, isNot(contains('images/local.png')));
  });

  test('project package keeps trusted external theme logos', () async {
    final project = Directory(p.join(tmp.path, 'project'))..createSync();
    final logo = File(p.join(tmp.path, 'brand.png'))
      ..writeAsBytesSync([9, 8, 7]);
    final deck = Deck(
      title: 'Brand',
      projectPath: project.path,
      themeProfile: ThemeProfile(logoPath: logo.path),
    );

    final members = await file.buildPackageMembers(deck);
    final logoMember = members.entries.firstWhere(
      (entry) => entry.key.startsWith('logos/'),
    );
    expect(logoMember.value, logo.readAsBytesSync());
  });

  test(
    'project package removes blocked HTML and background image paths',
    () async {
      final project = Directory(p.join(tmp.path, 'project'))..createSync();
      final outside = File(p.join(tmp.path, 'secret.png'))
        ..writeAsBytesSync([6, 6, 6]);
      final deck = Deck(
        title: 'Markup assets',
        projectPath: project.path,
        marpStyle: MarpStyle(
          backgroundImage: 'linear-gradient(red, blue), url("${outside.path}")',
        ),
        slides: [
          Slide.create(
            SlideType.freeMarkdown,
          ).copyWith(customMarkdown: '<img src="${outside.path}">'),
        ],
      );

      final members = await file.buildPackageMembers(deck);
      final markdown = utf8.decode(
        members.entries.firstWhere((entry) => entry.key.endsWith('.md')).value,
      );
      expect(markdown, isNot(contains(outside.path)));
      expect(members.keys.where((name) => name.startsWith('images/')), isEmpty);
    },
  );

  test('project package removes blocked PDF evidence paths', () async {
    final project = Directory(p.join(tmp.path, 'project'))..createSync();
    final outside = File(p.join(tmp.path, 'secret.pdf'))
      ..writeAsBytesSync([37, 80, 68, 70, 45, 1]);
    final deck = Deck(
      title: 'Evidence',
      projectPath: project.path,
      slides: [
        Slide.create(
          SlideType.freeMarkdown,
        ).copyWith(customMarkdown: '[bewijs](<${outside.path}>)'),
      ],
    );

    final members = await file.buildPackageMembers(deck);
    final markdown = utf8.decode(
      members.entries.firstWhere((entry) => entry.key.endsWith('.md')).value,
    );
    expect(markdown, isNot(contains(outside.path)));
    expect(members.keys.where((name) => name.startsWith('evidence/')), isEmpty);
  });

  test('project package removes blocked Windows PDF evidence paths', () async {
    final project = Directory(p.join(tmp.path, 'project'))..createSync();
    const outside = r'C:\outside\secret.pdf';
    final deck = Deck(
      title: 'Evidence',
      projectPath: project.path,
      slides: [
        Slide.create(
          SlideType.freeMarkdown,
        ).copyWith(customMarkdown: '[bewijs](<$outside>)'),
      ],
    );

    final members = await file.buildPackageMembers(deck);
    final markdown = utf8.decode(
      members.entries.firstWhere((entry) => entry.key.endsWith('.md')).value,
    );
    expect(markdown, isNot(contains(outside)));
    expect(members.keys.where((name) => name.startsWith('evidence/')), isEmpty);
  });

  // Een pakket is bedoeld om weg te geven: wat er niet in zit, ziet de
  // ontvanger niet. Een afbeelding in de vrije tekst hoort er dus net zo goed
  // in als eentje in een afbeeldingsveld.
  test('export then import bundles an image from the free text', () async {
    final srcImg = File(p.join(tmp.path, 'tekstfoto.png'))
      ..writeAsBytesSync([5, 6, 7, 8]);
    final staged = await AssetStaging.stage(srcImg.path, subdir: 'images');
    expect(staged, isNotNull);
    final stagedPath = staged!;

    final deck = Deck(
      title: 'Tekstdeck',
      slides: [
        Slide.create(SlideType.freeMarkdown).copyWith(
          title: 'Verhaal',
          customMarkdown: 'Zie ![w:600 de foto]($stagedPath) hierboven.',
        ),
      ],
    );

    final zipPath = p.join(tmp.path, 'tekst.ocideck');
    await file.exportPackage(deck, zipPath);

    // Het lid zit in het archief...
    final members = ZipDecoder()
        .decodeBytes(File(zipPath).readAsBytesSync())
        .files
        .map((f) => f.name);
    expect(members, contains('images/tekstfoto.png'));

    // ...en na import wijst de tekst ernaar, projectrelatief.
    final out = Directory(p.join(tmp.path, 'out_tekst'))..createSync();
    final mdPath = await file.importPackageBytes(
      File(zipPath).readAsBytesSync(),
      out.path,
    );
    final imported = await file.openDeck(mdPath!);
    expect(
      imported!.slides.single.customMarkdown,
      contains('![w:600 de foto](images/tekstfoto.png)'),
    );
    expect(
      File(
        p.join(imported.projectPath!, 'images', 'tekstfoto.png'),
      ).readAsBytesSync(),
      [5, 6, 7, 8],
    );
  });

  test('export then import preserves PDF evidence byte-for-byte', () async {
    final project = Directory(p.join(tmp.path, 'pdf-project'))..createSync();
    final src = File(p.join(project.path, 'evidence', 'bewijs.pdf'));
    src.parent.createSync();
    final original = Uint8List.fromList(
      '%PDF-1.7\nsigned-pdf-fixture'.codeUnits,
    );
    src.writeAsBytesSync(original);
    final deck = Deck(
      title: 'Bewijsdeck',
      projectPath: project.path,
      slides: [
        Slide.create(SlideType.freeMarkdown).copyWith(
          customMarkdown: PdfEvidenceService.markdownFor('evidence/bewijs.pdf'),
          findingId: 'F-01',
          findingRole: FindingRole.evidence,
        ),
      ],
    );

    final zipPath = p.join(tmp.path, 'bewijs.ocideck');
    await file.exportPackage(deck, zipPath);
    final members = ZipDecoder().decodeBytes(File(zipPath).readAsBytesSync());
    expect(
      members.files.map((member) => member.name),
      contains('evidence/bewijs.pdf'),
    );
    expect(
      Uint8List.fromList(
        members.files
            .singleWhere((m) => m.name == 'evidence/bewijs.pdf')
            .content,
      ),
      original,
    );

    final out = Directory(p.join(tmp.path, 'out_pdf'))..createSync();
    final mdPath = await file.importPackageBytes(
      File(zipPath).readAsBytesSync(),
      out.path,
    );
    final imported = await file.openDeck(mdPath!);
    final attachment = PdfEvidenceService.attachmentFromMarkdown(
      imported!.slides.single.customMarkdown,
    );
    expect(attachment?.path, 'evidence/bewijs.pdf');
    expect(
      File(p.join(imported.projectPath!, attachment!.path)).readAsBytesSync(),
      original,
    );
  });

  test('package bundles all nine images from an oversized question', () async {
    final paths = <String>[];
    for (var i = 0; i < 9; i++) {
      final source = File(p.join(tmp.path, 'antwoord-$i.png'))
        ..writeAsBytesSync([0x89, 0x50, 0x4e, 0x47, i]);
      final staged = await AssetStaging.stage(source.path, subdir: 'images');
      expect(staged, isNotNull);
      paths.add(staged!);
    }
    final question = const JsonEncoder.withIndent('  ').convert({
      'kind': 'imagePair',
      'prompt': 'Welke?',
      'answers': [
        for (var i = 0; i < paths.length; i++)
          {'text': 'Beeld $i', 'correct': i.isEven, 'image': paths[i]},
      ],
    });
    final deck = Deck(
      title: 'Te grote vraag',
      slides: [
        Slide.create(SlideType.question).copyWith(customMarkdown: question),
      ],
    );

    final zipPath = p.join(tmp.path, 'te-grote-vraag.ocideck');
    await file.exportPackage(deck, zipPath);
    final members = ZipDecoder()
        .decodeBytes(File(zipPath).readAsBytesSync())
        .files
        .map((member) => member.name)
        .toSet();

    expect(
      members,
      containsAll([for (var i = 0; i < 9; i++) 'images/antwoord-$i.png']),
    );
  });

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

    test(
      'versleutelde zip-bom stopt tijdens wachtwoordproef en extractie',
      () async {
        final expanded = List<int>.filled(64 * 1024, 65);
        final archive = Archive()
          ..addFile(ArchiveFile('deck.md', expanded.length, expanded));
        final bytes = Uint8List.fromList(
          ZipEncoder(password: 'pw').encode(archive),
        );
        // De inhoudsopgave liegt over de uitgepakte grootte: alleen de echte
        // begrensde writer kan de overschrijding dan nog tegenhouden.
        final directory = bytes.indexOf(0x50, 0);
        var central = -1;
        for (var i = directory; i < bytes.length - 28; i++) {
          if (bytes[i] == 0x50 &&
              bytes[i + 1] == 0x4b &&
              bytes[i + 2] == 0x01 &&
              bytes[i + 3] == 0x02) {
            central = i;
            break;
          }
        }
        expect(central, isNonNegative);
        bytes
          ..[central + 24] = 64
          ..[central + 25] = 0
          ..[central + 26] = 0
          ..[central + 27] = 0;
        const limit = 4096;
        expect(bytes.length, lessThan(limit));
        expect(
          () => file.canDecodePackage(bytes, 'pw', maxBytes: limit),
          throwsA(isA<ExtractionLimitException>()),
        );
        expect(
          file.decodePackageEntries(bytes, maxBytes: limit, password: 'pw'),
          isNull,
        );

        var prompts = 0;
        final outcome = await file.importPackageBytesDetailed(
          bytes,
          tmp.path,
          maxBytes: limit,
          onPassword: ({required bool retry}) async {
            prompts++;
            return 'pw';
          },
        );
        expect(prompts, 1);
        expect(outcome.failure, ImportFailure.tooLarge);
      },
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

      test('een aangetast pakket heet aangetast, en de vraag om het wachtwoord '
          'wordt niet eindeloos herhaald', () async {
        // Hier zat een echte vastloper. `canDecodePackage` faalt zowel bij een
        // fout wachtwoord als bij een aangetast pakket — WinZip-AES controleert
        // een MAC — en de lus vroeg daarom eindeloos om een nieuwe zin. Een
        // aanroeper die (zoals hierboven) altijd dezelfde zin teruggeeft, liet
        // de poort meer dan twintig minuten op één kern draaien.
        final tampered = tamperFirstMember(twoMemberPackage());
        final out = Directory(p.join(tmp.path, 'out_tampered_reason'))
          ..createSync();

        var gevraagd = 0;
        final outcome = await file.importPackageBytesDetailed(
          tampered,
          out.path,
          onPassword: ({required bool retry}) async {
            gevraagd++;
            return 'pw';
          },
        );

        expect(
          outcome.failure,
          ImportFailure.corrupt,
          reason: 'niet "verkeerd wachtwoord": de zin klopte, het pakket niet',
        );
        expect(
          gevraagd,
          lessThanOrEqualTo(2),
          reason: 'dezelfde zin tweemaal aanbieden kan niet alsnog lukken',
        );
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

  group('package budget (#1046)', () {
    // A deck with one on-disk image, reused so the helpers have something to
    // stat and pack.
    Deck deckWithImage(int imageBytes) {
      final img = File(p.join(tmp.path, 'big.bin'))
        ..writeAsBytesSync(Uint8List(imageBytes));
      return Deck(
        title: 'Budget',
        slides: [Slide.create(SlideType.image).copyWith(imagePath: img.path)],
      );
    }

    test('a single asset larger than the budget is refused before read', () {
      // The asset alone (1 KiB) tops a tiny budget, so the stat-before-read
      // guard trips without materialising it.
      final deck = deckWithImage(1024);
      expect(
        () => file.buildPackageBytes(deck, budgetBytes: 64),
        throwsA(isA<PackageBudgetExceeded>()),
      );
    });

    test(
      'the cumulative budget holds at the grens and one byte over',
      () async {
        final deck = deckWithImage(4096);
        // The true total of every member, learned with a generous budget.
        final members = await file.buildPackageMembers(deck);
        final total = members.values.fold<int>(0, (s, b) => s + b.length);

        // Exactly on the grens: the whole package still fits.
        final onLimit = await file.buildPackageBytes(deck, budgetBytes: total);
        expect(onLimit, isNotEmpty);

        // One byte under the total: the cumulative guard refuses it.
        expect(
          () => file.buildPackageBytes(deck, budgetBytes: total - 1),
          throwsA(isA<PackageBudgetExceeded>()),
        );
      },
    );

    test('a package within budget exports and re-imports (contract)', () async {
      final deck = deckWithImage(2048);
      final zipPath = p.join(tmp.path, 'ok.ocideck');
      await file.exportPackage(deck, zipPath);
      // The written package is no larger than what the importer accepts, so the
      // export/import contract holds by construction.
      expect(
        File(zipPath).lengthSync(),
        lessThanOrEqualTo(FileService.maxPackageBytes),
      );
      final out = Directory(p.join(tmp.path, 'reimport'))..createSync();
      final mdPath = await file.importPackageBytes(
        File(zipPath).readAsBytesSync(),
        out.path,
      );
      expect(mdPath, isNotNull);
    });
  });
}

/// De markdown uit een pakket, zonder aannames over de bestandsnaam.
Future<String> _markdownFromPackage(String zipPath) async {
  final archive = ZipDecoder().decodeBytes(File(zipPath).readAsBytesSync());
  final md = archive.files.firstWhere((f) => f.name.endsWith('.md'));
  return utf8.decode(md.content as List<int>);
}
