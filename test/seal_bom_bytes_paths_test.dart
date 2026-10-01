import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/models/deck.dart';
import 'package:ocideck/models/settings.dart';
import 'package:ocideck/models/slide.dart';
import 'package:ocideck/services/document_integrity.dart';
import 'package:ocideck/services/file_service.dart';
import 'package:ocideck/services/git/deck_repo_sidecars.dart';
import 'package:ocideck/services/image_service.dart';
import 'package:ocideck/services/markdown_service.dart';
import 'package:ocideck/services/recovery_service.dart';
import 'package:ocideck/state/tabs_provider.dart';
import 'package:ocideck/utils/utf8_bom.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

import 'git_forge_fake.dart';

/// Het zegel belooft dat `sha512sum` over de `.md` de vastgelegde hash geeft.
/// Een UTF-8-BOM voor het bestand is onzichtbaar in de tekst, maar niet in de
/// bytes — en dus een wijziging.
///
/// `seal_sidecar_test.dart` toetst het schijfpad (`openDeck`). Dit bestand de
/// paden waar de bytes uit het geheugen komen en de BOM al door `utf8.decode` is
/// weggehaald: de web-picker, drag-drop, URL-import, een pakket en git. Ze
/// delen één poort (`_gateAndParseContent`), dus hier staan de drie ingangen die
/// ertoe doen: kaal bestand, pakket en git.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  Deck deck() => Deck(
    title: 'Pentest',
    slides: [
      Slide.create(SlideType.title).copyWith(title: 'Pentest'),
      Slide.create(
        SlideType.bullets,
      ).copyWith(title: 'Bevindingen', bullets: const ['Eén', 'Twee']),
    ],
  );

  /// Een verzegeld deck zoals OciDeck het op schijf zet: de `.md` en zijn
  /// `.seal.json` ernaast. Levert hun bytes.
  Future<({Uint8List md, Uint8List seal})> verzegeld() async {
    final map = await Directory.systemTemp.createTemp('ocideck_zegel_bom_');
    addTearDown(() async {
      if (await map.exists()) await map.delete(recursive: true);
    });
    final pad = p.join(map.path, 'deck.md');
    await FileService(
      MarkdownService(),
      ImageService(),
      () => const ThemeProfile(),
    ).saveDeck(DocumentIntegrity(MarkdownService()).seal(deck()), pad);
    return (
      md: await File(pad).readAsBytes(),
      seal: await File(p.join(map.path, 'deck.seal.json')).readAsBytes(),
    );
  }

  Uint8List metBom(List<int> bytes) =>
      Uint8List.fromList([...utf8Bom, ...bytes]);

  Uint8List zip(Map<String, List<int>> leden) {
    final archive = Archive();
    leden.forEach(
      (naam, bytes) => archive.add(ArchiveFile(naam, bytes.length, bytes)),
    );
    return ZipEncoder().encodeBytes(archive);
  }

  (ProviderContainer, TabsNotifier) bouw() {
    final tijdelijk = Directory.systemTemp.createTempSync('ocideck_bom_tabs_');
    addTearDown(() {
      if (tijdelijk.existsSync()) tijdelijk.deleteSync(recursive: true);
    });
    final container = ProviderContainer(
      overrides: [
        recoveryServiceProvider.overrideWithValue(
          RecoveryService(baseDir: tijdelijk),
        ),
      ],
    );
    addTearDown(container.dispose);
    return (container, container.read(tabsProvider.notifier));
  }

  Deck geopend(ProviderContainer container) =>
      container.read(tabsProvider).current!.deckNotifier.currentState.deck!;

  group('parseDeck', () {
    test('hasht de bytes mét BOM wanneer het bestand er een had', () {
      const tekst = '---\nmarp: true\n---\n\n# Kop\n';
      final md = MarkdownService();

      final zonder = md.parseDeck(tekst)!;
      final met = md.parseDeck(tekst, hasUtf8Bom: true)!;

      expect(zonder.fileHash, DocumentIntegrity.hashBytes(utf8.encode(tekst)));
      expect(
        met.fileHash,
        DocumentIntegrity.hashBytes([...utf8Bom, ...utf8.encode(tekst)]),
      );
      expect(met.fileHash, isNot(zonder.fileHash));
    });
  });

  group('een kaal bestand uit het geheugen (web-picker, drag-drop, URL)', () {
    test('met BOM draagt het de hash van de bytes, BOM inbegrepen', () async {
      final (container, tabs) = bouw();
      final bytes = metBom((await verzegeld()).md);

      expect(await tabs.openDeckFromBytes(bytes, 'deck.md'), OpenResult.opened);

      expect(geopend(container).fileHash, DocumentIntegrity.hashBytes(bytes));
    });

    test('zonder BOM blijft het de hash van de bytes (tegenproef)', () async {
      final (container, tabs) = bouw();
      final bytes = (await verzegeld()).md;

      expect(await tabs.openDeckFromBytes(bytes, 'deck.md'), OpenResult.opened);

      expect(geopend(container).fileHash, DocumentIntegrity.hashBytes(bytes));
    });
  });

  group('een pakket met zegel', () {
    test('een BOM voor de .md maakt het zegel gewijzigd', () async {
      final (container, tabs) = bouw();
      final bestanden = await verzegeld();
      final pakket = zip({
        'deck.md': metBom(bestanden.md),
        'deck.seal.json': bestanden.seal,
      });

      expect(await tabs.openDeckFromBytes(pakket, 'deck.ocideck'), isNotNull);

      expect(deckIntegrityStatus(geopend(container)), IntegrityStatus.changed);
    });

    test('zonder BOM is het zegel intact (tegenproef)', () async {
      final (container, tabs) = bouw();
      final bestanden = await verzegeld();
      final pakket = zip({
        'deck.md': bestanden.md,
        'deck.seal.json': bestanden.seal,
      });

      expect(await tabs.openDeckFromBytes(pakket, 'deck.ocideck'), isNotNull);

      expect(deckIntegrityStatus(geopend(container)), IntegrityStatus.intact);
    });
  });

  group('een deck uit git met zegel', () {
    const config = GitRepoConfig(
      baseUrl: 'https://git.example.org',
      owner: 'librekat',
      repo: 'decks',
    );
    const deckDir = 'decks/pentest';

    Future<Deck> uitGit(
      ProviderContainer container,
      TabsNotifier tabs,
      List<int> md,
      List<int> seal,
    ) async {
      final repo = FakeRepo(
        branches: {'main': 'commit-main'},
        files: {
          '$deckDir/deck.md': Uint8List.fromList(md),
          '$deckDir/$sealRepoFileName': Uint8List.fromList(seal),
        },
      );
      final result = await tabs.openDeckFromGit(
        FakeForge(repo),
        config: config,
        deckDir: deckDir,
        branch: 'main',
      );
      expect(result, OpenResult.opened);
      return geopend(container);
    }

    test('een BOM voor de deck.md maakt het zegel gewijzigd', () async {
      final (container, tabs) = bouw();
      final bestanden = await verzegeld();

      final deck = await uitGit(
        container,
        tabs,
        metBom(bestanden.md),
        bestanden.seal,
      );

      expect(deckIntegrityStatus(deck), IntegrityStatus.changed);
    });

    test('zonder BOM is het zegel intact (tegenproef)', () async {
      final (container, tabs) = bouw();
      final bestanden = await verzegeld();

      final deck = await uitGit(container, tabs, bestanden.md, bestanden.seal);

      expect(deckIntegrityStatus(deck), IntegrityStatus.intact);
    });
  });
}
