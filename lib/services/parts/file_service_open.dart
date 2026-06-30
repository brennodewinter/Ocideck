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
  Future<Deck> _hydrateCharts(Deck deck) async {
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
      // A chart's CSV link must stay inside the project (no absolute paths or
      // `../` escapes) — otherwise an untrusted deck could read arbitrary files.
      final abs = resolveProjectRelative(deck.projectPath, spec.source!);
      final file = abs == null ? null : File(abs);
      if (file == null || !await file.exists()) {
        slides.add(s);
        continue;
      }
      try {
        final csv = await file.readAsString();
        slides.add(s.copyWith(customMarkdown: spec.withCsv(csv).toBlock()));
        changed = true;
      } catch (e) {
        logWarning('FileService._hydrateCharts: chart CSV unreadable', e);
        slides.add(s);
      }
    }
    return changed ? deck.copyWith(slides: slides) : deck;
  }

  /// For packaging: add a chart's linked CSV under data/ and rewrite its source
  /// path; if the CSV is missing, fall back to keeping the data inline.
  Slide _packChartSlide(Slide s, String? Function(String, String) addAsset) {
    final spec = ChartSpec.parse(s.customMarkdown);
    final src = spec.source;
    if (src == null) return s;
    final rel = addAsset(src, chartDataDirName);
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
