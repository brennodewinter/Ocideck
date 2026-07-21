import 'package:path/path.dart' as p;

import '../models/deck.dart';
import 'file_service.dart' show PackageEntry;
import 'image_service.dart';
import 'slide_image_refs.dart';
import 'web_asset_store.dart';

/// Zet de afbeeldings-leden van een `.ocideck`-pakket in de [WebAssetStore] en
/// herschrijf de slidepaden die ernaar verwijzen naar hun `mem:`-pad.
///
/// Verwijzingen zijn relatief aan de hoofd-markdown ([mdName]). Alleen leden
/// die de afbeeldingsvalidatie (magic bytes + cap) doorstaan doen mee, en een
/// verwijzing die met `../` buiten de pakketwortel wijst wordt niet gevolgd.
///
/// Gedeeld door het in-geheugen openen van een pakket in een tabblad en het
/// doorzoeken van pakketten op een remote bron (WebDAV/S3), zodat beide
/// dezelfde insluiting en validatie hanteren.
Deck attachPackageAssetsToMem(
  Deck deck,
  List<PackageEntry> entries,
  String mdName,
) {
  final mdDir = p.posix.dirname(mdName);
  final byName = {for (final e in entries) p.posix.normalize(e.name): e.bytes};
  final memFor = <String, String>{};
  String? memPath(String ref) {
    if (ref.trim().isEmpty || WebAssetStore.isMemPath(ref)) return null;
    final resolved = p.posix.normalize(
      mdDir == '.' ? ref : p.posix.join(mdDir, ref),
    );
    if (resolved.startsWith('..')) return null; // buiten het pakket
    final cached = memFor[resolved];
    if (cached != null) return cached;
    final bytes = byName[resolved];
    if (bytes == null ||
        bytes.isEmpty ||
        bytes.length > ImageService.maxImageBytes ||
        !ImageService.looksLikeImage(bytes)) {
      return null;
    }
    final mem = WebAssetStore.put(bytes, name: p.posix.basename(resolved));
    memFor[resolved] = mem;
    return mem;
  }

  // Ook een `![…](…)` in de vrije tekst wijst naar een lid van het pakket, en
  // moet dus dezelfde weg naar het geheugen lopen — anders opent het deck met
  // een verwijzing naar een bestand dat alleen ín het archief bestaat.
  final slides = [
    for (final s in deck.slides) rewriteSlideImagePaths(s, memPath),
  ];
  return deck.copyWith(slides: slides);
}
