// Part of the file_service library — see ../file_service.dart.
// Split out for navigability (open: truncation check, sidecars & chart hydration); all imports live in the main library
// file. These are private FileService helpers — they relocate verbatim
// into an extension on FileService, same library, no behaviour change.
part of '../file_service.dart';

/// Wat [FileService.openDeckDetailed] oplevert.
///
/// Een benoemde klasse en geen anoniem record: dit resultaat groeit mee met wat
/// het openen te melden heeft (eerst alleen het deck, toen de reden van een
/// weigering, toen grafiekdata-waarschuwingen, nu overgeslagen lagen). Elk veld
/// erbij kostte een regel op negen returnplekken, en dat zag je alleen doordat
/// de klassenratchet omviel. Een fabriek voor de weigering scheelt dat.
class DeckOpenResult {
  const DeckOpenResult({
    this.deck,
    this.failure,
    this.warnings = const <String>[],
    this.skippedSidecars = const <String>[],
  });

  /// Het geopende deck, of null bij een weigering.
  final Deck? deck;

  /// Waarom er geweigerd is, of null wanneer het gelukt is.
  final OpenFailure? failure;

  /// Grafiekdatabestanden die niet gelezen konden worden; die grafieken blijven
  /// leeg.
  final List<String> warnings;

  /// Lagen naast het deck die te groot waren om in te lezen — het bestand zelf
  /// is niet aangeraakt. Zie [FileService.maxDeckSidecarBytes].
  final List<String> skippedSidecars;

  /// Een weigering, met de reden.
  const DeckOpenResult.failed(OpenFailure reason)
    : deck = null,
      failure = reason,
      warnings = const <String>[],
      skippedSidecars = const <String>[];
}

/// Wat [FileServiceDocumentOpen.openDocumentDetailed] oplevert: het geopende
/// [MarkdownDocument], of de reden van een weigering.
///
/// Dezelfde vorm als [DeckOpenResult], maar voor het platte-.md-pad — het loopt
/// door dezelfde fail-closed poorten (cap, veiligheidsscan) zonder de bron te
/// deconstrueren tot slides. Geen `warnings`/`skippedSidecars`: die horen bij de
/// deck-hydratie (grafiekdata, sidecars) die een document nog niet kent.
class DocumentOpenResult {
  const DocumentOpenResult({this.document, this.failure});

  /// Het geopende document, of null bij een weigering.
  final MarkdownDocument? document;

  /// Waarom er geweigerd is, of null wanneer het gelukt is.
  final OpenFailure? failure;

  /// Een weigering, met de reden.
  const DocumentOpenResult.failed(OpenFailure reason)
    : document = null,
      failure = reason;
}

extension FileServiceDocumentOpen on FileService {
  /// Opent een gewoon, doorlopend Markdown-document (geen Marp-deck) als een
  /// byte-getrouw [MarkdownDocument].
  ///
  /// Dezelfde fail-closed poort als [FileService.openDeckDetailed] — grootte-cap,
  /// UTF-8, veiligheidsscan — maar zónder de `marp: true`-eis en zónder de bron
  /// te deconstrueren: wat op schijf staat, is wat je bewerkt (zie
  /// `docs/design/DOCUMENT_MODE.md`). De aanroeper kiest deck of document aan de
  /// hand van [MarkdownService.sniffFrontmatter]; dit pad opent wat het krijgt.
  Future<DocumentOpenResult> openDocumentDetailed(
    String filePath, {
    String? content,
  }) async {
    final read = await _readAndScanMarkdown(filePath, content);
    if (read.failure != null) {
      return DocumentOpenResult.failed(read.failure!);
    }
    return DocumentOpenResult(document: MarkdownDocument.parse(read.raw!));
  }

  /// Vraagt de gebruiker waar het document naartoe moet en schrijft het daar
  /// byte-getrouw heen (nieuw of nog niet opgeslagen document, DOCUMENT_MODE.md
  /// §3). Levert het gekozen pad, of null bij wegklikken of schrijffout — zie
  /// [_writeDocumentToPicked]. Spiegel van [saveDeckAsDetailed], zonder projectmap
  /// of sidecars: een document is één plat bestand.
  Future<String?> saveDocumentAs(
    MarkdownDocument document, {
    String? initialDirectory,
  }) async => _writeDocumentToPicked(
    document,
    await _saveDestination(
      dialogTitle: _d('Opslaan als'),
      fileName: 'document.md',
      initialDirectory: initialDirectory,
    ),
  );
}

/// Schrijft [document] naar het gekozen [dest] (vult `.md` aan wanneer die
/// ontbreekt). Levert het uiteindelijke pad, of null wanneer de gebruiker het
/// venster wegklikte (`dest == null`) of het schrijven mislukte (dat logt
/// [saveDocument]). Top-level en niet op [FileService]: hij raakt geen veld van
/// die klasse aan, en de klasse zit tegen haar plafond.
Future<String?> _writeDocumentToPicked(
  MarkdownDocument document,
  String? dest,
) async {
  if (dest == null) return null;
  final path = dest.endsWith('.md') ? dest : '$dest.md';
  return await saveDocument(document, path) ? path : null;
}

/// Schrijf een document byte-getrouw naar [filePath]: precies de bron, geen
/// deck-scaffold, geen `marp:`-kop, geen normalisatie (DOCUMENT_MODE.md §3).
/// Atomair via [writeStringAtomic], zodat een onderbroken schrijfactie nooit een
/// half bestand achterlaat. Levert `true` bij succes.
///
/// De veiligheidsscan hoort bij het *openen* (onvertrouwde invoer); wat de
/// gebruiker in zijn eigen editor typt en naar zijn eigen, gekozen pad
/// wegschrijft, is geen onvertrouwde invoer en gaat er niet nog eens doorheen.
///
/// Top-level en niet op [FileService]: hij raakt geen enkel veld van die klasse
/// aan, en de klasse zit tegen haar plafond.
Future<bool> saveDocument(MarkdownDocument document, String filePath) async {
  try {
    await writeStringAtomic(File(filePath), document.toMarkdown());
    return true;
  } catch (e) {
    logWarning('FileService.saveDocument: not writable', e);
    return false;
  }
}

/// True when [content] handed to [FileService.openDeckDetailed] is over the
/// markdown cap. A UTF-16 code unit is always ≥ 1 UTF-8 byte, so a code-unit
/// count over the cap guarantees the byte size is over it too — a cheap, O(1)
/// conservative guard that never has to encode the whole string to reject.
bool _providedContentOverCap(String content) {
  if (content.length <= FileService.maxDeckMarkdownBytes) return false;
  logWarning(
    'FileService.openDeck: provided content exceeds '
    '${FileService.maxDeckMarkdownBytes ~/ (1024 * 1024)} MiB cap',
  );
  return true;
}

/// Leest de bytes van een `.md` in en scant ze fail-closed op uitvoerbare
/// inhoud — de gedeelde poort vóór zowel het deck- als het documentpad.
///
/// De volgorde is veiligheidskritisch en identiek voor beide paden: grootte-cap
/// → bestaan → UTF-8-lees → veiligheidsscan. De scan draait op exact de bytes die
/// de aanroeper daarna parseert, zodat er geen gat zit tussen controle en gebruik
/// (een bestand op schijf kan tussen twee lezingen verwisseld worden). Levert de
/// bron óf de reden van een weigering; nooit allebei.
///
/// Top-level en niet op [FileService]: hij raakt geen enkel veld van die klasse
/// aan, en de klasse zit tegen haar plafond.
Future<({String? raw, OpenFailure? failure})> _readAndScanMarkdown(
  String filePath,
  String? content,
) async {
  String raw;
  if (content != null) {
    // Provided content bypasses the on-disk stat, so apply an equivalent cap.
    if (_providedContentOverCap(content)) {
      return (raw: null, failure: OpenFailure.tooLarge);
    }
    raw = content;
  } else {
    final file = File(filePath);
    if (!await file.exists()) {
      return (raw: null, failure: OpenFailure.notFound);
    }
    // Plain text (images/media are sidecar files), so a huge .md is
    // pathological. Cap it to avoid loading/parsing an attacker-sized file.
    try {
      if (await file.length() > FileService.maxDeckMarkdownBytes) {
        logWarning(
          'FileService.open: file exceeds '
          '${FileService.maxDeckMarkdownBytes ~/ (1024 * 1024)} MiB cap',
        );
        return (raw: null, failure: OpenFailure.tooLarge);
      }
    } catch (e) {
      logWarning('FileService.open: cannot stat file', e);
      return (raw: null, failure: OpenFailure.unreadable);
    }
    try {
      raw = await file.readAsString();
    } catch (e) {
      // Non-UTF8 / unreadable bytes must not crash the open flow.
      logWarning('FileService.open: file not readable as UTF-8', e);
      return (raw: null, failure: OpenFailure.unreadable);
    }
  }
  // Fail-closed: never open content that carries executable markup. Scanning
  // `raw` — the very bytes the caller parses next — closes any
  // time-of-check/time-of-use gap.
  final findings = MarkdownSafetyScanner.scan(raw);
  if (findings.isNotEmpty) {
    logWarning(
      'FileService.open: refused — executable content '
      '(${findings.length} finding(s))',
      filePath,
    );
    return (raw: null, failure: OpenFailure.unsafe);
  }
  return (raw: raw, failure: null);
}

extension _FileServiceOpen on FileService {
  /// True when [raw] opens with a complete frontmatter block but carries no
  /// slide body after it, while [parsed] degraded to the single placeholder
  /// slide — the signature of a truncated or corrupt deck file.
  bool _looksTruncated(String raw, Deck parsed) {
    if (parsed.slides.length != 1) return false;
    final norm = raw.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
    if (!norm.startsWith('---\n')) return false;
    final end = norm.indexOf('\n---\n', 4);
    // Unterminated frontmatter: leave it to the parser rather than reject here.
    if (end == -1) return false;
    // A complete frontmatter header followed by no slide body means the file
    // was cut short — trim only the part *after* the closing fence so the
    // fence's own trailing newline is preserved.
    return norm.substring(end + 5).trim().isEmpty;
  }

  /// Legt de lagen die naast de markdown wonen terug op [deck]: de
  /// inkt-annotaties, de gebruikersnotities, de MIAUW-dispositie en het zegel.
  ///
  /// Elke laag apart afgeschermd: een kapotte sidecar mag het openen van het
  /// deck nooit blokkeren — dat zou een tekening van vorige week een hele
  /// presentatie kosten.
  Future<Deck> _attachSidecars(
    Deck deck,
    String filePath,
    List<String> skipped,
  ) async {
    var hydrated = deck;
    final sidecar = File(_sidecarPath(filePath));
    if (await sidecar.exists()) {
      try {
        final raw = await _readSidecarCapped(sidecar, 'ink', skipped);
        if (raw != null) {
          final map = AnnotationCodec.decode(raw, hydrated.slides);
          if (map.isNotEmpty) hydrated = hydrated.copyWith(annotations: map);
        }
      } catch (e) {
        // A broken sidecar must never block opening the deck.
        logWarning('FileService.openDeck: annotation sidecar unreadable', e);
      }
    }
    final userNotesSidecar = File(_userNotesSidecarPath(filePath));
    if (await userNotesSidecar.exists()) {
      try {
        final raw = await _readSidecarCapped(
          userNotesSidecar,
          'user-notes',
          skipped,
        );
        if (raw != null) {
          final map = UserNotesCodec.decode(raw, hydrated.slides);
          if (map.isNotEmpty) hydrated = hydrated.copyWith(userNotes: map);
        }
      } catch (e) {
        logWarning('FileService.openDeck: user-notes sidecar unreadable', e);
      }
    }
    // De MIAUW-dispositie. Ligt er een sidecar, dan is die de waarheid; wat
    // de parser nog uit de oude base64-front matter haalde, is het
    // opwaardeerpad voor een bestand dat er nog geen heeft.
    final miauwSidecar = File(_miauwSidecarPath(filePath));
    if (await miauwSidecar.exists()) {
      try {
        final raw = await _readSidecarCapped(miauwSidecar, 'MIAUW', skipped);
        final d = raw == null
            ? const MiauwDisposition()
            : MiauwCodec.decode(raw);
        if (!d.isEmpty) {
          hydrated = hydrated.copyWith(miauw: d);
        }
      } catch (e) {
        logWarning('FileService.openDeck: MIAUW sidecar unreadable', e);
      }
    }
    // De terzijdegelegde privacybevindingen (#651). Ligt er geen sidecar, dan
    // is er niets terzijdegelegd — er is geen oude vorm om van op te waarderen,
    // want dit formaat begon hier.
    final dismissalsSidecar = File(_dismissalsSidecarPath(filePath));
    if (await dismissalsSidecar.exists()) {
      try {
        final raw = await _readSidecarCapped(
          dismissalsSidecar,
          'dismissals',
          skipped,
        );
        if (raw != null) {
          // Het zout uit het bestand wint; dit geldt alleen wanneer het bestand
          // er geen draagt, en dan valt er ook niets te matchen.
          final d = DismissalCodec.decode(
            raw,
            fallbackSalt: newDismissalSalt(),
          );
          if (!d.isEmpty) hydrated = hydrated.copyWith(dismissals: d);
        }
      } catch (e) {
        logWarning('FileService.openDeck: dismissals sidecar unreadable', e);
      }
    }
    // Het zegel en de handtekening. Ligt er een sidecar, dan is die de
    // waarheid; wat de parser nog uit de oude front matter haalde (met
    // [SealForm.canonical]) is het opwaardeerpad voor een bestand dat er nog
    // geen heeft.
    final sealSidecar = File(_sealSidecarPath(filePath));
    if (await sealSidecar.exists()) {
      try {
        final raw = await _readSidecarCapped(sealSidecar, 'seal', skipped);
        final record = raw == null ? null : SealCodec.decode(raw);
        if (record != null) hydrated = record.applyTo(hydrated);
      } catch (e) {
        logWarning('FileService.openDeck: seal sidecar unreadable', e);
      }
    }
    return hydrated;
  }

  /// Load the external CSV of any chart slide that links one, inlining the data
  /// into the in-memory spec so the renderer has it. The markdown on disk keeps
  /// only the `source` reference (data is stripped again on save).
  Future<Deck> _hydrateCharts(
    Deck deck,
    List<String> warnings, {
    required String deckPath,
  }) async {
    if (deck.projectPath == null) return deck;
    var changed = false;
    final slides = <Slide>[];
    for (final s in deck.slides) {
      if (s.type != SlideType.chart) {
        slides.add(s);
        continue;
      }
      final spec = ChartSpec.parse(s.customMarkdown);
      if (spec.source == null || spec.hasInlineData) {
        slides.add(s);
        continue;
      }
      // A chart's data link must stay inside the project (no absolute paths or
      // `../` escapes) — otherwise an untrusted deck could read arbitrary files.
      final abs = resolveProjectRelative(deck.projectPath, spec.source!);
      final file = abs == null ? null : File(abs);
      if (file == null || !await file.exists()) {
        // The chart will draw empty. Say so: silence here reads as "this chart
        // has no numbers" when the truth is "its file is missing or refused".
        warnings.add(spec.source!);
        slides.add(s);
        continue;
      }
      if (await file.length() > FileService.maxChartDataBytes) {
        // Dezelfde behandeling als een ontbrekend bestand: de grafiek tekent
        // leeg, en de waarschuwing zegt welk bestand het was. Stil overslaan
        // zou lezen als "deze grafiek heeft geen cijfers".
        logWarning(
          'FileService.openDeck: chart data exceeds '
          '${FileService.maxChartDataBytes ~/ (1024 * 1024)} MiB cap',
        );
        warnings.add(spec.source!);
        slides.add(s);
        continue;
      }
      try {
        final raw = await file.readAsString();
        final filled = spec.withData(raw, path: abs!);
        // Hydration happens on open, with no interface to interrupt, so an
        // unreadable value can only leave a trace here. It still beats a chart
        // that silently draws 0 with nothing anywhere recording why. Only the
        // CSV form needs it — a JSON data file already carries real numbers.
        // Parsing twice is deliberate and cheap: chart data is a handful of
        // rows, and threading the diagnosis through withData would change its
        // signature for every caller.
        //
        // Het *aantal*, nooit de waarden. Hier stonden tot vijf werkelijke
        // celwaarden in de logregel, tegen de regel in de kop van `log.dart`
        // in: een grafiekbestand kan een omzet per klant of een uitslag per
        // persoon bevatten, en een niet-numerieke cel is juist vaak de
        // tekstkolom ernaast. Het aantal zegt de ontwikkelaar alles wat hij
        // nodig heeft; de gebruiker ziet welke cellen het zijn in het bestand.
        if (!abs.toLowerCase().endsWith('.json')) {
          final unreadable = parseCsv(raw).unreadable;
          if (unreadable.isNotEmpty) {
            logWarning(
              'FileService._hydrateCharts: ${unreadable.length} value(s) in '
              '${spec.source} are not numbers and were charted as 0',
            );
          }
        }
        // Remember what the file held, so the save path can tell "the user
        // edited this chart" apart from "nobody touched it" — see
        // [_writeChartData]. Onder dit deck, niet op één hoop: zie
        // [_chartDataAtOpen].
        (_chartDataAtOpen[FileService._deckChartKey(deckPath)] ??= {})[abs] =
            filled.dataToJson();
        slides.add(s.copyWith(customMarkdown: filled.toBlock()));
        changed = true;
      } catch (e) {
        logWarning('FileService._hydrateCharts: chart data unreadable', e);
        warnings.add(spec.source!);
        slides.add(s);
      }
    }
    return changed ? deck.copyWith(slides: slides) : deck;
  }

  /// Give every chart that still carries its data inline a data file of its
  /// own, so the markdown keeps a reference instead of the numbers.
  ///
  /// This is the conversion that makes the whole thing invisible: decks written
  /// before data files existed move over on their next save, without the user
  /// doing anything. It runs on **save** and never on open — opening must not
  /// rewrite a deck you only looked at, or merely reading a presentation would
  /// produce a diff.
  ///
  /// A `source`, once assigned, never changes again, even when the chart's
  /// title does. Renaming on every title edit would churn the file (and, in a
  /// repository, its history) for no gain.
  Future<Deck> _externalizeCharts(Deck deck, String dir) async {
    final taken = <String>{};
    final slides = <Slide>[];
    for (final s in deck.slides) {
      if (s.type != SlideType.chart) {
        slides.add(s);
        continue;
      }
      final spec = ChartSpec.parse(s.customMarkdown);
      // Nothing to move: an empty starter chart should not leave a file behind.
      if (!spec.hasInlineData) {
        slides.add(s);
        if (spec.source != null) taken.add(spec.source!);
        continue;
      }
      final existing = spec.source;
      // A duplicated chart slide carries its twin's source. Left alone, the two
      // would write over each other's numbers, so the second one forks off.
      if (existing != null && !taken.contains(existing)) {
        taken.add(existing);
        slides.add(s);
        continue;
      }
      final source = await _freeChartDataSource(spec.title, dir, taken);
      taken.add(source);
      slides.add(
        s.copyWith(customMarkdown: spec.copyWith(source: source).toBlock()),
      );
    }
    return deck.copyWith(slides: slides);
  }

  /// `data/<slug>.json` that no other chart in this deck claims and no file on
  /// disk occupies — so auto-conversion never lands on someone else's file.
  Future<String> _freeChartDataSource(
    String title,
    String dir,
    Set<String> taken,
  ) async {
    final base = title.trim().isEmpty ? 'grafiek' : _safeName(title);
    for (var i = 1; ; i++) {
      final name = i == 1 ? '$base.json' : '$base-$i.json';
      final source = '$chartDataDirName/$name';
      if (!taken.contains(source) &&
          !await File(p.join(dir, chartDataDirName, name)).exists()) {
        return source;
      }
    }
  }

  /// Remove data files this deck left behind — a chart slide that was deleted,
  /// or one that forked onto a new file.
  ///
  /// Deliberately narrow: only files this service itself read or wrote **for
  /// this deck** ([_chartDataAtOpen], onder de sleutel van dit deck) are
  /// eligible. An unrelated file someone dropped in `data/` is none of our
  /// business, and `.csv` files are never removed at all — those were supplied
  /// by the user, not generated here.
  ///
  /// De sleutel doet het echte werk: twee decks kunnen dezelfde map delen, dus
  /// "ligt in [dir]" zegt niets over van wie een bestand is. Zonder die scheiding
  /// wist het opslaan van het ene deck het databestand van het andere.
  Future<void> _pruneChartData(
    Deck deck,
    String dir, {
    required String deckPath,
  }) async {
    final baselines = _chartDataAtOpen[FileService._deckChartKey(deckPath)];
    if (baselines == null) return;
    final referenced = <String>{
      for (final s in deck.slides)
        if (s.type == SlideType.chart)
          if (ChartSpec.parse(s.customMarkdown).source case final src?)
            resolveProjectRelative(dir, src) ?? '',
    };
    final ours = baselines.keys
        .where(
          (abs) => p.isWithin(dir, abs) && abs.toLowerCase().endsWith('.json'),
        )
        .toList();
    for (final abs in ours) {
      if (referenced.contains(abs)) continue;
      try {
        final file = File(abs);
        if (await file.exists()) await file.delete();
      } catch (e) {
        logWarning('FileService._pruneChartData: stale data file kept', e);
      }
      baselines.remove(abs);
    }
  }

  /// Write each linked chart's data back to its file — the other half of
  /// [_hydrateCharts], and what makes a linked chart editable in the app.
  ///
  /// Only writes a file whose data the user actually changed. The baseline is
  /// what the file held when it was read ([_chartDataAtOpen]); if the spec still
  /// matches it, nobody touched the chart and the file is left completely
  /// alone. That is what keeps the spreadsheet workflow intact: edit the file
  /// while the deck is open, save the deck, and your edit is still there.
  ///
  /// Veranderden beide kanten, dan wint niemand: het bestand blijft zoals het
  /// buiten de app is geworden en de klacht komt terug als waarschuwing. De app
  /// eroverheen laten schrijven was een verloren update — het werk van degene
  /// die het bestand bijwerkte verdween dan zonder dat iemand het zag. Wat in de
  /// editor staat is niet weg; het staat alleen nog niet op schijf, en de
  /// gebruiker kan kiezen (elders opslaan, of het deck opnieuw openen).
  Future<List<String>> _writeChartData(
    Deck deck,
    String dir, {
    required String deckPath,
  }) async {
    final warnings = <String>[];
    final baselines = _chartDataAtOpen[FileService._deckChartKey(deckPath)] ??=
        {};
    for (final s in deck.slides) {
      if (s.type != SlideType.chart) continue;
      final spec = ChartSpec.parse(s.customMarkdown);
      final source = spec.source;
      if (source == null || !spec.hasInlineData) continue;
      final abs = resolveProjectRelative(dir, source);
      if (abs == null) {
        warnings.add(source); // buiten de projectmap; nooit schrijven
        continue;
      }
      final baseline = baselines[abs];
      final current = spec.dataToJson();
      if (baseline == current) continue; // ongewijzigd: bestand niet aanraken
      final file = File(abs);
      try {
        if (baseline != null && await file.exists()) {
          final onDisk = spec
              .withData(await file.readAsString(), path: abs)
              .dataToJson();
          if (onDisk != baseline) {
            // Ook extern gewijzigd: niet overschrijven. De baseline blijft
            // staan, zodat een volgende opslag dezelfde botsing weer ziet in
            // plaats van hem alsnog stil weg te drukken.
            warnings.add(source);
            continue;
          }
        }
        await file.parent.create(recursive: true);
        await writeStringAtomic(file, _chartDataFor(spec, path: abs));
        baselines[abs] = current;
      } catch (e) {
        logWarning('FileService._writeChartData: chart data not writable', e);
        warnings.add(source);
      }
    }
    return warnings;
  }

  /// The bytes for a data file: JSON for anything new, but a deck that already
  /// links a `.csv` keeps getting CSV. Silently rewriting someone's CSV as JSON
  /// would break whatever they point at it from a spreadsheet.
  String _chartDataFor(ChartSpec spec, {required String path}) =>
      path.toLowerCase().endsWith('.csv')
      ? chartDataAsCsv(spec)
      : spec.dataToJson();

  /// For packaging: add a chart's linked CSV under data/ and rewrite its source
  /// path; if the CSV is missing, fall back to keeping the data inline.
  Future<Slide> _packChartSlide(
    Slide s,
    String Function(String name, String content) addChartData,
  ) async {
    final spec = ChartSpec.parse(s.customMarkdown);
    final src = spec.source;
    // Data staat inline (nooit opgeslagen deck, of web): dan reist ze zo mee.
    if (src == null || !spec.hasInlineData) return s;
    final rel = addChartData(
      p.posix.basename(src),
      _chartDataFor(spec, path: src),
    );
    return s.copyWith(
      customMarkdown: spec.copyWith(source: rel).toBlock(forStorage: true),
    );
  }

  /// Copy any linked chart CSVs into [destDir]/data (used by Save As to a new
  /// location). A normal save is a no-op because source and dest coincide.
  Future<void> _copyChartData(Deck deck, String destDir) async {
    for (final s in deck.slides) {
      if (s.type != SlideType.chart) continue;
      final src = ChartSpec.parse(s.customMarkdown).source;
      if (src == null || p.isAbsolute(src) || deck.projectPath == null) {
        continue;
      }
      // Containment guard, matching _hydrateCharts: a chart source like
      // ../../../secret.csv must not be copied out of the project on Save As.
      final resolved = resolveProjectRelative(deck.projectPath, src);
      if (resolved == null) continue;
      final from = File(resolved);
      final toPath = p.join(destDir, src);
      if (from.path == toPath || !from.existsSync()) continue;
      final out = File(toPath);
      await out.parent.create(recursive: true);
      await writeBytesAtomic(out, await from.readAsBytes());
    }
  }
}

// ── De sidecar-poort ────────────────────────────────────────────────────────
//
// Buiten de klasse, en niet alleen om de klassenratchet: deze twee raken geen
// enkel veld van FileService. Ze gaan over één bestand op schijf, en dat is de
// hele reden dat ze los te lezen zijn.

/// De tekst van [sidecar], of null zodra hij groter is dan
/// [FileService.maxDeckSidecarBytes].
///
/// Dezelfde herkomst als een deck of grafiekdata: een sidecar komt uit een
/// pakket, een repo of iemands map, en werd hier onbegrensd ingelezen — met de
/// tweede kopie die `jsonDecode` er meteen bovenop legt. [laag] noemt de laag
/// in de logregel, want stil overslaan leest als "er stond niets in".
Future<String?> _readSidecarCapped(
  File sidecar,
  String laag, [
  List<String>? skipped,
]) async {
  final length = await sidecar.length();
  if (length > FileService.maxDeckSidecarBytes) {
    logWarning(
      'FileService: $laag sidecar of $length bytes exceeds the '
      '${FileService.maxDeckSidecarBytes ~/ (1024 * 1024)} MiB cap and was '
      'not read',
      sidecar.path,
    );
    // De gebruiker hoort dit ook te zien, niet alleen het logbestand: zijn
    // strepen zijn er niet, en zonder melding leest dat als "ik heb nooit
    // getekend" in plaats van "deze laag is overgeslagen" (#564).
    skipped?.add(laag);
    return null;
  }
  return sidecar.readAsString();
}

// ── De sidecars naast een `<naam>.md` ────────────────────────────────────────
//
// Vijf bestanden, één vorm: bepaal het pad, laat een sidecar van een nieuwere
// build met rust, en schrijf of verwijder. Dat stond vijf keer uitgeschreven —
// twintig regels boilerplate per sidecar, met de kans om er bij de zesde één
// stap van te vergeten. De stap die je niet mag vergeten is de middelste: half
// inlezen en terugschrijven wist wat deze build niet begreep.
//
// Top-level en niet in `FileService`: geen van deze functies raakt een veld van
// die klasse aan. Ze stonden daar alleen omdat ze bij het opslaan horen.

/// Schrijft de sidecar met achtervoegsel [extension] naast [mdPath], of
/// verwijdert hem wanneer [encode] niets oplevert — dan hoort er ook geen
/// bestand te liggen.
///
/// Draagt het bestand op schijf een hogere versie dan [supportedVersion], dan
/// gebeurt er niets: niet lezen én niet overschrijven (`sidecar_format.dart`).
Future<void> _writeSidecarNextTo(
  String mdPath,
  String extension,
  int supportedVersion,
  String label,
  String? Function() encode,
) async {
  final sidecar = File(p.setExtension(mdPath, extension));
  if (await _sidecarUntouchable(sidecar, supportedVersion, label)) return;
  final json = encode();
  if (json == null) {
    if (await sidecar.exists()) await sidecar.delete();
  } else {
    await writeStringAtomic(sidecar, json);
  }
}

/// Pad van de annotatie-sidecar naast een deck `<naam>.md`.
String _sidecarPath(String mdPath) => p.setExtension(mdPath, '.ink.json');

Future<void> _writeSidecar(Deck deck, String filePath) => _writeSidecarNextTo(
  filePath,
  '.ink.json',
  AnnotationCodec.version,
  'ink',
  () => AnnotationCodec.encode(deck.slides, deck.annotations),
);

/// Pad van de gebruikersnotities-sidecar.
String _userNotesSidecarPath(String mdPath) =>
    p.setExtension(mdPath, '.user-notes.json');

Future<void> _writeUserNotesSidecar(Deck deck, String filePath) =>
    _writeSidecarNextTo(
      filePath,
      '.user-notes.json',
      UserNotesCodec.version,
      'user-notes',
      () => UserNotesCodec.encode(deck.slides, deck.userNotes),
    );

/// Pad van de MIAUW-dispositie-sidecar.
String _miauwSidecarPath(String mdPath) =>
    p.setExtension(mdPath, '.miauw.json');

Future<void> _writeMiauwSidecar(Deck deck, String filePath) =>
    _writeSidecarNextTo(
      filePath,
      '.miauw.json',
      MiauwCodec.version,
      'MIAUW',
      () => MiauwCodec.encodeDisposition(deck.miauw),
    );

/// Pad van de sidecar met terzijdegelegde privacybevindingen (§6.7, #651).
String _dismissalsSidecarPath(String mdPath) =>
    p.setExtension(mdPath, '.dismissals.json');

Future<void> _writeDismissalsSidecar(Deck deck, String filePath) =>
    _writeSidecarNextTo(
      filePath,
      '.dismissals.json',
      DismissalCodec.version,
      'dismissals',
      () {
        final value = deck.dismissals;
        return value == null ? null : DismissalCodec.encode(value);
      },
    );

/// Pad van de zegel-sidecar.
String _sealSidecarPath(String mdPath) => p.setExtension(mdPath, '.seal.json');

Future<void> _writeSealSidecar(Deck deck, String filePath) =>
    _writeSidecarNextTo(
      filePath,
      '.seal.json',
      SealCodec.version,
      'seal',
      () => SealCodec.encode(SealRecord.of(deck)),
    );

/// Of de sidecar op [sidecar] bij het opslaan met rust gelaten moet worden,
/// inclusief het niet-verwijderen. [laag] noemt de laag in de logregel.
///
/// Twee aanleidingen, één uitkomst. Hij komt uit een nieuwere OciDeck dan deze
/// build ([supported]) — de leeskant laadt zo'n bestand al niet in (zie de
/// codecs). Of hij is te groot om te lezen. In beide gevallen draagt het deck
/// de inhoud niet in het geheugen, en dan wist de eerstvolgende opslag het
/// bestand: niets laden en toch overschrijven is erger dan half lezen.
Future<bool> _sidecarUntouchable(
  File sidecar,
  int supported,
  String laag,
) async {
  if (!await sidecar.exists()) return false;
  try {
    final raw = await _readSidecarCapped(sidecar, laag);
    // De cap-reden staat al in het log van _readSidecarCapped.
    if (raw == null) return true;
    if (!sidecarIsFromNewerBuild(raw, supported)) return false;
    logWarning(
      'FileService: $laag sidecar is from a newer OciDeck and was left '
      'untouched',
      sidecar.path,
    );
    return true;
  } catch (e) {
    // Onleesbaar is niet "van later": dat valt onder gewone corruptie.
    logWarning('FileService: sidecar version unreadable', e);
    return false;
  }
}
