import 'dart:convert';

import 'package:html/parser.dart' as html;

import '../transcription/transcription_engine.dart';

enum CaptionParseFailure { tooLarge, malformed, empty, tooManyCues }

class CaptionParseException implements Exception {
  const CaptionParseException(this.failure);
  final CaptionParseFailure failure;
}

/// Parse bounded VTT/SRT, preserving real cue times rather than inventing
/// word times. Rolling deduplication is explicit, for automatic captions.
List<TranscriptSegment> parseTimedCaptions(
  String text, {
  bool rolling = false,
}) {
  if (utf8.encode(text).length > 2 * 1024 * 1024) {
    throw const CaptionParseException(CaptionParseFailure.tooLarge);
  }
  final result = <TranscriptSegment>[];
  var previousWords = <String>[];
  var previousEnd = Duration.zero;
  for (final block in text.replaceAll('\r\n', '\n').split(RegExp(r'\n\s*\n'))) {
    final cue = _parseCue(block);
    if (cue == null) continue;
    var words = cue.text.split(RegExp(r'\s+'));
    final fullWords = words;
    // YouTube rolling VTT also emits contiguous display cues, including a
    // short repeat between two growing lines. A gap always resets the chain.
    if (rolling && cue.start! <= previousEnd) {
      words = words.sublist(_repeatedPrefix(previousWords, words));
    }
    previousWords = fullWords;
    previousEnd = cue.end!;
    if (words.isEmpty) continue;
    result.add(
      TranscriptSegment(text: words.join(' '), start: cue.start, end: cue.end),
    );
    if (result.length > 20000) {
      throw const CaptionParseException(CaptionParseFailure.tooManyCues);
    }
  }
  if (result.isEmpty) {
    throw const CaptionParseException(CaptionParseFailure.empty);
  }
  return result;
}

TranscriptSegment? _parseCue(String block) {
  final lines = const LineSplitter().convert(block.trim());
  if (lines.isEmpty ||
      RegExp(r'^(WEBVTT|NOTE|STYLE|REGION)(\s|$)').hasMatch(lines.first)) {
    return null;
  }
  final index = lines.indexWhere((line) => line.contains('-->'));
  if (index < 0) return null;
  final times = lines[index].split('-->');
  if (times.length != 2) {
    throw const CaptionParseException(CaptionParseFailure.malformed);
  }
  final start = _captionTime(times[0].trim());
  final end = _captionTime(times[1].trim().split(RegExp(r'\s+')).first);
  if (start == null || end == null || end <= start) {
    throw const CaptionParseException(CaptionParseFailure.malformed);
  }
  final raw = lines
      .skip(index + 1)
      .join(' ')
      .replaceAll(RegExp(r'<\d{2}:\d{2}(?::\d{2})?[.,]\d{1,3}>'), '');
  final text = html.parseFragment(raw).text?.trim() ?? '';
  return text.isEmpty
      ? null
      : TranscriptSegment(text: text, start: start, end: end);
}

Duration? _captionTime(String value) {
  final match = RegExp(
    r'^(?:(\d{1,4}):)?(\d{2}):(\d{2})[.,](\d{1,3})$',
  ).firstMatch(value);
  if (match == null) return null;
  final hours = int.parse(match[1] ?? '0');
  final minutes = int.parse(match[2]!);
  final seconds = int.parse(match[3]!);
  if (hours > 48 || minutes > 59 || seconds > 59) return null;
  return Duration(
    hours: hours,
    minutes: minutes,
    seconds: seconds,
    milliseconds: int.parse(match[4]!.padRight(3, '0')),
  );
}

int _repeatedPrefix(List<String> previous, List<String> current) {
  // Bounded comparison even when an untrusted cue contains thousands of words.
  var count = previous.length < current.length
      ? previous.length
      : current.length;
  if (count > 200) count = 200;
  for (; count > 0; count--) {
    var same = true;
    for (var i = 0; i < count; i++) {
      if (previous[previous.length - count + i] != current[i]) {
        same = false;
        break;
      }
    }
    if (same) return count;
  }
  return 0;
}
