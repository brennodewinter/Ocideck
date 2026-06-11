import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:ocideck/services/image_dedup_service.dart';

void main() {
  late Directory tmp;
  final service = ImageDedupService();

  setUp(() => tmp = Directory.systemTemp.createTempSync('ocideck_dedup'));
  tearDown(() => tmp.deleteSync(recursive: true));

  String write(String name, List<int> bytes) {
    final file = File(p.join(tmp.path, name))..writeAsBytesSync(bytes);
    return file.path;
  }

  group('findDuplicateGroups', () {
    test('groups byte-identical files and leaves unique files out', () async {
      final a1 = write('a1.png', [1, 2, 3, 4]);
      final a2 = write('a2.png', [1, 2, 3, 4]);
      final b = write('b.png', [9, 9, 9]);

      final groups = await service.findDuplicateGroups([a1, a2, b]);

      expect(groups, hasLength(1));
      expect(groups.single, unorderedEquals([a1, a2]));
    });

    test('same size but different content is not a duplicate', () async {
      final a = write('a.png', [1, 2, 3, 4]);
      final b = write('b.png', [4, 3, 2, 1]);

      expect(await service.findDuplicateGroups([a, b]), isEmpty);
    });

    test('finds multiple independent groups', () async {
      final a1 = write('a1.png', [1, 2, 3]);
      final a2 = write('a2.png', [1, 2, 3]);
      final b1 = write('b1.png', [7, 7, 7, 7]);
      final b2 = write('b2.png', [7, 7, 7, 7]);
      final b3 = write('b3.png', [7, 7, 7, 7]);

      final groups = await service.findDuplicateGroups([a1, a2, b1, b2, b3]);

      expect(groups, hasLength(2));
      final bySize = {for (final g in groups) g.length: g};
      expect(bySize[2], unorderedEquals([a1, a2]));
      expect(bySize[3], unorderedEquals([b1, b2, b3]));
    });

    test('silently skips missing files', () async {
      final a1 = write('a1.png', [1, 2, 3]);
      final a2 = write('a2.png', [1, 2, 3]);
      final gone = p.join(tmp.path, 'bestaat-niet.png');

      final groups = await service.findDuplicateGroups([a1, gone, a2]);

      expect(groups, hasLength(1));
      expect(groups.single, unorderedEquals([a1, a2]));
    });
  });

  group('chooseKeeper', () {
    test('prefers the path with the most slide usages', () {
      final a = write('a.png', [1]);
      final b = write('b.png', [1]);

      final keeper = service.chooseKeeper([
        a,
        b,
      ], usageCountOf: (path) => path == b ? 2 : 0);

      expect(keeper, b);
    });

    test('falls back to the oldest file when usages are equal', () {
      final newer = write('newer.png', [1]);
      final older = write('older.png', [1]);
      File(
        older,
      ).setLastModifiedSync(DateTime.now().subtract(const Duration(days: 7)));

      expect(service.chooseKeeper([newer, older]), older);
    });
  });

  group('mergeMetadata', () {
    test('joins unique non-empty values', () {
      expect(
        service.mergeMetadata(['boot', null, '', 'haven'], separator: ', '),
        'boot, haven',
      );
    });

    test('drops values already contained in an earlier one', () {
      expect(
        service.mergeMetadata(['Boot in de haven', 'boot']),
        'Boot in de haven',
      );
    });

    test('returns empty string when nothing is set', () {
      expect(service.mergeMetadata([null, '', '  ']), '');
    });
  });
}
