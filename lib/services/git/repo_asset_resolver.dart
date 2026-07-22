import 'package:path/path.dart' as p;

import '../../models/deck.dart';
import '../../models/git_settings.dart';
import '../../models/slide.dart';
import '../../utils/log.dart';
import '../image_service.dart';
import '../slide_image_refs.dart';
import '../web_asset_store.dart';
import 'asset_pool.dart';
import 'git_forge.dart';

/// Vervang in [deck] elke `repo:`-afbeeldingsverwijzing door een in-geheugen
/// `mem:`-pad, met de bytes uit [pool]. Dit is de omkering van het opslaan naar
/// een repo (waar afbeeldingen naar de content-adresseerbare pool gaan) en de
/// gedeelde kern van zowel het openen van een git-deck in een tabblad als het
/// doorzoeken ervan met 'Slide zoeken'.
///
/// Een asset die niet op te halen is of geen afbeelding blijkt wordt
/// overgeslagen, niet fataal: het deck opent met een placeholder waar het
/// plaatje hoort, net als een pakket met een kapotte verwijzing. Het hele deck
/// weigeren omdat één plaatje ontbreekt zou een slechtere ruil zijn.
///
/// Levert [deck] ongewijzigd terug wanneer er geen enkele repo-asset in zit.
Future<Deck> resolveRepoAssetsToMem(
  Deck deck,
  AssetPool pool, {
  required String sourceName,
}) async {
  final memFor = <String, String>{};
  Future<String?> memPath(String reference) async {
    if (!GitRepoLayout.isRepoAsset(reference)) return null;
    final cached = memFor[reference];
    if (cached != null) return cached;
    try {
      final bytes = await pool.resolve(reference);
      // Een forge is onvertrouwd (P5): een blob onder een .png-naam hoeft geen
      // afbeelding te zijn. Dezelfde controle als bij de pakket-import.
      if (bytes.isEmpty ||
          bytes.length > ImageService.maxImageBytes ||
          !ImageService.looksLikeImage(bytes)) {
        return null;
      }
      final path = GitRepoLayout.assetPathOf(reference);
      final mem = WebAssetStore.put(
        bytes,
        name: path == null ? 'asset' : p.posix.basename(path),
      );
      memFor[reference] = mem;
      return mem;
    } on GitForgeException catch (e) {
      logWarning('resolveRepoAssetsToMem: asset onbereikbaar ($sourceName)', e);
      return null;
    }
  }

  // Ook de `![…](repo:…)` in de vrije tekst wordt teruggelezen — anders opent
  // het deck met een verwijzing die alleen de forge kent en tekent de dia een
  // leeg vak. Ophalen is asynchroon en herschrijven niet, dus eerst elke
  // verwijzing omzetten, dan de dia in haar geheel.
  final slides = <Slide>[];
  for (final slide in deck.slides) {
    final resolved = <String, String>{};
    for (final reference in slideImagePaths(slide).toSet()) {
      final mem = await memPath(reference);
      if (mem != null) resolved[reference] = mem;
    }
    slides.add(rewriteSlideImagePaths(slide, (path) => resolved[path]));
  }
  return memFor.isEmpty ? deck : deck.copyWith(slides: slides);
}
