import 'package:path/path.dart' as p;

import '../models/deck.dart';
import '../models/slide.dart';
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

  // Video/audio krijgen dezelfde weg naar het geheugen, maar met de media-cap
  // en zonder magic-byte-validatie (FILE_FORMAT §13, net als de desktop-import).
  // Zonder dit bleef een pakket-video op web naar een archief-intern pad wijzen
  // dat daar geen URL is (#854); [createMediaController] maakt van het
  // resulterende `mem:`-pad een `blob:`-URL.
  String? mediaMemPath(String ref) {
    final clean = ref.split('#').first.trim();
    if (clean.isEmpty || WebAssetStore.isMemPath(clean)) return null;
    final scheme = Uri.tryParse(clean)?.scheme.toLowerCase();
    if (scheme == 'http' || scheme == 'https') return null; // externe media
    final resolved = p.posix.normalize(
      mdDir == '.' ? clean : p.posix.join(mdDir, clean),
    );
    if (resolved.startsWith('..')) return null; // buiten het pakket
    final cached = memFor[resolved];
    if (cached != null) return cached;
    final bytes = byName[resolved];
    if (bytes == null ||
        bytes.isEmpty ||
        bytes.length > ImageService.maxMediaBytes) {
      return null;
    }
    final mem = WebAssetStore.put(bytes, name: p.posix.basename(resolved));
    memFor[resolved] = mem;
    return mem;
  }

  Slide rewriteMedia(Slide s) {
    var out = s;
    final mv = mediaMemPath(s.videoPath);
    if (mv != null) out = out.copyWith(videoPath: mv);
    final ma = mediaMemPath(s.audioPath);
    if (ma != null) out = out.copyWith(audioPath: ma);
    return out;
  }

  // Ook een `![…](…)` in de vrije tekst wijst naar een lid van het pakket, en
  // moet dus dezelfde weg naar het geheugen lopen — anders opent het deck met
  // een verwijzing naar een bestand dat alleen ín het archief bestaat.
  final slides = [
    for (final s in deck.slides)
      rewriteMedia(rewriteSlideImagePaths(s, memPath)),
  ];
  return deck.copyWith(slides: slides);
}
