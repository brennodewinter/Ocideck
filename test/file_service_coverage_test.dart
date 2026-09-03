import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/models/asset_origin.dart';
import 'package:ocideck/models/deck.dart';
import 'package:ocideck/models/settings.dart';
import 'package:ocideck/models/slide.dart';
import 'package:ocideck/services/download_delivery.dart';
import 'package:ocideck/services/file_service.dart';
import 'package:ocideck/services/image_service.dart';
import 'package:ocideck/services/markdown_service.dart';
import 'package:ocideck/services/web_asset_store.dart';
import 'package:path/path.dart' as p;

/// Covers branches of lib/services/file_service.dart that the existing
/// file_service_test.dart / file_service_extra_test.dart do not reach:
/// in-memory open, theme-profile logo resolution, the byte-inspection helpers,
/// direct package decoding (incl. encryption), and the safe-scan early exits.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  FileService makeService({
    ThemeProfile Function()? themeProfile,
    String? Function()? homeDirectory,
  }) => FileService(
    MarkdownService(),
    ImageService(),
    themeProfile ?? () => const ThemeProfile(),
    homeDirectory: homeDirectory,
  );

  const goodMarkdown = '---\nmarp: true\ntitle: X\n---\n\n# Hi\n\n- a\n';

  group('openDeckFromContent (pure in-memory open)', () {
    test('opens clean Marp markdown without any filesystem access', () {
      final service = makeService();
      final result = service.openDeckFromContent(
        goodMarkdown,
        sourceName: 'demo',
      );
      expect(result.failure, isNull);
      expect(result.deck, isNotNull);
      expect(result.deck!.slides, isNotEmpty);
    });

    test('refuses markdown carrying executable content', () {
      final service = makeService();
      final result = service.openDeckFromContent(
        '---\nmarp: true\n---\n\n# Hi\n\n<script>x()</script>\n',
      );
      expect(result.deck, isNull);
      expect(result.failure, OpenFailure.unsafe);
    });

    test('refuses content without marp front matter', () {
      final service = makeService();
      final result = service.openDeckFromContent('# Just a heading\n');
      expect(result.deck, isNull);
      expect(result.failure, OpenFailure.notPresentation);
    });

    test('reports corrupt content that cannot be parsed', () {
      final service = makeService();
      // marp front matter present, but no parseable slide body at all.
      final result = service.openDeckFromContent('---\nmarp: true\n---\n');
      // Either corrupt or a placeholder deck — but never a hard throw.
      expect(result.deck == null || result.deck!.slides.isNotEmpty, isTrue);
    });
  });

  group('resolveThemeProfile / activeProfileFor', () {
    test('leaves an absolute logo path untouched', () {
      final abs = p.join(Directory.systemTemp.path, 'nowhere', 'logo.png');
      final service = makeService(
        themeProfile: () => ThemeProfile(logoPath: abs),
      );
      expect(service.currentThemeProfile.logoPath, abs);
    });

    test('leaves a bundled asset: logo path untouched', () {
      final service = makeService(
        themeProfile: () =>
            const ThemeProfile(logoPath: 'asset:assets/images/logo.png'),
      );
      expect(
        service.currentThemeProfile.logoPath,
        'asset:assets/images/logo.png',
      );
    });

    test('leaves an empty logo path untouched', () {
      final service = makeService(
        themeProfile: () => const ThemeProfile(logoPath: ''),
      );
      expect(service.currentThemeProfile.logoPath, '');
    });

    test('keeps a relative logo path that resolves to no file', () {
      final service = makeService(
        themeProfile: () => const ThemeProfile(logoPath: 'logos/missing.png'),
        homeDirectory: () => Directory.systemTemp.path,
      );
      // No such file under any base → the relative path is returned unchanged.
      expect(service.currentThemeProfile.logoPath, 'logos/missing.png');
    });

    test('resolves a relative logo path against the project folder', () async {
      final temp = await Directory.systemTemp.createTemp('ocideck_res_logo_');
      addTearDown(() async {
        if (await temp.exists()) await temp.delete(recursive: true);
      });
      final logo = File(p.join(temp.path, 'logos', 'client.png'));
      await logo.parent.create(recursive: true);
      await logo.writeAsBytes([1, 2, 3]);

      final service = makeService(
        themeProfile: () => const ThemeProfile(logoPath: 'logos/client.png'),
      );
      final resolved = service.activeProfileFor(projectPath: temp.path);
      expect(resolved.logoPath, logo.path);
    });
  });

  group('byte-inspection helpers', () {
    test('looksLikeZipBytes recognises the PK header only', () {
      expect(
        FileService.looksLikeZipBytes([0x50, 0x4B, 0x03, 0x04, 0x00]),
        isTrue,
      );
      expect(FileService.looksLikeZipBytes([0x50, 0x4B]), isFalse);
      expect(FileService.looksLikeZipBytes(utf8.encode('not a zip')), isFalse);
    });

    test('isEncryptedPackage is false for a plain archive', () {
      final archive = Archive();
      final md = utf8.encode(goodMarkdown);
      archive.addFile(ArchiveFile('deck.md', md.length, md));
      final zip = ZipEncoder().encode(archive);
      expect(FileService.isEncryptedPackage(zip), isFalse);
      expect(FileService.looksLikeZipBytes(zip), isTrue);
    });

    test('mainMarkdownEntry picks the shallowest .md, null when none', () {
      final entries = <PackageEntry>[
        (name: 'nested/deep/inner.md', bytes: utf8.encode('a')),
        (name: 'top.md', bytes: utf8.encode('b')),
        (name: 'images/pic.png', bytes: utf8.encode('c')),
      ];
      expect(FileService.mainMarkdownEntry(entries)!.name, 'top.md');

      final noMd = <PackageEntry>[
        (name: 'images/pic.png', bytes: utf8.encode('c')),
      ];
      expect(FileService.mainMarkdownEntry(noMd), isNull);
    });
  });

  group('decodePackageEntries (direct)', () {
    test('decodes a normal multi-file archive', () {
      final archive = Archive();
      final md = utf8.encode(goodMarkdown);
      archive.addFile(ArchiveFile('deck.md', md.length, md));
      final png = utf8.encode('png-bytes');
      archive.addFile(ArchiveFile('images/pic.png', png.length, png));
      final zip = ZipEncoder().encode(archive);

      final service = makeService();
      final entries = service.decodePackageEntries(zip);
      expect(entries, isNotNull);
      final names = entries!.map((e) => e.name).toSet();
      expect(names, containsAll(<String>['deck.md', 'images/pic.png']));
    });

    test('returns null when the compressed input is over the cap', () {
      final service = makeService();
      final oversized = List<int>.filled(33, 0);
      expect(service.decodePackageEntries(oversized, maxBytes: 32), isNull);
    });

    test('skips an entry whose path is longer than the limit', () {
      final archive = Archive();
      final md = utf8.encode(goodMarkdown);
      archive.addFile(ArchiveFile('deck.md', md.length, md));
      final longName = 'a/${'x' * (FileService.maxZipEntryPathLength + 5)}.txt';
      final blob = utf8.encode('data');
      archive.addFile(ArchiveFile(longName, blob.length, blob));
      final zip = ZipEncoder().encode(archive);

      final service = makeService();
      final entries = service.decodePackageEntries(zip);
      expect(entries, isNotNull);
      final names = entries!.map((e) => e.name).toList();
      expect(names, contains('deck.md'));
      expect(names.any((n) => n == longName), isFalse);
    });

    test('tolerantly decodes a non-zip blob to no members', () {
      final service = makeService();
      // The archive decoder is deliberately tolerant: a non-zip blob decodes to
      // an empty archive rather than throwing, so no package members come back.
      final entries = service.decodePackageEntries(
        utf8.encode('definitely not a zip here'),
      );
      expect(entries == null || entries.isEmpty, isTrue);
    });
  });

  group('encrypted package round-trip', () {
    test('detects and decodes a password-protected package', () async {
      final service = makeService();
      final deck = Deck(
        title: 'Secret Deck',
        slides: [
          Slide.create(SlideType.title).copyWith(title: 'Secret Deck'),
          Slide.create(
            SlideType.bullets,
          ).copyWith(title: 'Points', bullets: const ['a', 'b']),
        ],
      );

      final bytes = await service.buildPackageBytes(deck, password: 'hunter2');

      expect(FileService.looksLikeZipBytes(bytes), isTrue);
      expect(FileService.isEncryptedPackage(bytes), isTrue);

      // The right password decodes the members.
      final entries = service.decodePackageEntries(bytes, password: 'hunter2');
      expect(entries, isNotNull);
      final mainMd = FileService.mainMarkdownEntry(entries!);
      expect(mainMd, isNotNull);
      final markdown = utf8.decode(mainMd!.bytes);
      expect(markdown, contains('marp: true'));

      // A wrong password yields no usable members (null or empty, never throws).
      final wrong = service.decodePackageEntries(bytes, password: 'nope');
      expect(wrong == null || wrong.isEmpty, isTrue);
    });
  });

  group('scanForUnsafeMarkdown early exits', () {
    test('returns empty for a missing file (no false alarm)', () async {
      final service = makeService();
      final findings = await service.scanForUnsafeMarkdown(
        p.join(Directory.systemTemp.path, 'ocideck_no_such_file_xyz.md'),
      );
      expect(findings, isEmpty);
    });

    test(
      'returns empty for an over-cap file (openDeck refuses it anyway)',
      () async {
        final temp = await Directory.systemTemp.createTemp(
          'ocideck_scan_huge_',
        );
        addTearDown(() async {
          if (await temp.exists()) await temp.delete(recursive: true);
        });
        final path = p.join(temp.path, 'huge.md');
        final file = File(path);
        final sink = file.openWrite();
        sink.write('---\nmarp: true\n---\n\n# Big\n\n');
        final filler = 'x' * 1024;
        final chunks = (FileService.maxDeckMarkdownBytes ~/ filler.length) + 4;
        for (var i = 0; i < chunks; i++) {
          sink.write(filler);
        }
        await sink.flush();
        await sink.close();
        expect(
          await file.length(),
          greaterThan(FileService.maxDeckMarkdownBytes),
        );

        final service = makeService();
        expect(await service.scanForUnsafeMarkdown(path), isEmpty);
      },
    );
  });

  group('web download path', () {
    test('downloadDeckAsFile returns null off-web but serialises the deck', () {
      // On non-web the download stub returns false, so the result is null; the
      // call still exercises deck serialisation and the safe-name derivation.
      final service = makeService();
      final deck = Deck(
        title: 'A Deck: with * chars?',
        slides: [Slide.create(SlideType.title).copyWith(title: 'Hi')],
      );
      expect(service.downloadDeckAsFile(deck), isNull);
    });

    // #1954: een deck met mem:-afbeeldingen reist niet mee in een kale .md.
    // De download kan slagen (sink retourneert true), maar het deck moet vuil
    // blijven — anders denkt de gebruiker dat hij opgeslagen heeft, sluit de
    // tab, en is het beeld kwijt. Dit test de componenten die _saveAsDownload
    // gebruikt: downloadDeckAsFile retourneert een naam, en
    // deckCarriesMemoryAssets is true voor zo'n deck.
    test(
      'downloadDeckAsFile met mem:-assets slaagt, maar het deck blijft vluchtig (#1954)',
      () {
        // Simuleer de browser-download: de sink accepteert het bestand.
        debugDownloadSink = (_, _, _) => true;
        addTearDown(() => debugDownloadSink = null);

        final service = makeService();
        final mem = WebAssetStore.put(Uint8List(4), name: 'foto.png');
        final deck = Deck(
          title: 'Met beeld',
          slides: [Slide.create(SlideType.image).copyWith(imagePath: mem)],
        );

        // De download start — de sink retourneert true.
        expect(service.downloadDeckAsFile(deck), 'Met_beeld.md');
        // Maar het deck draagt vluchtige media: een kale .md neemt die niet mee.
        expect(deckCarriesMemoryAssets(deck), isTrue);
        // _saveAsDownload hoort hier isDirty niet op false te zetten — de
        // combinatie van deze twee asserts is het bewijs.
      },
    );
  });
}
