// Tests voor transcript_audio_copy.dart — de bewaarkeuze die bij
// Opslaan landt (#2515): kopie onder `media/`, botsingsveilige naam en
// de eerlijke null wanneer de kopie niet kan.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/services/transcript_audio_copy.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory tmp;
  late Directory docDir;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('audio_copy_test_');
    docDir = await Directory(p.join(tmp.path, 'doc')).create();
  });

  tearDown(() async {
    if (await tmp.exists()) await tmp.delete(recursive: true);
  });

  File bron({String name = 'bron.wav', int bytes = 64}) =>
      File(p.join(tmp.path, name))
        ..writeAsBytesSync(List.generate(bytes, (i) => i % 251));

  test('kopieert onder media/ en levert het projectrelatieve pad', () async {
    final src = bron();
    final rel = await copyTranscriptAudioToMedia(src.path, docDir.path);
    expect(rel, 'media/bron.wav');
    final kopie = File(p.join(docDir.path, 'media', 'bron.wav'));
    expect(await kopie.exists(), isTrue);
    expect(await kopie.readAsBytes(), src.readAsBytesSync());
    // Het origineel staat er nog — de keuze kopieert, verplaatst niet.
    expect(await src.exists(), isTrue);
  });

  test(
    'een botsende naam krijgt een eigen vorm, geen overschrijving',
    () async {
      final eerste = bron(name: 'clip.wav');
      await copyTranscriptAudioToMedia(eerste.path, docDir.path);
      // Tweede bron, zelfde bestandsnaam, andere inhoud.
      final tweede = File(p.join(tmp.path, 'anders', 'clip.wav'))
        ..createSync(recursive: true)
        ..writeAsBytesSync([9, 9, 9]);
      final rel = await copyTranscriptAudioToMedia(tweede.path, docDir.path);
      expect(rel, isNotNull);
      expect(rel, isNot('media/clip.wav'));
      expect(rel, startsWith('media/'));
      // Beide staan er — niets overschreven.
      expect(
        File(p.join(docDir.path, 'media', 'clip.wav')).readAsBytesSync().length,
        64,
      );
      expect(File(p.join(docDir.path, rel!)).readAsBytesSync(), [9, 9, 9]);
    },
  );

  test('een weggevallen bron levert null — geen link-schijnbare', () async {
    final rel = await copyTranscriptAudioToMedia(
      p.join(tmp.path, 'weg.wav'),
      docDir.path,
    );
    expect(rel, isNull);
  });

  test('een leeg bronbestand levert null', () async {
    final leeg = bron(name: 'leeg.wav', bytes: 0);
    final rel = await copyTranscriptAudioToMedia(leeg.path, docDir.path);
    expect(rel, isNull);
  });
}
