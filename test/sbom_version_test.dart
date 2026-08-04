import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../tool/check_sbom_version.dart';

/// The SBOM records the project version, so a version bump makes it stale until
/// `make sbom` regenerates it. `make check-sbom-version` (in `STATIC_GATES`)
/// fails fast when the committed SBOM does not name the current version — the
/// gap that let a 1.2.1→0.3.0 bump pass the fast static gate with a version-old
/// SBOM. This pins the rule and checks the real committed files stay in sync.
void main() {
  group('sbomFilesMissingVersion', () {
    test('flags every file that lacks the version string', () {
      final missing = sbomFilesMissingVersion('0.3.0+7', {
        'a': 'ocideck 0.3.0+7 ...',
        'b': 'still ocideck 0.2.0+5 here', // stale
        'c': '{"version":"0.3.0+7"}',
      });
      expect(missing, ['b']);
    });

    test('a fully regenerated SBOM has no missing files', () {
      final missing = sbomFilesMissingVersion('1.4.2+9', {
        'a': 'v1.4.2+9',
        'b': 'name: ocideck-1.4.2+9',
      });
      expect(missing, isEmpty);
    });

    test('the build number matters — a version-only match is still stale', () {
      // 0.3.0 without +7 must not satisfy the check: `make sbom` writes the
      // full X.Y.Z+B, and the build number moves on a re-release too.
      final missing = sbomFilesMissingVersion('0.3.0+7', {
        'a': 'ocideck 0.3.0+6',
      });
      expect(missing, ['a']);
    });
  });

  test('the committed SBOM names the current pubspec version', () {
    // The live invariant: whatever version pubspec.yaml carries right now, all
    // three committed SBOM files must already name it.
    final version = readPubspecVersion('pubspec.yaml');
    final contents = {for (final f in sbomFiles) f: File(f).readAsStringSync()};
    expect(
      sbomFilesMissingVersion(version, contents),
      isEmpty,
      reason: 'SBOM is stale for $version — run `make sbom` and commit sbom/.',
    );
  });
}
