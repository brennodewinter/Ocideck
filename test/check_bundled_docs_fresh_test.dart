import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../tool/check_bundled_docs_fresh.dart';

void main() {
  group('compareDocs', () {
    List<int> bytes(String s) => s.codeUnits;

    test('reports nothing when every built copy matches its source', () {
      final result = compareDocs(
        source: {'docs/A.md': bytes('alpha'), 'LICENSE.md': bytes('eupl')},
        bundled: {'docs/A.md': bytes('alpha'), 'LICENSE.md': bytes('eupl')},
      );
      expect(result.ok, isTrue);
      expect(result.checked, 2);
      expect(result.stale, isEmpty);
      expect(result.missing, isEmpty);
    });

    test('flags a built copy whose bytes differ as stale', () {
      final result = compareDocs(
        source: {'docs/A.md': bytes('new text')},
        bundled: {'docs/A.md': bytes('old text')},
      );
      expect(result.ok, isFalse);
      expect(result.stale, ['docs/A.md']);
      expect(result.missing, isEmpty);
    });

    test('flags a doc absent from the build as missing', () {
      final result = compareDocs(
        source: {'docs/A.md': bytes('alpha')},
        bundled: {'docs/A.md': null},
      );
      expect(result.ok, isFalse);
      expect(result.missing, ['docs/A.md']);
      expect(result.stale, isEmpty);
    });

    test('a length difference alone counts as stale', () {
      final result = compareDocs(
        source: {'docs/A.md': bytes('alpha')},
        bundled: {'docs/A.md': bytes('alph')},
      );
      expect(result.stale, ['docs/A.md']);
    });

    test('sorts the reported paths for stable output', () {
      final result = compareDocs(
        source: {
          'docs/B.md': bytes('x'),
          'docs/A.md': bytes('x'),
          'docs/C.md': bytes('x'),
        },
        bundled: {
          'docs/B.md': bytes('y'),
          'docs/A.md': bytes('y'),
          'docs/C.md': bytes('y'),
        },
      );
      expect(result.stale, ['docs/A.md', 'docs/B.md', 'docs/C.md']);
    });
  });

  group('declaredMarkdownAssets', () {
    test('extracts the .md asset lines and ignores everything else', () {
      const pubspec = '''
flutter:
  assets:
    - assets/templates/
    - LICENSE.md
    - CONTRIBUTORS.md
    - docs/USER_GUIDE.md
    - docs/PRIVACY.md
    - assets/images/logo.png
''';
      expect(declaredMarkdownAssets(pubspec), [
        'CONTRIBUTORS.md',
        'LICENSE.md',
        'docs/PRIVACY.md',
        'docs/USER_GUIDE.md',
      ]);
    });

    test('matches the real pubspec.yaml keep-set (docs are bundled)', () {
      // Sanity against the actual manifest: the curated docs must be declared,
      // and the repo-only ones must not — the same split the reader enforces.
      final assets = declaredMarkdownAssets(
        File('pubspec.yaml').readAsStringSync(),
      );
      expect(assets, contains('docs/USER_GUIDE.md'));
      expect(assets, contains('docs/SECURITY_DESIGN.md'));
      expect(assets, contains('LICENSE.md'));
      expect(assets, isNot(contains('docs/ARCHITECTURE.md')));
      expect(assets, isNot(contains('docs/design/OCIWACHT.md')));
    });
  });
}
