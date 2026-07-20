// De dispositie op een dia onderdrukt de beeldmelding.
//
// Waarom dit een eigen test verdient: de detector kan het mis hebben op een
// manier die de auteur niet kan weerleggen. Een antropomorfe dierenkop scoort
// net boven de drempel (zie de meting bij `kFaceScanScoreThreshold`), en zonder
// deze uitweg blijft zo'n dia waarschuwen zonder dat er iets aan te doen valt.
//
// De echte OpenCV-laag laadt niet onder `flutter test` — daarom staat hier een
// neppe scanner die altijd één gezicht meldt. Dat is precies genoeg: getoetst
// wordt of de dispositie de melding tegenhoudt, niet of de detectie deugt.

import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/models/deck.dart';
import 'package:ocideck/models/privacy_disposition.dart';
import 'package:ocideck/models/settings.dart';
import 'package:ocideck/models/slide.dart';
import 'package:ocideck/services/file_service.dart';
import 'package:ocideck/services/image_service.dart';
import 'package:ocideck/services/markdown_service.dart';
import 'package:ocideck/services/privacy/image_face_scan.dart';
import 'package:ocideck/state/deck_provider.dart';
import 'package:ocideck/state/image_privacy_provider.dart';
import 'package:ocideck/state/settings_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _AlwaysOneFace implements ImageFaceScanner {
  @override
  bool get isSupported => true;

  @override
  Future<ImageFaceScanResult> countFaces(Uint8List bytes) async =>
      const ImageFaceScanResult(faces: 1, readable: true);

  @override
  void dispose() {}
}

class _FakeImageService extends ImageService {
  @override
  Future<Uint8List?> readSlideImageBytes(
    String path, {
    String? projectPath,
  }) async => Uint8List.fromList(const [1, 2, 3]);
}

DeckNotifier _deckNotifier(Deck deck) {
  final md = MarkdownService();
  final file = FileService(md, ImageService(), () => const ThemeProfile());
  final notifier = DeckNotifier(md, file);
  notifier.loadDeck(deck);
  return notifier;
}

Slide _imageSlide({PrivacyDisposition? privacy}) => Slide.create(
  SlideType.image,
).copyWith(imagePath: 'images/dieren.png', privacy: privacy);

ProviderContainer _container(Deck deck) => ProviderContainer(
  overrides: [
    deckProvider.overrideWith((ref) => _deckNotifier(deck)),
    imageServiceProvider.overrideWithValue(_FakeImageService()),
    imageFaceScannerProvider.overrideWithValue(
      Future<ImageFaceScanner>.value(_AlwaysOneFace()),
    ),
  ],
);

void main() {
  // De instellingenprovider leest SharedPreferences bij het opbouwen; zonder
  // binding en lege mock struikelt elke test hierop nog voor de beeldcontrole
  // aan bod komt.
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('een onbeslist beeld levert een melding op', () async {
    final container = _container(Deck(slides: [_imageSlide()], title: 'proef'));
    addTearDown(container.dispose);

    final issues = await container.read(imagePrivacyIssuesProvider.future);
    expect(issues, hasLength(1));
  });

  test('accept, shield en redact op de dia onderdrukken de melding', () async {
    for (final d in [
      PrivacyDisposition.accept,
      PrivacyDisposition.shield,
      PrivacyDisposition.redact,
    ]) {
      final container = _container(
        Deck(
          slides: [_imageSlide(privacy: d)],
          title: 'proef',
        ),
      );
      addTearDown(container.dispose);

      final issues = await container.read(imagePrivacyIssuesProvider.future);
      expect(issues, isEmpty, reason: d.key);
    }
  });

  test('warn op de dia laat de melding staan', () async {
    final container = _container(
      Deck(
        slides: [_imageSlide(privacy: PrivacyDisposition.warn)],
        title: 'proef',
      ),
    );
    addTearDown(container.dispose);

    final issues = await container.read(imagePrivacyIssuesProvider.future);
    expect(issues, hasLength(1));
  });

  // De dia erft de deck-stand als er zelf niets staat — dezelfde regel als
  // `effectivePrivacyDisposition` elders afdwingt.
  test('de deck-brede stand telt voor een dia zonder eigen keuze', () async {
    final container = _container(
      Deck(
        slides: [_imageSlide()],
        title: 'proef',
        privacy: PrivacyDisposition.accept,
      ),
    );
    addTearDown(container.dispose);

    final issues = await container.read(imagePrivacyIssuesProvider.future);
    expect(issues, isEmpty);
  });

  // ...maar een dia die er expliciet van afwijkt wint van het deck. Anders zou
  // "accepteer alles behalve deze ene" niet uit te drukken zijn.
  test('een dia met warn wint van een deck met accept', () async {
    final container = _container(
      Deck(
        slides: [_imageSlide(privacy: PrivacyDisposition.warn)],
        title: 'proef',
        privacy: PrivacyDisposition.accept,
      ),
    );
    addTearDown(container.dispose);

    final issues = await container.read(imagePrivacyIssuesProvider.future);
    expect(issues, hasLength(1));
  });

  // De ruwe scan is de tegenhanger: die houdt de bevinding op een afgehandelde
  // dia juist vást, zodat de badge grijs kan worden in plaats van te verdwijnen.
  // Verdween ze ook uit de ruwe uitslag, dan haalde één dubbelklik (accepteren)
  // elke aanwijzing weg dat er ooit iets gevonden was.
  test('de ruwe scan houdt een afgehandelde dia vast', () async {
    for (final d in [
      PrivacyDisposition.accept,
      PrivacyDisposition.shield,
      PrivacyDisposition.redact,
    ]) {
      final container = _container(
        Deck(
          slides: [_imageSlide(privacy: d)],
          title: 'proef',
        ),
      );
      addTearDown(container.dispose);

      final raw = await container.read(imagePrivacyRawIssuesProvider.future);
      expect(raw, hasLength(1), reason: d.key);
    }
  });

  // "Deze regel nooit meer melden" schrijft image.face in de uitgezette regels.
  // Zonder dat de beeldcontrole die lijst eert, deed die knop niets — de klacht.
  test('image.face in disabledRules leegt de ruwe beeldscan', () async {
    SharedPreferences.setMockInitialValues({
      'privacyDisabledRules': ['image.face'],
    });
    final container = _container(Deck(slides: [_imageSlide()], title: 'proef'));
    addTearDown(container.dispose);
    // De settings laden asynchroon. Trek die load op gang en laat hem settelen
    // vóórdat de beeldprovider voor het eerst leest: zou de provider halverwege
    // de load rekenen, dan maakt de settling hem ongeldig terwijl hij nog laadt.
    container.read(settingsProvider);
    await Future<void>.delayed(const Duration(milliseconds: 50));

    final raw = await container.read(imagePrivacyRawIssuesProvider.future);
    expect(raw, isEmpty);
  });
}
