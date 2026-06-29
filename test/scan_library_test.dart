import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/models/settings.dart';
import 'package:ocideck/services/file_service.dart';
import 'package:ocideck/services/image_service.dart';
import 'package:ocideck/services/markdown_service.dart';
import 'package:path/path.dart' as p;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('MarkdownService.sniffFrontmatter', () {
    final md = MarkdownService();

    test('detects marp:true and reads theme/title', () {
      final fm = md.sniffFrontmatter(
        '---\nmarp: true\ntheme: ocideck\ntitle: "Hello"\n---\n# Body\n',
      );
      expect(fm.marp, isTrue);
      expect(fm.theme, 'ocideck');
      expect(fm.title, 'Hello');
    });

    test('marp:false and missing marp both report not-marp', () {
      expect(md.sniffFrontmatter('---\nmarp: false\n---\n').marp, isFalse);
      expect(md.sniffFrontmatter('---\ntheme: ocideck\n---\n').marp, isFalse);
    });

    test('no frontmatter is not marp', () {
      expect(md.sniffFrontmatter('# Just a heading\n').marp, isFalse);
    });

    test('truncated header without closing --- still parses', () {
      // Only the first slice of a large file is read; the closing fence may be
      // beyond the cut, but the header lines we have must still be read.
      final fm = md.sniffFrontmatter('---\nmarp: true\ntheme: custom\n');
      expect(fm.marp, isTrue);
      expect(fm.theme, 'custom');
    });

    test('CRLF line endings are handled', () {
      final fm = md.sniffFrontmatter(
        '---\r\nmarp: true\r\ntheme: ocideck\r\n---\r\n',
      );
      expect(fm.marp, isTrue);
      expect(fm.theme, 'ocideck');
    });
  });

  group('FileService.scanKnownLocations', () {
    late Directory temp;
    late FileService service;

    Future<File> writeMd(String relPath, String content) async {
      final file = File(p.join(temp.path, relPath));
      await file.parent.create(recursive: true);
      await file.writeAsString(content);
      return file;
    }

    setUp(() async {
      temp = await Directory.systemTemp.createTemp('ocideck_scan_test_');
      // homeDirectory override points at temp so the scan never walks the real
      // ~/Documents etc. (those temp/Documents paths simply don't exist).
      service = FileService(
        MarkdownService(),
        ImageService(),
        () => const ThemeProfile(),
        homeDirectory: () => temp.path,
      );
    });

    tearDown(() async {
      if (await temp.exists()) await temp.delete(recursive: true);
    });

    test('returns only marp decks, ocideck theme first', () async {
      final oci = await writeMd(
        'decks/a.md',
        '---\nmarp: true\ntheme: ocideck\ntitle: Zeta\n---\n# A\n',
      );
      final other = await writeMd(
        'decks/b.md',
        '---\nmarp: true\ntheme: gaia\ntitle: Alpha\n---\n# B\n',
      );
      // Not Marp → excluded.
      await writeMd('decks/c.md', '# plain markdown\n');
      // marp:false → excluded.
      await writeMd('decks/d.md', '---\nmarp: false\n---\n# D\n');

      final hits = await service.scanKnownLocations(
        recentFiles: [p.join(temp.path, 'decks', 'a.md')],
      );

      expect(hits.map((h) => h.path), [oci.path, other.path]);
      expect(hits.first.isOcideckTheme, isTrue);
      expect(hits.first.theme, 'ocideck');
      expect(hits[1].isOcideckTheme, isFalse);
      expect(hits[1].theme, 'gaia');
    });

    test('ignored and denylisted directories are skipped', () async {
      await writeMd('good.md', '---\nmarp: true\ntheme: ocideck\n---\n# ok\n');
      await writeMd(
        'node_modules/skip.md',
        '---\nmarp: true\ntheme: ocideck\n---\n# no\n',
      );
      await writeMd(
        'Library/skip.md',
        '---\nmarp: true\ntheme: ocideck\n---\n# no\n',
      );
      await writeMd(
        '.hidden/skip.md',
        '---\nmarp: true\ntheme: ocideck\n---\n# no\n',
      );

      final hits = await service.scanKnownLocations(
        recentFiles: [p.join(temp.path, 'good.md')],
      );

      expect(hits.length, 1);
      expect(p.basename(hits.single.path), 'good.md');
    });

    test('maxMatches caps the number of results', () async {
      for (var i = 0; i < 5; i++) {
        await writeMd(
          'many/d$i.md',
          '---\nmarp: true\ntheme: ocideck\n---\n# d$i\n',
        );
      }
      final hits = await service.scanKnownLocations(
        recentFiles: [p.join(temp.path, 'many', 'd0.md')],
        maxMatches: 3,
      );
      expect(hits.length, lessThanOrEqualTo(3));
    });

    test('falls back to file name when title is absent', () async {
      await writeMd(
        'untitled.md',
        '---\nmarp: true\ntheme: ocideck\n---\n# body\n',
      );
      final hits = await service.scanKnownLocations(
        recentFiles: [p.join(temp.path, 'untitled.md')],
      );
      expect(hits.single.displayTitle, 'untitled');
    });
  });
}
