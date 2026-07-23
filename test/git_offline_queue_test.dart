import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/models/deck.dart';
import 'package:ocideck/models/slide.dart';
import 'package:ocideck/services/git/deck_mirror.dart';
import 'package:ocideck/services/git/deck_repo_serializer.dart';
import 'package:ocideck/services/git/draft_store.dart';
import 'package:ocideck/services/git/draft_store_io.dart';
import 'package:ocideck/services/git/offline_queue.dart';
import 'package:ocideck/services/git/outbox.dart';
import 'package:ocideck/services/markdown_service.dart';
import 'package:ocideck/services/web_asset_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'git_forge_fake.dart';

/// Offline werken met een git-repo: parkeren en weer uitpakken.
///
/// Deze twee stonden tot #518 als privémethoden op `TabsNotifier` en waren
/// alleen te bereiken via een opslagronde van de notifier. Ze staan nu in
/// `services/git/`, en dít bestand is waarom dat de moeite was: de afspraak
/// tussen de twee helften — de werkkopie bewaart `mem:`-verwijzingen, het
/// poolen zet ze om vlak vóór de commit — is hier rechtstreeks te toetsen.
Uint8List _b(String s) => Uint8List.fromList(utf8.encode(s));

/// Een werkkopie die elk deck weigert, zoals de webvariant doet bij een deck
/// dat te groot is of geen tekst.
class _RefusingMirror implements DeckMirror {
  @override
  Future<void> writeDeck(String deckDir, Map<String, Uint8List> files) async =>
      throw const DraftStoreUnsupported('Dit deck past niet in de browser.');
  @override
  Future<Map<String, Uint8List>> readDeck(String deckDir) async => const {};
  @override
  Future<bool> hasDeck(String deckDir) async => false;
  @override
  Future<void> discardDeck(String deckDir) async {}
  @override
  Future<List<String>> deckDirs() async => const [];
  @override
  bool get hasRealHistory => false;
  @override
  bool get isDurable => false;
  @override
  bool get discardsLandedWork => true;
}

void main() {
  const deckDir = 'decks/kwartaalcijfers';
  final md = MarkdownService();

  late Directory temp;
  late DeckMirror mirror;
  late Outbox outbox;

  setUp(() async {
    temp = Directory.systemTemp.createTempSync('ocideck_offline_queue');
    SharedPreferences.setMockInitialValues({});
    mirror = DraftMirror(store: FileDraftStore(baseDir: temp));
    outbox = Outbox(prefs: await SharedPreferences.getInstance());
  });
  tearDown(() {
    if (temp.existsSync()) temp.deleteSync(recursive: true);
  });

  Future<QueuedSave> queue(Deck deck, {DeckMirror? into}) => queueDeckSave(
    into ?? mirror,
    outbox,
    deck: deck,
    deckDir: deckDir,
    branch: 'main',
    message: 'offline opslag',
    baseSha: 'commit-main',
    md: md,
  );

  group('queueDeckSave', () {
    test('zet de tekst in de werkkopie en de intentie in de outbox', () async {
      final result = await queue(
        Deck(
          title: 'Kwartaalcijfers',
          slides: [Slide.create(SlideType.title).copyWith(title: 'Q3')],
        ),
      );

      expect(result.queued, isTrue);
      expect(result.refusal, isNull);

      final stored = await mirror.readDeck(deckDir);
      expect(stored.keys, contains('$deckDir/$deckRepoFileName'));

      final pending = await outbox.forDeck(deckDir);
      expect(pending, isNotNull);
      expect(pending!.branch, 'main');
      expect(pending.baseSha, 'commit-main');
      expect(pending.message, 'offline opslag');
    });

    test('bewaart de mem:-verwijzing ongepoold', () async {
      // Dit is de afspraak met poolPendingDeck en het is geen detail: offline
      // kunnen de blobs toch niet omhoog, dus de werkkopie houdt de
      // mem:-verwijzing en het poolen gebeurt pas vlak vóór de commit.
      final mem = WebAssetStore.put(_b('niet echt een plaatje'), name: 'a.png');
      final result = await queue(
        Deck(
          title: 'Met plaatje',
          slides: [Slide.create(SlideType.image).copyWith(imagePath: mem)],
        ),
      );
      expect(result.queued, isTrue);

      final stored = await mirror.readDeck(deckDir);
      final markdown = utf8.decode(stored['$deckDir/$deckRepoFileName']!);
      expect(markdown, contains(mem));
      expect(markdown, isNot(contains('repo:')));
    });

    test('een werkkopie die weigert levert geen halve wachtrij op', () async {
      // Het gat dat deze tak ooit dichtte: DraftStoreUnsupported is geen
      // GitForgeException, dus zonder de vangst liep hij ongevangen door —
      // geen melding, en niets in de wachtrij, terwijl de desktop netjes
      // "gaat mee zodra er weer verbinding is" toonde.
      final result = await queue(
        const Deck(title: 'Te groot'),
        into: _RefusingMirror(),
      );

      expect(result.queued, isFalse);
      expect(result.refusal, 'Dit deck past niet in de browser.');
      expect(await outbox.forDeck(deckDir), isNull);
    });
  });

  group('poolPendingDeck', () {
    final commit = PendingCommit(
      deckDir: deckDir,
      branch: 'main',
      message: 'offline opslag',
      baseSha: 'commit-main',
    );

    test('zet een wachtende mem:-afbeelding om naar repo:', () async {
      final mem = WebAssetStore.put(
        Uint8List.fromList([
          0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, //
          ...List.filled(64, 7),
        ]),
        name: 'grafiek.png',
      );
      await queue(
        Deck(
          title: 'Met plaatje',
          slides: [Slide.create(SlideType.image).copyWith(imagePath: mem)],
        ),
      );
      final stored = await mirror.readDeck(deckDir);

      final forge = FakeForge(
        FakeRepo(branches: {'main': 'commit-main'}, files: {}),
      );
      final pooled = await poolPendingDeck(forge, commit, stored, md: md);

      final markdown = utf8.decode(pooled['$deckDir/$deckRepoFileName']!);
      expect(markdown, contains('repo:'));
      expect(markdown, isNot(contains(mem)));
      // De blob zelf hoort er ook bij te zitten; een verwijzing zonder bytes
      // landt als een kapot plaatje bij de ontvanger.
      expect(pooled.keys.where((k) => k.contains('assets/')), isNotEmpty);
    });

    test('een deckmap zonder deck.md gaat ongewijzigd door', () async {
      final stored = {'$deckDir/deck.notes': _b('losse notities')};
      final forge = FakeForge(
        FakeRepo(branches: {'main': 'commit-main'}, files: {}),
      );

      expect(
        await poolPendingDeck(forge, commit, stored, md: md),
        same(stored),
      );
    });

    test('de lagen naast deck.md reizen mee', () async {
      // buildDeckRepoFiles schrijft alleen terug wat aan het deck hangt, dus
      // zonder het terughalen van de sidecars zou wachtend werk zijn
      // gebruikersnotities verliezen op het moment dat het landt.
      final slide = Slide.create(SlideType.title).copyWith(title: 'Q3');
      await queue(
        Deck(
          title: 'Met notities',
          slides: [slide],
          userNotes: {slide.id: 'losse aantekening die mee moet'},
        ),
      );
      final stored = await mirror.readDeck(deckDir);
      expect(stored.keys, contains('$deckDir/$userNotesRepoFileName'));

      final forge = FakeForge(
        FakeRepo(branches: {'main': 'commit-main'}, files: {}),
      );
      final pooled = await poolPendingDeck(forge, commit, stored, md: md);

      final notes = pooled['$deckDir/$userNotesRepoFileName'];
      expect(
        notes,
        isNotNull,
        reason: 'de notitielaag verdween bij het poolen: ${pooled.keys}',
      );
      expect(utf8.decode(notes!), contains('losse aantekening die mee moet'));
    });
  });
}
