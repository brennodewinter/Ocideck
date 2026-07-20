import 'package:path/path.dart' as p;

import '../services/asset_staging.dart';
import '../services/web_asset_store.dart';
import 'deck.dart';

/// Waar de media van een slide vandaan komt, gezien vanuit de vraag die er
/// werkelijk toe doet: verhuist dit mee als de presentatie naar iemand anders
/// gaat?
///
/// Je kunt er niet van uitgaan dat de ontvanger dezelfde schijven, netwerkmappen
/// of rechten heeft. Een verwijzing die bij de maker prima werkt, is bij de
/// ontvanger een gat — en dat verschil was tot nu toe nergens te zien.
enum AssetOrigin {
  /// Geen verwijzing ingevuld.
  none,

  /// In de presentatiemap: verhuist mee, niets aan de hand.
  inDeck,

  /// Gekopieerd naar de stagingmap omdat het deck nog niet is opgeslagen. De
  /// bytes zijn veilig; hun definitieve plek krijgen ze bij de eerste opslag.
  staged,

  /// Een absoluut pad buiten de presentatie. Werkt hier, en alleen hier.
  external,

  /// Een webadres. Werkt alleen mét internet, en alleen zolang de bron blijft
  /// staan — de presentatie draagt het niet zelf.
  remote,

  /// Alleen in het geheugen van deze browsersessie (webversie); weg na
  /// herladen.
  memory,
}

/// Bepaal de herkomst van [path] binnen een deck met [projectPath].
///
/// Puur lexicaal: geen enkele schijftoegang, want de UI roept dit per frame aan
/// voor elke zichtbare slide. Of het bestand er ook echt nog is, is een aparte
/// vraag — die beantwoordt de kwaliteitscontrole.
AssetOrigin classifyAssetPath(String path, String? projectPath) {
  final trimmed = path.trim();
  if (trimmed.isEmpty) return AssetOrigin.none;
  if (_looksRemote(trimmed)) return AssetOrigin.remote;
  if (WebAssetStore.isMemPath(trimmed)) return AssetOrigin.memory;

  // Een relatief pad is per definitie projectrelatief: zo staat het ook in de
  // markdown, en zo leest een ontvanger het.
  if (!p.isAbsolute(trimmed)) return AssetOrigin.inDeck;

  if (AssetStaging.isStagedPath(trimmed)) return AssetOrigin.staged;

  final normalized = p.normalize(trimmed);
  if (projectPath != null &&
      projectPath.isNotEmpty &&
      p.isWithin(projectPath, normalized)) {
    return AssetOrigin.inDeck;
  }
  return AssetOrigin.external;
}

bool _looksRemote(String path) {
  final lower = path.toLowerCase();
  return lower.startsWith('http://') || lower.startsWith('https://');
}

/// Of deze herkomst de gebruiker iets te melden heeft. [AssetOrigin.inDeck] en
/// [AssetOrigin.none] zijn stil: er is niets aan de hand, en een badge bij elke
/// gewone afbeelding leert niemand iets.
bool assetOriginNeedsAttention(AssetOrigin origin) => switch (origin) {
  AssetOrigin.none || AssetOrigin.inDeck => false,
  AssetOrigin.staged ||
  AssetOrigin.external ||
  AssetOrigin.remote ||
  AssetOrigin.memory => true,
};

/// Of [deck] beeld, video, audio of een logo draagt dat alleen in het geheugen
/// van deze browsersessie leeft ([AssetOrigin.memory], `mem:`-paden).
///
/// Dat is de vraag vóór een kale `.md`-opslag op web: zulke media reizen niet
/// mee in een los tekstbestand en zijn na herladen weg. Puur lexicaal, geen
/// schijftoegang — dezelfde regel als [classifyAssetPath].
bool deckCarriesMemoryAssets(Deck deck) {
  bool mem(String path) => WebAssetStore.isMemPath(path.trim());
  if (mem(deck.themeProfile.logoPath ?? '')) return true;
  for (final s in deck.slides) {
    if (mem(s.imagePath) ||
        mem(s.imagePath2) ||
        mem(s.videoPath) ||
        mem(s.audioPath)) {
      return true;
    }
  }
  return false;
}
