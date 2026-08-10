import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Regressietest voor de valse secret-lekken uit het lokale XMPP-testbed.
///
/// `make check-secrets` draait `gitleaks dir .` én `trufflehog filesystem .`
/// over de héle werkboom. Beide negeren de geneste `.gitignore` van het
/// docker-jitsi-meet-testbed, dus zodra iemand dat testbed opzet, komen de
/// gegenereerde, wegwerp-TLS-sleutels en het `.env` met wachtwoorden ineens in
/// beeld. Gevolg: élke `make check-release`/release strandde bij de
/// secret-poort op een vals alarm, terwijl er niets gecommit was.
///
/// De invariant: álles wat het testbed in zijn eigen `.gitignore` als
/// gegenereerd bestempelt, hoort in BEIDE scanner-allowlists te staan. Zo
/// verhuist de fout naar hier — een snelle, sprekende PR-poort — in plaats van
/// naar de volgende release. Voegt het testbed later een gegenereerd pad toe,
/// dan valt deze test, niet de release.
void main() {
  test('elk gegenereerd testbed-pad staat in beide secret-scanner-allowlists', () {
    const testbedDir = 'testbed/docker-jitsi-meet';
    final gitignore = File('$testbedDir/.gitignore');
    expect(
      gitignore.existsSync(),
      isTrue,
      reason: 'het testbed hoort een .gitignore te hebben',
    );

    // De gegenereerde paden die het testbed zélf declareert (regels zonder #).
    final generated = gitignore
        .readAsLinesSync()
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty && !l.startsWith('#'))
        .toList();
    expect(
      generated,
      isNotEmpty,
      reason: 'testbed/.gitignore hoort gegenereerde paden te noemen',
    );

    // De allowlists schrijven regexen met ontsnapte punten (`\.env`); we
    // vergelijken op het letterlijke pad, dus halen we de backslashes eruit.
    String plain(String s) => s.replaceAll(r'\', '');
    final gitleaks = plain(File('.gitleaks.toml').readAsStringSync());
    final trufflehog = plain(File('.trufflehogignore').readAsStringSync());

    for (final entry in generated) {
      final path = '$testbedDir/$entry'; // bv. testbed/docker-jitsi-meet/.env
      expect(
        gitleaks.contains(path),
        isTrue,
        reason: '.gitleaks.toml moet $path uitsluiten (gitleaks dir .)',
      );
      expect(
        trufflehog.contains(path),
        isTrue,
        reason:
            '.trufflehogignore moet $path uitsluiten (trufflehog filesystem .)',
      );
    }
  });
}
