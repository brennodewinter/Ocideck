import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/services/git/deck_mirror.dart';
import 'package:ocideck/services/git/draft_store_io.dart';
import 'package:ocideck/services/git/git_forge.dart';
import 'package:ocideck/services/git/outbox.dart';
import 'package:ocideck/services/git/sync_engine.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'git_forge_fake.dart';

Uint8List _b(String s) => Uint8List.fromList(utf8.encode(s));

/// A forge that is simply not there — the aeroplane.
class _OfflineForge extends FakeForge {
  _OfflineForge(super.repo);

  @override
  Future<List<RepoEntry>> listTree(
    String ref,
    String path, {
    bool recursive = false,
  }) async => throw const GitForgeException(
    GitForgeError.network,
    'Netwerkfout: geen verbinding',
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory temp;
  late SharedPreferences prefs;
  late FakeRepo repo;
  late DeckMirror mirror;
  late Outbox outbox;

  setUp(() async {
    temp = Directory.systemTemp.createTempSync('ocideck_sync');
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    repo = FakeRepo(
      branches: {'main': 'commit-main'},
      files: {
        'decks/kwartaalcijfers/deck.md': _b('# Zoals op de forge'),
        'decks/kwartaalcijfers/deck.notes': _b('oude notities'),
      },
    );
    mirror = DraftMirror(store: FileDraftStore(baseDir: temp));
    outbox = Outbox(prefs: prefs);
  });
  tearDown(() {
    if (temp.existsSync()) temp.deleteSync(recursive: true);
  });

  SyncEngine engineWith(GitForge forge) =>
      SyncEngine(forge: forge, mirror: mirror, outbox: outbox);

  /// Save, as the editor will do it: write the mirror, queue the intent.
  Future<void> save(String markdown, {String baseSha = 'commit-main'}) async {
    await mirror.writeDeck('decks/kwartaalcijfers', {
      'decks/kwartaalcijfers/deck.md': _b(markdown),
      'decks/kwartaalcijfers/deck.notes': _b('oude notities'),
    });
    await outbox.enqueue(
      const PendingCommit(
        deckDir: 'decks/kwartaalcijfers',
        branch: 'main',
        message: 'Update Kwartaalcijfers',
        baseSha: 'commit-main',
      ).copyWithBase(baseSha),
    );
  }

  group('Outbox', () {
    test('a queued commit survives a restart', () async {
      // P2: the aeroplane case. Close the laptop mid-flight and the intent is
      // still there on landing.
      await outbox.enqueue(
        const PendingCommit(
          deckDir: 'decks/a',
          branch: 'main',
          message: 'Werk',
          baseSha: 'sha-a',
        ),
      );
      final fresh = Outbox(prefs: prefs);
      expect((await fresh.forDeck('decks/a'))!.message, 'Werk');
    });

    test('saving again keeps the ORIGINAL baseSha', () async {
      // The subtle one. Two saves offline are both written against the commit
      // you opened. Letting the second overwrite baseSha with something newer
      // would quietly disarm the conflict guard — you would then overwrite
      // whoever committed in between.
      await outbox.enqueue(
        const PendingCommit(
          deckDir: 'decks/a',
          branch: 'main',
          message: 'Eerste',
          baseSha: 'origineel',
        ),
      );
      await outbox.enqueue(
        const PendingCommit(
          deckDir: 'decks/a',
          branch: 'main',
          message: 'Tweede',
          baseSha: 'nieuwer',
        ),
      );

      final pending = (await outbox.forDeck('decks/a'))!;
      expect(pending.baseSha, 'origineel');
      expect(pending.message, 'Tweede', reason: 'de boodschap mag wél mee');
    });

    test('forkFrom round-trips and is kept on re-enqueue', () async {
      await outbox.enqueue(
        const PendingCommit(
          deckDir: 'decks/a',
          branch: 'decks/a/2026-07-18',
          message: 'concept',
          baseSha: 'origineel',
          forkFrom: 'main',
        ),
      );
      expect((await Outbox(prefs: prefs).forDeck('decks/a'))!.forkFrom, 'main');

      // Opnieuw opslaan houdt de ronde-eigenschappen vast, net als baseSha.
      await outbox.enqueue(
        const PendingCommit(
          deckDir: 'decks/a',
          branch: 'decks/a/2026-07-18',
          message: 'tweede',
          baseSha: 'nieuwer',
          forkFrom: 'main',
        ),
      );
      final again = (await outbox.forDeck('decks/a'))!;
      expect(again.forkFrom, 'main');
      expect(again.baseSha, 'origineel');
    });

    test('one pending commit per deck, decks kept apart', () async {
      await outbox.enqueue(
        const PendingCommit(
          deckDir: 'decks/a',
          branch: 'main',
          message: 'A',
          baseSha: 's',
        ),
      );
      await outbox.enqueue(
        const PendingCommit(
          deckDir: 'decks/b',
          branch: 'main',
          message: 'B',
          baseSha: 's',
        ),
      );
      expect((await outbox.pending()).map((c) => c.deckDir), [
        'decks/a',
        'decks/b',
      ]);
    });

    test('removing one leaves the rest of the prefs domain alone', () async {
      await prefs.setString('languageCode', 'nl');
      await outbox.enqueue(
        const PendingCommit(
          deckDir: 'decks/a',
          branch: 'main',
          message: 'A',
          baseSha: 's',
        ),
      );
      await outbox.remove('decks/a');

      expect(await outbox.isEmpty, isTrue);
      expect(prefs.getString('languageCode'), 'nl');
    });

    test('an unreadable entry is skipped, not fatal', () async {
      await prefs.setString('git_outbox::decks/a', 'geen json');
      expect(await outbox.pending(), isEmpty);
    });

    test('an entry whose dir is not a deck is refused', () async {
      await prefs.setString(
        'git_outbox::assets',
        jsonEncode({
          'deckDir': 'assets',
          'branch': 'main',
          'message': 'x',
          'baseSha': 's',
        }),
      );
      expect(await outbox.pending(), isEmpty);
    });
  });

  group('SyncEngine.flush', () {
    test('commits the mirror and clears the queue', () async {
      await save('# Mijn werk');
      final outcome = await engineWith(
        FakeForge(repo),
      ).flushDeck('decks/kwartaalcijfers');

      expect(outcome.status, SyncStatus.committed);
      expect(outcome.sha, isNotNull);
      expect(await outbox.isEmpty, isTrue);
      expect(
        utf8.decode(repo.files['decks/kwartaalcijfers/deck.md']!),
        '# Mijn werk',
      );
    });

    test('the new sha is the branch head, ready to be the next base', () async {
      await save('# Mijn werk');
      final forge = FakeForge(repo);
      final outcome = await engineWith(
        forge,
      ).flushDeck('decks/kwartaalcijfers');

      expect(await forge.headSha('main'), outcome.sha);
    });

    test('a member dropped locally is deleted on the forge', () async {
      // Otherwise a removed slide leaves its file behind and the repo slowly
      // fills with things nothing references.
      await mirror.writeDeck('decks/kwartaalcijfers', {
        'decks/kwartaalcijfers/deck.md': _b('# Zonder notities'),
      });
      await outbox.enqueue(
        const PendingCommit(
          deckDir: 'decks/kwartaalcijfers',
          branch: 'main',
          message: 'Notities weg',
          baseSha: 'commit-main',
        ),
      );

      await engineWith(FakeForge(repo)).flushDeck('decks/kwartaalcijfers');
      expect(
        repo.files.containsKey('decks/kwartaalcijfers/deck.notes'),
        isFalse,
      );
    });

    test(
      'decks are independent: one failure does not block the other',
      () async {
        await mirror.writeDeck('decks/kwartaalcijfers', {
          'decks/kwartaalcijfers/deck.md': _b('# Q'),
        });
        await mirror.writeDeck('decks/jaarplan', {
          'decks/jaarplan/deck.md': _b('# J'),
        });
        await outbox.enqueue(
          const PendingCommit(
            deckDir: 'decks/kwartaalcijfers',
            branch: 'main',
            message: 'Q',
            baseSha: 'verouderd',
          ),
        );
        await outbox.enqueue(
          const PendingCommit(
            deckDir: 'decks/jaarplan',
            branch: 'main',
            message: 'J',
            baseSha: 'commit-main',
          ),
        );

        final outcomes = await engineWith(FakeForge(repo)).flush();
        final byDeck = {for (final o in outcomes) o.deckDir: o.status};
        expect(byDeck['decks/kwartaalcijfers'], SyncStatus.conflict);
        expect(byDeck['decks/jaarplan'], SyncStatus.committed);
      },
    );
  });

  group('SyncEngine offline and conflict', () {
    test('offline: nothing is lost, the work stays queued', () async {
      // The whole promise of P2 in one test: no network, no loss.
      await save('# Op het vliegtuig geschreven');
      final outcome = await engineWith(
        _OfflineForge(repo),
      ).flushDeck('decks/kwartaalcijfers');

      expect(outcome.status, SyncStatus.failed);
      expect(await outbox.isEmpty, isFalse, reason: 'blijft wachten');
      expect(
        utf8.decode(
          (await mirror.readDeck(
            'decks/kwartaalcijfers',
          ))['decks/kwartaalcijfers/deck.md']!,
        ),
        '# Op het vliegtuig geschreven',
        reason: 'de werkkopie is er nog',
      );
    });

    test('and lands on the next flush, once there is a network', () async {
      await save('# Op het vliegtuig geschreven');
      await engineWith(_OfflineForge(repo)).flushDeck('decks/kwartaalcijfers');

      final outcome = await engineWith(
        FakeForge(repo),
      ).flushDeck('decks/kwartaalcijfers');
      expect(outcome.status, SyncStatus.committed);
      expect(
        utf8.decode(repo.files['decks/kwartaalcijfers/deck.md']!),
        '# Op het vliegtuig geschreven',
      );
    });

    test(
      'a conflict keeps the work and does not touch the other author',
      () async {
        await save('# Van mij', baseSha: 'verouderd');
        final outcome = await engineWith(
          FakeForge(repo),
        ).flushDeck('decks/kwartaalcijfers');

        expect(outcome.status, SyncStatus.conflict);
        expect(outcome.message, isNotNull);
        expect(await outbox.isEmpty, isFalse);
        expect(
          utf8.decode(repo.files['decks/kwartaalcijfers/deck.md']!),
          '# Zoals op de forge',
          reason: 'het werk van de ander staat er nog',
        );
      },
    );
  });

  group('SyncEngine idempotency (§8.5)', () {
    test('a commit that already landed is detected, not duplicated', () async {
      // The nasty ordering: the commit succeeded but clearing the queue did not
      // (crash, kill, lost tab). On restart a blind retry would hit our own
      // commit and report a conflict against ourselves.
      await save('# Mijn werk');
      final forge = FakeForge(repo);
      await engineWith(forge).flushDeck('decks/kwartaalcijfers');
      final shaAfterFirst = await forge.headSha('main');

      // Re-queue with the now-stale base, as a crashed run would have left it.
      await outbox.enqueue(
        const PendingCommit(
          deckDir: 'decks/kwartaalcijfers',
          branch: 'main',
          message: 'Update Kwartaalcijfers',
          baseSha: 'commit-main',
        ),
      );

      final outcome = await engineWith(
        forge,
      ).flushDeck('decks/kwartaalcijfers');

      expect(outcome.status, SyncStatus.alreadyLanded);
      expect(outcome.sha, shaAfterFirst);
      expect(await outbox.isEmpty, isTrue, reason: 'wachtrij opgeruimd');
      expect(
        await forge.headSha('main'),
        shaAfterFirst,
        reason: 'geen tweede commit',
      );
    });

    test('identical content is not committed again', () async {
      // Save without changing anything: there is nothing to record, so recording
      // an empty commit would be noise in the history.
      await mirror.writeDeck('decks/kwartaalcijfers', {
        'decks/kwartaalcijfers/deck.md': _b('# Zoals op de forge'),
        'decks/kwartaalcijfers/deck.notes': _b('oude notities'),
      });
      await outbox.enqueue(
        const PendingCommit(
          deckDir: 'decks/kwartaalcijfers',
          branch: 'main',
          message: 'Niets veranderd',
          baseSha: 'commit-main',
        ),
      );
      final forge = FakeForge(repo);

      final outcome = await engineWith(
        forge,
      ).flushDeck('decks/kwartaalcijfers');
      expect(outcome.status, SyncStatus.alreadyLanded);
      expect(await forge.headSha('main'), 'commit-main');
    });
  });

  group('SyncEngine edge cases', () {
    test('nothing queued is not an error', () async {
      final outcome = await engineWith(FakeForge(repo)).flushDeck('decks/a');
      expect(outcome.status, SyncStatus.nothingToCommit);
      expect(outcome.isSettled, isTrue);
    });

    test('a discarded working copy drops its pending commit', () async {
      await save('# Werk');
      await mirror.discardDeck('decks/kwartaalcijfers');

      final outcome = await engineWith(
        FakeForge(repo),
      ).flushDeck('decks/kwartaalcijfers');
      expect(outcome.status, SyncStatus.nothingToCommit);
      expect(await outbox.isEmpty, isTrue);
    });

    test('a brand-new deck commits without a remote counterpart', () async {
      await mirror.writeDeck('decks/nieuw', {
        'decks/nieuw/deck.md': _b('# Splinternieuw'),
      });
      await outbox.enqueue(
        const PendingCommit(
          deckDir: 'decks/nieuw',
          branch: 'main',
          message: 'Nieuw deck',
          baseSha: 'commit-main',
        ),
      );

      final outcome = await engineWith(
        FakeForge(repo),
      ).flushDeck('decks/nieuw');
      expect(outcome.status, SyncStatus.committed);
      expect(
        utf8.decode(repo.files['decks/nieuw/deck.md']!),
        '# Splinternieuw',
      );
    });
  });

  group('work branch (D3)', () {
    const work = 'decks/kwartaalcijfers/2026-07-18';

    test('a round that began offline: the flush creates the work branch', () async {
      // The first save of a round happened on an aeroplane: the work branch
      // never got created. forkFrom lets the flush make it on landing, so
      // "verbinding kwijt is nooit werk kwijt" holds even for the first save.
      await mirror.writeDeck('decks/kwartaalcijfers', {
        'decks/kwartaalcijfers/deck.md': _b('# Concept'),
      });
      await outbox.enqueue(
        const PendingCommit(
          deckDir: 'decks/kwartaalcijfers',
          branch: work, // a branch that does not exist yet
          message: 'concept',
          baseSha: '', // no base known offline; the flush fills it
          forkFrom: 'main',
        ),
      );
      expect(repo.branches.containsKey(work), isFalse);

      final outcome = await engineWith(
        FakeForge(repo),
      ).flushDeck('decks/kwartaalcijfers');

      expect(outcome.status, SyncStatus.committed);
      // The branch now exists, forked from main, carrying our commit; main is
      // untouched — landing on it is a separate, gated act (the review PR).
      expect(repo.branches[work], outcome.sha);
      expect(repo.branches['main'], 'commit-main');
      expect(await outbox.isEmpty, isTrue);
    });

    test('an existing work branch is committed onto, not recreated', () async {
      repo.branches[work] = 'commit-main'; // created earlier in the round
      await mirror.writeDeck('decks/kwartaalcijfers', {
        'decks/kwartaalcijfers/deck.md': _b('# Volgende'),
      });
      await outbox.enqueue(
        const PendingCommit(
          deckDir: 'decks/kwartaalcijfers',
          branch: work,
          message: 'volgende',
          baseSha: '',
          forkFrom: 'main',
        ),
      );

      final outcome = await engineWith(
        FakeForge(repo),
      ).flushDeck('decks/kwartaalcijfers');
      expect(outcome.status, SyncStatus.committed);
      expect(repo.branches[work], outcome.sha);
      expect(repo.branches[work], isNot('commit-main')); // advanced
    });
  });
}

extension on PendingCommit {
  PendingCommit copyWithBase(String baseSha) => PendingCommit(
    deckDir: deckDir,
    branch: branch,
    message: message,
    baseSha: baseSha,
  );
}
