import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ocideck/services/git/deck_mirror.dart';
import 'package:ocideck/services/git/draft_store.dart';
import 'package:ocideck/services/git/draft_store_io.dart';
// The web branch of the conditional export. It leans on nothing browser-only —
// shared_preferences mocks on the VM — so it runs the very same contract as the
// desktop store. That equivalence is the point: it is exactly what an IndexedDB
// draft could never have given us here (§8.3).
import 'package:ocideck/services/git/draft_store_web.dart';
import 'package:ocideck/services/git/git_forge.dart';

Uint8List _b(String s) => Uint8List.fromList(utf8.encode(s));

/// The contract every [DeckMirror] must honour, stated once and run against
/// every implementation.
///
/// The same shape as the GitForge contract, and for the same reason: in Phase 3
/// `NativeGitMirror` must satisfy exactly this before it can replace
/// `DraftMirror` as the editing target. Whatever is asserted here is what the
/// editor may rely on regardless of which mirror is underneath — so
/// implementation specifics (where bytes land, what a checkpoint costs) stay out.
void runDeckMirrorContract(
  String name,
  DeckMirror Function() build, {
  bool expectRealHistory = false,
}) {
  group('$name honours the DeckMirror contract', () {
    late DeckMirror mirror;

    setUp(() => mirror = build());

    final deck = {
      'decks/kwartaalcijfers/deck.md': _b('# Kwartaalcijfers'),
      'decks/kwartaalcijfers/deck.notes': _b('spreeknotities'),
    };

    group('writeDeck / readDeck', () {
      test('reads back exactly what was written', () async {
        await mirror.writeDeck('decks/kwartaalcijfers', deck);
        expect(await mirror.readDeck('decks/kwartaalcijfers'), deck);
      });

      test('round-trips text that is not plain ascii', () async {
        // A working copy is text — deck.md is markdown, and both sidecar codecs
        // return JSON strings. Binary members are deliberately *not* in this
        // contract: the browser store cannot hold them (§8.3), so a caller may
        // not rely on it. What every mirror must do is keep text intact,
        // accents, emoji and all.
        const tricky = '# Kwartaal — cijfers\n\nÉén ≥ twee 🐾\n';
        await mirror.writeDeck('decks/a', {'decks/a/deck.md': _b(tricky)});
        expect(
          utf8.decode((await mirror.readDeck('decks/a'))['decks/a/deck.md']!),
          tricky,
        );
      });

      test('reaches nested members', () async {
        await mirror.writeDeck('decks/a', {
          'decks/a/deck.md': _b('# A'),
          'decks/a/sub/diep.md': _b('# Diep'),
        });
        expect(
          (await mirror.readDeck('decks/a')).keys,
          containsAll(['decks/a/deck.md', 'decks/a/sub/diep.md']),
        );
      });

      test('a second write replaces the deck rather than merging it', () async {
        // A member dropped from the deck must not linger: otherwise a deleted
        // slide would leave its asset behind and the next commit would carry a
        // file nothing references.
        await mirror.writeDeck('decks/a', {
          'decks/a/deck.md': _b('# A'),
          'decks/a/weg.png': _b('oud'),
        });
        await mirror.writeDeck('decks/a', {'decks/a/deck.md': _b('# A2')});

        final back = await mirror.readDeck('decks/a');
        expect(back.keys, ['decks/a/deck.md']);
        expect(utf8.decode(back['decks/a/deck.md']!), '# A2');
      });

      test('an absent deck reads as empty, not as an error', () async {
        expect(await mirror.readDeck('decks/bestaat-niet'), isEmpty);
      });

      test('decks do not bleed into each other', () async {
        await mirror.writeDeck('decks/a', {'decks/a/deck.md': _b('# A')});
        await mirror.writeDeck('decks/b', {'decks/b/deck.md': _b('# B')});

        expect((await mirror.readDeck('decks/a')).keys, ['decks/a/deck.md']);
        expect((await mirror.readDeck('decks/b')).keys, ['decks/b/deck.md']);
      });
    });

    group('hasDeck / discardDeck / deckDirs', () {
      test('hasDeck follows write and discard', () async {
        expect(await mirror.hasDeck('decks/a'), isFalse);
        await mirror.writeDeck('decks/a', {'decks/a/deck.md': _b('# A')});
        expect(await mirror.hasDeck('decks/a'), isTrue);
        await mirror.discardDeck('decks/a');
        expect(await mirror.hasDeck('decks/a'), isFalse);
      });

      test('discarding one deck leaves the others alone', () async {
        await mirror.writeDeck('decks/a', {'decks/a/deck.md': _b('# A')});
        await mirror.writeDeck('decks/b', {'decks/b/deck.md': _b('# B')});
        await mirror.discardDeck('decks/a');

        expect(await mirror.hasDeck('decks/b'), isTrue);
      });

      test('discarding what is not there is not an error', () async {
        await mirror.discardDeck('decks/nooit-bestaan');
      });

      test('deckDirs lists the working copies, sorted', () async {
        expect(await mirror.deckDirs(), isEmpty);
        await mirror.writeDeck('decks/zeta', {'decks/zeta/deck.md': _b('z')});
        await mirror.writeDeck('decks/alfa', {'decks/alfa/deck.md': _b('a')});

        expect(await mirror.deckDirs(), ['decks/alfa', 'decks/zeta']);
      });
    });

    group('guards', () {
      test('refuses a dir that is not a deck under the layout', () async {
        for (final dir in ['assets', 'decks/a/b', '../escape', 'los']) {
          await expectLater(
            mirror.writeDeck(dir, {'$dir/deck.md': _b('x')}),
            throwsA(isA<GitForgeException>()),
            reason: dir,
          );
        }
      });

      test('refuses a member that lands outside its deck', () async {
        for (final path in [
          'decks/b/deck.md', // een ánder deck
          'assets/x.png',
          '../buiten.md',
          'decks/a/../../etc/passwd',
        ]) {
          await expectLater(
            mirror.writeDeck('decks/a', {path: _b('x')}),
            throwsA(
              isA<GitForgeException>().having(
                (e) => e.kind,
                'kind',
                GitForgeError.malformed,
              ),
            ),
            reason: path,
          );
        }
      });

      test('a refused write leaves nothing behind', () async {
        await mirror.writeDeck('decks/a', {'decks/a/deck.md': _b('# goed')});
        await expectLater(
          mirror.writeDeck('decks/a', {
            'decks/a/deck.md': _b('# nieuw'),
            '../ontsnapt.md': _b('kwaad'),
          }),
          throwsA(isA<GitForgeException>()),
        );
        // The earlier good version must survive: a rejected write is not a
        // half-applied one.
        final back = await mirror.readDeck('decks/a');
        expect(utf8.decode(back['decks/a/deck.md']!), '# goed');
      });
    });

    group('honesty about what it is', () {
      test('reports its history capability honestly', () {
        // The seam of §8.1: UI that offers "commit" as its own act may only do
        // so when this is true. A queued draft must never be presented as a
        // commit log; a real clone may. Each implementation states which it is.
        expect(mirror.hasRealHistory, expectRealHistory);
      });
    });
  });
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory temp;
  late SharedPreferences prefs;

  setUp(() async {
    temp = Directory.systemTemp.createTempSync('ocideck_mirror');
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
  });
  tearDown(() {
    if (temp.existsSync()) temp.deleteSync(recursive: true);
  });

  runDeckMirrorContract(
    'DraftMirror (on-disk)',
    () => DraftMirror(store: FileDraftStore(baseDir: temp)),
  );

  group('FileDraftStore is not limited to text', () {
    test('holds a binary member, unlike the browser store', () async {
      // Not in the contract (see there), but free on a filesystem — and the
      // moment a deck grows a binary sidecar, this is the difference between the
      // two platforms rather than a surprise.
      final png = Uint8List.fromList([0x89, 0x50, 0x4e, 0x47, 0x00, 0xff]);
      final mirror = DraftMirror(store: FileDraftStore(baseDir: temp));
      await mirror.writeDeck('decks/a', {
        'decks/a/deck.md': _b('# A'),
        'decks/a/img.png': png,
      });
      expect((await mirror.readDeck('decks/a'))['decks/a/img.png'], png);
    });
  });

  group('FileDraftStore durability', () {
    test(
      'reports itself durable, and is: a fresh store sees the deck',
      () async {
        // P2 in one assertion: work written here survives the app, so losing the
        // network can never lose the deck.
        await DraftMirror(
          store: FileDraftStore(baseDir: temp),
        ).writeDeck('decks/a', {'decks/a/deck.md': _b('# A')});

        final fresh = DraftMirror(store: FileDraftStore(baseDir: temp));
        expect(fresh.isDurable, isTrue);
        expect(
          utf8.decode((await fresh.readDeck('decks/a'))['decks/a/deck.md']!),
          '# A',
        );
      },
    );

    test('the layout on disk is the repo layout', () async {
      // Not cosmetic: Phase 3 turns this directory into a real clone, so the
      // working tree must already *be* the repo (§6, §8.2).
      await DraftMirror(store: FileDraftStore(baseDir: temp)).writeDeck(
        'decks/kwartaalcijfers',
        {'decks/kwartaalcijfers/deck.md': _b('# Q')},
      );

      expect(
        File('${temp.path}/decks/kwartaalcijfers/deck.md').existsSync(),
        isTrue,
      );
    });
  });

  runDeckMirrorContract(
    'DraftMirror (browser key/value store)',
    () => DraftMirror(store: PrefsDraftStore(prefs: prefs)),
  );

  group('PrefsDraftStore limits', () {
    test('survives a reload: a fresh store reads the deck back', () async {
      // P2 on the web, which until now had nothing at all: text written here
      // outlives the page.
      await DraftMirror(
        store: PrefsDraftStore(prefs: prefs),
      ).writeDeck('decks/a', {'decks/a/deck.md': _b('# A')});

      final fresh = DraftMirror(store: PrefsDraftStore(prefs: prefs));
      expect(fresh.isDurable, isTrue);
      expect(
        utf8.decode((await fresh.readDeck('decks/a'))['decks/a/deck.md']!),
        '# A',
      );
    });

    test('refuses a member that is not text, rather than mangling it', () async {
      // The whole design rests on "a working copy is text". This makes that
      // assumption checkable: add a binary member later and you get told, rather
      // than silently storing broken UTF-8.
      final png = Uint8List.fromList([0x89, 0x50, 0x4e, 0x47, 0xff, 0xfe]);
      await expectLater(
        PrefsDraftStore(prefs: prefs).writeDeck('decks/a', {
          'decks/a/deck.md': _b('# A'),
          'decks/a/plaatje.png': png,
        }),
        throwsA(
          isA<DraftStoreUnsupported>().having(
            (e) => e.message,
            'message',
            contains('plaatje.png'),
          ),
        ),
      );
    });

    test(
      'refuses a deck that will not fit, with a size in the message',
      () async {
        final huge = _b('x' * (PrefsDraftStore.maxDraftBytes + 1));
        await expectLater(
          PrefsDraftStore(
            prefs: prefs,
          ).writeDeck('decks/a', {'decks/a/deck.md': huge}),
          throwsA(
            isA<DraftStoreUnsupported>().having(
              (e) => e.message,
              'message',
              contains('te groot'),
            ),
          ),
        );
      },
    );

    test('an ordinary deck is nowhere near the ceiling', () async {
      // Guards against the cap being cargo-culted as "decks are big": a real
      // deck.md is kilobytes. The 32 MiB in FileService is a hostile-input
      // guard, not a size to design storage around.
      final realistic = _b('# Titel\n\n${'Een regel tekst.\n' * 2000}');
      await PrefsDraftStore(
        prefs: prefs,
      ).writeDeck('decks/a', {'decks/a/deck.md': realistic});
      expect(realistic.length, lessThan(PrefsDraftStore.maxDraftBytes ~/ 20));
    });

    test('discarding a deck leaves the rest of the prefs domain alone', () async {
      // The settings live in this same store; a draft must never take them with
      // it.
      await prefs.setString('languageCode', 'nl');
      final store = PrefsDraftStore(prefs: prefs);
      await store.writeDeck('decks/a', {'decks/a/deck.md': _b('# A')});
      await store.discardDeck('decks/a');

      expect(prefs.getString('languageCode'), 'nl');
    });

    test('deckDirs ignores a key that is not a deck', () async {
      await prefs.setString('git_draft::assets', '{}');
      await prefs.setString('languageCode', 'nl');
      await PrefsDraftStore(
        prefs: prefs,
      ).writeDeck('decks/echt', {'decks/echt/deck.md': _b('# E')});

      expect(await PrefsDraftStore(prefs: prefs).deckDirs(), ['decks/echt']);
    });

    test('an unreadable draft reads as empty rather than throwing', () async {
      await prefs.setString('git_draft::decks/a', 'geen json');
      expect(await PrefsDraftStore(prefs: prefs).readDeck('decks/a'), isEmpty);
    });
  });
}
