import 'dart:convert';

import '../models/annotation.dart';
import '../models/slide.dart';
import '../utils/log.dart';
import 'sidecar_format.dart';

/// Serializes the annotation layer into a sidecar payload that is fully
/// decoupled from the Marp markdown.
///
/// Slide ids are regenerated every time a deck is parsed, so on disk we anchor
/// each slide's strokes by its position plus a content fingerprint. On load we
/// re-attach strokes to the matching slide (same fingerprint, preferring the
/// same index), and silently drop strokes whose slide no longer exists.
class AnnotationCodec {
  /// Versie 2 sinds #541: elke streek draagt een `id` en mag een `erased`-vlag
  /// hebben (GIT_STORAGE D7). Een bestand van versie 1 leest gewoon door —
  /// `InkStroke.fromJson` deelt een verse id uit en leest geen vlag — maar
  /// andersom niet: een oudere build zou de grafstenen niet begrijpen en
  /// gewiste streken weer tekenen. Vandaar de verhoging.
  static const int version = 2;

  /// A stable hash of a slide's visual content (ignores notes/timing/tlp).
  static String fingerprint(Slide s) {
    final buf = StringBuffer()
      ..write(s.type.index)
      ..write('\u0001${s.title}')
      ..write('\u0001${s.subtitle}')
      ..write('\u0001${s.bullets.join('\u0002')}')
      ..write('\u0001${s.bullets2.join('\u0002')}')
      ..write('\u0001${s.imagePath}')
      ..write('\u0001${s.imagePath2}')
      ..write('\u0001${s.quote}')
      ..write('\u0001${s.quoteAuthor}')
      ..write('\u0001${s.customMarkdown}')
      ..write('\u0001${s.codeLanguage}')
      ..write('\u0001${s.videoPath}')
      ..write(
        '\u0001${s.tableRows.map((r) => r.join('\u0002')).join('\u0003')}',
      );
    return _fnv1a(buf.toString());
  }

  static String _fnv1a(String input) {
    var hash = 0x811c9dc5;
    for (final unit in input.codeUnits) {
      hash ^= unit;
      hash = (hash * 0x01000193) & 0xFFFFFFFF;
    }
    return hash.toRadixString(16).padLeft(8, '0');
  }

  /// Encode the id-keyed [annotations] for [slides] into a JSON string, or null
  /// when there is nothing to store.
  ///
  /// With [forTextMerge] the JSON is written indented — the same trade as
  /// `UserNotesCodec.encode`: only the copy that goes into a repository pays
  /// for it, and there it earns its keep. Ink is *not* merged by git's text
  /// merge (the union with tombstones lives in `mergeDeckVersions`, D7), but a
  /// clone made by another tool has no driver, and git then falls back to the
  /// text merge — measured, not assumed: an undefined `merge=` attribute
  /// text-merges like any other file. Indented, two sides that drew on
  /// different slides still merge cleanly there; on one line every stroke is
  /// the same line and nothing ever does.
  static String? encode(
    List<Slide> slides,
    Map<String, List<InkStroke>> annotations, {
    bool forTextMerge = false,
  }) {
    final entries = <Map<String, dynamic>>[];
    for (var i = 0; i < slides.length; i++) {
      final id = slides[i].id;
      // A rich-text slide keys its strokes per page (id, id#p1, id#p2, …), so
      // gather every page that belongs to this slide, not just the bare id.
      final byPage = <int, List<InkStroke>>{};
      for (final e in annotations.entries) {
        final page = annotationPageForKey(e.key, id);
        if (page != null && e.value.isNotEmpty) byPage[page] = e.value;
      }
      if (byPage.isEmpty) continue;
      final fp = fingerprint(slides[i]);
      final pages = byPage.keys.toList()..sort();
      for (final page in pages) {
        entries.add({
          'index': i,
          'fp': fp,
          // Omit page 0 so a single-page deck round-trips byte-identically.
          if (page > 0) 'page': page,
          'strokes': encodeStrokes(byPage[page]!),
        });
      }
    }
    if (entries.isEmpty) return null;
    final payload = {'version': version, 'slides': entries};
    return forTextMerge
        ? '${const JsonEncoder.withIndent('  ').convert(payload)}\n'
        : jsonEncode(payload);
  }

  /// Decode [json] against the freshly parsed [slides], returning a map keyed by
  /// the current slide ids.
  static Map<String, List<InkStroke>> decode(String json, List<Slide> slides) {
    final result = <String, List<InkStroke>>{};
    try {
      final data = jsonDecode(json);
      // Een sidecar van later kent velden die deze build niet snapt; er iets
      // uit oppikken en dan opslaan wist de rest. Zie [sidecarIsFromNewerBuild];
      // de schrijfkant weigert hetzelfde bestand te overschrijven.
      if (declaredSidecarVersion(data) > version) {
        logWarning(
          'AnnotationCodec.decode: annotation sidecar is version '
          '${declaredSidecarVersion(data)}, this build reads $version — '
          'not loading it',
        );
        return {};
      }
      final raw = (data is Map ? data['slides'] : null) as List? ?? const [];
      // Track claimed (slide, page) keys — one slide legitimately carries
      // several entries (one per rich-text page), so we disambiguate on the
      // composite key rather than the slide index.
      final used = <String>{};
      for (final e in raw) {
        final entry = Map<String, dynamic>.from(e as Map);
        final fp = entry['fp'] as String?;
        final index = (entry['index'] as num?)?.toInt() ?? -1;
        final page = (entry['page'] as num?)?.toInt() ?? 0;
        final strokes = decodeStrokes((entry['strokes'] as List?) ?? const []);
        if (strokes.isEmpty) continue;

        // The free key for slide [i] at this entry's page, or null if taken.
        String? keyFor(int i) {
          final key = annotationKey(slides[i].id, page);
          return used.contains(key) ? null : key;
        }

        String? target;
        // Prefer the same index when its fingerprint still matches.
        if (index >= 0 &&
            index < slides.length &&
            fingerprint(slides[index]) == fp) {
          target = keyFor(index);
        }
        if (target == null) {
          // Otherwise re-anchor to any slide with the same fingerprint whose
          // slot for this page is still free.
          for (var i = 0; i < slides.length; i++) {
            if (fingerprint(slides[i]) == fp) {
              final key = keyFor(i);
              if (key != null) {
                target = key;
                break;
              }
            }
          }
        }
        if (target == null) continue; // slide gone/changed → drop these strokes
        used.add(target);
        result[target] = strokes;
      }
    } catch (e, s) {
      logError('AnnotationCodec.decode: decode annotation sidecar JSON', e, s);
      return {};
    }
    return result;
  }
}
