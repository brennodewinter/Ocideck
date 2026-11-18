@TestOn('vm')
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../tool/check_bundled_docs_fresh.dart';
import '../tool/web_bundle_assets.dart';

void main() {
  late Directory root;
  late Directory assets;
  setUp(() {
    root = Directory.systemTemp.createTempSync('ocideck-hashed-assets-');
    assets = Directory('${root.path}/assets')..createSync();
  });
  tearDown(() => root.deleteSync(recursive: true));

  File put(String name) {
    final file = File('${assets.path}/$name');
    file.parent.createSync(recursive: true);
    return file..writeAsStringSync('current bytes');
  }

  test('finds docs and fonts with Flutter content hashes', () {
    final guide = put('docs/USER_GUIDE.1234abcd.md');
    final font = put('assets/fonts/Roboto-Variable.abcdef12.ttf');
    expect(findAssetsDir(root)?.path, assets.path);
    expect(bundledAsset(assets, 'docs/USER_GUIDE.md')?.path, guide.path);
    expect(
      bundledAsset(assets, 'assets/fonts/Roboto-Variable.ttf')?.path,
      font.path,
    );
    final notice = put('NOTICES.12345678');
    expect(bundledAsset(assets, 'NOTICES')?.path, notice.path);
  });

  test('keeps ordinary desktop and previous web layouts working', () {
    final guide = put('docs/USER_GUIDE.md');
    expect(findAssetsDir(root)?.path, assets.path);
    expect(bundledAsset(assets, 'docs/USER_GUIDE.md')?.path, guide.path);
  });

  test('rejects ambiguous incremental output and similar names', () {
    put('docs/USER_GUIDE.1234abcd.md');
    put('docs/USER_GUIDE.abcdef12.md');
    put('docs/OTHER_GUIDE.1234abcd.md');
    expect(bundledAsset(assets, 'docs/USER_GUIDE.md'), isNull);
    expect(bundledAsset(assets, 'docs/GUIDE.md'), isNull);
    expect(bundledAsset(assets, 'missing/GUIDE.md'), isNull);
  });
}
