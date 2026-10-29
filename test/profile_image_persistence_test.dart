import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/models/deck.dart';
import 'package:ocideck/models/settings.dart';
import 'package:ocideck/models/slide.dart';
import 'package:ocideck/services/file_service.dart';
import 'package:ocideck/services/image_service.dart';
import 'package:ocideck/services/markdown_service.dart';
import 'package:path/path.dart' as p;

/// Regressietests voor het meereizen van profielafbeeldingen in een
/// Markdown-project en een `.ocideck`-pakket (#2641, #2642, #2645).
final _pngA = Uint8List.fromList([
  0x89,
  0x50,
  0x4e,
  0x47,
  0x0d,
  0x0a,
  0x1a,
  0x0a,
  1,
  1,
  1,
  1,
]);
final _pngB = Uint8List.fromList([
  0x89,
  0x50,
  0x4e,
  0x47,
  0x0d,
  0x0a,
  0x1a,
  0x0a,
  2,
  2,
  2,
  2,
]);
final _pngC = Uint8List.fromList([
  0x89,
  0x50,
  0x4e,
  0x47,
  0x0d,
  0x0a,
  0x1a,
  0x0a,
  3,
  3,
  3,
  3,
]);
final _pngD = Uint8List.fromList([
  0x89,
  0x50,
  0x4e,
  0x47,
  0x0d,
  0x0a,
  0x1a,
  0x0a,
  4,
  4,
  4,
  4,
]);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tmp;
  late Directory srcA;
  late Directory srcB;
  late FileService file;

  File image(Directory dir, String name, List<int> bytes) =>
      File(p.join(dir.path, name))..writeAsBytesSync(bytes);

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('ocideck_profileimg_test');
    srcA = Directory(p.join(tmp.path, 'src-a'))..createSync();
    srcB = Directory(p.join(tmp.path, 'src-b'))..createSync();
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
    'logo en merkstrook met gelijke naam maar andere bytes botsen niet (#2645)',
    () async {
      final logo = image(srcA, 'brand.png', _pngA);
      final strip = image(srcB, 'brand.png', _pngB);
      final deck = Deck(
        title: 'Botsing',
        themeProfile: ThemeProfile(
          logoPath: logo.path,
          brandStripPath: strip.path,
          brandStripHeight: 0.1,
        ),
        slides: [Slide.create(SlideType.title).copyWith(title: 'T')],
      );

      final proj = Directory(p.join(tmp.path, 'proj'))..createSync();
      final saved = await file.saveDeck(deck, p.join(proj.path, 'deck.md'));
      final logosDir = p.join(proj.path, 'logos');
      expect(saved.themeProfile.logoPath, 'logos/brand.png');
      expect(saved.themeProfile.brandStripPath, isNot('logos/brand.png'));
      expect(File(p.join(logosDir, 'brand.png')).readAsBytesSync(), _pngA);
      final stripRel = p.basename(saved.themeProfile.brandStripPath!);
      expect(File(p.join(logosDir, stripRel)).readAsBytesSync(), _pngB);
    },
  );

  test('gelijke bytes onder gelijke naam delen één kopie (#2645)', () async {
    final logo = image(srcA, 'brand.png', _pngA);
    final strip = image(srcB, 'brand.png', _pngA);
    final deck = Deck(
      title: 'Gedeeld',
      themeProfile: ThemeProfile(
        logoPath: logo.path,
        brandStripPath: strip.path,
        brandStripHeight: 0.1,
      ),
      slides: [Slide.create(SlideType.title).copyWith(title: 'T')],
    );

    final proj = Directory(p.join(tmp.path, 'proj'))..createSync();
    final saved = await file.saveDeck(deck, p.join(proj.path, 'deck.md'));
    expect(saved.themeProfile.logoPath, 'logos/brand.png');
    expect(saved.themeProfile.brandStripPath, 'logos/brand.png');
    expect(
      File(p.join(proj.path, 'logos', 'brand.png')).readAsBytesSync(),
      _pngA,
    );
  });

  test('het donkere logo reist mee in de projectmap (#2642)', () async {
    final logo = image(srcA, 'logo.png', _pngA);
    final dark = image(srcB, 'logo-donker.png', _pngB);
    final deck = Deck(
      title: 'Donker',
      themeProfile: ThemeProfile(logoPath: logo.path, logoDarkPath: dark.path),
      slides: [Slide.create(SlideType.title).copyWith(title: 'T')],
    );

    final projectDir = Directory(p.join(tmp.path, 'proj'))..createSync();
    final saved = await file.saveDeck(deck, p.join(projectDir.path, 'deck.md'));
    expect(saved.themeProfile.logoDarkPath, 'logos/logo-donker.png');
    expect(
      File(
        p.join(projectDir.path, 'logos', 'logo-donker.png'),
      ).readAsBytesSync(),
      _pngB,
    );

    // Save As naar een tweede map bewaart de variant ook als de bron weg is.
    dark.deleteSync();
    final secondDir = Directory(p.join(tmp.path, 'proj2'))..createSync();
    final saved2 = await file.saveDeck(
      saved.copyWith(projectPath: projectDir.path),
      p.join(secondDir.path, 'deck.md'),
    );
    expect(saved2.themeProfile.logoDarkPath, 'logos/logo-donker.png');
    expect(
      File(
        p.join(secondDir.path, 'logos', 'logo-donker.png'),
      ).readAsBytesSync(),
      _pngB,
    );
  });

  test(
    'een afwijkend documentlogo reist mee in project én pakket (#2641)',
    () async {
      final logo = image(srcA, 'logo.png', _pngA);
      final docLogo = image(srcB, 'document.png', _pngC);
      final deck = Deck(
        title: 'Documentlogo',
        themeProfile: ThemeProfile(
          logoPath: logo.path,
          documentLogoPath: docLogo.path,
        ),
        slides: [Slide.create(SlideType.title).copyWith(title: 'T')],
      );

      final projectDir = Directory(p.join(tmp.path, 'proj'))..createSync();
      final saved = await file.saveDeck(
        deck,
        p.join(projectDir.path, 'deck.md'),
      );
      expect(saved.themeProfile.documentLogoPath, 'logos/document.png');
      expect(
        File(
          p.join(projectDir.path, 'logos', 'document.png'),
        ).readAsBytesSync(),
        _pngC,
      );

      final members = await file.buildPackageMembers(deck);
      expect(members['logos/document.png'], _pngC);
    },
  );

  test(
    'documentlogo-betekenis blijft: null deelt, lege string zet uit (#2641)',
    () async {
      final deck = Deck(
        title: 'Betekenis',
        themeProfile: const ThemeProfile(documentLogoPath: ''),
        slides: [Slide.create(SlideType.title).copyWith(title: 'T')],
      );

      final proj = Directory(p.join(tmp.path, 'proj'))..createSync();
      final saved = await file.saveDeck(deck, p.join(proj.path, 'deck.md'));
      expect(saved.themeProfile.documentLogoPath, '');

      final members = await file.buildPackageMembers(
        deck.copyWith(themeProfile: const ThemeProfile(documentLogoPath: null)),
      );
      expect(members.keys.where((k) => k.startsWith('logos/')), isEmpty);
    },
  );

  test(
    'een .ocideck-pakket draagt de stijl mee als ocideck-style.json (#2644)',
    () async {
      final logo = image(srcA, 'logo.png', _pngA);
      final deck = Deck(
        title: 'Huisstijl',
        themeProfile: ThemeProfile(
          accentColor: '#AA0000',
          logoPath: logo.path,
          logoDarkPath: image(srcB, 'dark.png', _pngB).path,
          documentLogoPath: image(srcB, 'doc.png', _pngC).path,
          brandStripPath: image(srcB, 'strip.png', _pngD).path,
          brandStripHeight: 0.1,
        ),
        slides: [Slide.create(SlideType.title).copyWith(title: 'T')],
      );

      final members = await file.buildPackageMembers(deck);
      final themeJson = members['ocideck-style.json'];
      expect(themeJson, isNotNull);
      final decoded =
          jsonDecode(utf8.decode(themeJson!)) as Map<String, Object?>;
      expect(decoded['accentColor'], '#AA0000');

      // Openen bij een ontvanger met een ander actief profiel: de stijl van de
      // maker geldt, de logopaden wijzen in de uitgepakte map.
      final zip = await file.buildPackageBytes(deck);
      final out = Directory(p.join(tmp.path, 'out'))..createSync();
      final mdPath = await file.importPackageBytes(zip, out.path);
      expect(mdPath, isNotNull);
      final opened = await file.openDeckDetailed(mdPath!);
      final openedProfile = opened.deck?.themeProfile;
      expect(openedProfile, isNotNull);
      expect(openedProfile!.accentColor, '#AA0000');
      // resolveSymbolicLinks: de resolver geeft realpath-paden terug en op
      // macOS is /var een symlink naar /private/var.
      final projectDir = Directory(
        p.dirname(mdPath),
      ).resolveSymbolicLinksSync();
      for (final rel in [
        openedProfile.logoPath,
        openedProfile.logoDarkPath,
        openedProfile.documentLogoPath,
        openedProfile.brandStripPath,
      ]) {
        expect(rel, isNotNull);
        expect(p.isAbsolute(rel!), isTrue);
        expect(
          p.isWithin(projectDir, File(rel).resolveSymbolicLinksSync()),
          isTrue,
        );
        expect(File(rel).existsSync(), isTrue);
      }
    },
  );
}
