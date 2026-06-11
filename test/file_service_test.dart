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
}
