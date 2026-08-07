import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/utils/image_search_paths.dart';

void main() {
  group('deckImageSearchPaths', () {
    test('project images + project + libraries', () {
      expect(
        deckImageSearchPaths('/deck', ['/lib-a', '/lib-b']),
        ['/deck/images', '/deck', '/lib-a', '/lib-b'],
      );
    });

    test('zonder project alleen bibliotheken', () {
      expect(deckImageSearchPaths(null, ['/lib']), ['/lib']);
    });
  });

  group('documentImageSearchPaths', () {
    test('bibliotheken eerst, daarna alleen images naast het document', () {
      expect(
        documentImageSearchPaths('/Users/me/Desktop', ['/lib-a', '/lib-b']),
        ['/lib-a', '/lib-b', '/Users/me/Desktop/images'],
      );
    });

    test('geen Desktop-root — die zou de bestandsgrens vullen', () {
      final paths = documentImageSearchPaths('/Users/me/Desktop', [
        '/library',
      ]);
      expect(paths, isNot(contains('/Users/me/Desktop')));
      expect(paths.first, '/library');
    });

    test('zonder documentmap alleen bibliotheken', () {
      expect(documentImageSearchPaths(null, ['/lib']), ['/lib']);
    });

    test('open presentaties leveren images + projectmap (zoals presentatiemodus)', () {
      expect(
        documentImageSearchPaths(
          '/doc',
          ['/lib'],
          openDeckProjectPaths: ['/deck-a', '/deck-b'],
        ),
        [
          '/lib',
          '/deck-a/images',
          '/deck-a',
          '/deck-b/images',
          '/deck-b',
          '/doc/images',
        ],
      );
    });

    test('recente presentaties leveren images/logos, niet de hele map', () {
      final paths = documentImageSearchPaths(
        null,
        ['/lib'],
        recentPresentationDirectories: ['/Users/me/Desktop', '/presentaties'],
      );
      expect(paths, [
        '/lib',
        '/Users/me/Desktop/images',
        '/Users/me/Desktop/logos',
        '/presentaties/images',
        '/presentaties/logos',
      ]);
      expect(paths, isNot(contains('/Users/me/Desktop')));
    });

    test('dubbele paden worden één keer gehouden', () {
      expect(
        documentImageSearchPaths(
          '/deck',
          ['/deck'],
          openDeckProjectPaths: ['/deck'],
        ),
        ['/deck', '/deck/images'],
      );
    });
  });
}
