import '../../models/slide.dart';
import '../../models/video_source.dart';

/// A locally recognised video, before any metadata request or extraction.
/// URL time parameters are a proposal; callers explicitly choose the range.
class YoutubeReference {
  const YoutubeReference({
    required this.videoId,
    this.proposedStartMs = 0,
    this.proposedEndMs = 0,
  });

  final String videoId;
  final int proposedStartMs;
  final int proposedEndMs;

  Uri get canonicalUrl =>
      Uri.https('www.youtube.com', '/watch', {'v': videoId});

  String get selectionKey => '$videoId:$proposedStartMs:$proposedEndMs';

  Uri sourceLink(Duration time) => canonicalUrl.replace(
    queryParameters: {'v': videoId, 't': '${time.inSeconds}'},
  );

  static YoutubeReference? parse(String value, {int? startMs, int? endMs}) {
    final source = VideoSource.parse(value);
    if (source.kind != VideoSourceKind.youtube) return null;
    final uri = Uri.tryParse(value.trim());
    if (uri == null || uri.userInfo.isNotEmpty) return null;
    final Map<String, String> fragment;
    try {
      fragment = Uri.splitQueryString(uri.fragment);
    } on FormatException {
      return null;
    }
    final start =
        startMs ??
        _timeMs(
          uri.queryParameters['start'] ??
              uri.queryParameters['t'] ??
              fragment['t'],
        );
    final end = endMs ?? _timeMs(uri.queryParameters['end']);
    if (start < 0 || end < 0 || (end != 0 && end <= start)) return null;
    return YoutubeReference(
      videoId: source.embedId!,
      proposedStartMs: start,
      proposedEndMs: end,
    );
  }
}

int _timeMs(String? value) {
  if (value == null || value.isEmpty) return 0;
  final seconds = double.tryParse(value);
  if (seconds != null) {
    return seconds.isFinite && seconds >= 0 && seconds <= 86400
        ? (seconds * 1000).round()
        : 0;
  }
  final match = RegExp(
    r'^(?:(\d+)h)?(?:(\d+)m)?(?:(\d+)s)?$',
  ).firstMatch(value);
  if (match == null) return 0;
  final total =
      (int.tryParse(match[1] ?? '') ?? 0) * 3600 +
      (int.tryParse(match[2] ?? '') ?? 0) * 60 +
      (int.tryParse(match[3] ?? '') ?? 0);
  return total <= 86400 ? total * 1000 : 0;
}

/// Distinct video/range choices retain every referring slide (one-based).
class DeckYoutubeReference {
  DeckYoutubeReference(this.reference, this.slideNumbers);

  final YoutubeReference reference;
  final List<int> slideNumbers;
}

/// Recognition has no network side effects, including when a deck opens.
List<DeckYoutubeReference> findDeckYoutubeReferences(List<Slide> slides) {
  final found = <String, DeckYoutubeReference>{};
  for (var index = 0; index < slides.length; index++) {
    final slide = slides[index];
    final video = YoutubeReference.parse(
      slide.videoPath,
      startMs: slide.videoStartMs,
      endMs: slide.videoEndMs,
    );
    if (video != null) _addReference(found, video, index + 1);
    final text = [
      slide.title,
      slide.subtitle,
      slide.customMarkdown,
      slide.quote,
      slide.notes,
      ...slide.bullets,
      ...slide.bullets2,
      ...slide.tableRows.expand((row) => row),
      ...slide.preservedMarpLines,
    ].join('\n');
    for (final match in RegExp(
      r'''https?://[^\s<>\]\)"']+''',
    ).allMatches(text)) {
      final reference = YoutubeReference.parse(match[0]!);
      if (reference != null) _addReference(found, reference, index + 1);
    }
  }
  return found.values.toList(growable: false);
}

void _addReference(
  Map<String, DeckYoutubeReference> found,
  YoutubeReference reference,
  int slideNumber,
) {
  final entry = found.putIfAbsent(
    reference.selectionKey,
    () => DeckYoutubeReference(reference, []),
  );
  if (!entry.slideNumbers.contains(slideNumber)) {
    entry.slideNumbers.add(slideNumber);
  }
}
