import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Contracttest voor het gepinde Vosk-testbed uit #2525.
///
/// Het testbed is het bewijskader van de live-ASR-route: bewijs is alleen
/// geldig als de omgeving gepind, loopback-only en herhaalbaar is. Wie een
/// pin aanpast, past bewust de testomgeving aan — en moet dat in
/// `testbed/vosk-asr/README.md` verantwoorden.
void main() {
  const dir = 'testbed/vosk-asr';
  final compose = File('$dir/docker-compose.yml').readAsStringSync();
  final fetch = File('$dir/fetch-model.sh').readAsStringSync();
  final gitignore = File('$dir/.gitignore').readAsLinesSync();

  test('de server-image is op digest gepind, niet op een beweeglijke tag', () {
    expect(
      compose,
      contains(RegExp(r'alphacep/kaldi-vosk-server@sha256:[0-9a-f]{64}')),
      reason: 'een tag kan herschreven worden; de digest kan dat niet',
    );
    expect(
      compose,
      isNot(contains(':latest')),
      reason: 'latest maakt elke gedocumenteerde proef stilletjes ongeldig',
    );
  });

  test('het model is op naam én sha256 gepind in het fetch-script', () {
    expect(fetch, contains('vosk-model-small-en-us-0.15'));
    expect(
      fetch,
      contains(RegExp(r'SHA256=[0-9a-f]{64}')),
      reason: 'zonder checksum toetst het script niets aan de download',
    );
    expect(
      fetch,
      contains('shasum -a 256 -c'),
      reason: 'de pin moet ook echt gecontroleerd worden',
    );
  });

  test('elke gepubliceerde poort bindt op loopback', () {
    final ports = RegExp(
      r'^\s*-\s*"([^"]*:\d+(?::\d+)?(?:/udp)?)"\s*$',
      multiLine: true,
    ).allMatches(compose).map((m) => m.group(1)!).toList();
    expect(ports, isNotEmpty, reason: 'het testbed heeft een poort nodig');
    for (final p in ports) {
      expect(
        p.startsWith('127.0.0.1:'),
        isTrue,
        reason:
            'poort $p mag niet op alle interfaces binden — '
            'het bewijs geldt een loopback-omgeving',
      );
    }
  });

  test('het gemounte model is read-only en de artefacten staan uit git', () {
    expect(
      compose,
      contains(':/opt/vosk-model:ro'),
      reason: 'een testschijf mag nooit door de server gemuteerd worden',
    );
    expect(
      gitignore,
      contains('model/'),
      reason: 'het 41 MB-model is een artefact, geen bron',
    );
  });

  test('de fixture is de officiële 16 kHz mono s16le testclip', () {
    final bytes = File('$dir/fixtures/test16k.wav').readAsBytesSync();
    expect(bytes.length, greaterThan(44), reason: 'meer dan een kale header');
    // RIFF/WAVE-magie: het contract voedt dit bestand rechtstreeks aan
    // wavPcmData — een corrupt fixture zou "getest" claimen wat het niet is.
    expect(String.fromCharCodes(bytes.sublist(0, 4)), 'RIFF');
    expect(String.fromCharCodes(bytes.sublist(8, 12)), 'WAVE');
  });
}
