// De manifestlezer (#2530): alleen de vorm die de callsessie zelf schreef
// telt als provenance — geen bestand, stuk JSON, een niet-objecct of een
// andere versie leveren allemaal null.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/meetings/call_audio_manifest_io.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory dir;
  late String wavPath;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('call_sources_test_');
    wavPath = p.join(dir.path, 'recording.wav');
  });

  tearDown(() async {
    if (await dir.exists()) await dir.delete(recursive: true);
  });

  void write(String body) {
    File(p.join(dir.path, 'sources.json')).writeAsStringSync(body);
  }

  test('geen bestand, stuk JSON of vreemde vorm leveren null', () {
    expect(readCallSources(wavPath), isNull);

    write('not json{');
    expect(readCallSources(wavPath), isNull);

    write(jsonEncode(<String>['sources']));
    expect(readCallSources(wavPath), isNull);

    write(jsonEncode({'version': 2, 'sources': <Object?>[]}));
    expect(readCallSources(wavPath), isNull);
  });

  test('een v1-manifest van de sessie komt terug', () {
    const manifest = {
      'version': 1,
      'sources': [
        {'trackId': 't1', 'silenceTicks': 3},
      ],
    };
    write(jsonEncode(manifest));
    expect(readCallSources(wavPath), manifest);
  });
}
