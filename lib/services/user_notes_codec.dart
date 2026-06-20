import 'dart:convert';

import '../models/slide.dart';
import '../utils/log.dart';
import 'annotation_codec.dart';

/// Serializes per-slide user notes (recipient/course notes) into a sidecar
/// payload fully decoupled from Marp markdown and speaker notes.
///
/// Slide ids are regenerated every time a deck is parsed, so on disk we anchor
/// each note by its position plus a content fingerprint. On load we re-attach
/// notes to the matching slide (same fingerprint, preferring the same index),
/// and silently drop notes whose slide no longer exists.
class UserNotesCodec {
  static const int version = 1;

  /// Encode the id-keyed [userNotes] for [slides] into a JSON string, or null
  /// when there is nothing to store.
  static String? encode(List<Slide> slides, Map<String, String> userNotes) {
    final entries = <Map<String, dynamic>>[];
    for (var i = 0; i < slides.length; i++) {
      final text = userNotes[slides[i].id]?.trim() ?? '';
      if (text.isEmpty) continue;
      entries.add({
        'index': i,
        'fp': AnnotationCodec.fingerprint(slides[i]),
        'text': text,
      });
    }
    if (entries.isEmpty) return null;
    return jsonEncode({'version': version, 'slides': entries});
  }

  /// Decode [json] against the freshly parsed [slides], returning a map keyed
  /// by the current slide ids.
  static Map<String, String> decode(String json, List<Slide> slides) {
    final result = <String, String>{};
    try {
      final data = jsonDecode(json);
      final raw = (data is Map ? data['slides'] : null) as List? ?? const [];
      final used = <int>{};
      for (final e in raw) {
        final entry = Map<String, dynamic>.from(e as Map);
        final fp = entry['fp'] as String?;
        final index = (entry['index'] as num?)?.toInt() ?? -1;
        final text = (entry['text'] as String?)?.trim() ?? '';
        if (text.isEmpty) continue;

        int target = -1;
        // Prefer the same index when its fingerprint still matches.
        if (index >= 0 &&
            index < slides.length &&
            !used.contains(index) &&
            AnnotationCodec.fingerprint(slides[index]) == fp) {
          target = index;
        } else {
          // Otherwise re-anchor to any unused slide with the same fingerprint.
          for (var i = 0; i < slides.length; i++) {
            if (!used.contains(i) &&
                AnnotationCodec.fingerprint(slides[i]) == fp) {
              target = i;
              break;
            }
          }
        }
        if (target < 0) continue; // slide gone/changed → drop this note
        used.add(target);
        result[slides[target].id] = text;
      }
    } catch (e, s) {
      logError('UserNotesCodec.decode: decode user-notes sidecar JSON', e, s);
      return {};
    }
    return result;
  }
}
