import 'dart:typed_data';

import 'package:path/path.dart' as p;

import '../../models/deck.dart';
import '../../models/git_settings.dart';
import '../../models/slide.dart';
import '../../utils/log.dart';
import '../../platform/platform_features.dart';
import '../asset_staging.dart';
import '../image_service.dart';
import '../slide_image_refs.dart';
import '../web_asset_store.dart';
import 'asset_pool.dart';
import 'deck_repo_serializer.dart';
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
  final pendingWebAssets = <String, ({Uint8List bytes, String name})>{};

  /// Media komt niet terug zoals een afbeelding. [WebAssetStore] is een map in
  /// het geheugen — prima voor een plaatje, verkeerd voor de gigabyte die
  /// [ImageService.maxMediaBytes] toestaat. Op een platform met een
  /// bestandssysteem gaat media daarom naar de staging-map en speelt de speler
  /// hem van schijf, net als bij een deck uit een gewone map (D12).
  Future<String?> mediaPath(String reference) async {
    if (!GitRepoLayout.isRepoAsset(reference)) return null;
    final cached = memFor[reference];
    if (cached != null) return cached;
    try {
      final bytes = await pool.resolve(reference);
      // Een forge is onvertrouwd (P5), net als bij een afbeelding: de bytes
      // moeten als bekende container snuiven en binnen de mediagrens blijven.
      if (bytes.isEmpty ||
          bytes.length > ImageService.maxMediaBytes ||
          ImageService.mediaMimeFromBytes(bytes.take(16).toList()) == null) {
        logWarning(
          'resolveRepoAssetsToMem: media geweigerd ($sourceName) — geen '
          'bekende container of buiten de grens',
        );
        return null;
      }
      final path = GitRepoLayout.assetPathOf(reference);
      final name = path == null ? 'media' : p.posix.basename(path);
      // De naam in de staging-map is de assetverwijzing zelf, en die is de
      // hash van de inhoud: twee dia's met dezelfde film delen één bestand, en
      // een tweede keer openen overschrijft hetzelfde pad in plaats van te
      // stapelen.
      if (!supportsLocalProjectFolders) {
        pendingWebAssets[reference] = (bytes: bytes, name: name);
        return null;
      }
      final staged = await AssetStaging.stageBytes(
        bytes,
        subdir: 'repo-media',
        filename: name,
      );
      if (staged == null) return null;
      memFor[reference] = staged;
      return staged;
    } on GitForgeException catch (e) {
      logWarning('resolveRepoAssetsToMem: media onbereikbaar ($sourceName)', e);
      return null;
    }
  }

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
      final name = path == null ? 'asset' : p.posix.basename(path);
      // Eerst alle asynchrone forge-reads afronden; daarna materialiseert de
      // synchrone atomic-scope hieronder alles-of-niets. Ook desktop gebruikt
      // voor afbeeldingen `mem:` (zonder productieplafond), zodat dezelfde
      // route in VM-tests bewijsbaar blijft.
      pendingWebAssets[reference] = (bytes: bytes, name: name);
      return null;
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
    var next = rewriteSlideImagePaths(slide, (path) => resolved[path]);
    final video = await mediaPath(slide.videoPath);
    final audio = await mediaPath(slide.audioPath);
    if (video != null) next = next.copyWith(videoPath: video);
    if (audio != null) next = next.copyWith(audioPath: audio);
    slides.add(next);
  }

  WebAssetStore.atomic(() {
    for (final entry in pendingWebAssets.entries) {
      memFor[entry.key] = WebAssetStore.put(
        entry.value.bytes,
        name: entry.value.name,
      );
    }
  });
  if (pendingWebAssets.isEmpty) {
    return memFor.isEmpty ? deck : deck.copyWith(slides: slides);
  }
  final rewritten = <Slide>[];
  for (var slide in slides) {
    slide = rewriteSlideImagePaths(slide, (path) => memFor[path]);
    final video = memFor[slide.videoPath];
    final audio = memFor[slide.audioPath];
    if (video != null) slide = slide.copyWith(videoPath: video);
    if (audio != null) slide = slide.copyWith(audioPath: audio);
    rewritten.add(slide);
  }
  return deck.copyWith(slides: rewritten);
}

/// Waar de bytes van een afbeelding vandaan komen bij het schrijven naar een
/// repo: uit de webstore als het een `mem:`-pad is, anders van schijf, relatief
/// aan het project waar het deck bij hoort.
///
/// Stond vijf keer letterlijk uitgeschreven in de state-laag — één per
/// schrijfpad. Vijf kopieën van dezelfde regel is er vier te veel: een zesde
/// pad dat er één vergeet, schrijft een kapotte verwijzing zonder dat er iets
/// misgaat waar de app op kan wijzen.
///
/// De tegenhanger van [resolveRepoAssetsToMem], en daarom hier: die leest een
/// repo-asset terug naar het geheugen, deze levert de bytes die er naartoe
/// gaan.
AssetByteResolver repoAssetBytes(String? projectPath) {
  final image = ImageService();
  return (path) async => WebAssetStore.isMemPath(path)
      ? WebAssetStore.bytesFor(path)
      : image.readSlideImageBytes(path, projectPath: projectPath);
}
