import '../transcription/transcript_document.dart';
import '../transcription/transcription_engine.dart';
import '../transcription/transcription_errors.dart';
import 'youtube_reference.dart';

/// The chosen interval is explicit. Source offsets apply only to ASR of a
/// cut audio file; imported/provider captions already use the video clock.
class YoutubeTranscriptOrigin {
  const YoutubeTranscriptOrigin({
    required this.reference,
    required this.title,
    this.start = Duration.zero,
    this.end,
  });

  final YoutubeReference reference;
  final String title;
  final Duration start;
  final Duration? end;
}

String youtubeTranscriptMarkdown({
  required YoutubeTranscriptOrigin origin,
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
      sourceLabel: origin.reference.canonicalUrl.toString(),
      recordedAt: _literal(processedAtLabel),
      sourceKindLabel: 'YouTube · ${origin.reference.videoId}',
      durationLabel: interval,
      engineLabel: _literal(methodLabel),
      languageCode: language == null ? null : _literal(language),
    ),
    formatTranscriptBody(
      shifted,
      sourceLink: origin.reference.sourceLink,
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
