import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/models/git_settings.dart';
import 'package:ocideck/services/git/draft_store.dart';
import 'package:ocideck/services/git/draft_store_web.dart';
import 'package:ocideck/services/git/outbox.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// De wachtrij en de werkkopie horen bij één repository.
///
/// Zolang er precies één repo kon bestaan viel het niet op dat de sleutel
/// alleen de deckmap droeg. Zodra er twee zijn is het een lek: een commit die
/// voor de ene opdrachtgever wachtte, wordt gepusht naar de repo van de andere
/// zodra díe is ingesteld. Geen foutmelding, want elke stap op zich klopt — en
/// dus is dit de test die het moet tegenhouden.
void main() {
  const klantA = GitRepoConfig(
    baseUrl: 'https://git.a.example',
    owner: 'klant-a',
    repo: 'decks',
  );
  const klantB = GitRepoConfig(
    baseUrl: 'https://git.b.example',
    owner: 'klant-b',
    repo: 'decks',
  );

  PendingCommit commit(String deck, String message) => PendingCommit(
    deckDir: 'decks/$deck',
    branch: 'main',
    message: message,
    baseSha: 'abc123',
  );

  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('Outbox', () {
    test('twee repo\'s met hetzelfde deck raken elkaar niet', () async {
      final a = Outbox(scope: klantA.storageSlug);
      final b = Outbox(scope: klantB.storageSlug);

      await a.enqueue(commit('kwartaalcijfers', 'werk voor A'));
      await b.enqueue(commit('kwartaalcijfers', 'werk voor B'));

      expect(
        (await a.forDeck('decks/kwartaalcijfers'))?.message,
        'werk voor A',
      );
      expect(
        (await b.forDeck('decks/kwartaalcijfers'))?.message,
        'werk voor B',
      );
    });

    test('een flush ziet alleen de eigen wachtrij', () async {
      final a = Outbox(scope: klantA.storageSlug);
      final b = Outbox(scope: klantB.storageSlug);
      await a.enqueue(commit('alpha', 'voor A'));
      await b.enqueue(commit('beta', 'voor B'));

      // Dit is de kern: zou pending() de andere repo meenemen, dan duwde een
      // flush het werk van klant B naar de forge van klant A.
      expect((await a.pending()).map((c) => c.deckDir), ['decks/alpha']);
      expect((await b.pending()).map((c) => c.deckDir), ['decks/beta']);
    });

    test('verwijderen bij de een laat de ander staan', () async {
      final a = Outbox(scope: klantA.storageSlug);
      final b = Outbox(scope: klantB.storageSlug);
      await a.enqueue(commit('alpha', 'voor A'));
      await b.enqueue(commit('alpha', 'voor B'));

      await a.remove('decks/alpha');
      expect(await a.isEmpty, isTrue);
      expect((await b.forDeck('decks/alpha'))?.message, 'voor B');
    });

    test('werk uit de tijd zonder scope wordt overgenomen', () async {
      // Wat hier staat is nog nergens op een server aangekomen; het laten
      // liggen zou het stilletjes onbereikbaar maken.
      SharedPreferences.setMockInitialValues({
        'git_outbox::decks/oud': jsonEncode(
          commit('oud', 'nog niet gepusht').toJson(),
        ),
      });
      final a = Outbox(scope: klantA.storageSlug);
      expect(await a.adoptLegacyEntries(), 1);
      expect((await a.forDeck('decks/oud'))?.message, 'nog niet gepusht');

      // Idempotent: een tweede ronde vindt niets meer, en gooit niets weg.
      expect(await a.adoptLegacyEntries(), 0);
      expect((await a.forDeck('decks/oud'))?.message, 'nog niet gepusht');
    });

    test('overname pakt de sleutels van een andere repo niet af', () async {
      final b = Outbox(scope: klantB.storageSlug);
      await b.enqueue(commit('alpha', 'voor B'));

      final a = Outbox(scope: klantA.storageSlug);
      expect(await a.adoptLegacyEntries(), 0);
      expect((await b.forDeck('decks/alpha'))?.message, 'voor B');
      expect(await a.isEmpty, isTrue);
    });

    test('overname overschrijft nieuwer werk niet', () async {
      final a = Outbox(scope: klantA.storageSlug);
      await a.enqueue(commit('oud', 'het actuele werk'));
      // Daarnaast staat er nog een oude, ongescopede sleutel voor dat deck.
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        'git_outbox::decks/oud',
        jsonEncode(commit('oud', 'van vroeger').toJson()),
      );

      await a.adoptLegacyEntries();
      expect((await a.forDeck('decks/oud'))?.message, 'het actuele werk');
      expect(prefs.containsKey('git_outbox::decks/oud'), isFalse);
    });
  });

  group('PrefsDraftStore', () {
    test('een beschadigde werkkopie meldt corruptie, geen leeg deck', () async {
      // Een leeg deck betekent "verworpen" en laat de sync-motor de commit
      // vallen. Een onleesbare (beschadigde) sleutel mag daar niet op lijken —
      // die gooit DraftStoreCorrupt, zodat het als een échte fout telt.
      SharedPreferences.setMockInitialValues({
        'git_draft::decks/alpha': 'geen json',
      });
      final store = PrefsDraftStore();
      await expectLater(
        store.readDeck('decks/alpha'),
        throwsA(isA<DraftStoreCorrupt>()),
      );
    });

    test('een afwezige werkkopie is gewoon leeg, geen fout', () async {
      final store = PrefsDraftStore();
      expect(await store.readDeck('decks/bestaat-niet'), isEmpty);
    });

    test('twee repo\'s met hetzelfde deck delen geen bestanden', () async {
      final a = PrefsDraftStore(scope: klantA.storageSlug);
      final b = PrefsDraftStore(scope: klantB.storageSlug);

      await a.writeDeck('decks/alpha', {
        'deck.md': Uint8List.fromList(utf8.encode('# van A')),
      });
      await b.writeDeck('decks/alpha', {
        'deck.md': Uint8List.fromList(utf8.encode('# van B')),
      });

      expect(
        utf8.decode((await a.readDeck('decks/alpha'))['deck.md']!),
        '# van A',
      );
      expect(
        utf8.decode((await b.readDeck('decks/alpha'))['deck.md']!),
        '# van B',
      );
      expect(await a.deckDirs(), ['decks/alpha']);
    });

    test('een oude werkkopie wordt overgenomen', () async {
      final legacy = PrefsDraftStore();
      await legacy.writeDeck('decks/oud', {
        'deck.md': Uint8List.fromList(utf8.encode('# van vroeger')),
      });

      final a = PrefsDraftStore(scope: klantA.storageSlug);
      expect(await a.adoptLegacyEntries(), 1);
      expect(
        utf8.decode((await a.readDeck('decks/oud'))['deck.md']!),
        '# van vroeger',
      );
      expect(await a.adoptLegacyEntries(), 0);
    });
  });

  test('storageSlug scheidt repo\'s en bevat geen dubbele punt', () {
    expect(klantA.storageSlug, isNot(klantB.storageSlug));
    // Zonder dit is een gescopede sleutel niet te onderscheiden van een oude.
    expect(klantA.storageSlug.contains(':'), isFalse);
    // Twee repo's met dezelfde naam bij verschillende eigenaren of hosts
    // blijven uit elkaar.
    const zelfdeNaamAndereHost = GitRepoConfig(
      baseUrl: 'https://git.c.example',
      owner: 'klant-a',
      repo: 'decks',
    );
    expect(klantA.storageSlug, isNot(zelfdeNaamAndereHost.storageSlug));
  });
}
