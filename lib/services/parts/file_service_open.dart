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

  /// Write the annotation sidecar next to [filePath], or remove it when empty.
  Future<void> _writeSidecar(Deck deck, String filePath) async {
    final sidecar = File(_sidecarPath(filePath));
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
    final json = UserNotesCodec.encode(deck.slides, deck.userNotes);
    if (json == null) {
      if (await sidecar.exists()) await sidecar.delete();
    } else {
      await writeStringAtomic(sidecar, json);
    }
  }

  /// Load the external CSV of any chart slide that links one, inlining the data
  /// into the in-memory spec so the renderer has it. The markdown on disk keeps
  /// only the `source` reference (data is stripped again on save).
  Future<Deck> _hydrateCharts(Deck deck, List<String> warnings) async {
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
        final filled = spec.withData(await file.readAsString(), path: abs!);
        // Remember what the file held, so the save path can tell "the user
        // edited this chart" apart from "nobody touched it" — see
        // [_writeChartData].
        _chartDataAtOpen[abs] = filled.dataToJson();
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
  Future<List<String>> _writeChartData(Deck deck, String dir) async {
    final warnings = <String>[];
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
      final baseline = _chartDataAtOpen[abs];
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
        _chartDataAtOpen[abs] = current;
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
      ? _chartDataAsCsv(spec)
      : spec.dataToJson();

  /// [parseCsv] in reverse: a header row of series names, then one row per
  /// label.
  ///
  /// Quotes any value that would otherwise change meaning on the way back —
  /// this is one half of a round trip we own (written on save, read on open),
  /// so writing something [parseCsv] cannot read back would corrupt a deck by
  /// saving it.
  String _chartDataAsCsv(ChartSpec spec) {
    final buf = StringBuffer()
      ..writeln(',${spec.series.map((s) => _csvValue(s.name)).join(',')}');
    for (var r = 0; r < spec.x.length; r++) {
      buf.writeln(
        [
          _csvValue(spec.x[r]),
          for (final s in spec.series) r < s.data.length ? s.data[r] : 0,
        ].join(','),
      );
    }
    return buf.toString();
  }

  /// A cell as CSV: quoted when it contains a comma, a quote or edge
  /// whitespace, with `"` doubled — the form [parseCsv] reads back verbatim.
  String _csvValue(String raw) =>
      raw.contains(',') || raw.contains('"') || raw.trim() != raw
      ? '"${raw.replaceAll('"', '""')}"'
      : raw;

  /// For packaging: add a chart's linked CSV under data/ and rewrite its source
  /// path; if the CSV is missing, fall back to keeping the data inline.
  Future<Slide> _packChartSlide(
    Slide s,
    Future<String?> Function(String, String) addAsset,
  ) async {
    final spec = ChartSpec.parse(s.customMarkdown);
    final src = spec.source;
    if (src == null) return s;
    final rel = await addAsset(src, chartDataDirName);
    if (rel == null) {
      return s.copyWith(
        customMarkdown: spec.copyWith(clearSource: true).toBlock(),
      );
    }
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
