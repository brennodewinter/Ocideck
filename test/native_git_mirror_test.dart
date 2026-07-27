@TestOn('vm')
// Deze suite doet échte git-subprocessen (clone/commit/push/diff). Op de
// Windows-CI zijn die onder gelijktijdige belasting fors trager dan de 30s die
// het testframework standaard per test geeft, wat losstaande tests
// intermitterend liet aflopen (#933). Alléén op Windows krijgen ze daarom ruimer
// de tijd; elders blijft de strakke standaard staan, zodat een echte vastloper
// lokaal snel opvalt.
@OnPlatform(<String, dynamic>{'windows': Timeout(Duration(minutes: 3))})
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/models/git_settings.dart';
import 'package:ocideck/services/git/deck_search.dart';
import 'package:ocideck/services/git/git_cli_io.dart';
import 'package:ocideck/services/git/native_git_mirror_api.dart';
import 'package:ocideck/services/git/native_git_mirror_io.dart';

import 'git_deck_mirror_contract_test.dart' show runDeckMirrorContract;
import 'support/temp_dir.dart';

// NativeGitMirror over een échte lokale git-repo. De opslag-methodes moeten voor
// exact hetzelfde DeckMirror-contract slagen als de REST-variant; de commit/push
// wordt tegen een bare origin op schijf gedraaid, zodat de mechaniek (landen,
// conflict, offline) echt getest is en niet nagebootst.

Uint8List _b(String s) => Uint8List.fromList(utf8.encode(s));

Future<void> _rawGit(List<String> args, String cwd) async {
  final r = await Process.run(
    'git',
    [
      '-c',
      'user.name=Test',
      '-c',
      'user.email=t@example.org',
      '-c',
      'commit.gpgsign=false',
      ...args,
    ],
    workingDirectory: cwd,
    environment: {
      'GIT_TERMINAL_PROMPT': '0',
      'GIT_CONFIG_NOSYSTEM': '1',
      'GIT_CONFIG_GLOBAL': '/dev/null',
    },
  );
  if (r.exitCode != 0) {
    throw StateError('git ${args.join(' ')} → ${r.stderr}');
  }
}

void main() {
  // ── Opslag-contract: gelijkwaardig aan DraftMirror ─────────────────────────
  // De opslag-methodes werken op de werkboom en hebben geen clone nodig.
  group('storage contract', () {
    late Directory temp;
    late NativeGitMirror mirror;
    setUp(() async {
      temp = Directory.systemTemp.createTempSync('ngm_contract');
      mirror = (await createNativeGitMirror(
        git: NativeGitCli(),
        config: const GitRepoConfig(
          baseUrl: 'file:///x',
          owner: 'x',
          repo: 'origin',
        ),
        token: '',
        baseDir: '${temp.path}/m',
      ))!;
    });
    tearDown(() => deleteTempDir(temp));

    runDeckMirrorContract(
      'NativeGitMirror',
      () => mirror,
      expectRealHistory: true,
    );
  });

  // ── Git-mechaniek tegen een echte bare origin ──────────────────────────────
  group('native commit/push', () {
    late Directory temp;
    late String bare;
    late GitRepoConfig config;
    late NativeGitMirror mirror;
    const deckDir = 'decks/kwartaalcijfers';

    setUp(() async {
      temp = Directory.systemTemp.createTempSync('ngm');
      Directory('${temp.path}/x').createSync(recursive: true);
      bare = '${temp.path}/x/origin.git';
      await _rawGit([
        'init',
        '--bare',
        '--initial-branch=main',
        bare,
      ], temp.path);

      // Seed: een clone met een beginversie van het deck, gepusht naar origin.
      final seed = '${temp.path}/seed';
      await _rawGit(['clone', bare, seed], temp.path);
      File('$seed/$deckDir/deck.md')
        ..parent.createSync(recursive: true)
        ..writeAsStringSync('# Kwartaalcijfers\n');
      await _rawGit(['add', '-A'], seed);
      await _rawGit(['commit', '-m', 'init'], seed);
      await _rawGit(['push', 'origin', 'main'], seed);

      config = GitRepoConfig(
        baseUrl: 'file://${temp.path}',
        owner: 'x',
        repo: 'origin',
      );
      mirror = (await createNativeGitMirror(
        git: NativeGitCli(),
        config: config,
        token: '',
        baseDir: '${temp.path}/clone',
      ))!;
    });
    tearDown(() => deleteTempDir(temp));

    test('prepareForOpen kloont en leest het deck', () async {
      await mirror.prepareForOpen();
      final files = await mirror.readDeck(deckDir);
      expect(
        utf8.decode(files['$deckDir/deck.md']!),
        contains('Kwartaalcijfers'),
      );
      expect(await mirror.headSha(), isNotNull);
    });

    test('commitDeck landt op de forge, met de pool-blob', () async {
      await mirror.prepareForOpen();
      final result = await mirror.commitDeck(deckDir, {
        '$deckDir/deck.md': _b('# Nieuwe titel\n'),
        'assets/abc123.png': _b('PNGBYTES'),
      }, 'wijziging');
      expect(result.outcome, GitCommitOutcome.pushed);

      // Verse clone van origin ziet de nieuwe inhoud én de blob.
      final verify = '${temp.path}/verify';
      await _rawGit(['clone', bare, verify], temp.path);
      expect(
        File('$verify/$deckDir/deck.md').readAsStringSync(),
        contains('Nieuwe titel'),
      );
      expect(File('$verify/assets/abc123.png').existsSync(), isTrue);
    });

    test(
      'commitDeck met een werkbranch pusht die branch, niet main (D3)',
      () async {
        await mirror.prepareForOpen();
        const work = 'decks/kwartaalcijfers/2026-07-18';

        final first = await mirror.commitDeck(
          deckDir,
          {'$deckDir/deck.md': _b('# Concept-ronde\n')},
          'concept 1',
          workBranch: work,
          forkFrom: 'main',
        );
        expect(first.outcome, GitCommitOutcome.pushed);

        // Een tweede opslag blijft op dezelfde werkbranch voortbouwen.
        final second = await mirror.commitDeck(
          deckDir,
          {'$deckDir/deck.md': _b('# Concept-ronde 2\n')},
          'concept 2',
          workBranch: work,
          forkFrom: 'main',
        );
        expect(second.outcome, GitCommitOutcome.pushed);

        // Op de origin: main draagt de beginversie, de werkbranch onze ronde.
        final verify = '${temp.path}/verifywb';
        await _rawGit(['clone', bare, verify], temp.path);
        expect(
          File('$verify/$deckDir/deck.md').readAsStringSync(),
          contains('# Kwartaalcijfers'),
          reason: 'main ongemoeid',
        );
        await _rawGit(['checkout', work], verify);
        expect(
          File('$verify/$deckDir/deck.md').readAsStringSync(),
          contains('Concept-ronde 2'),
        );
      },
    );

    test('niets veranderd → unchanged', () async {
      await mirror.prepareForOpen();
      final result = await mirror.commitDeck(deckDir, {
        '$deckDir/deck.md': _b('# Kwartaalcijfers\n'),
      }, 'geen wijziging');
      expect(result.outcome, GitCommitOutcome.unchanged);
    });

    test('een verzette branch → committedConflict, lokaal bewaard', () async {
      await mirror.prepareForOpen();

      // Iemand anders pusht intussen een andere versie.
      final other = '${temp.path}/other';
      await _rawGit(['clone', bare, other], temp.path);
      File(
        '$other/$deckDir/deck.md',
      ).writeAsStringSync('# Van iemand anders\n');
      await _rawGit(['add', '-A'], other);
      await _rawGit(['commit', '-m', 'ander'], other);
      await _rawGit(['push', 'origin', 'main'], other);

      final result = await mirror.commitDeck(deckDir, {
        '$deckDir/deck.md': _b('# Onze versie\n'),
      }, 'onze');
      expect(result.outcome, GitCommitOutcome.committedConflict);

      // Onze commit staat lokaal (niet weg), de forge heeft die van de ander.
      expect(result.sha, isNotNull);
      final verify = '${temp.path}/verify2';
      await _rawGit(['clone', bare, verify], temp.path);
      expect(
        File('$verify/$deckDir/deck.md').readAsStringSync(),
        contains('iemand anders'),
      );
    });

    test('history geeft de commits van het deck, nieuwste eerst', () async {
      await mirror.prepareForOpen();
      await mirror.commitDeck(deckDir, {
        '$deckDir/deck.md': _b('# Tweede versie\n'),
      }, 'tweede');
      final log = await mirror.history(deckDir);
      expect(log.length, greaterThanOrEqualTo(2));
      expect(log.first.subject, 'tweede'); // nieuwste eerst
      expect(log.first.pushed, isTrue); // gepusht
      expect(log.first.sha, isNotEmpty);
      expect(log.first.shortSha.length, 7);
      // De init-commit staat er ook nog.
      expect(log.any((e) => e.subject == 'init'), isTrue);
    });

    test('een niet-gepushte commit is als zodanig gemarkeerd', () async {
      await mirror.prepareForOpen();
      Directory(bare).renameSync('$bare.weg'); // origin onbereikbaar
      await mirror.commitDeck(deckDir, {
        '$deckDir/deck.md': _b('# Lokaal\n'),
      }, 'alleen lokaal');
      Directory('$bare.weg').renameSync(bare);
      final log = await mirror.history(deckDir);
      expect(log.first.subject, 'alleen lokaal');
      expect(log.first.pushed, isFalse); // wacht nog om gepusht te worden
    });

    test('het token belandt nooit in .git/config (OQ-10)', () async {
      const secret = 'geheim-pat-abc123';
      final tokenMirror = (await createNativeGitMirror(
        git: NativeGitCli(),
        config: config,
        token: secret,
        baseDir: '${temp.path}/tokenclone',
      ))!;
      await tokenMirror.prepareForOpen();
      // Een echte commit-cyclus (push faalt op file:// met een auth-header, maar
      // de commit landt lokaal — genoeg om .git/config te laten schrijven).
      await tokenMirror.commitDeck(deckDir, {
        '$deckDir/deck.md': _b('# Met token\n'),
      }, 'met token');
      final gitConfig = File(
        '${temp.path}/tokenclone/.git/config',
      ).readAsStringSync();
      expect(gitConfig, isNot(contains(secret)));
      expect(gitConfig.toLowerCase(), isNot(contains('extraheader')));

      // En breder dan alleen config: nergens in de clone — dus ook niet in een
      // reflog, een credential-cache of een tracebestand dat git zelf had
      // kunnen wegschrijven. Dit is de vorm die OQ-10 vraagt; op elk platform
      // waar deze suite draait, bewijst hij het daar.
      final leaked = <String>[];
      for (final entity in Directory(
        '${temp.path}/tokenclone',
      ).listSync(recursive: true, followLinks: false)) {
        if (entity is! File) continue;
        final List<int> bytes;
        try {
          bytes = entity.readAsBytesSync();
        } on FileSystemException {
          continue; // niet leesbaar is ook niet lekbaar
        }
        // Ruwe bytes, want een pack of een index is geen tekst.
        if (_containsBytes(bytes, utf8.encode(secret))) {
          leaked.add(entity.path);
        }
      }
      expect(
        leaked,
        isEmpty,
        reason: 'het token staat op schijf in: ${leaked.join(', ')}',
      );
    });

    test('geen verbinding → committedOffline, commit blijft lokaal', () async {
      await mirror.prepareForOpen();
      // Maak de origin onbereikbaar.
      Directory(bare).renameSync('$bare.weg');

      final result = await mirror.commitDeck(deckDir, {
        '$deckDir/deck.md': _b('# Offline gemaakt\n'),
      }, 'offline');
      expect(result.outcome, GitCommitOutcome.committedOffline);
      expect(result.sha, isNotNull);

      // Origin terug: sync duwt de lokale commit alsnog omhoog.
      Directory('$bare.weg').renameSync(bare);
      final synced = await mirror.sync();
      expect(synced.outcome, GitCommitOutcome.pushed);
      final verify = '${temp.path}/verify3';
      await _rawGit(['clone', bare, verify], temp.path);
      expect(
        File('$verify/$deckDir/deck.md').readAsStringSync(),
        contains('Offline gemaakt'),
      );
    });

    // ── git grep als zoekversneller (§9.3) ──────────────────────────────────
    group('grepDeckDirs', () {
      test('vindt de deckmap waarvan de deck.md de term bevat', () async {
        await mirror.prepareForOpen();
        final dirs = await mirror.grepDeckDirs(
          'Kwartaalcijfers',
          caseSensitive: false,
          branch: 'main',
        );
        expect(dirs, [deckDir]);
      });

      test('niets gevonden geeft een lege lijst, geen fout', () async {
        await mirror.prepareForOpen();
        final dirs = await mirror.grepDeckDirs(
          'bestaatnietinditdeck',
          caseSensitive: false,
          branch: 'main',
        );
        // Exitcode 1 van git grep is "niets gevonden" — een leeg, exhaustief
        // antwoord, niet een terugval naar null.
        expect(dirs, <String>[]);
      });

      test('is hoofdlettergevoelig op verzoek', () async {
        await mirror.prepareForOpen();
        // De inhoud is '# Kwartaalcijfers' (hoofdletter K).
        expect(
          await mirror.grepDeckDirs(
            'kwartaalcijfers',
            caseSensitive: true,
            branch: 'main',
          ),
          <String>[],
        );
        expect(
          await mirror.grepDeckDirs(
            'kwartaalcijfers',
            caseSensitive: false,
            branch: 'main',
          ),
          [deckDir],
        );
      });

      test('een term met een leidend streepje versnelt niet', () async {
        await mirror.prepareForOpen();
        // De gehardde runner weigert een operand met een streepje; grep valt dan
        // terug (null) in plaats van te proberen.
        expect(
          await mirror.grepDeckDirs('-x', caseSensitive: false, branch: 'main'),
          isNull,
        );
      });

      test('een andere branch dan de uitgecheckte versnelt niet', () async {
        await mirror.prepareForOpen();
        expect(
          await mirror.grepDeckDirs(
            'Kwartaalcijfers',
            caseSensitive: false,
            branch: 'ergens-anders',
          ),
          isNull,
        );
      });

      test('zonder clone versnelt het niet', () async {
        // Een verse mirror, nooit geopend: er is niets om te doorzoeken, dus null
        // en de aanroeper valt terug op de volledige scan.
        final fresh = (await createNativeGitMirror(
          git: NativeGitCli(),
          config: config,
          token: '',
          baseDir: '${temp.path}/nogrep',
        ))!;
        expect(
          await fresh.grepDeckDirs('x', caseSensitive: false, branch: 'main'),
          isNull,
        );
      });

      test('NativeGrepShortlister verpakt de treffers exhaustief', () async {
        await mirror.prepareForOpen();
        final shortlister = NativeGrepShortlister(mirror);

        final hit = await shortlister.shortlist(
          'Kwartaalcijfers',
          caseSensitive: false,
          branch: 'main',
        );
        expect(hit, isNotNull);
        expect(hit!.deckDirs, {deckDir});
        expect(hit.coverage, DeckSearchCoverage.exhaustive);

        // Kan de mirror niet versnellen, dan geeft de shortlister null door.
        expect(
          await shortlister.shortlist(
            '-x',
            caseSensitive: false,
            branch: 'main',
          ),
          isNull,
        );
      });
    });
  });
}

/// Zoekt [needle] in [haystack] op byte-niveau — een pack of een index is geen
/// tekst, dus een string-zoektocht zou daar overheen kijken.
bool _containsBytes(List<int> haystack, List<int> needle) {
  if (needle.isEmpty || haystack.length < needle.length) return false;
  for (var i = 0; i <= haystack.length - needle.length; i++) {
    var match = true;
    for (var j = 0; j < needle.length; j++) {
      if (haystack[i + j] != needle[j]) {
        match = false;
        break;
      }
    }
    if (match) return true;
  }
  return false;
}
