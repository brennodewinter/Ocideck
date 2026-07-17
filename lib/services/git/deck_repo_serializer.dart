import 'dart:convert';
import 'dart:typed_data';

import 'package:path/path.dart' as p;

import '../../models/deck.dart';
import '../../models/git_settings.dart';
import '../../models/slide.dart';
import '../markdown_service.dart';
import '../web_asset_store.dart';
import 'asset_pool.dart';

/// Standaardnaam van het markdown-bestand binnen een deckmap (§6). Gespiegeld in
/// `TabsNotifierGit.deckFileName`; hier apart zodat de serializer los te testen
/// is zonder de state-laag.
const String deckRepoFileName = 'deck.md';

/// Levert de bytes achter een afbeeldingsverwijzing, of null wanneer die niet te
/// lezen is (web zonder mem:-treffer, een pad buiten het project, een leesfout).
/// In de app is dit `ImageService.readSlideImageBytes`; in tests een fake.
typedef AssetByteResolver = Future<Uint8List?> Function(String path);

/// De repo-bestandenset van één deck (§9.1): het tekstbestand plus de nieuwe
/// pool-blobs die nog niet in de repo stonden.
class RepoDeckFiles {
  /// Pad → bytes voor `GitForge.commitFiles(upserts:)` — `<deckDir>/deck.md`
  /// plus elke pool-blob (`assets/<sha>.<ext>`) die nog geüpload moet worden.
  final Map<String, Uint8List> upserts;

  /// Mediaverwijzingen die niet mee konden: video/audio (die round-trippen nog
  /// niet door git, §9.3) en afbeeldingen waarvan de bytes niet te lezen waren.
  /// Het deck slaat wél op, maar deze verwijzingen zijn niet mee-gecommit — de
  /// aanroeper meldt dat, in plaats van een kapotte verwijzing te verzwijgen.
  final List<String> warnings;

  const RepoDeckFiles({required this.upserts, required this.warnings});
}

/// Zet [deck] om naar zijn repo-bestandenset onder [deckDir].
///
/// De afbeeldingen gaan naar de gedeelde, content-geadresseerde pool: elke
/// `mem:`- of bestandsafbeelding wordt gehasht naar een `repo:`-verwijzing
/// ([AssetPool.refFor]), de slidepaden worden herschreven, en `deck.md` wordt
/// geserialiseerd met die verwijzingen. Zo is het de exacte omkering van het
/// open-pad (`_withRepoAssets`), dat `repo:` juist naar `mem:` terugleest —
/// en omdat de pool op inhoud adresseert, levert opnieuw hashen dezelfde
/// verwijzing op, dus de heenweg is omkeerbaar.
///
/// Alleen afbeeldingen (`imagePath`/`imagePath2`), gelijk aan wat het open-pad
/// terugzet; video en audio round-trippen nog niet door git en worden gemeld in
/// plaats van als kapotte verwijzing weggeschreven.
///
/// Alleen blobs die nog niet in de repo staan komen in [RepoDeckFiles.upserts] —
/// dát is waar de pool zijn geld verdient ([AssetPool.existing]): een afbeelding
/// die vijf decks delen staat er één keer.
Future<RepoDeckFiles> buildDeckRepoFiles(
  Deck deck, {
  required MarkdownService md,
  required AssetPool pool,
  required String deckDir,
  required AssetByteResolver resolveBytes,
}) async {
  final refForMem = <String, String>{}; // bronpad → repo:-verwijzing (dedup)
  final bytesForRef = <String, Uint8List>{}; // repo:-verwijzing → bytes
  final warnings = <String>{};

  Future<String?> poolImage(String path) async {
    if (path.isEmpty) return null;
    // Al gepoold (bv. een afbeelding die ongemoeid bleef sinds het openen).
    if (GitRepoLayout.isRepoAsset(path)) return path;
    final cached = refForMem[path];
    if (cached != null) return cached;

    final bytes = await resolveBytes(path);
    if (bytes == null) {
      warnings.add(path); // web zonder mem:, buiten project, of leesfout
      return null;
    }
    final name = WebAssetStore.isMemPath(path)
        ? (WebAssetStore.nameFor(path) ?? 'afbeelding.png')
        : p.basename(path);
    final ref = await AssetPool.refFor(bytes, name: name);
    if (ref == null) {
      warnings.add(path); // geen bruikbare extensie
      return null;
    }
    refForMem[path] = ref;
    bytesForRef[ref] = bytes;
    return ref;
  }

  void warnUnpooledMedia(String path) {
    if (path.isNotEmpty && !GitRepoLayout.isRepoAsset(path)) warnings.add(path);
  }

  final slides = <Slide>[];
  for (final slide in deck.slides) {
    final img1 = await poolImage(slide.imagePath);
    final img2 = await poolImage(slide.imagePath2);
    warnUnpooledMedia(slide.videoPath);
    warnUnpooledMedia(slide.audioPath);
    slides.add(
      slide.copyWith(
        imagePath: img1 ?? slide.imagePath,
        imagePath2: img2 ?? slide.imagePath2,
      ),
    );
  }
  final rewritten = deck.copyWith(slides: slides);

  final upserts = <String, Uint8List>{
    p.posix.join(deckDir, deckRepoFileName): Uint8List.fromList(
      utf8.encode(md.generateDeck(rewritten)),
    ),
  };

  // Alleen de nog niet aanwezige blobs uploaden.
  final already = await pool.existing(bytesForRef.keys);
  for (final entry in bytesForRef.entries) {
    if (already.contains(entry.key)) continue;
    final poolPath = GitRepoLayout.assetPathOf(entry.key);
    if (poolPath != null) upserts[poolPath] = entry.value;
  }

  return RepoDeckFiles(upserts: upserts, warnings: warnings.toList());
}
