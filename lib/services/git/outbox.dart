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

  /// De branch waar [branch] van afgetakt moet worden als hij bij het flushen
  /// nog niet bestaat (D3). Zo kan een bewerkingsronde óók offline op zijn
  /// werkbranch beginnen: de branch wordt pas bij de eerste geslaagde push
  /// aangemaakt. `null` voor een gewone opslag naar een bestaande branch.
  final String? forkFrom;

  const PendingCommit({
    required this.deckDir,
    required this.branch,
    required this.message,
    required this.baseSha,
    this.forkFrom,
  });

  Map<String, Object?> toJson() => {
    'deckDir': deckDir,
    'branch': branch,
    'message': message,
    'baseSha': baseSha,
    if (forkFrom != null) 'forkFrom': forkFrom,
  };

  static PendingCommit? fromJson(Map<String, Object?> json) {
    final deckDir = json['deckDir'];
    final branch = json['branch'];
    final message = json['message'];
    final baseSha = json['baseSha'];
    final forkFrom = json['forkFrom'];
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
      forkFrom: forkFrom is String ? forkFrom : null,
    );
  }
}

/// De wachtrij van nog niet gepushte decks (§8.5).
///
/// Zit in de sleutel/waarde-opslag op élk platform, niet alleen op web. Dat is
/// geen inconsistentie met de mirror: die draagt deckinhoud en wil op desktop
/// echte bestanden (want in Fase 3 wórdt die map een clone). Dit is een handvol
/// JSON per deck — daar is een bestandssysteem niets voor.
///
/// De wachtrij hoort bij één repository. Vroeger niet: de sleutel was alleen de
/// deckmap, waardoor twee repo's met een gelijknamig deck elkaars wachtende
/// commit overschreven — en een flush duwde de hele wachtrij naar de forge die
/// op dát moment was ingesteld. Met één repo viel dat niet op; met twee zou het
/// werk van de ene opdrachtgever in de repository van de andere belanden,
/// zonder foutmelding, want elke stap op zich klopt.
class Outbox {
  /// [scope] is `GitRepoConfig.storageSlug` van de repo waar deze wachtrij bij
  /// hoort. Leeg is toegestaan voor tests die maar één repo kennen; dan gedraagt
  /// hij zich als de oude, ongescopede wachtrij.
  Outbox({SharedPreferences? prefs, this.scope = ''}) : _injected = prefs;

  final SharedPreferences? _injected;
  SharedPreferences? _cached;

  final String scope;

  static const String _prefix = 'git_outbox::';

  /// Het sleutelvoorvoegsel van déze wachtrij.
  String get _scopedPrefix => scope.isEmpty ? _prefix : '$_prefix$scope::';

  Future<SharedPreferences> _prefs() async =>
      _injected ?? (_cached ??= await SharedPreferences.getInstance());

  String _keyFor(String deckDir) => '$_scopedPrefix$deckDir';

  /// Neem wachtende commits over uit de tijd dat de wachtrij nog niet per repo
  /// was gescheiden.
  ///
  /// Alleen aan te roepen voor de repo die toen was ingesteld — er was er maar
  /// één, dus dat is de enige die er aanspraak op maakt. Wat hier staat is werk
  /// dat nog nergens op een server terecht is gekomen; het laten liggen zou het
  /// stilletjes onbereikbaar maken.
  ///
  /// Een oude sleutel is te herkennen aan wat er ná het voorvoegsel staat: een
  /// gescopede draagt daar nog een `::`, een deckmap nooit (zie
  /// [GitRepoConfig.storageSlug]). Idempotent: na de eerste keer is er niets
  /// meer te vinden.
  Future<int> adoptLegacyEntries() async {
    if (scope.isEmpty) return 0;
    final prefs = await _prefs();
    var moved = 0;
    for (final key in prefs.getKeys().toList()) {
      if (!key.startsWith(_prefix)) continue;
      final rest = key.substring(_prefix.length);
      if (rest.contains('::')) continue; // hoort al bij een repo
      final raw = prefs.getString(key);
      if (raw == null) continue;
      // Niet overschrijven: staat er voor dit deck al iets onder de nieuwe
      // sleutel, dan is dát het actuele werk.
      final target = _keyFor(rest);
      if (!prefs.containsKey(target)) {
        await prefs.setString(target, raw);
        moved++;
      }
      await prefs.remove(key);
    }
    if (moved > 0) {
      logWarning('Outbox: $moved wachtende commit(s) overgenomen naar $scope');
    }
    return moved;
  }

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
            // Ronde-eigenschappen horen bij de oorspronkelijke baseSha: hield hij
            // een nog-niet-bestaande werkbranch aan, dan blijft dat zo tot de
            // eerste push hem aanmaakt.
            forkFrom: existing.forkFrom,
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
      if (!key.startsWith(_scopedPrefix)) continue;
      final rest = key.substring(_scopedPrefix.length);
      // Zonder scope zou de ongescopede lus ook de gescopede sleutels van álle
      // repo's oppikken — precies de vermenging die dit moet uitsluiten.
      if (scope.isEmpty && rest.contains('::')) continue;
      final commit = await forDeck(rest);
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
