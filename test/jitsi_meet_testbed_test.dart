import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Contracttest voor het gepinde Jitsi-calltestbed uit #2540.
///
/// Het testbed is het bewijskader voor alle call-issues: bewijs is alleen
/// geldig als de omgeving gepind, loopback-only en hermetisch is. Deze test
/// kan dus niet rood om een foute reden — wie de pin aanpast, past bewust de
/// testomgeving aan en moet dat óók in `EVIDENCE_FORM.md` verantwoorden.
void main() {
  const dir = 'testbed/jitsi-meet';
  final compose = File('$dir/docker-compose.yml').readAsStringSync();
  final envExample = File('$dir/.env.example').readAsStringSync();
  final gitignore = File('$dir/.gitignore').readAsLinesSync();

  test('alle vier de services zijn gepind via JITSI_IMAGE_VERSION', () {
    for (final service in ['web', 'prosody', 'jicofo', 'jvb']) {
      expect(
        compose,
        contains('/$service:\${JITSI_IMAGE_VERSION'),
        reason: '$service moet de pinvariabele gebruiken, geen vaste tag',
      );
    }
    expect(
      compose,
      isNot(contains(':latest')),
      reason: 'latest maakt elke gedocumenteerde proef stilletjes ongeldig',
    );
  });

  test('de pin in .env.example is een echte stable-tag', () {
    expect(
      envExample,
      contains(RegExp(r'^JITSI_IMAGE_VERSION=stable-\d+', multiLine: true)),
      reason: 'de testomgeving claimt een specifieke upstream-release',
    );
  });

  test('elke gepubliceerde poort bindt op loopback', () {
    final ports = RegExp(
      r"^\s*-\s*'([^']*:\d+(?::\d+)?(?:/udp)?)'\s*$",
      multiLine: true,
    ).allMatches(compose).map((m) => m.group(1)!).toList();
    expect(ports, isNotEmpty, reason: 'het testbed heeft poorten nodig');
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

  test('de stack is hermetisch: geen externe STUN, harvest of p2p', () {
    for (final flag in [
      'JVB_DISABLE_STUN=1',
      'DISABLE_AWS_HARVESTER=1',
      'ENABLE_P2P=0',
      'ENABLE_THIRD_PARTY_REQUESTS=0',
    ]) {
      expect(
        envExample,
        contains(RegExp('^$flag\$', multiLine: true)),
        reason: '$flag hoort bij de hermetische pin uit #2540',
      );
    }
  });

  test('gegenereerde paden en secrets blijven uit git', () {
    for (final entry in ['.env', 'config/', 'evidence/']) {
      expect(
        gitignore,
        contains(entry),
        reason: '$entry bevat wachtwoorden/certs en mag nooit gecommit worden',
      );
    }
  });

  test('procedure, bewijsformulier en readme zijn aanwezig', () {
    for (final doc in ['README.md', 'PROCEDURE.md', 'EVIDENCE_FORM.md']) {
      expect(
        File('$dir/$doc').existsSync(),
        isTrue,
        reason: '#2540 eist een gedocumenteerde proef met bewijsformulier',
      );
    }
  });
}
