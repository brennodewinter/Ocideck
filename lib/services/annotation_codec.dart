import 'dart:convert';

import '../models/annotation.dart';
import '../models/slide.dart';

/// Serializes the annotation layer into a sidecar payload that is fully
/// decoupled from the Marp markdown.
///
/// Slide ids are regenerated every time a deck is parsed, so on disk we anchor
/// each slide's strokes by its position plus a content fingerprint. On load we
/// re-attach strokes to the matching slide (same fingerprint, preferring the
/// same index), and silently drop strokes whose slide no longer exists.
class AnnotationCodec {
  static const int version = 1;

  /// A stable hash of a slide's visual content (ignores notes/timing/tlp).
  static String fingerprint(Slide s) {
    final buf = StringBuffer()
      ..write(s.type.index)
      ..write('${s.title}')
      ..write('${s.subtitle}')
      ..write('${s.bullets.join('')}')
      ..write('${s.bullets2.join('')}')
      ..write('${s.imagePath}')
      ..write('${s.imagePath2}')
      ..write('${s.quote}')
      ..write('${s.quoteAuthor}')
      ..write('${s.customMarkdown}')
      ..write('${s.codeLanguage}')
      ..write('${s.videoPath}')
      ..write('${s.tableRows.map((r) => r.join('')).join('')}');
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
  static String? encode(List<Slide> slides, Map<String, List<InkStroke>> annotations) {
    final entries = <Map<String, dynamic>>[];
    for (var i = 0; i < slides.length; i++) {
      final strokes = annotations[slides[i].id];
      if (strokes == null || strokes.isEmpty) continue;
      entries.add({
        'index': i,
        'fp': fingerprint(slides[i]),
        'strokes': encodeStrokes(strokes),
      });
    }
    if (entries.isEmpty) return null;
    return jsonEncode({'version': version, 'slides': entries});
  }

  /// Decode [json] against the freshly parsed [slides], returning a map keyed by
  /// the current slide ids.
  static Map<String, List<InkStroke>> decode(String json, List<Slide> slides) {
    final result = <String, List<InkStroke>>{};
    try {
      final data = jsonDecode(json);
      final raw = (data is Map ? data['slides'] : null) as List? ?? const [];
      final used = <int>{};
      for (final e in raw) {
        final entry = Map<String, dynamic>.from(e as Map);
        final fp = entry['fp'] as String?;
        final index = (entry['index'] as num?)?.toInt() ?? -1;
        final strokes = decodeStrokes(
          (entry['strokes'] as List?) ?? const [],
        );
        if (strokes.isEmpty) continue;

        int target = -1;
        // Prefer the same index when its fingerprint still matches.
        if (index >= 0 &&
            index < slides.length &&
            !used.contains(index) &&
            fingerprint(slides[index]) == fp) {
          target = index;
        } else {
          // Otherwise re-anchor to any unused slide with the same fingerprint.
          for (var i = 0; i < slides.length; i++) {
            if (!used.contains(i) && fingerprint(slides[i]) == fp) {
              target = i;
              break;
            }
          }
        }
        if (target < 0) continue; // slide gone/changed → drop these strokes
        used.add(target);
        result[slides[target].id] = strokes;
      }
    } catch (_) {
      return {};
    }
    return result;
  }
}
