import 'package:archive/archive.dart';
import 'package:ocideck/models/deck.dart';
import 'package:ocideck/models/slide.dart';
import 'package:ocideck/models/settings.dart';
import 'package:ocideck/services/file_service.dart';
import 'package:ocideck/services/markdown_service.dart';
import 'package:ocideck/services/image_service.dart';
import 'package:ocideck/services/web_asset_store.dart';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/services/browser_deck_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test(
    'browser packages survive a fresh store and replace by id, not title',
    () async {
      final store = BrowserDeckStore();
      final id = await store.save('Deck', Uint8List.fromList([1, 2, 3]));
      await store.save('Deck', Uint8List.fromList([4]));
      await store.save('Renamed', Uint8List.fromList([5, 6]), id: id);
      final loaded = await BrowserDeckStore().list();
      expect(loaded, hasLength(2));
      expect(loaded.singleWhere((e) => e.id == id).bytes, [5, 6]);
      expect(loaded.singleWhere((e) => e.id == id).title, 'Renamed');
      await store.remove(id);
      expect(await store.list(), hasLength(1));
    },
  );

  test('quota rejection preserves the previously saved package', () async {
    final store = BrowserDeckStore();
    final id = await store.save('Original', Uint8List.fromList([1]));
    await expectLater(
      store.save(
        'Too large',
        Uint8List(BrowserDeckStore.maxEncodedLength),
        id: id,
      ),
      throwsStateError,
    );
    expect((await store.list()).single.bytes, [1]);
  });

  test('concurrent writes retain both presentations', () async {
    await Future.wait([
      BrowserDeckStore().save('A', Uint8List(1)),
      BrowserDeckStore().save('B', Uint8List(1)),
    ]);
    expect(await BrowserDeckStore().list(), hasLength(2));
  });

  test('reset clears settings and keeps browser presentations', () async {
    final id = await BrowserDeckStore().save('Keep', Uint8List.fromList([1]));
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('privacyChecksEnabled', false);
    await clearSettingsPreservingBrowserDecks(prefs);
    expect(prefs.containsKey('privacyChecksEnabled'), isFalse);
    expect((await BrowserDeckStore().list()).single.id, id);
  });

  test('damaged storage is not silently overwritten', () async {
    SharedPreferences.setMockInitialValues({
      '${BrowserDeckStore.key}broken': 'damaged',
    });
    await expectLater(
      BrowserDeckStore().save('A', Uint8List(1)),
      throwsFormatException,
    );
    expect(
      (await SharedPreferences.getInstance()).getString(
        '${BrowserDeckStore.key}broken',
      ),
      'damaged',
    );
  });

  test('package bytes are independent of browser memory asset paths', () async {
    final image = Uint8List.fromList([
      0x89,
      0x50,
      0x4e,
      0x47,
      13,
      10,
      26,
      10,
      1,
      2,
      3,
    ]);
    final path = WebAssetStore.put(image, name: 'picture.png');
    final deck = Deck(
      title: 'Media',
      slides: [Slide.create(SlideType.image).copyWith(imagePath: path)],
    );
    final files = FileService(
      MarkdownService(),
      ImageService(),
      () => const ThemeProfile(),
    );
    final package = await files.buildPackageBytes(deck);
    WebAssetStore.clear();
    final id = await BrowserDeckStore().save('Media', package);
    expect(
      (await BrowserDeckStore().list()).singleWhere((e) => e.id == id).bytes,
      package,
    );
    final archive = ZipDecoder().decodeBytes(
      (await BrowserDeckStore().list()).single.bytes,
    );
    expect(archive.files.where((f) => f.name.endsWith('.png')), isNotEmpty);
    expect(
      archive.files.firstWhere((f) => f.name.endsWith('.png')).content,
      image,
    );
  });
}
