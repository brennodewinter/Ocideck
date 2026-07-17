import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../../models/git_settings.dart';
import '../../utils/log.dart';

/// Eén deck dat nog naar de forge moet.
///
/// Draagt bewust géén bytes, alleen de *intentie*. De inhoud staat al in de
/// [DeckMirror]; hier nog eens neerzetten zou dezelfde bytes twee keer duurzaam
/// maken en ze uit elkaar laten lopen zodra er één wint. Bij het flushen leest
/// de [SyncEngine] de mirror — dat is per definitie de laatste versie.
///
/// Dat sluit ook aan op wat een [DraftMirror] is: één concept per deck, geen
/// reeks commits (§8.3). Een outbox met bytes zou suggereren dat je tien
/// offline commits kunt stapelen; dat kan pas met `NativeGitMirror` (Fase 3).
class PendingCommit {
  final String deckDir;
  final String branch;
  final String message;

  /// De commit waarop dit werk is geschreven. Blijft staan zolang er niet
  /// gesynct is — ook als er ondertussen tien keer wordt opgeslagen. Dát is wat
  /// een non-fast-forward detecteerbaar maakt.
  final String baseSha;

  const PendingCommit({
    required this.deckDir,
    required this.branch,
    required this.message,
    required this.baseSha,
  });

  Map<String, Object?> toJson() => {
    'deckDir': deckDir,
    'branch': branch,
    'message': message,
    'baseSha': baseSha,
  };

  static PendingCommit? fromJson(Map<String, Object?> json) {
    final deckDir = json['deckDir'];
    final branch = json['branch'];
    final message = json['message'];
    final baseSha = json['baseSha'];
    if (deckDir is! String ||
        branch is! String ||
        message is! String ||
        baseSha is! String) {
      return null;
    }
    if (GitRepoLayout.deckNameOf(deckDir) == null) return null;
    return PendingCommit(
      deckDir: deckDir,
      branch: branch,
      message: message,
      baseSha: baseSha,
    );
  }
}

/// De wachtrij van nog niet gepushte decks (§8.5).
///
/// Zit in de sleutel/waarde-opslag op élk platform, niet alleen op web. Dat is
/// geen inconsistentie met de mirror: die draagt deckinhoud en wil op desktop
/// echte bestanden (want in Fase 3 wórdt die map een clone). Dit is een handvol
/// JSON per deck — daar is een bestandssysteem niets voor.
class Outbox {
  Outbox({SharedPreferences? prefs}) : _injected = prefs;

  final SharedPreferences? _injected;
  SharedPreferences? _cached;

  static const String _prefix = 'git_outbox::';

  Future<SharedPreferences> _prefs() async =>
      _injected ?? (_cached ??= await SharedPreferences.getInstance());

  String _keyFor(String deckDir) => '$_prefix$deckDir';

  /// Zet [commit] in de wachtrij.
  ///
  /// Eén wachtende commit per deck: opslaan terwijl er al iets wacht vervangt de
  /// boodschap, maar **behoudt de oorspronkelijke `baseSha`**. Dat is het
  /// venijn — het werk is nog steeds tegen díe commit geschreven, en de nieuwere
  /// sha eroverheen zetten zou precies de conflictdetectie slopen waar de hele
  /// constructie voor bestaat.
  Future<void> enqueue(PendingCommit commit) async {
    final existing = await forDeck(commit.deckDir);
    final effective = existing == null
        ? commit
        : PendingCommit(
            deckDir: commit.deckDir,
            branch: commit.branch,
            message: commit.message,
            baseSha: existing.baseSha,
          );
    await (await _prefs()).setString(
      _keyFor(commit.deckDir),
      jsonEncode(effective.toJson()),
    );
  }

  Future<PendingCommit?> forDeck(String deckDir) async {
    final raw = (await _prefs()).getString(_keyFor(deckDir));
    if (raw == null) return null;
    try {
      final json = jsonDecode(raw) as Map<String, Object?>;
      return PendingCommit.fromJson(json);
    } catch (e) {
      logError('Outbox: wachtende commit onleesbaar ($deckDir)', e);
      return null;
    }
  }

  /// Alles wat wacht, op deckmap gesorteerd zodat een flush voorspelbaar loopt.
  Future<List<PendingCommit>> pending() async {
    final prefs = await _prefs();
    final out = <PendingCommit>[];
    for (final key in prefs.getKeys().toList()..sort()) {
      if (!key.startsWith(_prefix)) continue;
      final commit = await forDeck(key.substring(_prefix.length));
      if (commit != null) out.add(commit);
    }
    return out;
  }

  /// Haal een deck uit de wachtrij. Alléén deze sleutel — hier staan ook de
  /// instellingen van de gebruiker.
  Future<void> remove(String deckDir) async =>
      (await _prefs()).remove(_keyFor(deckDir));

  Future<bool> get isEmpty async => (await pending()).isEmpty;
}
