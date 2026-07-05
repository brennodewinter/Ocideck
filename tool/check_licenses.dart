// Verifies that every resolved Dart/Flutter dependency (direct and transitive)
// uses a recognised open-source licence. Bundled JS/font assets are documented
// separately in THIRD_PARTY_NOTICES.md and enumerated in the SBOM (make sbom).
//
//   dart run tool/check_licenses.dart     (or: make licenses)
//
// Exits non-zero if any package has an unrecognised or non-open-source licence,
// so it can run in CI. The licence-detection logic is shared with the SBOM
// generator (tool/lib/license_detect.dart) so the two can never disagree.

import 'dart:convert';
import 'dart:io';

import 'license_detect.dart';

void main() {
  final cfgFile = File('.dart_tool/package_config.json');
  if (!cfgFile.existsSync()) {
    stderr.writeln(
      'No .dart_tool/package_config.json — run "flutter pub get" first.',
    );
    exit(2);
  }
  final base = cfgFile.absolute.parent.uri;
  final cfg = jsonDecode(cfgFile.readAsStringSync()) as Map<String, dynamic>;

  final rows = <(String, String)>[];
  final problems = <String>[];

  for (final pkg in (cfg['packages'] as List)) {
    final name = pkg['name'] as String;
    final rootUri = pkg['rootUri'] as String;
    final resolved = rootUri.startsWith('file:')
        ? Uri.parse(rootUri.endsWith('/') ? rootUri : '$rootUri/')
        : base.resolve(rootUri.endsWith('/') ? rootUri : '$rootUri/');
    final root = Directory.fromUri(resolved);

    final kind = licenseForPackage(name, root);
    rows.add((name, kind));
    if (!allowedLicenses.contains(licenseFamily(kind))) {
      problems.add('$name → $kind');
    }
  }

  rows.sort((a, b) => a.$1.compareTo(b.$1));

  final counts = <String, int>{};
  for (final r in rows) {
    final k = licenseFamily(r.$2);
    counts[k] = (counts[k] ?? 0) + 1;
  }
  stdout.writeln('Scanned ${rows.length} packages:');
  final keys = counts.keys.toList()..sort((a, b) => counts[b]! - counts[a]!);
  for (final k in keys) {
    stdout.writeln('  ${counts[k]!.toString().padLeft(3)}  $k');
  }

  if (problems.isEmpty) {
    stdout.writeln(
      '\nOK — all dependencies use recognised open-source licences.',
    );
    stdout.writeln(
      'Bundled JS/font assets are listed in THIRD_PARTY_NOTICES.md '
      'and the SBOM (make sbom).',
    );
    exit(0);
  }

  stderr.writeln('\nPROBLEM — ${problems.length} package(s) need review:');
  for (final p in problems) {
    stderr.writeln('  $p');
  }
  exit(1);
}
