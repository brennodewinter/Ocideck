import 'dart:convert';
import 'dart:typed_data';

import 'package:path/path.dart' as p;

import '../../models/deck.dart';
import '../../models/git_settings.dart';
import '../../models/slide.dart';
import '../../models/chart.dart';
import '../../utils/log.dart';
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

/// Levert de bytes van één bestand ín de deckmap, of null als het er niet is.
/// De forge leest het als blob, de werkkopie uit haar bestandenmap.
typedef RepoFileReader = Future<Uint8List?> Function(String repoPath);

/// Het repo-pad van een chart-`source`, of null wanneer die buiten de deckmap
/// zou wijzen.
///
/// Een deck kan van een onvertrouwde bron komen, dus een `source` als
/// `../../../geheim.json` mag noch gelezen noch geschreven worden — dezelfde
/// insluiting als `resolveProjectRelative` op schijf.
String? repoChartDataPath(String deckDir, String source) {
  if (source.trim().isEmpty || p.posix.isAbsolute(source)) return null;
  final joined = p.posix.normalize(p.posix.join(deckDir, source));
  return p.posix.isWithin(deckDir, joined) ? joined : null;
}

/// De databestanden van [deck]: `source` → inhoud, voor elke chart-slide die
/// zijn cijfers aan een bestand koppelt en ze in het geheugen heeft.
///
/// Zonder inline data valt er niets te schrijven: het bestand in de repo is dan
/// het enige exemplaar en moet met rust gelaten worden, niet met een leeg
/// bestand overschreven.
Map<String, String> chartDataFilesOf(Deck deck) {
  final files = <String, String>{};
  for (final slide in deck.slides) {
    if (slide.type != SlideType.chart) continue;
    final spec = ChartSpec.parse(slide.customMarkdown);
    final source = spec.source;
    if (source == null || !spec.hasInlineData) continue;
    files[source] = source.toLowerCase().endsWith('.csv')
        ? chartDataAsCsv(spec)
        : spec.dataToJson();
  }
  return files;
}

/// Vul chart-slides met de data uit hun bestand naast `deck.md` — de omkering
/// van wat [buildDeckRepoFiles] schrijft.
///
/// Een bestand dat niet te lezen is levert een lege grafiek op, geen mislukte
/// open: net als op schijf en bij een pakket met een kapotte verwijzing. Het
/// hele deck weigeren omdat één grafiek zijn cijfers mist zou een slechtere
/// ruil zijn. De aanroeper krijgt de bronnen terug die het niet haalden, zodat
/// het niet stil blijft.
Future<({Deck deck, List<String> missing})> withRepoChartData(
  Deck deck, {
  required String deckDir,
  required RepoFileReader read,
}) async {
  final missing = <String>[];
  var changed = false;
  final slides = <Slide>[];
  for (final slide in deck.slides) {
    if (slide.type != SlideType.chart) {
      slides.add(slide);
      continue;
    }
    final spec = ChartSpec.parse(slide.customMarkdown);
    final source = spec.source;
    if (source == null || spec.hasInlineData) {
      slides.add(slide);
      continue;
    }
    final path = repoChartDataPath(deckDir, source);
    Uint8List? bytes;
    try {
      bytes = path == null ? null : await read(path);
    } catch (e) {
      logWarning('withRepoChartData: databestand onbereikbaar', e);
      bytes = null;
    }
    if (bytes == null || bytes.isEmpty) {
      missing.add(source);
      slides.add(slide);
      continue;
    }
    try {
      slides.add(
        slide.copyWith(
          customMarkdown: spec
              .withData(utf8.decode(bytes), path: source)
              .toBlock(),
        ),
      );
      changed = true;
    } on FormatException catch (e) {
      logWarning('withRepoChartData: databestand is geen geldige UTF-8', e);
      missing.add(source);
      slides.add(slide);
    }
  }
  return (
    deck: changed ? deck.copyWith(slides: slides) : deck,
    missing: missing,
  );
}

/// Wat er van een deck níét meereist naar git (§9.3), geteld per soort.
///
/// De git-opslag schrijft `deck.md`, de afbeeldingenpool en de grafiekdata. Alle
/// overige lagen blijven achter: video en audio round-trippen nog niet, en de
/// twee sidecars (`.ink.json` met de tekeningen, `.user-notes.json` met de
/// notities) worden nergens in `services/git/` geschreven. Op schijf gaan die
/// wél mee, dus wie van een bestand naar git verhuist raakt ze kwijt zonder dat
/// er iets misgaat waar de app op kan wijzen.
///
/// Dit meenemen is een grotere ingreep dan een waarschuwing; de waarschuwing kan
/// niet wachten. De UI toont hem vóór de commit — daarna is de keuze al gemaakt.
class GitDeckOmissions {
  /// Dia's met een video die niet mee-gecommit wordt.
  final int videoSlides;

  /// Dia's met audio die niet mee-gecommit wordt.
  final int audioSlides;

  /// Dia's waarop getekend is; die tekenlaag gaat niet mee.
  final int annotatedSlides;

  /// Dia's met gebruikersnotities; die notities gaan niet mee.
  final int noteSlides;

  const GitDeckOmissions({
    this.videoSlides = 0,
    this.audioSlides = 0,
    this.annotatedSlides = 0,
    this.noteSlides = 0,
  });

  bool get isEmpty =>
      videoSlides == 0 &&
      audioSlides == 0 &&
      annotatedSlides == 0 &&
      noteSlides == 0;

  bool get isNotEmpty => !isEmpty;
}

/// Tel per soort wat er bij een commit van [deck] achterblijft.
///
/// Alleen niet-lege lagen tellen mee: een lege notitie of een dia zonder
/// streken is niets om over te waarschuwen, en een waarschuwing die ook afgaat
/// wanneer er niets aan de hand is, leert de gebruiker hem weg te klikken.
GitDeckOmissions gitDeckOmissions(Deck deck) {
  var video = 0;
  var audio = 0;
  for (final slide in deck.slides) {
    if (slide.videoPath.trim().isNotEmpty) video++;
    if (slide.audioPath.trim().isNotEmpty) audio++;
  }
  final ids = {for (final s in deck.slides) s.id};
  final ink = deck.annotations.entries
      .where((e) => ids.contains(e.key) && e.value.isNotEmpty)
      .length;
  final notes = deck.userNotes.entries
      .where((e) => ids.contains(e.key) && e.value.trim().isNotEmpty)
      .length;
  return GitDeckOmissions(
    videoSlides: video,
    audioSlides: audio,
    annotatedSlides: ink,
    noteSlides: notes,
  );
}

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
/// Grafiekdata volgt geen van beide routes: die krijgt een eigen bestand naast
/// `deck.md`, op het pad dat de chart-`source` noemt. Bewust niet in de pool —
/// een poolpad ís de hash van de inhoud, dus elke gewijzigde cel zou een nieuw
/// bestand opleveren en het vorige laten wegkwijnen, wat precies geen diff
/// oplevert. Op een vast pad is een wijziging te lezen als wat ze is. Terug
/// gelezen door [withRepoChartData].
///
/// Met een [pool] komen alleen blobs die nog niet in de repo staan in
/// [RepoDeckFiles.upserts] — dát is waar de pool zijn geld verdient
/// ([AssetPool.existing]): een afbeelding die vijf decks delen staat er één
/// keer. Op het native plane is [pool] `null`: git ontdubbelt zelf op inhoud, dus
/// dan gaan álle blobs mee en zijn de al aanwezige simpelweg geen wijziging.
Future<RepoDeckFiles> buildDeckRepoFiles(
  Deck deck, {
  required MarkdownService md,
  required AssetPool? pool,
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

  // Grafiekdata krijgt een eigen bestand naast deck.md, op een stabiel pad —
  // niet in de content-geadresseerde pool. Een poolpad is de hash van de
  // inhoud, dus elke gewijzigde cel zou een nieuw bestand opleveren en het
  // vorige laten wegkwijnen: precies geen diff. Op een vast pad laat een
  // wijziging zich lezen als "deze cel ging van 120 naar 138".
  for (final entry in chartDataFilesOf(rewritten).entries) {
    final path = repoChartDataPath(deckDir, entry.key);
    if (path == null) {
      warnings.add(entry.key); // buiten de deckmap; nooit schrijven
      continue;
    }
    upserts[path] = Uint8List.fromList(utf8.encode(entry.value));
  }

  // Met een pool alleen de nog niet aanwezige blobs; zonder pool (native) alle.
  final already = pool == null
      ? const <String>{}
      : await pool.existing(bytesForRef.keys);
  for (final entry in bytesForRef.entries) {
    if (already.contains(entry.key)) continue;
    final poolPath = GitRepoLayout.assetPathOf(entry.key);
    if (poolPath != null) upserts[poolPath] = entry.value;
  }

  return RepoDeckFiles(upserts: upserts, warnings: warnings.toList());
}
