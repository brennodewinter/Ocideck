import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/services/transcription/speaker_corrections.dart';
import 'package:ocideck/services/transcription/transcript_document.dart';
import 'package:ocideck/services/transcription/transcription_engine.dart';
import 'package:ocideck/models/markdown_document.dart';
import 'package:ocideck/state/document_provider.dart';

void main() {
  final body = formatTranscriptBody(const [
    TranscriptSegment(
      text: 'Eerste zin. Andere stem.',
      start: Duration(seconds: 1),
      end: Duration(seconds: 4),
      speakerIds: ['a'],
    ),
    TranscriptSegment(
      text: 'Antwoord.',
      start: Duration(seconds: 5),
      speakerIds: ['b'],
    ),
    TranscriptSegment(text: 'Nog een antwoord.', speakerIds: ['c']),
    TranscriptSegment(text: 'Door elkaar.', speakerIds: ['a', 'b']),
  ]);
  final source = buildTranscriptMarkdown(
    const TranscriptProvenance(
      title: 'Test',
      sourceLabel: 'test.wav',
      recordedAt: 'vandaag',
      sourceKindLabel: 'bestand',
    ),
    body,
  );

  void roundtrip(String edited) {
    final dir = Directory.systemTemp.createTempSync('speaker-corrections-');
    try {
      final file = File('${dir.path}/transcript.md')..writeAsStringSync(edited);
      final reopened = MarkdownDocument.parse(file.readAsStringSync());
      expect(reopened.source, edited);
      expect(SpeakerCorrections.read(reopened.source), isNotNull);
      final notifier = DocumentNotifier()
        ..loadDocument(MarkdownDocument.parse(source));
      notifier.edit(edited, coalesceKey: null);
      expect(notifier.state.document!.source, edited);
      notifier.undo();
      expect(notifier.state.document!.source, source);
      notifier.redo();
      expect(notifier.state.document!.source, edited);
      expect(
        planTranscriptUpdate(
          edited,
          body,
          baseline: transcriptBodyText(edited),
        ),
        isA<TranscriptConflict>(),
      );
      expect(
        planTranscriptUpdate(edited, body, baseline: body),
        isA<TranscriptConflict>(),
      );
      expect(
        planTranscriptUpdate(edited, transcriptBodyText(edited)!),
        isA<TranscriptUnchanged>(),
      );
    } finally {
      dir.deleteSync(recursive: true);
    }
  }

  test('wrong tag: selected segments change, IDs and visible labels agree', () {
    final model = SpeakerCorrections.read(source)!;
    model.assign({0, 2}, 'b');
    final edited = model.apply(source);
    final reopened = SpeakerCorrections.read(edited)!;
    expect(reopened.idsAt(0), ['b']);
    expect(reopened.idsAt(2), ['b']);
    expect(reopened.lines[0], contains('**Spreker 2:**'));
    expect(reopened.lines[1], model.lines[1]);
    expect(
      edited.substring(0, transcriptBodySpan(edited)!.$1),
      source.substring(0, transcriptBodySpan(source)!.$1),
    );
    roundtrip(edited);
  });
  test('same person: merge all occurrences and deduplicate overlap', () {
    final model = SpeakerCorrections.read(source)!;
    expect(model.mergeCount('b'), 2);
    model.merge('b', 'a');
    final edited = model.apply(source);
    final reopened = SpeakerCorrections.read(edited)!;
    expect(reopened.idsAt(1), ['a']);
    expect(reopened.idsAt(3), ['a']);
    expect(reopened.names.containsKey('b'), false);
    expect(reopened.idsAt(2), ['c']);
    roundtrip(edited);
  });
  test(
    'extra speaker: split mid-fragment, assign new identity without invented time',
    () {
      final model = SpeakerCorrections.read(source)!;
      model.split(0, 'Eerste zin. '.length);
      final id = model.addSpeaker('Extra spreker');
      model.assign({1}, id);
      final edited = model.apply(source);
      final reopened = SpeakerCorrections.read(edited)!;
      expect(reopened.lines, hasLength(5));
      expect(reopened.spokenText(0), 'Eerste zin.');
      expect(reopened.spokenText(1), 'Andere stem.');
      expect(reopened.idsAt(1), [id]);
      expect(reopened.metadata[1]['start_us'], isNull);
      expect(reopened.metadata[1]['end_us'], isNull);
      expect(reopened.idsAt(2), ['b']);
      roundtrip(edited);
    },
  );
  test(
    'manually changed corrected text cannot silently reuse stale indices',
    () {
      final model = SpeakerCorrections.read(source)!..assign({0}, 'b');
      expect(
        SpeakerCorrections.read(
          model.apply(source).replaceFirst('Eerste zin.', 'Aangepast.'),
        ),
        isNull,
      );
    },
  );
  test('invalid split and unsafe labels are rejected', () {
    final model = SpeakerCorrections.read(source)!;
    expect(() => model.split(0, 0), throwsArgumentError);
    expect(() => model.addSpeaker('**injectie'), throwsArgumentError);
  });
}
