import 'dart:io';

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
}
