// Synthetische 100 ms/440 Hz-fixtures, geen opgenomen of gebruikersaudio.
// Gegenereerd met ffmpeg: -f lavfi -i sine=frequency=440:sample_rate=16000:duration=0.1
// -ac 1 -c:a <aac/libmp3lame/libvorbis/libopus/pcm_s16be/pcm_s16le> -f <container>.
// tone-no-id3.mp3: bovendien -id3v2_version 0 -write_xing 0.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/services/transcription/media_sniff.dart';

void main() {
  const fixtures = {
    'tone.aac': MediaContainer.aac,
    'tone.mp3': MediaContainer.mp3,
    'tone-no-id3.mp3': MediaContainer.mp3,
    'tone.ogg': MediaContainer.ogg,
    'tone.opus': MediaContainer.ogg,
    'tone.aiff': MediaContainer.aiff,
    'tone.aifc': MediaContainer.aiff,
    'tone.caf': MediaContainer.caf,
    'tone.3gp': MediaContainer.mpeg4,
    'tone.m4b': MediaContainer.mpeg4,
  };
  for (final entry in fixtures.entries) {
    test(
      'echte ${entry.key}-fixture wordt op bytes herkend, ook met verkeerde naam',
      () async {
        final bytes = await File(
          'test/fixtures/transcription/${entry.key}',
        ).readAsBytes();
        final head = bytes.sublist(0, bytes.length.clamp(0, sniffHeadBytes));
        expect(sniffContainer(head), entry.value);
        expect(sniffContainer(head, extension: '.txt'), entry.value);
        expect(classifyOpenTarget(head, extension: '.txt'), OpenTarget.media);
      },
    );
  }
}
