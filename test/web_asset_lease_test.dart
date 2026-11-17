import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/services/web_asset_store.dart';

void main() {
  setUp(WebAssetStore.clear);
  tearDown(WebAssetStore.clear);

  String put(int byte) =>
      WebAssetStore.put(Uint8List.fromList([byte]), name: '$byte.bin');

  test('twee leases delen bytes maar geven eigendom onafhankelijk vrij', () {
    final unregister = WebAssetStore.registerRoots(() => {});
    addTearDown(unregister);
    final path = put(1);
    final a = WebAssetStore.lease([path]);
    final b = WebAssetStore.lease([put(1)]);
    expect(WebAssetStore.totalBytes, 1);
    expect(WebAssetStore.retain({}), 0);
    a.release();
    a.release();
    expect(WebAssetStore.bytesFor(path), [1]);
    b.release();
    expect(WebAssetStore.bytesFor(path), isNull);
    expect(WebAssetStore.totalBytes, 0);
  });

  test(
    'vrijgeven gebruikt actuele documentwortels zonder voorafgaande sweep',
    () {
      final roots = <String>{};
      addTearDown(WebAssetStore.registerRoots(() => roots));
      final path = put(2);
      final lease = WebAssetStore.lease([path]);
      roots.add(path);
      lease.release();
      expect(WebAssetStore.bytesFor(path), [2]);
      roots.clear();
      expect(WebAssetStore.collectGarbage(), 1);
      expect(WebAssetStore.totalBytes, 0);
    },
  );

  test(
    'verschillende scopes en toegevoegde decodebytes blijven onafhankelijk',
    () {
      final image = put(3);
      final style = put(4);
      final source = put(5);
      final decoded = put(6);
      final removeImage = WebAssetStore.registerRoots(() => {image});
      addTearDown(removeImage);
      addTearDown(WebAssetStore.registerRoots(() => {style}));
      final job = WebAssetStore.lease([source])..add(decoded);
      expect(WebAssetStore.retain({}), 0);
      job.release();
      expect(WebAssetStore.bytesFor(source), isNull);
      expect(WebAssetStore.bytesFor(decoded), isNull);
      expect(WebAssetStore.bytesFor(image), [3]);
      expect(WebAssetStore.bytesFor(style), [4]);
      removeImage();
      WebAssetStore.collectGarbage();
      expect(WebAssetStore.bytesFor(image), isNull);
      expect(WebAssetStore.bytesFor(style), [4]);
    },
  );

  test('oude dubbele release kan een volgende taak niet ontkoppelen', () {
    addTearDown(WebAssetStore.registerRoots(() => {}));
    final path = put(7);
    final first = WebAssetStore.lease([path]);
    final second = WebAssetStore.lease([path]);
    first.release();
    first.release();
    WebAssetStore.retain({});
    expect(WebAssetStore.bytesFor(path), [7]);
    second.release();
    expect(WebAssetStore.totalBytes, 0);
    expect(() => first.add(path), throwsStateError);
  });

  test(
    'zonder volledige wortelregistratie verwijdert release geen vreemde assets',
    () {
      final path = put(8);
      WebAssetStore.lease([path]).release();
      expect(WebAssetStore.bytesFor(path), [8]);
      expect(WebAssetStore.retain({}), 1);
    },
  );
}
