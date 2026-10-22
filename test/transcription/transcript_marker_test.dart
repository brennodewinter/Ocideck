import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/services/transcription/transcript_marker.dart';

void main() {
  group('detectTranscript', () {
    test('een gewoon document is geen transcript', () {
      expect(detectTranscript('# Rapport\n\nTekst.\n'), isA<NoTranscript>());
    });

    test('geldige marker zonder audio', () {
      final detection = detectTranscript(
        '<!-- transcript version=1 -->\n# Transcript — x\n\n---\n\nTekst.\n',
      );
      final valid = detection as ValidTranscript;
      expect(valid.marker.version, 1);
      expect(valid.marker.audioPath, isNull);
      expect(valid.marker.line, '<!-- transcript version=1 -->');
    });

    test('geldige marker met media-verwijzing', () {
      final detection = detectTranscript(
        '<!-- transcript version=1 audio="media/opname-1.m4a" -->\n# T\n',
      );
      expect(
        (detection as ValidTranscript).marker.audioPath,
        'media/opname-1.m4a',
      );
    });

    test('marker mag direct onder de front matter staan', () {
      final detection = detectTranscript(
        '---\ntheme: Test\n---\n\n<!-- transcript version=1 -->\n# T\n',
      );
      expect(detection, isA<ValidTranscript>());
    });

    test('marker later in het document is verplaatst', () {
      final detection = detectTranscript(
        '# Kop\n\n<!-- transcript version=1 -->\n\nTekst.\n',
      );
      final malformed = detection as MalformedTranscript;
      expect(
        malformed.issues.map((i) => i.kind),
        contains(TranscriptMarkerIssueKind.misplaced),
      );
    });

    test('een tweede marker is een duplicaat', () {
      final detection = detectTranscript(
        '<!-- transcript version=1 -->\n\n<!-- transcript version=1 -->\n',
      );
      final malformed = detection as MalformedTranscript;
      expect(
        malformed.issues.map((i) => i.kind),
        contains(TranscriptMarkerIssueKind.duplicate),
      );
    });

    test('marker zonder version is beschadigd', () {
      final detection = detectTranscript('<!-- transcript -->\n# T\n');
      expect(
        (detection as MalformedTranscript).issues.single.kind,
        TranscriptMarkerIssueKind.malformed,
      );
    });

    test('marker met verkeerd attribuut is beschadigd', () {
      final detection = detectTranscript('<!-- transcript versie=1 -->\n# T\n');
      expect(
        (detection as MalformedTranscript).issues.single.kind,
        TranscriptMarkerIssueKind.malformed,
      );
    });

    test('een hogere versie wordt gemeld, niet gelezen', () {
      final detection = detectTranscript(
        '<!-- transcript version=2 -->\n# T\n',
      );
      expect(
        (detection as MalformedTranscript).issues.single.kind,
        TranscriptMarkerIssueKind.unsupportedVersion,
      );
    });

    for (final bad in [
      '../opname.m4a',
      '/etc/passwd',
      'media/../x.wav',
      'C:\\\\x.wav',
      'images/x.wav',
      'https://x/y.m4a',
      'media/',
    ]) {
      test('onveilig audiopad wordt geweigerd: $bad', () {
        final detection = detectTranscript(
          '<!-- transcript version=1 audio="$bad" -->\n# T\n',
        );
        expect(
          (detection as MalformedTranscript).issues.single.kind,
          TranscriptMarkerIssueKind.unsafeAudioPath,
        );
      });
    }

    test('geneste media-map is toegestaan', () {
      final detection = detectTranscript(
        '<!-- transcript version=1 audio="media/2026/opname.wav" -->\n# T\n',
      );
      expect(
        (detection as ValidTranscript).marker.audioPath,
        'media/2026/opname.wav',
      );
    });

    test('inspringing van drie spaties tolereert de marker', () {
      final detection = detectTranscript(
        '   <!-- transcript version=1 -->\n# T\n',
      );
      expect(detection, isA<ValidTranscript>());
    });

    test('commentaar zonder transcript is gewoon commentaar', () {
      expect(
        detectTranscript('<!-- een opmerking -->\n# T\n'),
        isA<NoTranscript>(),
      );
    });
  });

  group('formatTranscriptMarker', () {
    test('canonieke vorm zonder en met audio', () {
      expect(formatTranscriptMarker(), '<!-- transcript version=1 -->');
      expect(
        formatTranscriptMarker(audioRelPath: 'media/x.wav'),
        '<!-- transcript version=1 audio="media/x.wav" -->',
      );
    });
  });
}
