import '../transcription/transcript_document.dart';
import '../transcription/transcription_engine.dart';
import '../transcription/transcription_errors.dart';
import 'youtube_reference.dart';

/// The chosen interval is explicit. Source offsets apply only to ASR of a
/// cut audio file; imported/provider captions already use the video clock.
abstract interface class MediaTranscriptOrigin {
  String get title;
  Duration get start;
  Duration? get end;
  Uri get sourceUrl;
  String get sourceKind;
  Uri sourceLink(Duration time);
}

class UrlTranscriptOrigin implements MediaTranscriptOrigin {
  const UrlTranscriptOrigin(this._sourceUrl, {required this.title});
  final Uri _sourceUrl;
  @override
  Uri get sourceUrl =>
      _sourceUrl.replace(userInfo: '', query: '', fragment: '');
  @override
  final String title;
  @override
  Duration get start => Duration.zero;
  @override
  Duration? get end => null;
  @override
  String get sourceKind => 'URL · ${sourceUrl.host}';
  @override
  Uri sourceLink(Duration time) =>
      sourceUrl.replace(fragment: 't=${time.inSeconds}');
}

class YoutubeTranscriptOrigin implements MediaTranscriptOrigin {
  const YoutubeTranscriptOrigin({
    required this.reference,
    required this.title,
    this.start = Duration.zero,
    this.end,
  });

  final YoutubeReference reference;
  @override
  final String title;
  @override
  final Duration start;
  @override
  final Duration? end;
  @override
  Uri get sourceUrl => reference.canonicalUrl;
  @override
  String get sourceKind => 'YouTube · ${reference.videoId}';
  @override
  Uri sourceLink(Duration time) => reference.sourceLink(time);
}

String mediaTranscriptMarkdown({
  required MediaTranscriptOrigin origin,
  required List<TranscriptSegment> segments,
  required String methodLabel,
  required String processedAtLabel,
  Duration audioOffset = Duration.zero,
  String? language,
  String speakerLabel = 'Spreker',
  String unknownLabel = 'Onbekend',
}) {
  final shifted = <TranscriptSegment>[];
  for (final segment in segments) {
    final start = segment.start == null ? null : segment.start! + audioOffset;
    final end = segment.end == null ? null : segment.end! + audioOffset;
    // Keep complete overlapping caption cues: there are no word boundaries
    // from which to invent an exact text cut at the requested interval edge.
    if ((end != null && end <= origin.start) ||
        (origin.end != null && start != null && start >= origin.end!)) {
      continue;
    }
    shifted.add(
      TranscriptSegment(
        text: _literal(segment.text),
        start: start,
        end: end,
        speaker: segment.speaker == null ? null : _literal(segment.speaker!),
        speakerIds: segment.speakerIds,
        speakerUncertain: segment.speakerUncertain,
        language: segment.language,
        languageUncertain: segment.languageUncertain,
      ),
    );
  }
  if (shifted.isEmpty) {
    throw const SourceUnavailable('geen tekst binnen het gekozen fragment');
  }
  final interval =
      '${sourceTimeLabel(origin.start)} – '
      '${origin.end == null ? '∞' : sourceTimeLabel(origin.end!)}';
  return buildTranscriptMarkdown(
    TranscriptProvenance(
      title: _literal(origin.title),
      sourceLabel: origin.sourceUrl.toString(),
      recordedAt: _literal(processedAtLabel),
      sourceKindLabel: origin.sourceKind,
      durationLabel: interval,
      engineLabel: _literal(methodLabel),
      languageCode: language == null ? null : _literal(language),
    ),
    formatTranscriptBody(
      shifted,
      sourceLink: origin.sourceLink,
      speakerLabel: speakerLabel,
      unknownLabel: unknownLabel,
    ),
  );
}

String sourceTimeLabel(Duration time) =>
    '${time.inHours}:'
    '${time.inMinutes.remainder(60).toString().padLeft(2, '0')}:'
    '${time.inSeconds.remainder(60).toString().padLeft(2, '0')}';

String _literal(String text) => text
    .replaceAll(RegExp(r'[\x00-\x1f\x7f]'), ' ')
    .replaceAllMapped(
      RegExp(r'[\\`*_{}\[\]()#+\-.!|<>~]'),
      (match) => '\\${match[0]}',
    );
