import 'dart:convert';
import 'dart:typed_data';

import 'package:path/path.dart' as p;

import '../../models/deck.dart';
import '../../models/git_settings.dart';
import '../../models/slide.dart';
import '../../models/chart.dart';
import '../../utils/log.dart';
import '../markdown_service.dart';
import '../slide_image_refs.dart';
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

/// Wat er van een deck níét meereist naar git (§9.1), geteld per soort.
///
/// De git-opslag schrijft `deck.md`, de assetpool (afbeeldingen **en** media,
/// zie D5/D12) en de grafiekdata. Wat achterblijft zijn de sidecars:
/// `.ink.json` met de tekeningen, `.user-notes.json` met de notities en
/// `.seal.json` met het zegel en de handtekening worden nergens in
/// `services/git/` geschreven. Op schijf gaan die wél mee, dus wie van een
/// bestand naar git verhuist raakt ze kwijt zonder dat er iets misgaat waar de
/// app op kan wijzen.
///
/// Dit meenemen is een grotere ingreep dan een waarschuwing; de waarschuwing kan
/// niet wachten. De UI toont hem vóór de commit — daarna is de keuze al gemaakt.
class GitDeckOmissions {
  /// Dia's waarop getekend is; die tekenlaag gaat niet mee.
  final int annotatedSlides;

  /// Dia's met gebruikersnotities; die notities gaan niet mee.
  final int noteSlides;

  /// Of het deck een zegel of een handtekening draagt die niet meegaat.
  ///
  /// Zwaarder dan de andere drie, want hier verdwijnt niet alleen werk maar een
  /// verklaring: een verzegeld rapport dat via git terugkomt, leest als een
  /// rapport dat nooit verzegeld is. Sinds 0.1.0 staat het zegel naast de
  /// markdown in plaats van erin, dus het reist niet meer vanzelf mee in
  /// `deck.md` — precies de stilte waar deze waarschuwing voor bestaat.
  final bool sealed;

  const GitDeckOmissions({
    this.annotatedSlides = 0,
    this.noteSlides = 0,
    this.sealed = false,
  });

  bool get isEmpty => annotatedSlides == 0 && noteSlides == 0 && !sealed;

  bool get isNotEmpty => !isEmpty;
}

/// Tel per soort wat er bij een commit van [deck] achterblijft.
///
/// Alleen niet-lege lagen tellen mee: een lege notitie of een dia zonder
/// streken is niets om over te waarschuwen, en een waarschuwing die ook afgaat
/// wanneer er niets aan de hand is, leert de gebruiker hem weg te klikken.
GitDeckOmissions gitDeckOmissions(Deck deck) {
  final ids = {for (final s in deck.slides) s.id};
  final ink = deck.annotations.entries
      .where((e) => ids.contains(e.key) && e.value.isNotEmpty)
      .length;
  final notes = deck.userNotes.entries
      .where((e) => ids.contains(e.key) && e.value.trim().isNotEmpty)
      .length;
  return GitDeckOmissions(
    annotatedSlides: ink,
    noteSlides: notes,
    sealed: deck.finalized || (deck.signature?.isNotEmpty ?? false),
  );
}

/// De repo-bestandenset van één deck (§9.1): het tekstbestand plus de nieuwe
/// pool-blobs die nog niet in de repo stonden.
class RepoDeckFiles {
  /// Pad → bytes voor `GitForge.commitFiles(upserts:)` — `<deckDir>/deck.md`
  /// plus elke pool-blob (`assets/<sha>.<ext>`) die nog geüpload moet worden.
  final Map<String, Uint8List> upserts;

  /// Mediaverwijzingen die niet mee konden: video/audio (die round-trippen nog
  /// niet door git, §9.1) en afbeeldingen waarvan de bytes niet te lezen waren.
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
/// Alleen afbeeldingen — de velden én de `![…](…)` in de vrije tekst, gelijk aan
/// wat het open-pad terugzet; video en audio round-trippen nog niet door git en
/// worden gemeld in plaats van als kapotte verwijzing weggeschreven.
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

  Future<String?> poolAsset(String path, {required String fallback}) async {
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
        ? (WebAssetStore.nameFor(path) ?? fallback)
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

  final slides = <Slide>[];
  for (final slide in deck.slides) {
    // Élke afbeeldingsverwijzing van de dia gaat door de pool, ook eentje midden
    // in de vrije tekst. Blijft die achter als gewoon bestandspad, dan staat er
    // in `deck.md` een verwijzing die de forge niet kent én telt de asset voor
    // [AssetIndex] als ongebruikt — en opruimen is onomkeerbaar.
    //
    // Poolen is asynchroon en herschrijven niet, dus het gaat in twee slagen:
    // eerst elke verwijzing naar een `repo:`-pad, dan de dia in haar geheel om.
    final pooled = <String, String>{};
    for (final path in slideImagePaths(slide).toSet()) {
      final ref = await poolAsset(path, fallback: 'afbeelding.png');
      if (ref != null) pooled[path] = ref;
    }
    // Video en audio gaan door dezelfde pool. Wie zijn presentaties in git
    // bewaart, hoort zijn media daar ook te vinden: een deck waarin de film
    // ontbreekt is geen kopie maar een fragment (D5). De pool adresseert op
    // inhoud, dus een ongewijzigde film levert bij elke commit hetzelfde blob
    // op en groeit de historie niet.
    final videoRef = await poolAsset(slide.videoPath, fallback: 'video.mp4');
    final audioRef = await poolAsset(slide.audioPath, fallback: 'audio.m4a');

    var next = rewriteSlideImagePaths(slide, (path) => pooled[path]);
    if (videoRef != null) next = next.copyWith(videoPath: videoRef);
    if (audioRef != null) next = next.copyWith(audioPath: audioRef);
    slides.add(next);
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
