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
    // Not a Marp file: probe must skip it.
    File(
      p.join(docs.path, 'ignore.md'),
    ).writeAsStringSync('# no frontmatter here\n');

    final service = makeService(homeDirectory: () => home.path);
    final hits = await service.scanKnownLocations();

    final byName = <String, ScanHit>{for (final h in hits) h.fileName: h};
    expect(byName.keys, containsAll(<String>['themed.md', 'plain.md']));
    expect(byName.containsKey('ignore.md'), isFalse);

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
