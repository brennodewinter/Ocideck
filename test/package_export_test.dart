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

  test(
    'importing the same package twice does not overwrite the first',
    () async {
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
      final second = await file.importPackageBytes(bytes, out.path);

      expect(first, isNotNull);
      expect(second, isNotNull);
      expect(p.dirname(first!), isNot(p.dirname(second!))); // aparte mappen
    },
  );
}
