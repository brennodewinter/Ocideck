import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/models/deck.dart';
import 'package:ocideck/models/settings.dart';
import 'package:ocideck/models/slide.dart';
import 'package:ocideck/services/file_service.dart';
import 'package:ocideck/services/image_service.dart';
import 'package:ocideck/services/markdown_service.dart';
import 'package:ocideck/services/user_notes_codec.dart';
import 'package:path/path.dart' as p;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('saveDeck copies logo into project logos directory', () async {
    final temp = await Directory.systemTemp.createTemp('ocideck_logo_test_');
    addTearDown(() async {
      if (await temp.exists()) await temp.delete(recursive: true);
    });

    final sourceLogo = File(p.join(temp.path, 'client.png'));
    await sourceLogo.writeAsBytes([1, 2, 3]);

    final service = FileService(
      MarkdownService(),
      ImageService(),
      () => ThemeProfile(logoPath: sourceLogo.path),
    );
    final deck = Deck(
      title: 'Logo test',
      themeProfile: ThemeProfile(logoPath: sourceLogo.path),
      slides: [Slide.create(SlideType.title).copyWith(title: 'Logo test')],
    );

    final saved = await service.saveDeck(deck, p.join(temp.path, 'deck.md'));

    expect(saved.themeProfile.logoPath, 'logos/client.png');
    expect(await File(p.join(temp.path, 'logos', 'client.png')).exists(), true);
  });

  test(
    'current theme resolves a relative logo from the home directory',
    () async {
      final temp = await Directory.systemTemp.createTemp(
        'ocideck_theme_logo_test_',
      );
      addTearDown(() async {
        if (await temp.exists()) await temp.delete(recursive: true);
      });

      final logo = File(p.join(temp.path, 'logos', 'client.png'));
      await logo.parent.create(recursive: true);
      await logo.writeAsBytes([1, 2, 3]);

      final service = FileService(
        MarkdownService(),
        ImageService(),
        () => const ThemeProfile(logoPath: 'logos/client.png'),
        homeDirectory: () => temp.path,
      );

      expect(service.currentThemeProfile.logoPath, logo.path);
    },
  );

  test(
    'importPackageBytes ignores path-traversal entries (zip slip)',
    () async {
      final temp = await Directory.systemTemp.createTemp('ocideck_zipslip_');
      addTearDown(() async {
        if (await temp.exists()) await temp.delete(recursive: true);
      });

      final archive = Archive();
      final md = utf8.encode('---\nmarp: true\n---\n# Hi');
      archive.addFile(ArchiveFile('deck.md', md.length, md));
      final evil = utf8.encode('pwned');
      archive.addFile(ArchiveFile('../evil.txt', evil.length, evil));
      final zipBytes = ZipEncoder().encode(archive);

      final service = FileService(
        MarkdownService(),
        ImageService(),
        () => const ThemeProfile(),
      );
      final mdPath = await service.importPackageBytes(zipBytes, temp.path);

      // The traversal entry must not have escaped the extraction folder.
      expect(await File(p.join(temp.path, 'evil.txt')).exists(), isFalse);
      // The legitimate markdown landed inside it.
      expect(mdPath, isNotNull);
      expect(p.isWithin(temp.path, mdPath!), isTrue);
      expect(await File(mdPath).exists(), isTrue);
    },
  );

  test('importPackageBytes rejects archives with too many entries', () async {
    final temp = await Directory.systemTemp.createTemp('ocideck_zip_entries_');
    addTearDown(() async {
      if (await temp.exists()) await temp.delete(recursive: true);
    });

    final archive = Archive();
    final md = utf8.encode('---\nmarp: true\n---\n# Hi');
    archive.addFile(ArchiveFile('deck.md', md.length, md));
    for (var i = 0; i < FileService.maxPackageEntries; i++) {
      archive.addFile(ArchiveFile('extra/$i.txt', 1, [0]));
    }
    final zipBytes = ZipEncoder().encode(archive);

    final service = FileService(
      MarkdownService(),
      ImageService(),
      () => const ThemeProfile(),
    );
    expect(await service.importPackageBytes(zipBytes, temp.path), isNull);
  });

  test('importPackageBytes rejects oversized compressed input', () async {
    final temp = await Directory.systemTemp.createTemp('ocideck_zip_size_');
    addTearDown(() async {
      if (await temp.exists()) await temp.delete(recursive: true);
    });

    final service = FileService(
      MarkdownService(),
      ImageService(),
      () => const ThemeProfile(),
    );
    final oversized = List<int>.filled(FileService.maxPackageBytes + 1, 0);
    expect(await service.importPackageBytes(oversized, temp.path), isNull);
  });

  test('importPackageBytes aborts when decompressed size exceeds limit', () async {
    final temp = await Directory.systemTemp.createTemp('ocideck_zip_bomb_');
    addTearDown(() async {
      if (await temp.exists()) await temp.delete(recursive: true);
    });

    final archive = Archive();
    final md = utf8.encode('---\nmarp: true\n---\n# Hi');
    archive.addFile(ArchiveFile('deck.md', md.length, md));
    final huge = List<int>.filled(FileService.maxPackageBytes + 1, 0);
    archive.addFile(ArchiveFile('images/huge.bin', huge.length, huge));

    final service = FileService(
      MarkdownService(),
      ImageService(),
      () => const ThemeProfile(),
    );
    expect(
      await service.importPackageBytes(ZipEncoder().encode(archive), temp.path),
      isNull,
    );
  });

  test(
    'importFromUrl refuses non-web schemes and private/loopback hosts',
    () async {
      final temp = await Directory.systemTemp.createTemp('ocideck_ssrf_');
      addTearDown(() async {
        if (await temp.exists()) await temp.delete(recursive: true);
      });
      final service = FileService(
        MarkdownService(),
        ImageService(),
        () => const ThemeProfile(),
      );

      // These are all rejected before any network access happens.
      for (final url in [
        'ftp://example.com/x', // non-web scheme
        'file:///etc/passwd', // non-web scheme
        'http://localhost:8080/x.ocideck', // loopback name
        'http://127.0.0.1/x', // loopback IP
        'http://192.168.1.5/x', // private IP
        'http://10.0.0.9/x', // private IP
        'http://169.254.1.1/x', // link-local IP
      ]) {
        expect(
          await service.importFromUrl(url, temp.path),
          isNull,
          reason: 'should refuse $url',
        );
      }
    },
  );

  test('saveDeck writes user-notes sidecar and openDeck reloads it', () async {
    final temp = await Directory.systemTemp.createTemp('ocideck_user_notes_');
    addTearDown(() async {
      if (await temp.exists()) await temp.delete(recursive: true);
    });

    final service = FileService(
      MarkdownService(),
      ImageService(),
      () => const ThemeProfile(),
    );
    final slide = Slide.create(
      SlideType.bullets,
    ).copyWith(title: 'Slide', notes: 'Spreker alleen');
    final deck = Deck(
      title: 'Notes test',
      slides: [slide],
      userNotes: {slide.id: 'Cursist notitie'},
    );

    final mdPath = p.join(temp.path, 'notes_test.md');
    await service.saveDeck(deck, mdPath);

    final sidecar = File(p.setExtension(mdPath, '.user-notes.json'));
    expect(await sidecar.exists(), isTrue);
    final decoded = UserNotesCodec.decode(await sidecar.readAsString(), [
      slide,
    ]);
    expect(decoded.values, contains('Cursist notitie'));

    final markdown = await File(mdPath).readAsString();
    expect(markdown, contains('Spreker alleen'));
    expect(markdown, isNot(contains('Cursist notitie')));

    final reopened = await service.openDeck(mdPath);
    expect(reopened, isNotNull);
    expect(reopened!.slides.single.notes, 'Spreker alleen');
    expect(reopened.userNotes.length, 1);
    expect(reopened.userNotes.values.single, 'Cursist notitie');
  });

  test('saveDeck removes empty user-notes sidecar', () async {
    final temp = await Directory.systemTemp.createTemp(
      'ocideck_user_notes_empty_',
    );
    addTearDown(() async {
      if (await temp.exists()) await temp.delete(recursive: true);
    });

    final service = FileService(
      MarkdownService(),
      ImageService(),
      () => const ThemeProfile(),
    );
    final mdPath = p.join(temp.path, 'empty_notes.md');
    final sidecar = File(p.setExtension(mdPath, '.user-notes.json'));
    await sidecar.writeAsString('{"version":1,"slides":[]}');

    final deck = Deck(
      title: 'Empty notes',
      slides: [Slide.create(SlideType.bullets)],
    );
    await service.saveDeck(deck, mdPath);

    expect(await sidecar.exists(), isFalse);
  });
}
