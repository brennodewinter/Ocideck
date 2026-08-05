@TestOn('vm')
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Bewaakt dat `scripts/deploy_web.sh` de webbundel op macOS zónder
/// Apple-metadata inpakt.
///
/// macOS' bsdtar bakt extended attributes (com.apple.provenance/quarantine/
/// FinderInfo) en BSD-file-flags als pax-headers in het archief. De GNU-tar op
/// de deployserver kan die keywords niet lezen en drukt dan per bestand een
/// "Ignoring unknown extended header keyword"-waarschuwing af — bij de
/// v0.3.4-release duizenden regels ruis over een verder geslaagde deploy. De
/// webbundel heeft er niets aan, dus strippen we ze bij de bron met vlaggen die
/// alléén Apple-bsdtar kent; het CI-pad draait op GNU-tar en mag ze dus niet
/// onvoorwaardelijk krijgen.
///
/// Dit is de enige plek waar de bundel op macOS wordt ingepakt, dus een
/// string-guard volstaat: de vlaggen moeten er staan, en achter een Darwin-poort.
void main() {
  final script = File('scripts/deploy_web.sh').readAsStringSync();

  test('de macOS-tar strips Apple-metadata (geen pax-ruis op de server)', () {
    for (final flag in const [
      '--no-mac-metadata',
      '--no-xattrs',
      '--no-fflags',
    ]) {
      expect(
        script.contains(flag),
        isTrue,
        reason:
            'deploy_web.sh mist `$flag`; macOS-tar bakt dan weer '
            'Apple-metadata in de bundel en de GNU-tar op de server spuwt '
            'per bestand een "unknown extended header keyword"-waarschuwing.',
      );
    }
  });

  test(
    'de strip-vlaggen staan achter een Darwin-poort (GNU-tar kent ze niet)',
    () {
      // De CI-deploy draait op GNU-tar, dat geen van de vlaggen kent; ze mogen
      // dus alleen op macOS worden toegevoegd. Borg de platformcheck én dat de
      // tar-aanroep de opgebouwde optielijst gebruikt.
      expect(
        RegExp(r'uname -s.*==.*Darwin').hasMatch(script),
        isTrue,
        reason:
            'De tar-strip-vlaggen moeten achter een `uname -s == Darwin`-'
            'poort staan, anders faalt de GNU-tar in CI erop.',
      );
      expect(
        RegExp(r'tar "\$\{TAR_OPTS\[@\]\}"').hasMatch(script),
        isTrue,
        reason:
            'De tar-aanroep gebruikt de platformafhankelijke TAR_OPTS niet.',
      );
    },
  );
}
