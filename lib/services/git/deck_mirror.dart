import 'dart:typed_data';

import 'package:path/path.dart' as p;

import '../../models/git_settings.dart';
import 'draft_store.dart';
import 'draft_store_factory.dart';
import 'git_forge.dart';

/// De werkkopie waar de editor naartoe schrijft (§8.1).
///
/// De forge is nooit het directe bewerkingsdoel: verbinding kwijt mag nooit werk
/// kwijt betekenen (P2). De editor schrijft hier, en de `SyncEngine` verzoent
/// het later met de forge (Fase 2).
///
/// Er komen twee implementaties, en [hasRealHistory] is de naad ertussen.
/// [DraftMirror] houdt één concept vast dat als één commit wordt geflusht;
/// `NativeGitMirror` (Fase 3) maakt echte lokale commits en kan er dus tien op
/// een vliegtuig bewaren. Die twee mogen niet als hetzelfde worden
/// gepresenteerd — vandaar dat de vraag beantwoordbaar is in plaats van
/// verzwegen.
abstract class DeckMirror {
  /// Schrijf de bestandenset van een deck naar de werkkopie. Slaagt offline.
  Future<void> writeDeck(String deckDir, Map<String, Uint8List> files);

  /// Lees de bestandenset terug. Leeg wanneer het deck er niet is.
  Future<Map<String, Uint8List>> readDeck(String deckDir);

  Future<bool> hasDeck(String deckDir);

  /// Gooi de werkkopie van een deck weg. Raakt de forge niet aan.
  Future<void> discardDeck(String deckDir);

  /// Welke decks een werkkopie hebben, als deckmap-paden.
  Future<List<String>> deckDirs();

  /// Onwaar voor [DraftMirror]: aanroepers mogen dan geen historie beloven,
  /// alleen "opgeslagen, gaat mee zodra er verbinding is".
  bool get hasRealHistory;

  /// Overleeft de werkkopie het afsluiten van de app? Onwaar betekent dat P2
  /// hier niet gehaald wordt en de UI dat moet zéggen in plaats van te doen
  /// alsof. Beide huidige stores melden waar — op desktop bestanden, op web de
  /// sleutel/waarde-opslag van de browser (§8.3).
  bool get isDurable;

  /// Of de werkkopie van een deck weg mag zodra het werk bevestigd op de forge
  /// staat.
  ///
  /// **Waar voor [DraftMirror].** Dat concept bestáát alleen om werk vast te
  /// houden tot het geland is; daarna is het een kopie zonder taak. Op web
  /// staat het in de sleutel/waarde-opslag van de browser — gedeeld met wie
  /// dat profiel verder gebruikt — en het draagt de volledige markdown, de
  /// gebruikersnotities en de annotaties. Voor een deck met een
  /// TLP-classificatie of persoonsgegevens is blijven staan de verkeerde
  /// standaard.
  ///
  /// **Onwaar voor `NativeGitMirror`.** Daar is de werkkopie een échte clone,
  /// en dat is precies waar `openDeckFromGitNative` het deck uit leest.
  /// Weghalen zou het bestand onder de gebruiker vandaan trekken en de historie
  /// die de clone draagt onbruikbaar maken. Die clone staat bovendien in de
  /// app-support-map, met de accountbescherming van het besturingssysteem
  /// eromheen — niet in een opslag die het hele browserprofiel deelt. Hier
  /// gelden dus andere feiten, niet alleen een andere implementatie.
  bool get discardsLandedWork;
}

/// De werkkopie zonder git: één concept per deck, dat in Fase 2 als één commit
/// omhoog gaat (§8.3).
///
/// Dit is de eerlijke ondergrens. Hij kan geen tien commits van een vliegtuig
/// bewaren — daarvoor bestaat `NativeGitMirror` — en presenteert zich ook niet
/// zo: [hasRealHistory] is onwaar.
class DraftMirror implements DeckMirror {
  DraftMirror({DraftStore? store}) : _store = store ?? createDraftStore();

  final DraftStore _store;

  @override
  bool get hasRealHistory => false;

  @override
  bool get isDurable => _store.isDurable;

  @override
  bool get discardsLandedWork => true;

  void _requireDeckDir(String deckDir) {
    if (GitRepoLayout.deckNameOf(deckDir) == null) {
      throw const GitForgeException(
        GitForgeError.malformed,
        'Pad is geen deckmap volgens de repo-layout',
      );
    }
  }

  @override
  Future<void> writeDeck(String deckDir, Map<String, Uint8List> files) async {
    _requireDeckDir(deckDir);
    for (final path in files.keys) {
      // Elk lid moet ónder de deckmap vallen. De set komt uit
      // buildPackageMembers, dus dit is geen vijandige invoer — maar een bug
      // daar zou hier stilletjes buiten het deck schrijven, en dat is precies
      // wat een containment-check hoort te vangen.
      //
      // Op de genormaliseerde vorm, niet de ruwe: `decks/a/../../etc/passwd`
      // begint letterlijk met `decks/a/` maar is na normalisatie `etc/passwd`.
      // Een prefix-vergelijking op het ruwe pad zou dat doorlaten.
      if (!GitRepoLayout.isSafeRepoPath(path) ||
          !p.posix.isWithin(deckDir, p.posix.normalize(path))) {
        throw GitForgeException(
          GitForgeError.malformed,
          'Bestand valt buiten de deckmap: $path',
        );
      }
    }
    await _store.writeDeck(deckDir, files);
  }

  @override
  Future<Map<String, Uint8List>> readDeck(String deckDir) async {
    _requireDeckDir(deckDir);
    return _store.readDeck(deckDir);
  }

  @override
  Future<bool> hasDeck(String deckDir) async {
    _requireDeckDir(deckDir);
    return _store.hasDeck(deckDir);
  }

  @override
  Future<void> discardDeck(String deckDir) async {
    _requireDeckDir(deckDir);
    await _store.discardDeck(deckDir);
  }

  @override
  Future<List<String>> deckDirs() => _store.deckDirs();
}
