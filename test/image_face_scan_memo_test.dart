// De gezichtsscan-memo: hij mag het typen niet meer laten haperen, maar nooit
// een verouderde uitslag teruggeven.
//
// [imagePrivacyRawIssuesProvider] hangt aan het hele deck en draaide dus opnieuw
// bij élke toetsaanslag. De scan is een synchrone OpenCV-aanroep (decode + YuNet
// op drie schalen) die de UI-thread vasthoudt; op een deck vol beeld werd typen
// daardoor onwerkbaar traag. Sinds de per-afbeelding-memo blijft van een
// wijziging die geen afbeelding raakt — een titel typen — niets te scannen over.
// Maar een privacycontrole mag geen verouderde uitslag serveren: een overschreven
// bestand moet wél opnieuw langs de detector.
//
// De echte OpenCV-laag laadt niet onder `flutter test`; hier telt een neppe
// scanner zijn aanroepen. Dat is precies genoeg: getoetst wordt of de memo de
// scan overslaat, niet of de detectie deugt.

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/models/deck.dart';
import 'package:ocideck/models/settings.dart';
import 'package:ocideck/models/slide.dart';
import 'package:ocideck/services/file_service.dart';
import 'package:ocideck/services/image_service.dart';
import 'package:ocideck/services/markdown_service.dart';
import 'package:ocideck/services/privacy/image_face_scan.dart';
import 'package:ocideck/state/deck_provider.dart';
import 'package:ocideck/state/image_privacy_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Telt hoe vaak de detector werkelijk draait.
class _CountingFace implements ImageFaceScanner {
  int calls = 0;

  @override
  bool get isSupported => true;

  @override
  Future<ImageFaceScanResult> countFaces(Uint8List bytes) async {
    calls++;
    return const ImageFaceScanResult(faces: 1, readable: true);
  }

  @override
  void dispose() {}
}

DeckNotifier _deckNotifier(Deck deck) {
  final md = MarkdownService();
  final file = FileService(md, ImageService(), () => const ThemeProfile());
  final notifier = DeckNotifier(md, file);
  notifier.loadDeck(deck);
  return notifier;
}

ProviderContainer _container(
  DeckNotifier notifier,
  ImageFaceScanner scanner,
) => ProviderContainer(
  overrides: [
    deckProvider.overrideWith((ref) => notifier),
    imageFaceScannerProvider.overrideWithValue(
      Future<ImageFaceScanner>.value(scanner),
    ),
    // imageServiceProvider bewust níét overschreven: de echte dienst leest de
    // tempbestanden van schijf, zodat de memo een echt pad + mtime + grootte
    // ziet — precies de sleutel die deze test bewaakt.
  ],
);

void main() {
  // De instellingenprovider leest SharedPreferences bij het opbouwen; zonder
  // binding en lege mock struikelt elke test hierop. De memo is globaal, dus
  // leeg hem tussen tests door.
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    clearImageFaceScanMemo();
  });

  // Een echt bestand op schijf: de memo sleutelt op pad + mtime + grootte, dus
  // zonder bestand valt hij terug op ongecachet scannen (zie `_faceScanKey`).
  Future<(Directory, String)> tempImage(List<int> bytes) async {
    final dir = await Directory.systemTemp.createTemp('ocideck_face_memo');
    final file = File('${dir.path}/foto.png')..writeAsBytesSync(bytes);
    return (dir, file.path);
  }

  test('een wijziging die de afbeelding niet raakt herscant niet', () async {
    final (dir, path) = await tempImage(const [1, 2, 3, 4]);
    addTearDown(() => dir.delete(recursive: true));
    final scanner = _CountingFace();

    final notifier = _deckNotifier(
      Deck(
        title: 'proef',
        slides: [
          Slide.create(SlideType.title).copyWith(title: 'Titel'),
          Slide.create(SlideType.image).copyWith(imagePath: path),
        ],
      ),
    );
    final container = _container(notifier, scanner);
    addTearDown(container.dispose);

    final first = await container.read(imagePrivacyRawIssuesProvider.future);
    expect(first, hasLength(1));
    expect(scanner.calls, 1, reason: 'de eerste scan vult de memo');

    // Simuleer een toetsaanslag op de titel: het deck verandert, de afbeelding
    // niet. De provider draait opnieuw, maar de memo hoort de scan over te slaan.
    final title = container.read(deckProvider).deck!.slides[0];
    notifier.updateSlide(0, title.copyWith(title: 'Titel!'));

    final second = await container.read(imagePrivacyRawIssuesProvider.future);
    expect(second, hasLength(1));
    expect(scanner.calls, 1, reason: 'de afbeelding is niet veranderd');
  });

  test('een overschreven bestand wordt wél opnieuw gescand', () async {
    final (dir, path) = await tempImage(const [1, 2, 3, 4]);
    addTearDown(() => dir.delete(recursive: true));
    final scanner = _CountingFace();

    final notifier = _deckNotifier(
      Deck(
        title: 'proef',
        slides: [Slide.create(SlideType.image).copyWith(imagePath: path)],
      ),
    );
    final container = _container(notifier, scanner);
    addTearDown(container.dispose);

    await container.read(imagePrivacyRawIssuesProvider.future);
    expect(scanner.calls, 1);

    // Overschrijf het bestand met een andere grootte. De grootte zit in de
    // sleutel (naast mtime, dat op een grove klok kan samenvallen), dus dit moet
    // een misser zijn: een verouderde uitslag zou hier een gezicht kunnen
    // verzwijgen, en dat is bij een privacycontrole de verkeerde fout.
    File(path).writeAsBytesSync(const [9, 9, 9, 9, 9, 9, 9, 9]);
    container.invalidate(imagePrivacyRawIssuesProvider);

    await container.read(imagePrivacyRawIssuesProvider.future);
    expect(
      scanner.calls,
      2,
      reason: 'het bestand veranderde, dus opnieuw scannen',
    );
  });
}
