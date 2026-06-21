/// Helpers for notes tied to a rich-text page within a slide.
library;

import '../models/slide.dart';
import '../models/settings.dart';
import '../services/rich_text_layout.dart';

final _pageMarker = RegExp(r'^<!--\s*ocideck_page:(\d+)\s*-->$');

/// Storage key for [deck.userNotes]: [slideId] or [slideId]#p[pageIndex].
String userNoteStorageKey(
  String slideId,
  int pageIndex, {
  required bool multiPage,
}) {
  if (!multiPage) return slideId;
  return '$slideId#p$pageIndex';
}

int? pageIndexFromUserNoteKey(String key, String slideId) {
  final prefix = '$slideId#p';
  if (!key.startsWith(prefix)) return null;
  return int.tryParse(key.substring(prefix.length));
}

bool userNoteKeyBelongsToSlide(String key, String slideId) =>
    key == slideId || key.startsWith('$slideId#p');

/// True when [slide] has a rich-text note on any page (or legacy slide-wide).
bool slideHasUserNotes(Map<String, String> notes, String slideId) {
  for (final entry in notes.entries) {
    if (userNoteKeyBelongsToSlide(entry.key, slideId) &&
        entry.value.trim().isNotEmpty) {
      return true;
    }
  }
  return false;
}

String? userNoteForPage(
  Map<String, String> notes,
  String slideId,
  int pageIndex, {
  required bool multiPage,
}) {
  if (!multiPage) return notes[slideId]?.trim();
  final keyed = notes[userNoteStorageKey(slideId, pageIndex, multiPage: true)]
      ?.trim();
  if (keyed != null && keyed.isNotEmpty) return keyed;
  // Legacy slide-wide note applies to page 1 only.
  if (pageIndex == 0) return notes[slideId]?.trim();
  return null;
}

/// Rich-text page count for [slide] at reference layout (0 when not rich text).
int richTextPageCount(Slide slide, ThemeProfile profile) {
  if (!slideUsesRichText(slide)) return 0;
  return richTextPageCountForSlide(
    slide: slide,
    profile: profile,
    splitWithImage: slide.type == SlideType.bulletsImage,
  );
}

/// Parse speaker / user notes that may contain per-page sections.
Map<int, String> parsePageScopedNotes(String raw) {
  if (raw.trim().isEmpty) return {};

  final lines = raw.replaceAll('\r\n', '\n').split('\n');
  final result = <int, String>{};
  final buf = StringBuffer();
  var currentPage = 0;

  void flush() {
    final text = buf.toString().trim();
    buf.clear();
    if (text.isEmpty) return;
    result[currentPage] = result.containsKey(currentPage)
        ? '${result[currentPage]}\n\n$text'
        : text;
  }

  for (final line in lines) {
    final marker = _pageMarker.firstMatch(line.trim());
    if (marker != null) {
      flush();
      final oneBased = int.tryParse(marker.group(1)!) ?? 1;
      currentPage = (oneBased - 1).clamp(0, 999);
      continue;
    }
    if (buf.isNotEmpty) buf.writeln();
    buf.write(line);
  }
  flush();
  return result;
}

String encodePageScopedNotes(Map<int, String> byPage) {
  if (byPage.isEmpty) return '';
  final sorted = byPage.entries
      .where((e) => e.value.trim().isNotEmpty)
      .toList()
    ..sort((a, b) => a.key.compareTo(b.key));
  if (sorted.isEmpty) return '';
  if (sorted.length == 1 && sorted.first.key == 0) {
    return sorted.first.value.trim();
  }

  final buf = StringBuffer();
  for (final entry in sorted) {
    if (entry.key > 0 || sorted.length > 1) {
      buf.writeln('<!-- ocideck_page:${entry.key + 1} -->');
    }
    buf.writeln(entry.value.trim());
    buf.writeln();
  }
  return buf.toString().trim();
}

String speakerNoteForPage(String raw, int pageIndex, int pageCount) {
  if (pageCount <= 1) return raw.trim();
  final map = parsePageScopedNotes(raw);
  return map[pageIndex]?.trim() ?? '';
}

String updateSpeakerNoteForPage(
  String raw,
  int pageIndex,
  int pageCount,
  String text,
) {
  if (pageCount <= 1) return text.trim();
  final map = parsePageScopedNotes(raw);
  final trimmed = text.trim();
  if (trimmed.isEmpty) {
    map.remove(pageIndex);
  } else {
    map[pageIndex] = trimmed;
  }
  return encodePageScopedNotes(map);
}

bool speakerNotesSpanMultiplePages(String raw) {
  if (raw.trim().isEmpty) return false;
  return parsePageScopedNotes(raw).length > 1 ||
      _pageMarker.hasMatch(raw);
}
