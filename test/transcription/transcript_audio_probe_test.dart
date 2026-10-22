// De audio-probe op het echte bestandssysteem: aanwezig, verplaatst/
// verwijderd, buiten de projectmap, en zonder projectpad (§3.4 —
// "niet te verifiëren" is een ander antwoord dan "weg").
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/services/transcription/transcript_audio_probe.dart';
import 'package:ocideck/services/transcription/transcript_audio_probe_stub.dart'
    as stub;
import 'package:path/path.dart' as p;

void main() {
  late Directory dir;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('transcript_probe');
    Directory(p.join(dir.path, 'media')).createSync();
  });

  tearDown(() => dir.deleteSync(recursive: true));

  test('aanwezig bestand in media/ → true', () {
    File(p.join(dir.path, 'media', 'opname.wav')).writeAsBytesSync([0]);
    expect(transcriptAudioExists(dir.path, 'media/opname.wav'), isTrue);
  });

  test('verplaatst of verwijderd bestand → false', () {
    expect(transcriptAudioExists(dir.path, 'media/opname.wav'), isFalse);
  });

  test('een verwijzing buiten de projectmap is niet te verifiëren', () {
    expect(transcriptAudioExists(dir.path, '../buiten.wav'), isNull);
  });

  test('zonder projectpad is er niets om te verifiëren', () {
    expect(transcriptAudioExists(null, 'media/opname.wav'), isNull);
  });

  group('web-stub (§3.4 "niet te verifiëren")', () {
    test('antwoordt altijd null — nooit een vals-alarm op web', () {
      expect(stub.transcriptAudioExists('/map', 'media/opname.wav'), isNull);
      expect(stub.transcriptAudioExists(null, 'media/opname.wav'), isNull);
    });
  });
}
