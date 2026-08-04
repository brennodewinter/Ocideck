// Fast guard that the committed SBOM names the *current* version.
//
// The SBOM records the project version — CRA (Reg. (EU) 2024/2847, Annex I
// Part II §1) wants "which version is this inventory for". So bumping the
// version in pubspec.yaml makes the SBOM stale until `make sbom` regenerates
// it. `sbom_test` already catches that, but only as a full regenerate-and-diff
// flutter test in `make check-registrations` — slow, and outside the fast
// `make check-static` subset. A version bump therefore passed the fast static
// gate green while the SBOM was quietly a version behind, and the drift only
// surfaced later (0.3.0 release).
//
// This closes that gap: a cheap string check, in `STATIC_GATES`, so a stale
// SBOM fails at the same fast tier as the rest — no dependency scan, no flutter.
// It checks only the version (the part a bump breaks); `sbom_test` still owns
// the full dependency-set freshness.
//
// The rule: the exact pubspec version *including the build number*
// (`X.Y.Z+B`) must appear in every committed SBOM file. `make sbom` writes that
// string into all three at once, so a file that lacks it was not regenerated.

import 'dart:io';

/// The committed SBOM files that carry the project version.
const List<String> sbomFiles = [
  'sbom/ocideck.cdx.json',
  'sbom/ocideck.spdx.json',
  'sbom/ocideck.sbom.md',
];

/// The SBOM files (by key) whose content does not contain [version]. Pure and
/// content-injected so the test can drive it without touching disk.
List<String> sbomFilesMissingVersion(
  String version,
  Map<String, String> contentsByFile,
) => contentsByFile.entries
    .where((e) => !e.value.contains(version))
    .map((e) => e.key)
    .toList();

/// Reads the raw `version:` value (with any `+build` suffix) from pubspec.yaml
/// at [path]. Throws when the field is missing.
String readPubspecVersion(String path) {
  for (final line in File(path).readAsLinesSync()) {
    final m = RegExp(r'^version:\s*(\S+)').firstMatch(line);
    if (m != null) return m.group(1)!;
  }
  throw StateError('No `version:` field in $path');
}

void main(List<String> args) {
  final version = readPubspecVersion('pubspec.yaml');

  final contents = <String, String>{};
  for (final f in sbomFiles) {
    final file = File(f);
    if (!file.existsSync()) {
      stderr.writeln(
        'check-sbom-version: missing SBOM file $f — run `make sbom`.',
      );
      exit(1);
    }
    contents[f] = file.readAsStringSync();
  }

  final missing = sbomFilesMissingVersion(version, contents);
  if (missing.isEmpty) {
    stdout.writeln('check-sbom-version: OK (SBOM names $version).');
    return;
  }

  stderr
    ..writeln('check-sbom-version: the SBOM does not name the current version.')
    ..writeln('  pubspec version : $version')
    ..writeln('  not found in    : ${missing.join(', ')}')
    ..writeln('')
    ..writeln(
      'The SBOM records the project version, so a version bump makes it',
    )
    ..writeln('stale. Regenerate and commit it:')
    ..writeln('  make sbom')
    ..writeln('  git add sbom/');
  exit(1);
}
