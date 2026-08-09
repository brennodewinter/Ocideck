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

  group('unwritable destination (ingestelde thuismap op weg-volume)', () {
    // Regressie voor #open-ocideck-package: een ingestelde thuismap op een
    // niet-aangekoppeld/alleen-lezen volume liet het uitpakken een niet-gevangen
    // PathAccessException gooien die stil verdween — het deck opende niet en er
    // kwam geen melding. Nu een gerichte weiger-reden, en géén worp.
    //
    // Een doelmap die niet aan te maken is, wordt hier nagebootst door hem ónder
    // een gewoon bestand te leggen: `create(recursive: true)` faalt dan met een
    // FileSystemException, net als op een weg-volume.
    Future<String> unwritableParent() async {
      final temp = await Directory.systemTemp.createTemp('ocideck_nowrite_');
      addTearDown(() async {
        if (await temp.exists()) await temp.delete(recursive: true);
      });
      final blocker = File(p.join(temp.path, 'blocker'));
      await blocker.writeAsString('ik ben een bestand, geen map');
      return p.join(blocker.path, 'eronder');
    }

    FileService service() => FileService(
      MarkdownService(),
      ImageService(),
      () => const ThemeProfile(),
    );

    test('importPackageBytesDetailed meldt destinationUnavailable i.p.v. te '
        'gooien', () async {
      final archive = Archive();
      final md = utf8.encode('---\nmarp: true\n---\n# Hi');
      archive.addFile(ArchiveFile('deck.md', md.length, md));
      final zipBytes = ZipEncoder().encode(archive);

      final outcome = await service().importPackageBytesDetailed(
        zipBytes,
        await unwritableParent(),
      );

      expect(outcome.mdPath, isNull);
      expect(outcome.failure, ImportFailure.destinationUnavailable);
    });

    test('importMarkdownBytesDetailed meldt destinationUnavailable i.p.v. te '
        'gooien', () async {
      final bytes = utf8.encode('---\nmarp: true\n---\n# Hi');

      final outcome = await service().importMarkdownBytesDetailed(
        bytes,
        await unwritableParent(),
        'deck.md',
      );

      expect(outcome.mdPath, isNull);
      expect(outcome.failure, ImportFailure.destinationUnavailable);
    });

    test(
      'een schrijfbare doelmap slaagt gewoon (geen valse terugval)',
      () async {
        final temp = await Directory.systemTemp.createTemp('ocideck_ok_');
        addTearDown(() async {
          if (await temp.exists()) await temp.delete(recursive: true);
        });
        final archive = Archive();
        final md = utf8.encode('---\nmarp: true\n---\n# Hi');
        archive.addFile(ArchiveFile('deck.md', md.length, md));

        final outcome = await service().importPackageBytesDetailed(
          ZipEncoder().encode(archive),
          temp.path,
        );

        expect(outcome.failure, isNull);
        expect(outcome.mdPath, isNotNull);
        expect(await File(outcome.mdPath!).exists(), isTrue);
      },
    );
  });

  test('importPackageBytes extracts a normal multi-file package', () async {
    final temp = await Directory.systemTemp.createTemp('ocideck_zip_ok_');
    addTearDown(() async {
      if (await temp.exists()) await temp.delete(recursive: true);
    });

    final archive = Archive();
    final md = utf8.encode('---\nmarp: true\n---\n# Hi');
    archive.addFile(ArchiveFile('deck.md', md.length, md));
    final png = utf8.encode('not-really-a-png-but-bytes');
    archive.addFile(ArchiveFile('images/pic.png', png.length, png));
    final zipBytes = ZipEncoder().encode(archive);

    final service = FileService(
      MarkdownService(),
      ImageService(),
      () => const ThemeProfile(),
    );
    final mdPath = await service.importPackageBytes(zipBytes, temp.path);

    expect(mdPath, isNotNull);
    expect(await File(mdPath!).exists(), isTrue);
    final asset = File(p.join(p.dirname(mdPath), 'images', 'pic.png'));
    expect(await asset.exists(), isTrue);
    expect(await asset.readAsBytes(), png);
  });

  test('importPackageBytes reuses an earlier identical import', () async {
    final temp = await Directory.systemTemp.createTemp('ocideck_zip_reuse_');
    addTearDown(() async {
      if (await temp.exists()) await temp.delete(recursive: true);
    });

    final archive = Archive();
    final md = utf8.encode('---\nmarp: true\n---\n# Hi');
    archive.addFile(ArchiveFile('deck.md', md.length, md));
    final png = utf8.encode('fake-png-bytes');
    archive.addFile(ArchiveFile('images/pic.png', png.length, png));
    final zipBytes = ZipEncoder().encode(archive);

    final service = FileService(
      MarkdownService(),
      ImageService(),
      () => const ThemeProfile(),
    );
    final first = await service.importPackageBytes(zipBytes, temp.path);
    final second = await service.importPackageBytes(zipBytes, temp.path);

    // Same package again: same extraction folder, no "deck (2)" copy.
    expect(second, first);
    final dirs = temp.listSync().whereType<Directory>().toList();
    expect(dirs, hasLength(1));

    // Sidecars the app writes next to the markdown (annotations, notes) do
    // not block reuse: nothing gets overwritten by reusing the folder.
    final sidecar = File(p.join(p.dirname(first!), 'deck.ink.json'));
    await sidecar.writeAsString('{"strokes":[]}');
    final third = await service.importPackageBytes(zipBytes, temp.path);
    expect(third, first);
    expect(await sidecar.exists(), isTrue);
  });

  test('importPackageBytes keeps an edited copy and extracts fresh', () async {
    final temp = await Directory.systemTemp.createTemp('ocideck_zip_edit_');
    addTearDown(() async {
      if (await temp.exists()) await temp.delete(recursive: true);
    });

    final archive = Archive();
    final md = utf8.encode('---\nmarp: true\n---\n# Hi');
    archive.addFile(ArchiveFile('deck.md', md.length, md));
    final zipBytes = ZipEncoder().encode(archive);

    final service = FileService(
      MarkdownService(),
      ImageService(),
      () => const ThemeProfile(),
    );
    final first = await service.importPackageBytes(zipBytes, temp.path);
    // The user edited the extracted copy; a re-import must not clobber it.
    await File(first!).writeAsString('---\nmarp: true\n---\n# Edited');
    final second = await service.importPackageBytes(zipBytes, temp.path);

    expect(second, isNot(first));
    expect(p.basename(p.dirname(second!)), 'deck (2)');
    expect(await File(first).readAsString(), '---\nmarp: true\n---\n# Edited');
  });

  test(
    'importMarkdownBytes reuses identical markdown, copies on change',
    () async {
      final temp = await Directory.systemTemp.createTemp('ocideck_md_reuse_');
      addTearDown(() async {
        if (await temp.exists()) await temp.delete(recursive: true);
      });

      final service = FileService(
        MarkdownService(),
        ImageService(),
        () => const ThemeProfile(),
      );
      final bytes = utf8.encode('---\nmarp: true\n---\n# Hi');
      final first = await service.importMarkdownBytes(
        bytes,
        temp.path,
        'Demo.md',
      );
      final second = await service.importMarkdownBytes(
        bytes,
        temp.path,
        'Demo.md',
      );
      expect(second, first);

      final changed = utf8.encode('---\nmarp: true\n---\n# Changed');
      final third = await service.importMarkdownBytes(
        changed,
        temp.path,
        'Demo.md',
      );
      expect(third, isNot(first));
      expect(p.basename(p.dirname(third!)), 'Demo (2)');
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
    final oversized = List<int>.filled(17, 0);
    expect(
      await service.importPackageBytes(oversized, temp.path, maxBytes: 16),
      isNull,
    );
  });

  test(
    'importPackageBytes aborts when decompressed size exceeds limit',
    () async {
      final temp = await Directory.systemTemp.createTemp('ocideck_zip_bomb_');
      addTearDown(() async {
        if (await temp.exists()) await temp.delete(recursive: true);
      });

      final archive = Archive();
      final md = utf8.encode('---\nmarp: true\n---\n# Hi');
      archive.addFile(ArchiveFile('deck.md', md.length, md));
      final huge = List<int>.filled(2048, 0);
      archive.addFile(ArchiveFile('images/huge.bin', huge.length, huge));
      final zipBytes = ZipEncoder().encode(archive);
      final maxBytes = zipBytes.length + 1;

      final service = FileService(
        MarkdownService(),
        ImageService(),
        () => const ThemeProfile(),
      );
      expect(huge.length + md.length, greaterThan(maxBytes));
      final outcome = await service.importPackageBytesDetailed(
        zipBytes,
        temp.path,
        maxBytes: maxBytes,
      );
      expect(outcome.mdPath, isNull);
      expect(outcome.failure, ImportFailure.limitExceeded);
      // Een afgebroken extractie ruimt de half uitgepakte map weer op.
      expect(temp.listSync(), isEmpty);
    },
  );

  test('importPackageBytesDetailed names the refusal reason', () async {
    final temp = await Directory.systemTemp.createTemp('ocideck_zip_reason_');
    addTearDown(() async {
      if (await temp.exists()) await temp.delete(recursive: true);
    });
    final service = FileService(
      MarkdownService(),
      ImageService(),
      () => const ThemeProfile(),
    );

    // Een pseudo-zip levert bij de tolerante decoder een leeg archief op:
    // geen markdown → unsupported.
    final notAZip = await service.importPackageBytesDetailed(
      utf8.encode('PK\x03\x04not-a-zip'),
      temp.path,
    );
    expect(notAZip.failure, ImportFailure.unsupported);

    // Ongeldig UTF-8 in een los markdownbestand → corrupt.
    final badUtf8 = await service.importMarkdownBytesDetailed(
      [0xC3, 0x28, 0xA0, 0xA1],
      temp.path,
      'kapot.md',
    );
    expect(badUtf8.failure, ImportFailure.corrupt);

    // Zip zonder markdown → unsupported.
    final archive = Archive();
    final png = utf8.encode('bytes');
    archive.addFile(ArchiveFile('images/pic.png', png.length, png));
    final noMd = await service.importPackageBytesDetailed(
      ZipEncoder().encode(archive),
      temp.path,
    );
    expect(noMd.failure, ImportFailure.unsupported);

    // Te groot → tooLarge.
    final tooBig = await service.importPackageBytesDetailed(
      List<int>.filled(17, 0),
      temp.path,
      maxBytes: 16,
    );
    expect(tooBig.failure, ImportFailure.tooLarge);
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

  test(
    'openDeck always refuses markdown with executable content (fail-closed)',
    () async {
      final temp = await Directory.systemTemp.createTemp(
        'ocideck_unsafe_open_',
      );
      addTearDown(() async {
        if (await temp.exists()) await temp.delete(recursive: true);
      });

      final service = FileService(
        MarkdownService(),
        ImageService(),
        () => const ThemeProfile(),
      );
      final unsafe = p.join(temp.path, 'unsafe.md');
      await File(unsafe).writeAsString(
        '---\nmarp: true\ntitle: X\n---\n\n# Hi\n\n<script>steal()</script>\n',
      );
      // The scanner reports it and openDeck refuses it — there is no trust bypass.
      expect(await service.scanForUnsafeMarkdown(unsafe), isNotEmpty);
      expect(await service.openDeck(unsafe), isNull);

      // A clean deck on the same path opens normally.
      final safe = p.join(temp.path, 'safe.md');
      await File(safe).writeAsString(
        '---\nmarp: true\ntitle: Y\n---\n\n# Hi\n\n- data only\n',
      );
      expect(await service.openDeck(safe), isNotNull);
    },
  );

  test('openDeck only opens Marp/OciDeck presentations', () async {
    final temp = await Directory.systemTemp.createTemp('ocideck_marp_check_');
    addTearDown(() async {
      if (await temp.exists()) await temp.delete(recursive: true);
    });
    final service = FileService(
      MarkdownService(),
      ImageService(),
      () => const ThemeProfile(),
    );

    // A plain markdown file (no `marp: true`) picked from anywhere is refused,
    // so it can't open as a blank/garbled deck.
    final plain = p.join(temp.path, 'README.md');
    await File(plain).writeAsString('# Just notes\n\nSome text, not a deck.\n');
    expect(await service.openDeck(plain), isNull);

    // A Marp presentation living outside any library folder opens fine.
    final loose = p.join(temp.path, 'elders.md');
    await File(loose).writeAsString(
      '---\nmarp: true\ntitle: Elders\n---\n\n# Titel\n\n- punt\n',
    );
    expect(await service.openDeck(loose), isNotNull);
  });

  test('openDeckDetailed reports why a file could not open', () async {
    final temp = await Directory.systemTemp.createTemp('ocideck_open_why_');
    addTearDown(() async {
      if (await temp.exists()) await temp.delete(recursive: true);
    });
    final service = FileService(
      MarkdownService(),
      ImageService(),
      () => const ThemeProfile(),
    );
    Future<OpenFailure?> failureFor(String name, String body) async {
      final path = p.join(temp.path, name);
      await File(path).writeAsString(body);
      return (await service.openDeckDetailed(path)).failure;
    }

    expect(
      (await service.openDeckDetailed(p.join(temp.path, 'gone.md'))).failure,
      OpenFailure.notFound,
    );
    expect(
      await failureFor('readme.md', '# Plain notes, not a deck\n'),
      OpenFailure.notPresentation,
    );
    expect(
      await failureFor('trunc.md', '---\nmarp: true\ntitle: X\n---\n'),
      OpenFailure.corrupt,
    );
    expect(
      await failureFor(
        'unsafe.md',
        '---\nmarp: true\n---\n\n# Hi\n\n<script>x()</script>\n',
      ),
      OpenFailure.unsafe,
    );

    final ok = p.join(temp.path, 'ok.md');
    await File(
      ok,
    ).writeAsString('---\nmarp: true\ntitle: Y\n---\n\n# Hi\n\n- a\n');
    final good = await service.openDeckDetailed(ok);
    expect(good.failure, isNull);
    expect(good.deck, isNotNull);
  });

  test('scanPresentations skips hidden and ignored directories', () async {
    final temp = await Directory.systemTemp.createTemp('ocideck_scan_hidden_');
    addTearDown(() async {
      if (await temp.exists()) await temp.delete(recursive: true);
    });
    const deck = '---\nmarp: true\ntitle: T\n---\n\n# Hi\n\n- a\n';
    // A deck in a hidden subfolder must not be scanned.
    final hidden = Directory(p.join(temp.path, '.cache'));
    await hidden.create();
    await File(p.join(hidden.path, 'secret.md')).writeAsString(deck);
    // One in a normal folder is found.
    await File(p.join(temp.path, 'visible.md')).writeAsString(deck);

    final service = FileService(
      MarkdownService(),
      ImageService(),
      () => const ThemeProfile(),
    );
    final names = (await service.scanPresentations(
      temp.path,
    )).map((r) => r.fileName).toList();
    expect(names, contains('visible.md'));
    expect(names, isNot(contains('secret.md')));
  });

  test('saveDeck keeps an already-relative logos/ logo path as-is', () async {
    final temp = await Directory.systemTemp.createTemp('ocideck_rellogo_');
    addTearDown(() async {
      if (await temp.exists()) await temp.delete(recursive: true);
    });
    // The logo is already a project-relative logos/ path: it must be kept,
    // not re-copied or mangled.
    final service = FileService(
      MarkdownService(),
      ImageService(),
      () => const ThemeProfile(logoPath: 'logos/client.png'),
    );
    final deck = Deck(
      title: 'Rel logo',
      themeProfile: const ThemeProfile(logoPath: 'logos/client.png'),
      slides: [Slide.create(SlideType.title).copyWith(title: 'Rel logo')],
    );
    final saved = await service.saveDeck(deck, p.join(temp.path, 'deck.md'));
    expect(saved.themeProfile.logoPath, 'logos/client.png');
  });
}
