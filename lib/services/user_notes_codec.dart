import 'dart:convert';

import '../models/slide.dart';
import '../utils/log.dart';
import '../utils/page_scoped_notes.dart';
import 'annotation_codec.dart';

/// Serializes per-slide user notes (recipient/course notes) into a sidecar
/// payload fully decoupled from Marp markdown and speaker notes.
///
/// Slide ids are regenerated every time a deck is parsed, so on disk we anchor
/// each note by its position plus a content fingerprint. On load we re-attach
/// notes to the matching slide (same fingerprint, preferring the same index),
/// and silently drop notes whose slide no longer exists.
///
/// Version 2 adds optional [page] (0-based) for rich-text slides split across
/// multiple presentation pages.
class UserNotesCodec {
  static const int version = 2;

  /// Encode the id-keyed [userNotes] for [slides] into a JSON string, or null
  /// when there is nothing to store.
  static String? encode(List<Slide> slides, Map<String, String> userNotes) {
    final entries = <Map<String, dynamic>>[];
    for (var i = 0; i < slides.length; i++) {
      final slideId = slides[i].id;
      for (final entry in userNotes.entries) {
        if (!userNoteKeyBelongsToSlide(entry.key, slideId)) continue;
        final text = entry.value.trim();
        if (text.isEmpty) continue;
        final page = pageIndexFromUserNoteKey(entry.key, slideId) ?? 0;
        entries.add({
          'index': i,
          'fp': AnnotationCodec.fingerprint(slides[i]),
          'text': text,
          if (page > 0) 'page': page,
        });
      }
    }
    if (entries.isEmpty) return null;
    return jsonEncode({'version': version, 'slides': entries});
  }

  /// Decode [json] against the freshly parsed [slides], returning a map keyed
  /// by the current slide ids (and slideId#pN when page-specific).
  static Map<String, String> decode(String json, List<Slide> slides) {
    final result = <String, String>{};
    try {
      final data = jsonDecode(json);
      final fileVersion =
          (data is Map ? data['version'] as num? : null)?.toInt() ?? 1;
      final raw = (data is Map ? data['slides'] : null) as List? ?? const [];
      // Op (dia, pagina), niet op dia alleen: een rijke-tekstdia die over
      // meerdere pagina's loopt levert meerdere notities met hetzelfde
      // `index`. Op dia alleen geclaimd stootte de tweede notitie af naar de
      // zoeklus, en die zette hem op een andere dia met dezelfde
      // vingerafdruk — of nergens.
      final used = <String>{};
      String claim(int slideIndex, int page) => '$slideIndex#$page';
      for (final e in raw) {
        final entry = Map<String, dynamic>.from(e as Map);
        final fp = entry['fp'] as String?;
        final index = (entry['index'] as num?)?.toInt() ?? -1;
        final text = (entry['text'] as String?)?.trim() ?? '';
        if (text.isEmpty) continue;
        final page = fileVersion >= 2
            ? ((entry['page'] as num?)?.toInt() ?? 0)
            : 0;

        int target = -1;
        if (index >= 0 &&
            index < slides.length &&
            !used.contains(claim(index, page)) &&
            AnnotationCodec.fingerprint(slides[index]) == fp) {
          target = index;
        } else {
          for (var i = 0; i < slides.length; i++) {
            if (!used.contains(claim(i, page)) &&
                AnnotationCodec.fingerprint(slides[i]) == fp) {
              target = i;
              break;
            }
          }
        }
        if (target < 0) continue;
        used.add(claim(target, page));
        final slideId = slides[target].id;
        final key = page > 0
            ? userNoteStorageKey(slideId, page, multiPage: true)
            : slideId;
        result[key] = text;
      }
    } catch (e, s) {
      logError('UserNotesCodec.decode: decode user-notes sidecar JSON', e, s);
      return {};
    }
    return result;
  }
}
