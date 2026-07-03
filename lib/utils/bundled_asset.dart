/// Paden met dit schema wijzen naar een méégebundelde Flutter-asset in plaats
/// van een bestand op schijf, bv. `asset:assets/images/librekat-logo.png`.
///
/// Gebruikt voor logo's van ingebouwde stijlprofielen: die moeten op elk
/// platform (ook web, waar geen bestandssysteem bestaat) renderen én mee
/// kunnen in pakket-exports. De gewone pad-resolvers zien dit schema nooit —
/// aanroepers herkennen het vóór elke bestandsresolutie, net als `mem:`.
const bundledAssetScheme = 'asset:';

bool isBundledAssetPath(String path) => path.startsWith(bundledAssetScheme);

/// De asset-sleutel achter een `asset:`-pad (voor Image.asset/rootBundle).
String bundledAssetKey(String path) =>
    path.substring(bundledAssetScheme.length);
