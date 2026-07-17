import 'dart:typed_data';

import '../../utils/log.dart';
import 'deck_mirror.dart';
import 'git_forge.dart';
import 'outbox.dart';

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
  Future<List<SyncOutcome>> flush() async {
    final out = <SyncOutcome>[];
    for (final commit in await outbox.pending()) {
      out.add(await _flush(commit));
    }
    return out;
  }

  /// Werk één deck af. Geeft [SyncStatus.nothingToCommit] wanneer er niets
  /// wacht.
  Future<SyncOutcome> flushDeck(String deckDir) async {
    final commit = await outbox.forDeck(deckDir);
    if (commit == null) {
      return SyncOutcome(deckDir: deckDir, status: SyncStatus.nothingToCommit);
    }
    return _flush(commit);
  }

  Future<SyncOutcome> _flush(PendingCommit commit) async {
    final local = await mirror.readDeck(commit.deckDir);
    if (local.isEmpty) {
      // Geen werkkopie meer (deck verworpen): de intentie is zinloos geworden.
      await outbox.remove(commit.deckDir);
      return SyncOutcome(
        deckDir: commit.deckDir,
        status: SyncStatus.nothingToCommit,
      );
    }

    try {
      final remote = await _remoteDeck(commit.branch, commit.deckDir);

      // De idempotentie-garantie van §8.5, en ze is eenvoudiger dan ze klinkt:
      // stáát het er al precies zo, dan is het werk geland. Dat dekt de nare
      // volgorde waarin de commit slaagde maar het opruimen van de wachtrij niet
      // — bij een herstart zou een blinde retry op de oude baseSha anders een
      // conflict opleveren met onze éigen commit. Vergelijken op inhoud in
      // plaats van op sha lost dat op zonder ergens een vlag te hoeven bewaren.
      if (_sameTree(local, remote)) {
        await outbox.remove(commit.deckDir);
        return SyncOutcome(
          deckDir: commit.deckDir,
          status: SyncStatus.alreadyLanded,
          sha: await forge.headSha(commit.branch),
        );
      }

      final deletes = [
        for (final path in remote.keys)
          if (!local.containsKey(path)) path,
      ];
      final result = await forge.commitFiles(
        branch: commit.branch,
        message: commit.message,
        upserts: local,
        deletes: deletes,
        baseSha: commit.baseSha,
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
