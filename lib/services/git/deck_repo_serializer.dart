import 'dart:convert';
import 'dart:typed_data';

import 'package:path/path.dart' as p;

import '../../models/deck.dart';
import '../../models/git_settings.dart';
import '../../models/seal_record.dart';
import '../../models/slide.dart';
import '../../models/chart.dart';
import '../../utils/log.dart';
import '../annotation_codec.dart';
import '../markdown_service.dart';
import '../miauw_codec.dart';
import '../privacy/dismissal_codec.dart';
import '../seal_codec.dart';
import '../user_notes_codec.dart';
import '../slide_image_refs.dart';
import '../web_asset_store.dart';
import 'asset_pool.dart';
import 'deck_merge.dart';
import 'deck_repo_sidecars.dart';

// De sidecarlaag is afgesplitst (regelplafond) maar blijft hiervandaan
// bereikbaar: elke bestaande importeur ziet dezelfde namen.
export 'deck_repo_sidecars.dart';
import 'git_forge.dart';
import 'native_git_mirror_api.dart';

/// Standaardnaam van het markdown-bestand binnen een deckmap (§6). Gespiegeld in
/// `TabsNotifierGit.deckFileName`; hier apart zodat de serializer los te testen
/// is zonder de state-laag.
const String deckRepoFileName = 'deck.md';

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
/// De databestanden die [deck] noemt, als repo-paden onder [deckDir].
///
/// Anders dan [chartDataFilesOf] kijkt dit niet of de cijfers in het geheugen
/// staan: de vraag is wélke bestanden bij dit deck horen, niet wat er
/// geschreven moet worden. Dat onderscheid is precies wat de terugvalweg van
/// [resolveRepoDeckMerge] nodig heeft — daar zijn de cijfers per definitie niet
/// ingelezen, en moeten de bestanden toch overeind blijven.
Iterable<String> chartDataPathsOf(Deck deck, {required String deckDir}) sync* {
  for (final slide in deck.slides) {
    if (slide.type != SlideType.chart) continue;
    final source = ChartSpec.parse(slide.customMarkdown).source;
    if (source == null) continue;
    final path = repoChartDataPath(deckDir, source);
    if (path != null) yield path;
  }
}

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

/// Alles wat naast `deck.md` in de deckmap ligt, terug aan [deck] gehangen —
/// de omkering van [buildDeckRepoFiles] in één stap.
///
/// Bestaat omdat elk leespad in de app dezelfde dingen moet doen in dezelfde
/// volgorde, met dezelfde lezer: eerst de grafiekdata, dan de notities, dan de
/// tekeningen. Drie keer los aanroepen betekent drie plekken waar een volgende
/// laag vergeten kan worden — en die vergissing is stil: het deck opent
/// gewoon, alleen zonder wat er ook nog bij hoorde. Er is er hier maar één.
///
/// De ontbrekende grafiekbronnen reizen mee terug omdat de aanroeper daarover
/// meldt. Bij de notities en de tekeningen is er niets te melden: geen bestand
/// is de gewone toestand voor een deck zonder die laag.
Future<
  ({
    Deck deck,
    List<String> missingChartData,
    bool userNotesUnreadable,
    bool inkUnreadable,
    bool dismissalsUnreadable,
    bool miauwUnreadable,
    bool sealUnreadable,
  })
>
withRepoSidecars(
  Deck deck, {
  required String deckDir,
  required RepoFileReader read,
}) async {
  final charts = await withRepoChartData(deck, deckDir: deckDir, read: read);
  final notes = await withRepoUserNotes(
    charts.deck,
    deckDir: deckDir,
    read: read,
  );
  final ink = await withRepoInk(notes.deck, deckDir: deckDir, read: read);
  final dismissals = await withRepoDismissals(
    ink.deck,
    deckDir: deckDir,
    read: read,
  );
  final miauw = await withRepoMiauw(
    dismissals.deck,
    deckDir: deckDir,
    read: read,
  );
  final seal = await withRepoSeal(miauw.deck, deckDir: deckDir, read: read);
  return (
    deck: seal.deck,
    missingChartData: charts.missing,
    userNotesUnreadable: notes.onleesbaar,
    inkUnreadable: ink.onleesbaar,
    dismissalsUnreadable: dismissals.onleesbaar,
    miauwUnreadable: miauw.onleesbaar,
    sealUnreadable: seal.onleesbaar,
  );
}

/// [RepoFileReader] over één ref van [forge], mét het contract dat de typedef
/// belooft: **null als het er niet is**.
///
/// `GitForge.readBlob` gooit bij een ontbrekend bestand ([GitForgeError
/// .notFound]), en de sidecar-laag leest élke worp als "niet aanraken" —
/// terecht bij een netwerkhapering, maar fataal bij "bestaat nog niet": dan
/// werd geen enkele sidecar ooit geschreven op een branch waar hij nog niet
/// stond, en reisde er op het REST-pad stilletjes niets (#541). Afwezig en
/// onbereikbaar zijn verschillende antwoorden; alleen de eerste is hier null.
RepoFileReader repoFileReaderFor(GitForge forge, String ref) => (path) async {
  try {
    return await forge.readBlob(ref, path);
  } on GitForgeException catch (e) {
    if (e.kind == GitForgeError.notFound) return null;
    rethrow;
  }
};

// De weigering `gitRefusesSealedDeck` die hier stond is ingetrokken (#541,
// 23-07-2026): git is een bestandssysteem, geen enforcer. Het zegel reist nu
// als sidecar mee (`deck.seal.json`, zie `deck_repo_sidecars.dart`); dat een
// verzegeld deck afgekaart is, bewaakt de app zelf door het alleen-lezen te
// maken. De klasse `GitDeckOmissions` en de "niet alles gaat mee"-waarschuwing
// die hier stonden zijn eerder al opgeheven (#541): met media (#540),
// grafiekdata, notities en tekeningen was er geen ware regel meer over. De
// geschiedenis van dat krimpen staat in §9.1 — de waarschuwing verloor per
// gelande laag precies zijn regel, tot hij leeg was.

/// De repo-bestandenset van één deck (§9.1): het tekstbestand plus de nieuwe
/// pool-blobs die nog niet in de repo stonden.
class RepoDeckFiles {
  /// Pad → bytes voor `GitForge.commitFiles(upserts:)` — `<deckDir>/deck.md`
  /// plus elke pool-blob (`assets/<sha>.<ext>`) die nog geüpload moet worden.
  final Map<String, Uint8List> upserts;

  /// Paden voor `GitForge.commitFiles(deletes:)` — bestanden die er in de repo
  /// nog wél zijn maar in dit deck niet meer.
  ///
  /// Vandaag de sidecars naast `deck.md`. Zonder dit zou het wissen van je
  /// laatste notitie niets doen: de commit laat het oude bestand staan, en bij
  /// de volgende open hangt de notitie er weer aan. Een wissing die terugkomt
  /// is erger dan een die niet werkt — de gebruiker denkt dat het weg is.
  ///
  /// Een pad hier is een *belofte over deze deckmap*, geen vrije opdracht: de
  /// samensteller zet er alleen paden in die hij zelf ook kan schrijven.
  final List<String> deletes;

  /// Mediaverwijzingen die niet mee konden: video/audio (die round-trippen nog
  /// niet door git, §9.1) en afbeeldingen waarvan de bytes niet te lezen waren.
  /// Het deck slaat wél op, maar deze verwijzingen zijn niet mee-gecommit — de
  /// aanroeper meldt dat, in plaats van een kapotte verwijzing te verzwijgen.
  final List<String> warnings;

  const RepoDeckFiles({
    required this.upserts,
    required this.warnings,
    this.deletes = const [],
  });
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

  /// Waarmee een bestand ín de deckmap te lezen is. Alleen gebruikt om vast te
  /// stellen wat er op het notitiepad ligt vóórdat we het aanraken — zie
  /// [repoUserNotesState]. Zonder lezer wordt er nooit verwíjderd (niet weten
  /// is geen reden om te wissen) maar wél geschreven: anders zouden de notities
  /// op het native pad, dat geen lezer meegeeft, nooit reizen.
  RepoFileReader? read,
}) async {
  final refForMem = <String, String>{}; // bronpad → repo:-verwijzing (dedup)
  final bytesForRef = <String, Uint8List>{}; // repo:-verwijzing → bytes
  final warnings = <String>{};
  final deletes = <String>[];

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

  // De sidecars gaan mee (#541/#651/#756): notities, tekeningen,
  // terzijdeleggingen, de MIAUW-dispositie en het zegel, elk op een stabiel
  // pad naast deck.md. Waarom ingesprongen, wat de aanraakregels zijn en
  // waarom grafstenen inhoud tellen staat bij [writeAllRepoSidecars].
  await writeAllRepoSidecars(
    rewritten,
    deckDir: deckDir,
    read: read,
    upserts: upserts,
    deletes: deletes,
  );

  // Met een pool alleen de nog niet aanwezige blobs; zonder pool (native) alle.
  final already = pool == null
      ? const <String>{}
      : await pool.existing(bytesForRef.keys);
  for (final entry in bytesForRef.entries) {
    if (already.contains(entry.key)) continue;
    final poolPath = GitRepoLayout.assetPathOf(entry.key);
    if (poolPath != null) upserts[poolPath] = entry.value;
  }

  return RepoDeckFiles(
    upserts: upserts,
    warnings: warnings.toList(),
    deletes: deletes,
  );
}

/// De tekstbestanden van [deck] voor de lokale werkkopie ([DeckMirror]) —
/// wat er in de wachtrij belandt als er geen verbinding is (§8.5).
///
/// Alleen tekst: geen afbeeldingen en geen media. Die staan bij een offline
/// opslag nog in het geheugen en worden bij het legen van de wachtrij alsnog
/// gepoold; de werkkopie is er om de *inhoud* veilig te stellen, niet om de
/// repo na te bouwen.
///
/// **Wat hier niet in staat, wordt verwijderd.** Dat is geen bijwerking maar
/// het contract van [SyncEngine], die zijn `deletes` afleidt uit wat er in de
/// repo staat maar hier niet — zodat een dia die je weghaalde ook echt zijn
/// bestanden meeneemt. Elk bestand dat de werkkopie in hoort, hoort dus hier,
/// en een vergeten laag is geen "reist niet mee" maar een verwíjdering op de
/// tak. Vandaar dat dit één functie is met één lijst, in plaats van een map
/// die ergens in de state-laag wordt opgebouwd.
Map<String, Uint8List> mirrorDeckFiles(
  Deck deck, {
  required String deckDir,
  required MarkdownService md,
}) {
  final notes = UserNotesCodec.encode(
    deck.slides,
    deck.userNotes,
    forTextMerge: true,
  );
  final ink = AnnotationCodec.encode(
    deck.slides,
    deck.annotations,
    forTextMerge: true,
  );
  final dismissals = switch (deck.dismissals) {
    null => null,
    final d => DismissalCodec.encode(d, forTextMerge: true),
  };
  final miauw = MiauwCodec.encodeDisposition(deck.miauw, forTextMerge: true);
  final seal = SealCodec.encode(SealRecord.of(deck));
  return <String, Uint8List>{
    p.posix.join(deckDir, deckRepoFileName): Uint8List.fromList(
      utf8.encode(md.generateDeck(deck)),
    ),
    // De markdown draagt straks alleen de verwijzing naar de grafiekdata; zonder
    // deze bestanden komt daar bij het legen van de wachtrij een lege grafiek
    // uit.
    for (final entry in chartDataFilesOf(deck).entries)
      ?repoChartDataPath(deckDir, entry.key): Uint8List.fromList(
        utf8.encode(entry.value),
      ),
    p.posix.join(deckDir, userNotesRepoFileName): ?switch (notes) {
      final String json => Uint8List.fromList(utf8.encode(json)),
      null => null,
    },
    p.posix.join(deckDir, inkRepoFileName): ?switch (ink) {
      final String json => Uint8List.fromList(utf8.encode(json)),
      null => null,
    },
    p.posix.join(deckDir, dismissalsRepoFileName): ?switch (dismissals) {
      final String json => Uint8List.fromList(utf8.encode(json)),
      null => null,
    },
    p.posix.join(deckDir, miauwRepoFileName): ?switch (miauw) {
      final String json => Uint8List.fromList(utf8.encode(json)),
      null => null,
    },
    p.posix.join(deckDir, sealRepoFileName): ?switch (seal) {
      final String json => Uint8List.fromList(utf8.encode(json)),
      null => null,
    },
  };
}

/// Los één native merge van een deckmap op: de drie kanten samenvoegen, mét de
/// lagen die naast hun `deck.md` staan, en er de nieuwe deckmap van maken.
///
/// Dit is de hele opdracht die `NativeGitMirror.mergeRemote` aan zijn aanroeper
/// geeft, en hij hoort hier omdat elke regel erin over opslag gaat: welke lagen
/// een kant draagt, wat er overblijft als het niet lukt, en wat de deckmap
/// wordt. De state-laag levert alleen wat zij als enige weet — de importpoort
/// ([gate]) en waar afbeeldingsbytes vandaan komen.
///
/// **Wat hier terugkomt wordt geschreven; wat níet genoemd wordt blijft staan.**
/// Dat was ooit andersom — de deckmap werd leeggemaakt en opnieuw gevuld — en
/// dat kostte elk bestand waar de resolver geen weet van had: `data/*.json` bij
/// élke merge, ook een geslaagde, en sinds #541 ook de notities. De resolver
/// kán die volledigheid niet waarmaken (hij kent de deckmap niet, alleen de
/// drie `deck.md`'s), dus ligt de bewijslast nu de andere kant op: verwijderen
/// gebeurt alleen op verzoek, via [RepoMergeOutcome.deletes]. Zie #670.
///
/// Elke kant wordt eerst gehydrateerd met de lagen die naast zijn `deck.md`
/// staan. Zonder dat lijken alle drie de decks notitie- en cijferloos, komt er
/// niets van beide uit de merge, en verdwijnt andermans werk zonder dat er ooit
/// een conflict was.
///
/// [merge] is null wanneer een van de drie kanten niet door de poort kwam; dan
/// draagt [RepoMergeOutcome.files] ónze kant ongewijzigd.
typedef RepoMergeOutcome = ({
  Map<String, Uint8List> files,
  List<String> deletes,
  bool clean,
  DeckMergeResult? merge,
  List<String> missingChartData,
});

Future<RepoMergeOutcome> resolveRepoDeckMerge({
  required String deckDir,
  required String deckFile,
  required Uint8List? baseBytes,
  required Uint8List? ourBytes,
  required Uint8List? theirBytes,
  required Future<Uint8List?> Function(MergeSide side, String path) read,
  required Deck? Function(Uint8List? bytes) gate,
  required MarkdownService md,
  required AssetByteResolver resolveBytes,
}) async {
  final missing = <String>[];

  Future<Deck> hydrated(Deck deck, MergeSide side) async {
    final sidecars = await withRepoSidecars(
      deck,
      deckDir: deckDir,
      read: (path) => read(side, path),
    );
    // Alleen over ónze kant valt iets zinnigs te melden: een bestand dat bij
    // hen ontbreekt is hun zaak, en de voorouder is historie.
    if (side == MergeSide.ours) missing.addAll(sidecars.missingChartData);
    return sidecars.deck;
  }

  final base = gate(baseBytes);
  final ours = gate(ourBytes);
  final theirs = gate(theirBytes);
  if (base == null || ours == null || theirs == null) {
    // Onze kant ongewijzigd — en dat is méér dan `deck.md`. Git's eigen
    // tekst-merge is hierboven al over de deckmap gegaan, dus de notities en de
    // grafiekdata kunnen conflictmarkeringen dragen; die schrijven we terug
    // zoals ze bij ons stonden. Verwijderen doen we niets: één geweigerde kant
    // hoort de rest van de deckmap niet te kosten.
    final files = <String, Uint8List>{
      deckFile: ?ourBytes,
      p.posix.join(deckDir, userNotesRepoFileName): ?await read(
        MergeSide.ours,
        p.posix.join(deckDir, userNotesRepoFileName),
      ),
      p.posix.join(deckDir, inkRepoFileName): ?await read(
        MergeSide.ours,
        p.posix.join(deckDir, inkRepoFileName),
      ),
      p.posix.join(deckDir, dismissalsRepoFileName): ?await read(
        MergeSide.ours,
        p.posix.join(deckDir, dismissalsRepoFileName),
      ),
      p.posix.join(deckDir, miauwRepoFileName): ?await read(
        MergeSide.ours,
        p.posix.join(deckDir, miauwRepoFileName),
      ),
      p.posix.join(deckDir, sealRepoFileName): ?await read(
        MergeSide.ours,
        p.posix.join(deckDir, sealRepoFileName),
      ),
    };
    for (final path
        in ours == null
            ? const <String>[]
            : chartDataPathsOf(ours, deckDir: deckDir)) {
      final bytes = await read(MergeSide.ours, path);
      if (bytes != null) files[path] = bytes;
    }
    return (
      files: files,
      deletes: const <String>[],
      clean: false,
      merge: null,
      missingChartData: const <String>[],
    );
  }

  final merge = mergeDeckVersions(
    await hydrated(base, MergeSide.base),
    await hydrated(ours, MergeSide.ours),
    await hydrated(theirs, MergeSide.theirs),
  );
  final built = await buildDeckRepoFiles(
    merge.merged,
    md: md,
    pool: null, // native: git ontdubbelt zelf op inhoud
    deckDir: deckDir,
    resolveBytes: resolveBytes,
    read: (path) => read(MergeSide.ours, path),
  );
  return (
    files: built.upserts,
    deletes: built.deletes,
    clean: merge.isClean,
    merge: merge,
    missingChartData: missing,
  );
}

/// Wat een poging tot samenvoegen-na-conflict opleverde.
///
/// Drie uitkomsten, en ze sluiten elkaar uit. [merge] null: er viel niets
/// samen te voegen (geen voorouder, of een van de twee kanten was niet te
/// lezen) — de aanroeper houdt het conflict. [merge] gezet maar niet schoon:
/// er zijn botsingen die de gebruiker moet beslechten, en er is niets gecommit.
/// [sha] gezet: schoon samengevoegd én geland.
typedef RepoConflictMerge = ({
  DeckMergeResult? merge,
  String? sha,
  String? head,
  List<String> warnings,
});

/// Voeg [ours] samen met wat er inmiddels op [branch] staat, en commit het als
/// het schoon ging (§8.6).
///
/// Hoort hier en niet in de state-laag omdat elke stap over de repo gaat: welke
/// twee refs de andere kanten zijn, wat de nieuwe basis wordt, en welke
/// bestanden de commit draagt. Wat de state-laag ervan moet weten staat in
/// [RepoConflictMerge]; het bijwerken van het tabblad blijft daar.
///
/// [readDeckAt] leest een deck op een ref — door de importpoort, want de branch
/// van een ander is niet vertrouwder dan welke invoer ook (P5). Die poort woont
/// in de state-laag, dus hij komt als parameter binnen.
///
/// Zonder [baseSha] valt er niets driewegs te doen: dan is er geen
/// gemeenschappelijke voorouder en is de enige eerlijke uitkomst "conflict".
///
/// [RepoConflictMerge.head] is hún kop op het moment van samenvoegen, en die
/// hoort de nieuwe basis van het tabblad te worden — óók wanneer de merge niet
/// schoon was. De gebruiker kijkt dan naar een deck dat tegen die kop is
/// samengevoegd; blijft de oude basis staan, dan botst zijn volgende opslag
/// tegen een voorouder die hij allang voorbij is.
Future<RepoConflictMerge> mergeIntoRemote(
  GitForge forge, {
  required String deckDir,
  required String branch,
  required String baseSha,
  required Deck ours,
  required String message,
  required MarkdownService md,
  required AssetByteResolver Function(Deck merged) resolveBytesFor,
  required Future<Deck?> Function(String ref) readDeckAt,
}) async {
  if (baseSha.isEmpty) {
    return (merge: null, sha: null, head: null, warnings: const <String>[]);
  }

  final base = await readDeckAt(baseSha);
  final theirs = await readDeckAt(branch);
  if (base == null || theirs == null) {
    return (merge: null, sha: null, head: null, warnings: const <String>[]);
  }

  final merge = mergeDeckVersions(base, ours, theirs);
  // Hun kop vóór de commit: dat is de basis waar deze merge tegenaan is
  // gemaakt. Erna opvragen zou een commit kunnen meenemen die er tussendoor
  // kwam, en dan claimt de guard een voorouder die hij niet gelezen heeft.
  final head = await forge.headSha(branch);
  if (!merge.isClean) {
    return (merge: merge, sha: null, head: head, warnings: const <String>[]);
  }

  final files = await buildDeckRepoFiles(
    merge.merged,
    md: md,
    pool: AssetPool(forge: forge, branch: branch),
    deckDir: deckDir,
    resolveBytes: resolveBytesFor(merge.merged),
    read: (path) => forge.readBlob(branch, path),
  );
  final result = await forge.commitFiles(
    branch: branch,
    message: message,
    upserts: files.upserts,
    deletes: files.deletes,
    baseSha: head,
  );
  return (merge: merge, sha: result.sha, head: head, warnings: files.warnings);
}
