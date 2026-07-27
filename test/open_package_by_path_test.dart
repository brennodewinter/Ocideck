import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/models/deck.dart';
import 'package:ocideck/models/settings.dart';
import 'package:ocideck/models/slide.dart';
import 'package:ocideck/services/file_service.dart';
import 'package:ocideck/services/image_service.dart';
import 'package:ocideck/services/markdown_service.dart';
import 'package:ocideck/state/settings_provider.dart';
import 'package:ocideck/state/tabs_provider.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

/// Een `.ocideck`-pakket openen via "Bestand → Openen" (#905).
///
/// Een `.ocideck` is OciDeck's eigen formaat: een zip met de deck plus assets.
/// Toch behandelde `openFileByPath` — het pad achter "Openen", de bibliotheek-
/// scan en het welkomstscherm — élk gekozen bestand als platte markdown. Een
/// pakket is binair en groter dan de 32 MiB-markdowngrens, dus de gebruiker
/// kreeg een misleidend "dit bestand is te groot om te openen" (een klein
/// pakket zou "onleesbaar" hebben gekregen) in plaats van dat het werd
/// uitgepakt. Slepen-en-neerzetten en de web-open herkenden het pakket wél —
/// deze test bewaakt dat "Openen" nu dezelfde afslag neemt.
void main() {
  late Directory temp;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    temp = Directory.systemTemp.createTempSync('open_package_by_path');
  });

  tearDown(() => temp.deleteSync(recursive: true));

  /// Bouwt een echt `.ocideck`/zip-pakket op schijf onder [name].
  Future<String> writePackage(String name) async {
    final file = FileService(
      MarkdownService(),
      ImageService(),
      () => const ThemeProfile(),
    );
    final deck = Deck(
      title: 'Proefpresentatie',
      slides: [
        Slide.create(SlideType.title).copyWith(title: 'Hoi'),
        Slide.create(SlideType.bullets).copyWith(bullets: ['een', 'twee']),
      ],
    );
    final path = p.join(temp.path, name);
    await file.exportPackage(deck, path);
    return path;
  }

  /// Verse container met een bibliotheekmap, zodat de pakket-import een echte
  /// bestemmingsmap heeft (en niet op `path_provider` terugvalt, dat onder
  /// `flutter test` geen implementatie heeft).
  Future<ProviderContainer> containerWithHome() async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final home = Directory(p.join(temp.path, 'home'))..createSync();
    await container
        .read(settingsProvider.notifier)
        .addLibrary('home', home.path);
    return container;
  }

  test('een .ocideck-pakket opent i.p.v. "te groot" te melden', () async {
    final zipPath = await writePackage('proefpresentatie.ocideck');
    // Wat de gebruiker koos ís een zip, geen tekst.
    expect(
      FileService.looksLikeZipBytes(File(zipPath).readAsBytesSync()),
      isTrue,
    );

    final container = await containerWithHome();
    final tabs = container.read(tabsProvider.notifier);
    final result = await tabs.openFileByPath(zipPath);

    expect(result, OpenResult.opened);
    expect(
      container.read(openFailureProvider),
      isNull,
      reason: 'een pakket is geen te grote of onleesbare markdown',
    );
    expect(
      tabs.currentState.current?.deckNotifier.currentState.deck?.title,
      'Proefpresentatie',
      reason: 'het uitgepakte deck hoort in een tabblad te staan',
    );
  });

  test('een losse .zip met een deck opent langs hetzelfde pad', () async {
    final zipPath = await writePackage('deck.zip');

    final container = await containerWithHome();
    final tabs = container.read(tabsProvider.notifier);
    final result = await tabs.openFileByPath(zipPath);

    expect(result, OpenResult.opened);
    expect(container.read(openFailureProvider), isNull);
  });

  test(
    'een zip zonder presentatie zegt "geen presentatie", niet "te groot"',
    () async {
      // Een geldige zip, maar zonder markdown erin — geen OciDeck-pakket. De
      // gebruiker hoort een gerichte reden te krijgen in plaats van het
      // misleidende "te groot" (of stilte) van vroeger.
      final archive = Archive()
        ..addFile(ArchiveFile('readme.txt', 2, utf8.encode('hi')));
      final path = p.join(temp.path, 'geen-deck.ocideck');
      File(path).writeAsBytesSync(ZipEncoder().encode(archive));

      final container = await containerWithHome();
      final tabs = container.read(tabsProvider.notifier);
      final result = await tabs.openFileByPath(path);

      expect(result, OpenResult.notAPresentation);
      expect(container.read(openFailureProvider), OpenFailure.notPresentation);
    },
  );

  test('een gewoon .md-bestand blijft de markdown-open volgen', () async {
    // De pakket-afslag mag een losse presentatie niet wegkapen.
    final mdPath = p.join(temp.path, 'deck.md');
    File(mdPath).writeAsStringSync('---\nmarp: true\n---\n\n# Titel\n\nHoi.\n');

    final container = await containerWithHome();
    final tabs = container.read(tabsProvider.notifier);
    final result = await tabs.openFileByPath(mdPath);

    expect(result, OpenResult.opened);
    expect(
      tabs.currentState.current?.deckNotifier.currentState.filePath,
      mdPath,
      reason: 'een los .md houdt zijn pad; alleen een pakket wordt uitgepakt',
    );
  });
}
