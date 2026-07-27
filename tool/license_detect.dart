// Shared open-source licence detection for the repo tooling.
//
// Both `tool/check_licenses.dart` (the compliance gate) and
// `tool/generate_sbom.dart` (the SBOM generator) need the same answer to the
// same question: "given a resolved package on disk, which licence family does
// it use?". Keeping that logic here means the SBOM can never disagree with the
// gate about a package's licence.
//
// This file is deliberately dependency-free (only dart:io) so both plain
// `dart run tool/...` scripts can import it without pulling in Flutter.

import 'dart:io';

/// Licence families accepted by the compliance gate (all OSI-approved / open
/// source). The gate fails on anything whose family is not in this set.
const allowedLicenses = <String>{
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
const sdkNoLicense = <String>{
  'flutter',
  'flutter_test',
  'flutter_localizations',
  'flutter_web_plugins',
  'flutter_driver',
  // Pulled in transitively by flutter_driver/flutter_test; lives under
  // `<flutter>/packages/` and carries no LICENSE of its own.
  'fuchsia_remote_debug_protocol',
  'integration_test',
  'sky_engine',
};

/// Filenames to look for when locating a package's licence text.
const _licenseFileNames = <String>[
  'LICENSE',
  'LICENSE.md',
  'LICENSE.txt',
  'COPYING',
  'license',
];

/// Classify the SPDX-ish licence family from raw licence [text].
///
/// Returns a short identifier (e.g. `MIT`, `BSD-3-Clause`, `Apache-2.0`) or
/// `UNKNOWN` when nothing matches. Order matters: reciprocal licences that
/// *reference* the GNU family in their compatibility clauses are matched before
/// the GNU keywords to avoid false positives.
String classifyLicense(String text) {
  final t = text.toLowerCase();
  if (t.contains('european union public licence') ||
      t.contains('european union public license')) {
    return 'EUPL-1.2';
  }
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

/// The first licence file found in [root], or null if the package ships none.
File? findLicenseFile(Directory root) {
  for (final name in _licenseFileNames) {
    final f = File('${root.path}/$name');
    if (f.existsSync()) return f;
  }
  return null;
}

/// The licence family for a resolved package named [name] rooted at [root].
///
/// `ocideck` is the project itself (EUPL-1.2). A Flutter-SDK package without a
/// licence file is reported as covered by the SDK licence; any other package
/// without one is `NO LICENSE FILE` so the caller can flag it.
String licenseForPackage(String name, Directory root) {
  if (name == 'ocideck') return 'EUPL-1.2';
  final lic = findLicenseFile(root);
  if (lic == null) {
    return sdkNoLicense.contains(name)
        ? 'BSD-3-Clause (Flutter SDK)'
        : 'NO LICENSE FILE';
  }
  final txt = lic.readAsStringSync();
  return classifyLicense(txt.length > 6000 ? txt.substring(0, 6000) : txt);
}

/// The leading family token of a classification string (drops any parenthetical
/// note such as `BSD-3-Clause (Flutter SDK)`), for membership tests against
/// [allowedLicenses].
String licenseFamily(String kind) => kind.split(' ').first;
