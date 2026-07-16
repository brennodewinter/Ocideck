import 'dart:convert';

import '../../models/git_settings.dart';
import 'git_forge.dart';

/// Wat de pool over één asset weet.
class AssetUsage {
  /// De `repo:`-verwijzing.
  final String reference;

  /// Deknamen die hem aanhalen, gesorteerd.
  final List<String> decks;

  /// Grootte in bytes, of null wanneer de forge die niet meestuurde.
  final int? size;

  const AssetUsage({required this.reference, required this.decks, this.size});

  /// Geen enkel deck in deze index haalt hem aan. Let op [AssetIndexSnapshot
  /// .isComplete]: "niemand gebruikt hem" is alleen waar als élk deck gelezen
  /// is.
  bool get isUnused => decks.isEmpty;
}

/// Eén ronde over de repo: de pool plus wie wat gebruikt.
class AssetIndexSnapshot {
  final List<AssetUsage> assets;

  /// Deckmappen waarvan de `deck.md` niet te lezen viel. Zolang deze niet leeg
  /// is, is "niemand gebruikt deze asset" een onbewezen bewering.
  final List<String> unreadableDecks;

  const AssetIndexSnapshot({
    required this.assets,
    required this.unreadableDecks,
  });

  bool get isComplete => unreadableDecks.isEmpty;
}

/// De omgekeerde blik op de pool: van asset naar de decks die hem gebruiken.
///
/// §9.3 noemt dit een natuurlijk bijproduct van §6, en dat is het ook — de pool
/// is plat en de verwijzingen staan in de deck-markdown, dus "welke decks
/// gebruiken deze afbeelding" is één keer alles lezen en omdraaien. Het levert
/// twee dingen tegelijk: beeldzoeken, en de kandidatenlijst voor de handmatige
/// opruiming.
class AssetIndex {
  AssetIndex({required this.forge, required this.branch});

  final GitForge forge;
  final String branch;

  /// Vindt `repo:`-verwijzingen in ruwe markdown.
  ///
  /// Bewust een scan over de tekst en geen markdown-parse: we willen élke
  /// verwijzing, ook uit een slide-soort die de parser nu niet kent of overslaat.
  /// Een gemiste verwijzing zou een asset ten onrechte als ongebruikt aanmerken,
  /// en die fout is duur — opruimen is onomkeerbaar.
  static final RegExp _reference = RegExp(
    '${GitRepoLayout.assetScheme}${GitRepoLayout.assetsRoot}'
    '/[0-9a-f]{64}\\.[a-z0-9]{1,10}',
  );

  static Set<String> referencesIn(String markdown) =>
      _reference.allMatches(markdown).map((m) => m.group(0)!).toSet();

  /// Bouw de index over [branch].
  ///
  /// Leest élke `deck.md` en de hele pool: één ronde over de repo. Op een native
  /// clone wordt dat een mappenwandeling (Fase 3); hier zijn het N REST-lezingen,
  /// dus de aanroeper cachet dit en bouwt het niet per toetsaanslag opnieuw.
  ///
  /// Een deck dat niet te lezen valt maakt de ronde niet stuk maar wél
  /// onvolledig: het komt in [AssetIndexSnapshot.unreadableDecks]. Beeldzoeken
  /// heeft aan een gedeeltelijk antwoord genoeg; [unusedAssets] niet.
  Future<AssetIndexSnapshot> build() async {
    final decks = await forge.listDecks(branch);

    final usage = <String, Set<String>>{};
    final unreadable = <String>[];
    for (final entry in decks.entries) {
      final markdown = await _deckMarkdown(entry.value);
      if (markdown == null) {
        unreadable.add(entry.key);
        continue;
      }
      for (final ref in referencesIn(markdown)) {
        usage.putIfAbsent(ref, () => <String>{}).add(entry.key);
      }
    }

    final pool = await forge.listTree(
      branch,
      GitRepoLayout.assetsRoot,
      recursive: true,
    );

    final assets = <AssetUsage>[];
    for (final entry in pool) {
      if (entry.type != RepoEntryType.file) continue;
      final ref = '${GitRepoLayout.assetScheme}${entry.path}';
      // Alleen wat de poolvorm heeft telt mee: een handmatig neergezet bestand
      // onder assets/ is geen pool-asset en heeft dus geen verwijzing.
      if (!_reference.hasMatch(ref)) continue;
      assets.add(
        AssetUsage(
          reference: ref,
          decks: (usage[ref]?.toList() ?? <String>[])..sort(),
          size: entry.size,
        ),
      );
    }
    assets.sort((a, b) => a.reference.compareTo(b.reference));
    return AssetIndexSnapshot(assets: assets, unreadableDecks: unreadable);
  }

  /// Welke decks [reference] aanhalen. Leeg wanneer niemand hem gebruikt of hij
  /// niet bestaat. Een onleesbaar deck maakt dit antwoord onvolledig, niet fout:
  /// wie hier staat gebruikt hem echt.
  Future<List<String>> decksUsing(String reference) async {
    final snapshot = await build();
    for (final usage in snapshot.assets) {
      if (usage.reference == reference) return usage.decks;
    }
    return const [];
  }

  /// De assets die door geen enkel deck worden aangehaald — de kandidaten voor
  /// de handmatige opruiming van §6.2.
  ///
  /// Gooit wanneer de index onvolledig is, en dat is het punt: "niemand gebruikt
  /// hem" mag je niet beweren op grond van een deck dat je niet hebt kunnen
  /// lezen. Zo'n asset zou dan ten onrechte als weg-te-gooien worden
  /// gepresenteerd, en dat is onomkeerbaar. Fail-closed (P2).
  ///
  /// En zelfs een volledige lijst is een *voorstel*, geen oordeel: een asset die
  /// op deze branch nergens meer voorkomt, kan op een andere branch of onder een
  /// oudere release-tag nog gewoon in gebruik zijn (§6.2).
  Future<List<AssetUsage>> unusedAssets() async {
    final snapshot = await build();
    if (!snapshot.isComplete) {
      throw GitForgeException(
        GitForgeError.malformed,
        'Kan niet bepalen wat ongebruikt is: de presentatie(s) '
        '${snapshot.unreadableDecks.join(', ')} zijn niet te lezen.',
      );
    }
    return snapshot.assets.where((a) => a.isUnused).toList();
  }

  Future<String?> _deckMarkdown(String deckDir) async {
    try {
      final bytes = await forge.readBlob(branch, '$deckDir/deck.md');
      return utf8.decode(bytes, allowMalformed: true);
    } on GitForgeException {
      return null;
    }
  }
}
