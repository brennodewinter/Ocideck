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

  FileService makeService({String? Function()? homeDirectory}) => FileService(
    MarkdownService(),
    ImageService(),
    () => const ThemeProfile(),
    homeDirectory: homeDirectory,
  );

  test('openDeck returns null for a missing file', () async {
    final temp = await Directory.systemTemp.createTemp('ocideck_open_missing_');
    addTearDown(() async {
      if (await temp.exists()) await temp.delete(recursive: true);
    });

    final service = makeService();
    final result = await service.openDeck(p.join(temp.path, 'nope.md'));

    expect(result, isNull);
  });

  test('openDeck returns null for a file exceeding the markdown cap', () async {
    final temp = await Directory.systemTemp.createTemp('ocideck_open_huge_');
    addTearDown(() async {
      if (await temp.exists()) await temp.delete(recursive: true);
    });

    final mdPath = p.join(temp.path, 'huge.md');
    final file = File(mdPath);
    // Write a header plus a body that pushes the file past the size cap.
    final filler = 'x' * 1024;
    final sink = file.openWrite();
    sink.write('---\nmarp: true\n---\n\n# Big\n\n');
    final chunks = (FileService.maxDeckMarkdownBytes ~/ filler.length) + 8;
    for (var i = 0; i < chunks; i++) {
      sink.write(filler);
    }
    await sink.flush();
    await sink.close();

    expect(await file.length(), greaterThan(FileService.maxDeckMarkdownBytes));

    final service = makeService();
    expect(await service.openDeck(mdPath), isNull);
  });

  test('saveDeck then openDeck round-trips title and slide count', () async {
    final temp = await Directory.systemTemp.createTemp('ocideck_roundtrip_');
    addTearDown(() async {
      if (await temp.exists()) await temp.delete(recursive: true);
    });

    final service = makeService();
    final deck = Deck(
      title: 'Round Trip',
      slides: <Slide>[
        Slide.create(SlideType.title).copyWith(title: 'Round Trip'),
        Slide.create(
          SlideType.bullets,
        ).copyWith(title: 'Agenda', bullets: <String>['alpha', 'beta']),
      ],
    );

    final mdPath = p.join(temp.path, 'round_trip.md');
    await service.saveDeck(deck, mdPath);
    expect(await File(mdPath).exists(), isTrue);

    final reopened = await service.openDeck(mdPath);
    expect(reopened, isNotNull);
    expect(reopened!.title, 'Round Trip');
    expect(reopened.slides.length, 2);
  });

  test(
    'scanPresentations finds Marp decks and skips the excluded one',
    () async {
      final temp = await Directory.systemTemp.createTemp('ocideck_scan_');
      addTearDown(() async {
        if (await temp.exists()) await temp.delete(recursive: true);
      });

      final a = p.join(temp.path, 'alpha.md');
      final b = p.join(temp.path, 'beta.md');
      File(a).writeAsStringSync(
        '---\nmarp: true\ntheme: ocideck\n---\n\n# Alpha\n\n- a\n',
      );
      File(b).writeAsStringSync(
        '---\nmarp: true\ntheme: ocideck\n---\n\n# Beta\n\n- b\n',
      );

      final service = makeService();
      final all = await service.scanPresentations(temp.path);
      final names = all.map((s) => s.fileName).toSet();
      expect(names, containsAll(<String>['alpha.md', 'beta.md']));
      // The parsed decks carry their frontmatter titles.
      final titles = all.map((s) => s.deck.title).toSet();
      expect(titles, containsAll(<String>['Alpha', 'Beta']));

      final excluded = await service.scanPresentations(
        temp.path,
        excludePath: a,
      );
      final excludedNames = excluded.map((s) => s.fileName).toSet();
      expect(excludedNames, contains('beta.md'));
      expect(excludedNames, isNot(contains('alpha.md')));
    },
  );

  test('scanPresentations descends deeper than four levels', () async {
    final temp = await Directory.systemTemp.createTemp('ocideck_scan_deep_');
    addTearDown(() async {
      if (await temp.exists()) await temp.delete(recursive: true);
    });

    // Zes mappen diep — voorbij de oude limiet van vier.
    final deep = p.join(temp.path, 'a', 'b', 'c', 'd', 'e', 'f');
    await Directory(deep).create(recursive: true);
    File(p.join(deep, 'diep.md')).writeAsStringSync(
      '---\nmarp: true\ntheme: ocideck\ntitle: Diep\n---\n\n# Diep\n',
    );

    final service = makeService();
    final all = await service.scanPresentations(temp.path);
    expect(all.map((s) => s.fileName), contains('diep.md'));
    expect(all.single.deck.title, 'Diep');
  });

  test('scanPresentations skips a file over the markdown cap', () async {
    final temp = await Directory.systemTemp.createTemp('ocideck_scan_huge_');
    addTearDown(() async {
      if (await temp.exists()) await temp.delete(recursive: true);
    });

    // A normal deck alongside one that blows past the 32 MiB cap.
    File(p.join(temp.path, 'ok.md')).writeAsStringSync(
      '---\nmarp: true\ntheme: ocideck\ntitle: Ok\n---\n\n# Ok\n',
    );
    final huge = File(p.join(temp.path, 'huge.md'));
    final filler = 'x' * 1024;
    final sink = huge.openWrite();
    sink.write('---\nmarp: true\n---\n\n# Big\n\n');
    final chunks = (FileService.maxDeckMarkdownBytes ~/ filler.length) + 8;
    for (var i = 0; i < chunks; i++) {
      sink.write(filler);
    }
    await sink.flush();
    await sink.close();
    expect(await huge.length(), greaterThan(FileService.maxDeckMarkdownBytes));

    final service = makeService();
    final names = (await service.scanPresentations(
      temp.path,
    )).map((s) => s.fileName).toSet();
    expect(names, contains('ok.md'));
    expect(names, isNot(contains('huge.md')));
  });

  test('scanPresentations stops at the cumulative scan budget', () async {
    final temp = await Directory.systemTemp.createTemp('ocideck_scan_budget_');
    addTearDown(() async {
      if (await temp.exists()) await temp.delete(recursive: true);
    });

    // Five equally-sized valid decks; the budget only admits the first two.
    final body = 'x' * 900; // padded so every file is the same, known size.
    late int fileSize;
    for (var i = 0; i < 5; i++) {
      final f = File(p.join(temp.path, 'deck_$i.md'));
      f.writeAsStringSync(
        '---\nmarp: true\ntheme: ocideck\ntitle: Deck$i\n---\n\n# Deck$i\n\n- $body\n',
      );
      fileSize = f.lengthSync();
    }

    final service = makeService();
    // Room for two files, not the third (2*size ≤ budget < 3*size).
    final budget = fileSize * 2 + fileSize ~/ 2;
    final results = await service.scanPresentations(
      temp.path,
      maxScanBytes: budget,
    );
    expect(results.length, 2);
  });

  test('openDeck refuses provided content over the markdown cap', () async {
    final service = makeService();
    final oversized =
        '---\nmarp: true\n---\n\n# Big\n\n${'x' * (FileService.maxDeckMarkdownBytes + 1)}';
    final result = await service.openDeck('memory.md', content: oversized);
    expect(result, isNull);
  });

  test('scanPresentations returns empty for a missing directory', () async {
    final service = makeService();
    final result = await service.scanPresentations(
      p.join(Directory.systemTemp.path, 'ocideck_does_not_exist_xyz'),
    );
    expect(result, isEmpty);
  });

  test('scanKnownLocations probes frontmatter and flags the theme', () async {
    final home = await Directory.systemTemp.createTemp('ocideck_known_home_');
    addTearDown(() async {
      if (await home.exists()) await home.delete(recursive: true);
    });

    final docs = Directory(p.join(home.path, 'Documents'));
    await docs.create(recursive: true);
    File(p.join(docs.path, 'themed.md')).writeAsStringSync(
      '---\nmarp: true\ntheme: ocideck\ntitle: Themed Deck\n---\n\n# Themed\n',
    );
    File(
      p.join(docs.path, 'plain.md'),
    ).writeAsStringSync('---\nmarp: true\ntheme: default\n---\n\n# Plain\n');
    // Geen Marp-bestand: dat is een document, en dat hoort de scan óók te
    // vinden — met de eerste kop als naam.
    File(
      p.join(docs.path, 'ignore.md'),
    ).writeAsStringSync('# no frontmatter here\n');

    final service = makeService(homeDirectory: () => home.path);
    final hits = await service.scanKnownLocations();

    final byName = <String, ScanHit>{for (final h in hits) h.fileName: h};
    expect(byName.keys, containsAll(<String>['themed.md', 'plain.md']));
    final document = byName['ignore.md']!;
    expect(document.kind, MarkdownKind.document);
    expect(document.displayTitle, 'no frontmatter here');
    expect(document.theme, isNull);

    final themed = byName['themed.md']!;
    expect(themed.title, 'Themed Deck');
    expect(themed.isOcideckTheme, isTrue);
    expect(themed.displayTitle, 'Themed Deck');

    final plain = byName['plain.md']!;
    expect(plain.isOcideckTheme, isFalse);
    // No frontmatter title → display falls back to the file's base name.
    expect(plain.displayTitle, 'plain');
  });

  test('exportPackage then importPackageBytes round-trips the deck', () async {
    final temp = await Directory.systemTemp.createTemp(
      'ocideck_pkg_roundtrip_',
    );
    addTearDown(() async {
      if (await temp.exists()) await temp.delete(recursive: true);
    });

    final service = makeService();
    final deck = Deck(
      title: 'Portable Deck',
      slides: <Slide>[
        Slide.create(SlideType.title).copyWith(title: 'Portable Deck'),
        Slide.create(
          SlideType.bullets,
        ).copyWith(title: 'Points', bullets: <String>['x', 'y', 'z']),
      ],
    );

    final destPath = p.join(temp.path, 'portable.ocideck');
    await service.exportPackage(deck, destPath);
    final packageFile = File(destPath);
    expect(await packageFile.exists(), isTrue);

    final importDir = Directory(p.join(temp.path, 'imported'));
    await importDir.create(recursive: true);
    final mdPath = await service.importPackageBytes(
      await packageFile.readAsBytes(),
      importDir.path,
    );

    expect(mdPath, isNotNull);
    expect(p.isWithin(importDir.path, mdPath!), isTrue);
    expect(await File(mdPath).exists(), isTrue);

    final reopened = await service.openDeck(mdPath);
    expect(reopened, isNotNull);
    expect(reopened!.title, 'Portable Deck');
    expect(reopened.slides.length, 2);
  });

  test('importPackageBytes returns null when no markdown is present', () async {
    final temp = await Directory.systemTemp.createTemp('ocideck_pkg_nomd_');
    addTearDown(() async {
      if (await temp.exists()) await temp.delete(recursive: true);
    });

    final service = makeService();
    // Bytes that are not a valid ZIP archive decode to nothing useful.
    final result = await service.importPackageBytes(<int>[
      1,
      2,
      3,
      4,
      5,
      6,
      7,
      8,
    ], temp.path);
    expect(result, isNull);
  });
}
