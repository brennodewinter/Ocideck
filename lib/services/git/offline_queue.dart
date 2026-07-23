// De twee helften van offline werken met een git-repo: het parkeren en het
// weer uitpakken.
//
// [queueDeckSave] zet een opslag zonder verbinding weg — de tekst in de
// werkkopie, de intentie in de outbox. [poolPendingDeck] haalt hem er vlak vóór
// de commit weer uit en maakt hem compleet. Ze horen bij elkaar: wat de eerste
// bewust ongepoold wegschrijft, is precies wat de tweede alsnog moet poolen, en
// die afspraak is nergens anders opgeschreven.
//
// Stonden tot #518 als privémethoden op `TabsNotifier`. Ze zijn geen
// toestandswerk: er komt geen tabblad, geen Riverpod en geen huidige selectie
// aan te pas — alleen een werkkopie, een outbox en een forge. Wat er wél
// toestandswerk aan was (de wachtrijteller ongeldig maken, de waarschuwingen
// aan de gebruiker) is achtergebleven waar het hoort.
import 'dart:convert';
import 'dart:typed_data';

import 'package:path/path.dart' as p;

import '../../models/deck.dart';
import '../../utils/log.dart';
import '../markdown_service.dart';
import 'asset_pool.dart';
import 'deck_mirror.dart';
import 'deck_repo_serializer.dart';
import 'draft_store.dart';
import 'git_forge.dart';
import 'outbox.dart';
import 'repo_asset_resolver.dart';

/// Hoe [queueDeckSave] afliep.
///
/// `refusal` is een gebruikersgerichte zin, niet een foutobject: de enige
/// manier waarop dit misgaat is een werkkopie die dit deck niet kan bergen, en
/// die weigering draagt haar eigen uitleg al mee.
typedef QueuedSave = ({bool queued, String? refusal});

/// Parkeer een opslag in de wachtrij: de tekst gaat naar de werkkopie, de
/// intentie in de outbox.
///
/// De werkkopie bewaart `deck.md` **ongepoold** — met `mem:`-verwijzingen,
/// zoals het deck nu in de editor staat. De afbeeldingen worden nog niet
/// omgezet: offline kunnen de blobs toch niet omhoog, en hun bytes staan nu nog
/// in het geheugen. Bij het synchroniseren pakt [poolPendingDeck] die op en
/// poolt ze alsnog, zodat de commit compleet landt (§8.3).
///
/// De herkomst van het tabblad blijft ongemoeid — dat is aan de aanroeper, en
/// er is ook niets nieuws geland om de basis op te verzetten.
Future<QueuedSave> queueDeckSave(
  DeckMirror mirror,
  Outbox outbox, {
  required Deck deck,
  required String deckDir,
  required String branch,
  required String message,
  required String baseSha,
  required MarkdownService md,
  String? forkFrom,
}) async {
  final deckFiles = mirrorDeckFiles(deck, deckDir: deckDir, md: md);
  try {
    await mirror.writeDeck(deckDir, deckFiles);
  } on DraftStoreUnsupported catch (e) {
    // De webwerkkopie kan dit deck niet bergen (te groot of niet-tekst). De
    // uitzondering is géén GitForgeException, dus zonder deze vangst liep hij
    // ongevangen door: geen melding, en niets in de wachtrij, terwijl de
    // desktop netjes "gaat mee zodra er weer verbinding is" toont. De
    // uitzondering draagt al een gebruikersgerichte tekst; die geven we terug.
    logWarning('queueDeckSave: webwerkkopie weigert het deck', e);
    return (queued: false, refusal: e.message);
  }
  await outbox.enqueue(
    PendingCommit(
      deckDir: deckDir,
      branch: branch,
      message: message,
      baseSha: baseSha,
      forkFrom: forkFrom,
    ),
  );
  return (queued: true, refusal: null);
}

/// Pool de afbeeldingen van een wachtend deck vlak vóór de commit: lees de
/// bewaarde `deck.md`, en zet zijn `mem:`-afbeeldingen om naar `repo:` met de
/// bijbehorende blobs (§8.3).
///
/// Zo landt een offline gemaakte afbeelding alsnog, zolang de bytes nog in het
/// geheugen staan; een afbeelding die na een herstart weg is houdt zijn
/// verwijzing en toont een placeholder.
///
/// Geeft [stored] ongewijzigd terug wanneer er geen leesbaar deck in zit — dan
/// valt er niets te poolen en gaan de bytes door zoals ze zijn.
Future<Map<String, Uint8List>> poolPendingDeck(
  GitForge forge,
  PendingCommit commit,
  Map<String, Uint8List> stored, {
  required MarkdownService md,
}) async {
  final raw = stored[p.posix.join(commit.deckDir, deckRepoFileName)];
  if (raw == null) return stored;
  final deck = md.parseDeck(utf8.decode(raw));
  if (deck == null) return stored;

  // deck.md draagt alleen de verwijzingen, dus de lagen eerst terughalen uit
  // de werkkopie: wat hier niet aan het deck hangt schrijft buildDeckRepoFiles
  // niet terug, en wachtend werk zou dat verliezen net als het landt.
  final sidecars = await withRepoSidecars(
    deck,
    deckDir: commit.deckDir,
    read: (path) async => stored[path],
  );

  final files = await buildDeckRepoFiles(
    sidecars.deck,
    md: md,
    pool: AssetPool(forge: forge, branch: commit.branch),
    deckDir: commit.deckDir,
    read: (path) async => stored[path],
    resolveBytes: repoAssetBytes(deck.projectPath),
  );
  return files.upserts;
}
