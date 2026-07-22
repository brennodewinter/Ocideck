import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/services/export_metadata.dart';
import 'package:yaml/yaml.dart';

/// De versie leeft op twee plekken die geen compiler aan elkaar knoopt:
/// `pubspec.yaml` (de bron van de waarheid, en wat `flutter build` gebruikt
/// om elk platform zijn eigen versieveld te geven) en [kOciDeckVersion] (de
/// Dart-`const` die in de metadata van elke geëxporteerde PDF/PPTX en in het
/// About-paneel belandt — een `const` kan `pubspec.yaml` niet op
/// compileertijd inlezen).
///
/// Zonder deze toets kan iemand de versie op de ene plek ophogen en de
/// andere vergeten, waarna een release exportbestanden aflevert die de vorige
/// versie noemen. Dit is de bewuste keuze voor "een test die de twee
/// vergelijkt" uit issue #520, in plaats van codegeneratie: een Dart `const`
/// die niets inleest is eenvoudiger dan een build-stap die dat wel doet, en
/// deze toets faalt hard zodra ze uiteenlopen.
void main() {
  test('kOciDeckVersion matches the version in pubspec.yaml', () {
    final pubspec =
        loadYaml(File('pubspec.yaml').readAsStringSync()) as YamlMap;
    final pubspecVersion = (pubspec['version'] as String).split('+').first;

    expect(
      kOciDeckVersion,
      pubspecVersion,
      reason:
          'lib/services/export_metadata.dart#kOciDeckVersion ($kOciDeckVersion) '
          'loopt uiteen van pubspec.yaml ($pubspecVersion). Werk '
          'kOciDeckVersion bij zodat exportmetadata en het About-paneel de '
          'juiste versie tonen.',
    );
  });
}
