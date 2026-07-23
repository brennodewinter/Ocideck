import 'dart:typed_data';

import 'package:path/path.dart' as p;

import '../../utils/log.dart';
import 'deck_mirror.dart';
import 'deck_repo_serializer.dart';
import 'draft_store.dart';
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
    final Map<String, Uint8List> stored;
    try {
      stored = await mirror.readDeck(commit.deckDir);
    } on DraftStoreCorrupt catch (e) {
      // Beschadigde werkkopie: níét als "verworpen" behandelen. De commit valt
      // uit de wachtrij (de bytes zijn onherstelbaar), maar het wordt als een
      // échte fout gemeld in plaats van als het geruststellende "niets te
      // synchroniseren" — anders raakt offline werk stil zoek.
      logWarning('SyncEngine._flush: werkkopie beschadigd', e);
      await outbox.remove(commit.deckDir);
      return SyncOutcome(
        deckDir: commit.deckDir,
        status: SyncStatus.failed,
        message:
            'Een gewijzigd deck kon niet uit de wachtrij worden gelezen en is '
            'overgeslagen.',
      );
    }
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
        if (match.isEmpty) {
          baseSha = (await forge.createBranch(
            commit.branch,
            fromRef: commit.forkFrom!,
          )).sha;
        } else if (baseSha.isEmpty) {
          // Bestaat de branch al, dan nemen we zijn kop alléén over als deze
          // commit zelf geen basis draagt. Anders zou de guard altijd
          // fast-forwarden en schreven we weg wat er inmiddels op de branch
          // staat — precies het werk dat de wachtrij hoort te beschermen.
          baseSha = match.first.sha;
        }
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
        await _releaseLandedWork(commit.deckDir, stored);
        return SyncOutcome(
          deckDir: commit.deckDir,
          status: SyncStatus.alreadyLanded,
          sha: await forge.headSha(commit.branch),
        );
      }

      // Wat er in de repo staat maar niet in de werkkopie, is weggehaald: een
      // dia die verdween neemt zo ook haar bestanden mee. Met de sidecars als
      // uitzondering — waarom die soms niet van ons zijn staat bij
      // [_sidecarNietVanOns].
      final deletes = <String>[];
      for (final path in remote.keys) {
        if (deckLocal.containsKey(path)) continue;
        if (await _sidecarNietVanOns(path, remote)) continue;
        deletes.add(path);
      }
      final result = await forge.commitFiles(
        branch: commit.branch,
        message: commit.message,
        upserts: upserts,
        deletes: deletes,
        baseSha: baseSha,
      );
      await outbox.remove(commit.deckDir);
      await _releaseLandedWork(commit.deckDir, stored);
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

  /// Gooi de werkkopie weg nu dit deck bevestigd op de forge staat.
  ///
  /// Alleen ná een bevestigde landing — beide aanroepplekken staan achter
  /// `outbox.remove`, dus achter het punt waar de motor heeft vastgesteld dat
  /// het werk er is. Bij een conflict, een netwerkfout of een afwijzing komt de
  /// motor hier niet, en blijft alles staan.
  ///
  /// **En alleen als er sindsdien niets bij is gekomen.** Tussen het lezen van
  /// [flushed] en dit moment kan de gebruiker opnieuw hebben opgeslagen; dan
  /// draagt de werkkopie nieuw werk dat níét geland is en dat een nieuwe
  /// wachtende commit heeft gekregen. Dat weggooien zou precies het dataverlies
  /// zijn dat de wachtrij hoort te voorkomen. Bij het minste verschil laten we
  /// het staan — een kopie te veel is hier altijd goedkoper dan een kopie te
  /// weinig.
  ///
  /// Een fout tijdens het opruimen is geen mislukte synchronisatie: het werk
  /// staat op de forge. Loggen en doorgaan.
  Future<void> _releaseLandedWork(
    String deckDir,
    Map<String, Uint8List> flushed,
  ) async {
    if (!mirror.discardsLandedWork) return;
    try {
      final current = await mirror.readDeck(deckDir);
      if (current.isEmpty || !_sameTree(current, flushed)) return;
      await mirror.discardDeck(deckDir);
    } catch (e) {
      logWarning('SyncEngine: werkkopie opruimen na landing mislukt', e);
    }
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

/// Of [path] een sidecar is die deze build niet als de zijne kan lezen — en
/// dus niet verwijderd mag worden, ook al ontbreekt hij lokaal.
///
/// De sidecars zijn de bestanden in een deckmap die van iemand ánders kunnen
/// zijn. Kon deze build ze niet lezen (conflictmarkeringen uit een merge
/// buiten OciDeck, of een sidecar van een nieuwere versie), dan draagt het
/// deck die laag niet om een reden die niets zegt over wat er in de repo
/// hoort te staan — en "ontbreekt lokaal" is dan geen opdracht om andermans
/// werk te wissen. Buiten [SyncEngine._flush] omdat die methode tegen zijn
/// regelplafond zit; de regel is bovendien van de sidecar-laag, niet van de
/// flush.
Future<bool> _sidecarNietVanOns(
  String path,
  Map<String, Uint8List> remote,
) async {
  Future<Uint8List?> read(String q) async => remote[q];
  final state = switch (p.posix.basename(path)) {
    userNotesRepoFileName => repoUserNotesState(path, read),
    inkRepoFileName => repoInkState(path, read),
    dismissalsRepoFileName => repoDismissalsState(path, read),
    miauwRepoFileName => repoMiauwState(path, read),
    sealRepoFileName => repoSealState(path, read),
    _ => null,
  };
  if (state == null) return false;
  return await state != RepoSidecarState.ours;
}
