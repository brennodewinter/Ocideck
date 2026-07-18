import 'dart:typed_data';

import 'package:path/path.dart' as p;

import '../../utils/log.dart';
import 'deck_mirror.dart';
import 'git_forge.dart';
import 'outbox.dart';

/// Bewerkt de opgeslagen deckbestanden vlak vóór de commit, en geeft de
/// volledige upsert-set terug: het (herschreven) `deck.md` plus de nog
/// ontbrekende pool-blobs.
///
/// Dít is waar afbeeldingen alsnog gepoold worden bij het synchroniseren. De
/// werkkopie bewaart offline een `deck.md` met `mem:`-verwijzingen — de bytes
/// stonden op dat moment in het geheugen, niet in de repo. Bij verbinding zet
/// deze hook die om naar `repo:`-verwijzingen en levert de bijbehorende blobs,
/// zodat de commit compleet is. Gooit [GitForgeException] als het poolen de
/// forge nodig heeft en die er niet is — dan blijft het deck in de wachtrij.
typedef DeckFilePreparer =
    Future<Map<String, Uint8List>> Function(
      PendingCommit commit,
      Map<String, Uint8List> stored,
    );

/// Hoe één deck uit de wachtrij afliep.
enum SyncStatus {
  /// Gecommit en gepusht; [SyncOutcome.sha] is de nieuwe basis.
  committed,

  /// Stond er al precies zo — zie [SyncEngine.flushDeck]. Ook een goede afloop:
  /// het werk ís op de forge, alleen niet door déze poging.
  alreadyLanded,

  /// Iemand anders heeft de branch verzet. Blijft in de wachtrij staan; de
  /// aanroeper moet herladen (of, vanaf Fase 3, mergen).
  conflict,

  /// Netwerk of forge deed het niet. Blijft in de wachtrij staan.
  failed,

  /// De mirror had niets voor dit deck. De wachtende commit is opgeruimd.
  nothingToCommit,
}

class SyncOutcome {
  final String deckDir;
  final SyncStatus status;

  /// De nieuwe basis-sha bij [SyncStatus.committed] of
  /// [SyncStatus.alreadyLanded].
  final String? sha;

  /// Uitlegbare tekst bij [SyncStatus.conflict] en [SyncStatus.failed].
  final String? message;

  const SyncOutcome({
    required this.deckDir,
    required this.status,
    this.sha,
    this.message,
  });

  bool get isSettled =>
      status == SyncStatus.committed ||
      status == SyncStatus.alreadyLanded ||
      status == SyncStatus.nothingToCommit;
}

/// Verzoent de werkkopie met de forge (§8).
///
/// De editor schrijft naar de [DeckMirror] en zet een intentie in de [Outbox];
/// deze klasse maakt daar commits van zodra dat kan. Verbinding kwijt is dus
/// nooit werk kwijt (P2): de mirror is duurzaam en de wachtrij overleeft het
/// afsluiten.
class SyncEngine {
  SyncEngine({required this.forge, required this.mirror, required this.outbox});

  final GitForge forge;
  final DeckMirror mirror;
  final Outbox outbox;

  /// Werk alles af wat wacht. Een deck dat faalt houdt de rest niet tegen: ze
  /// zijn onafhankelijk, en één onbereikbare branch mag niet betekenen dat het
  /// andere deck ook blijft hangen.
  ///
  /// [prepare] krijgt elk deck vlak vóór de commit; zo worden offline
  /// toegevoegde afbeeldingen alsnog gepoold. Zonder [prepare] gaat de werkkopie
  /// ongewijzigd omhoog.
  Future<List<SyncOutcome>> flush({DeckFilePreparer? prepare}) async {
    final out = <SyncOutcome>[];
    for (final commit in await outbox.pending()) {
      out.add(await _flush(commit, prepare));
    }
    return out;
  }

  /// Werk één deck af. Geeft [SyncStatus.nothingToCommit] wanneer er niets
  /// wacht.
  Future<SyncOutcome> flushDeck(
    String deckDir, {
    DeckFilePreparer? prepare,
  }) async {
    final commit = await outbox.forDeck(deckDir);
    if (commit == null) {
      return SyncOutcome(deckDir: deckDir, status: SyncStatus.nothingToCommit);
    }
    return _flush(commit, prepare);
  }

  Future<SyncOutcome> _flush(
    PendingCommit commit,
    DeckFilePreparer? prepare,
  ) async {
    final stored = await mirror.readDeck(commit.deckDir);
    if (stored.isEmpty) {
      // Geen werkkopie meer (deck verworpen): de intentie is zinloos geworden.
      await outbox.remove(commit.deckDir);
      return SyncOutcome(
        deckDir: commit.deckDir,
        status: SyncStatus.nothingToCommit,
      );
    }

    try {
      // Poolen kan de forge nodig hebben (de bestaande blobs opsommen); een
      // netwerkfout hier is dus gewoon "nog offline" en valt in de catch.
      final upserts = prepare == null ? stored : await prepare(commit, stored);

      // Een ronde kan offline op zijn werkbranch begonnen zijn: die branch
      // bestaat dan nog niet op de forge (D3). De eerste commit van een ronde
      // (forkFrom gezet) landt op de kop van de werkbranch — hij tákt net af, dus
      // er is nog geen basis om tegen te botsen; bestaat de branch nog niet, maak
      // hem dan af van waar de ronde vandaan kwam. Een netwerkfout hier valt net
      // als de rest in de catch — het werk blijft gewoon in de wachtrij.
      var baseSha = commit.baseSha;
      if (commit.forkFrom != null) {
        final branches = await forge.listBranches();
        final match = branches.where((b) => b.name == commit.branch);
        baseSha = match.isNotEmpty
            ? match.first.sha
            : (await forge.createBranch(
                commit.branch,
                fromRef: commit.forkFrom!,
              )).sha;
      }

      // Idempotentie en verwijderingen kijken alléén naar de deckmap, niet naar
      // de pool-blobs die buiten de map liggen: een blob is content-geadresseerd
      // en onveranderlijk, dus die telt niet mee in "staat het er al precies zo".
      final deckLocal = <String, Uint8List>{
        for (final entry in upserts.entries)
          if (p.posix.isWithin(commit.deckDir, p.posix.normalize(entry.key)))
            entry.key: entry.value,
      };
      final remote = await _remoteDeck(commit.branch, commit.deckDir);

      // De idempotentie-garantie van §8.5, en ze is eenvoudiger dan ze klinkt:
      // stáát het er al precies zo, dan is het werk geland. Dat dekt de nare
      // volgorde waarin de commit slaagde maar het opruimen van de wachtrij niet
      // — bij een herstart zou een blinde retry op de oude baseSha anders een
      // conflict opleveren met onze éigen commit. Vergelijken op inhoud in
      // plaats van op sha lost dat op zonder ergens een vlag te hoeven bewaren.
      if (_sameTree(deckLocal, remote)) {
        await outbox.remove(commit.deckDir);
        return SyncOutcome(
          deckDir: commit.deckDir,
          status: SyncStatus.alreadyLanded,
          sha: await forge.headSha(commit.branch),
        );
      }

      final deletes = [
        for (final path in remote.keys)
          if (!deckLocal.containsKey(path)) path,
      ];
      final result = await forge.commitFiles(
        branch: commit.branch,
        message: commit.message,
        upserts: upserts,
        deletes: deletes,
        baseSha: baseSha,
      );
      await outbox.remove(commit.deckDir);
      return SyncOutcome(
        deckDir: commit.deckDir,
        status: SyncStatus.committed,
        sha: result.sha,
      );
    } on GitConflictException catch (e) {
      // Blijft staan: het werk is niet weg, het kan alleen niet zó landen.
      return SyncOutcome(
        deckDir: commit.deckDir,
        status: SyncStatus.conflict,
        message: e.message,
      );
    } on GitForgeException catch (e) {
      logWarning('SyncEngine: ${commit.deckDir} niet gesynct', e);
      return SyncOutcome(
        deckDir: commit.deckDir,
        status: SyncStatus.failed,
        message: e.message,
      );
    }
  }

  /// De bestanden van een deck zoals ze op [branch] staan. Leeg wanneer het deck
  /// er nog niet is (een nieuw deck).
  Future<Map<String, Uint8List>> _remoteDeck(
    String branch,
    String deckDir,
  ) async {
    final entries = await forge.listTree(branch, deckDir, recursive: true);
    final out = <String, Uint8List>{};
    for (final entry in entries) {
      if (entry.type != RepoEntryType.file) continue;
      out[entry.path] = await forge.readBlob(branch, entry.path);
    }
    return out;
  }

  static bool _sameTree(Map<String, Uint8List> a, Map<String, Uint8List> b) {
    if (a.length != b.length) return false;
    for (final entry in a.entries) {
      final other = b[entry.key];
      if (other == null || other.length != entry.value.length) return false;
      for (var i = 0; i < other.length; i++) {
        if (other[i] != entry.value[i]) return false;
      }
    }
    return true;
  }
}
