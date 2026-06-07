// Verifies that every resolved Dart/Flutter dependency (direct and transitive)
// uses a recognised open-source licence. Bundled JS/font assets are documented
// separately in THIRD_PARTY_NOTICES.md.
//
//   dart run tool/check_licenses.dart     (or: make licenses)
//
// Exits non-zero if any package has an unrecognised or non-open-source licence,
// so it can run in CI.

import 'dart:convert';
import 'dart:io';

/// Licence families we accept (all OSI-approved / open source).
const allowed = <String>{
  'MIT',
  'BSD',
  'BSD-2-Clause',
  'BSD-3-Clause',
  'Apache-2.0',
  'MPL-2.0',
  'ISC',
  'Zlib',
  'BSL-1.0',
  'Unlicense',
  'OFL-1.1',
  'CC0-1.0',
  'EUPL-1.2', // OciDeck itself
};

/// Packages that ship as part of the Flutter SDK without their own LICENSE file
/// (covered by the Flutter SDK licence, BSD-3-Clause).
const sdkNoLicenseOk = <String>{
  'flutter',
  'flutter_test',
  'flutter_localizations',
  'flutter_web_plugins',
  'flutter_driver',
  'integration_test',
  'sky_engine',
};

String classify(String text) {
  final t = text.toLowerCase();
  if (t.contains('european union public licence') ||
      t.contains('european union public license')) {
    return 'EUPL-1.2';
  }
  // Note: the MPL-2.0 and EUPL texts *reference* the GNU licences in their
  // compatibility clauses, so detect those reciprocal-but-distinct licences
  // before the GNU keywords to avoid false positives.
  if (t.contains('mozilla public license')) return 'MPL-2.0';
  if (t.contains('apache license')) return 'Apache-2.0';
  if (t.contains('gnu affero')) return 'AGPL';
  if (t.contains('gnu lesser general public')) return 'LGPL';
  if (t.contains('gnu general public')) return 'GPL';
  if (t.contains('sil open font')) return 'OFL-1.1';
  if (t.contains('isc license')) return 'ISC';
  if (t.contains('boost software license')) return 'BSL-1.0';
  if (t.contains('the unlicense')) return 'Unlicense';
  if (t.contains('cc0')) return 'CC0-1.0';
  if (t.contains('permission is hereby granted, free of charge')) return 'MIT';
  if (t.contains('mit license')) return 'MIT';
  if (t.contains('bsd 3-clause') ||
      (t.contains('redistribution and use') &&
          t.contains('neither the name'))) {
    return 'BSD-3-Clause';
  }
  if (t.contains('redistribution and use in source and binary forms')) {
    return 'BSD';
  }
  if (t.contains('bsd')) return 'BSD';
  return 'UNKNOWN';
}

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

    File? lic;
    for (final c in [
      'LICENSE',
      'LICENSE.md',
      'LICENSE.txt',
      'COPYING',
      'license',
    ]) {
      final f = File('${root.path}/$c');
      if (f.existsSync()) {
        lic = f;
        break;
      }
    }

    String kind;
    if (name == 'ocideck') {
      kind = 'EUPL-1.2';
    } else if (lic == null) {
      kind = sdkNoLicenseOk.contains(name)
          ? 'BSD-3-Clause (Flutter SDK)'
          : 'NO LICENSE FILE';
    } else {
      final txt = lic.readAsStringSync();
      kind = classify(txt.length > 6000 ? txt.substring(0, 6000) : txt);
    }

    rows.add((name, kind));
    final family = kind.split(' ').first;
    if (!allowed.contains(family)) problems.add('$name → $kind');
  }

  rows.sort((a, b) => a.$1.compareTo(b.$1));

  final counts = <String, int>{};
  for (final r in rows) {
    final k = r.$2.split(' ').first;
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
      'Bundled JS/font assets are listed in THIRD_PARTY_NOTICES.md.',
    );
    exit(0);
  }

  stderr.writeln('\nPROBLEM — ${problems.length} package(s) need review:');
  for (final p in problems) {
    stderr.writeln('  $p');
  }
  exit(1);
}
