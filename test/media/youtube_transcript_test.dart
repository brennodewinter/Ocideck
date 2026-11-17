import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/models/markdown_document.dart';
import 'package:ocideck/services/media/youtube_reference.dart';
import 'package:ocideck/services/media/youtube_transcript.dart';
import 'package:ocideck/services/transcription/transcription_engine.dart';

void main() {
  final reference = YoutubeReference.parse(
    'https://youtu.be/M7lc1UVf-VE?list=discarded',
  )!;

  test(
    'cut ASR retains the source clock, metadata and canonical links on reopen',
    () {
      final markdown = youtubeTranscriptMarkdown(
        origin: YoutubeTranscriptOrigin(
          reference: reference,
          title: 'Fixture',
          start: const Duration(seconds: 60),
          end: const Duration(seconds: 80),
        ),
        segments: const [
          TranscriptSegment(
            text: 'Hello',
            start: Duration(seconds: 2),
            end: Duration(seconds: 5),
            speakerIds: ['cluster-a'],
            speakerUncertain: true,
          ),
        ],
        methodLabel: 'local ASR (test model)',
        processedAtLabel: '2026-11-17',
        audioOffset: const Duration(seconds: 60),
      );
      expect(
        markdown,
        contains('[0:01:02](https://www.youtube.com/watch?v=M7lc1UVf-VE&t=62)'),
      );
      expect(markdown, contains('"start_us":62000000'));
      expect(markdown, contains('"end_us":65000000'));
      expect(markdown, contains('cluster-a'));
      expect(markdown, isNot(contains('discarded')));
      final reopened = MarkdownDocument.parse(markdown);
      expect(reopened.source, markdown);
    },
  );

  test(
    'caption range preserves a complete overlapping cue with its real time',
    () {
      final markdown = youtubeTranscriptMarkdown(
        origin: YoutubeTranscriptOrigin(
          reference: reference,
          title: 'Fixture',
          start: const Duration(seconds: 10),
          end: const Duration(seconds: 20),
        ),
        segments: const [
          TranscriptSegment(
            text: 'Before',
            start: Duration(seconds: 1),
            end: Duration(seconds: 9),
          ),
          TranscriptSegment(
            text: 'Overlap',
            start: Duration(seconds: 9),
            end: Duration(seconds: 11),
          ),
          TranscriptSegment(
            text: 'After',
            start: Duration(seconds: 20),
            end: Duration(seconds: 21),
          ),
        ],
        methodLabel: 'manual captions (whole cues)',
        processedAtLabel: '2026-11-17',
      );
      expect(
        markdown,
        contains(
          '[0:00:09](https://www.youtube.com/watch?v=M7lc1UVf-VE&t=9) Overlap',
        ),
      );
      expect(markdown, isNot(contains('Before')));
      expect(markdown, isNot(contains('After')));
    },
  );

  test(
    'provider content cannot insert Markdown images, HTML or new directives',
    () {
      final markdown = youtubeTranscriptMarkdown(
        origin: YoutubeTranscriptOrigin(
          reference: reference,
          title: 'Title\n---\n<script>',
        ),
        segments: const [
          TranscriptSegment(
            text: '![remote](https://evil.test/x) <script>alert()</script>',
            start: Duration.zero,
          ),
        ],
        methodLabel: 'captions',
        processedAtLabel: '2026-11-17',
      );
      expect(markdown, isNot(contains('![remote]')));
      expect(markdown, isNot(contains('<script>')));
      expect(markdown.split('\n---\n'), hasLength(2));
    },
  );
}
