// Part of the file_service library — see ../file_service.dart.
// Split out for navigability (open: truncation check, sidecars & chart hydration); all imports live in the main library
// file. These are private FileService helpers — they relocate verbatim
// into an extension on FileService, same library, no behaviour change.
part of '../file_service.dart';

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

  /// Path of the annotation sidecar next to a deck `<name>.md` → `<name>.ink.json`.
  String _sidecarPath(String mdPath) => p.setExtension(mdPath, '.ink.json');

  /// Of [sidecar] uit een nieuwere OciDeck komt dan deze build ([supported]) —
  /// dan blijft hij onaangeroerd, inclusief het niet-verwijderen.
  ///
  /// De leeskant laadt zo'n bestand al niet in (zie de codecs). Zonder deze
  /// tweede helft was dat juist gevaarlijk: het deck heeft dan geen strepen of
  /// notities in het geheugen, en de eerstvolgende opslag zou het bestand
  /// daarom wíssen. Niets laden en toch overschrijven is erger dan half lezen.
  Future<bool> _sidecarFromNewerBuild(File sidecar, int supported) async {
    if (!await sidecar.exists()) return false;
    try {
      return sidecarIsFromNewerBuild(await sidecar.readAsString(), supported);
    } catch (e) {
      // Onleesbaar is niet "van later": dat valt onder gewone corruptie.
      logWarning('FileService: sidecar version unreadable', e);
      return false;
    }
  }

  /// Write the annotation sidecar next to [filePath], or remove it when empty.
  Future<void> _writeSidecar(Deck deck, String filePath) async {
    final sidecar = File(_sidecarPath(filePath));
    if (await _sidecarFromNewerBuild(sidecar, AnnotationCodec.version)) {
      logWarning(
        'FileService._writeSidecar: annotation sidecar is from a newer '
        'OciDeck and was left untouched',
        sidecar.path,
      );
      return;
    }
    final json = AnnotationCodec.encode(deck.slides, deck.annotations);
    if (json == null) {
      if (await sidecar.exists()) await sidecar.delete();
    } else {
      await writeStringAtomic(sidecar, json);
    }
  }

  /// Path of the user-notes sidecar next to a deck `<name>.md`.
  String _userNotesSidecarPath(String mdPath) =>
      p.setExtension(mdPath, '.user-notes.json');

  /// Write the user-notes sidecar next to [filePath], or remove it when empty.
  Future<void> _writeUserNotesSidecar(Deck deck, String filePath) async {
    final sidecar = File(_userNotesSidecarPath(filePath));
    if (await _sidecarFromNewerBuild(sidecar, UserNotesCodec.version)) {
      logWarning(
        'FileService._writeUserNotesSidecar: user-notes sidecar is from a '
        'newer OciDeck and was left untouched',
        sidecar.path,
      );
      return;
    }
    final json = UserNotesCodec.encode(deck.slides, deck.userNotes);
    if (json == null) {
      if (await sidecar.exists()) await sidecar.delete();
    } else {
      await writeStringAtomic(sidecar, json);
    }
  }

  /// Path of the MIAUW-disposition sidecar next to a deck `<name>.md`.
  String _miauwSidecarPath(String mdPath) =>
      p.setExtension(mdPath, '.miauw.json');

  /// Write the MIAUW sidecar next to [filePath], or remove it when empty.
  Future<void> _writeMiauwSidecar(Deck deck, String filePath) async {
    final sidecar = File(_miauwSidecarPath(filePath));
    if (await _sidecarFromNewerBuild(sidecar, MiauwCodec.version)) {
      logWarning(
        'FileService._writeMiauwSidecar: MIAUW sidecar is from a newer '
        'OciDeck and was left untouched',
        sidecar.path,
      );
      return;
    }
    final json = MiauwCodec.encode(deck.miauwWaivers, deck.miauwConfirmations);
    if (json == null) {
      if (await sidecar.exists()) await sidecar.delete();
    } else {
      await writeStringAtomic(sidecar, json);
    }
  }

  /// Legt de lagen die naast de markdown wonen terug op [deck]: de
  /// inkt-annotaties, de gebruikersnotities en de MIAUW-dispositie.
  ///
  /// Elke laag apart afgeschermd: een kapotte sidecar mag het openen van het
  /// deck nooit blokkeren — dat zou een tekening van vorige week een hele
  /// presentatie kosten.
  Future<Deck> _attachSidecars(Deck deck, String filePath) async {
    var hydrated = deck;
    final sidecar = File(_sidecarPath(filePath));
    if (await sidecar.exists()) {
      try {
        final map = AnnotationCodec.decode(
          await sidecar.readAsString(),
          hydrated.slides,
        );
        if (map.isNotEmpty) hydrated = hydrated.copyWith(annotations: map);
      } catch (e) {
        // A broken sidecar must never block opening the deck.
        logWarning('FileService.openDeck: annotation sidecar unreadable', e);
      }
    }
    final userNotesSidecar = File(_userNotesSidecarPath(filePath));
    if (await userNotesSidecar.exists()) {
      try {
        final map = UserNotesCodec.decode(
          await userNotesSidecar.readAsString(),
          hydrated.slides,
        );
        if (map.isNotEmpty) hydrated = hydrated.copyWith(userNotes: map);
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
        final d = MiauwCodec.decode(await miauwSidecar.readAsString());
        if (!d.isEmpty) {
          hydrated = hydrated.copyWith(
            miauwWaivers: d.waivers,
            miauwConfirmations: d.confirmations,
          );
        }
      } catch (e) {
        logWarning('FileService.openDeck: MIAUW sidecar unreadable', e);
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
  /// When both sides changed, the app wins — it holds what the user last saw
  /// and edited — but the clash is reported rather than swallowed.
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
          if (onDisk != baseline) warnings.add(source); // ook extern gewijzigd
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
