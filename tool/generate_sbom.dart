// Generates OciDeck's Software Bill of Materials in two commonly used,
// machine-readable formats — CycloneDX 1.6 JSON and SPDX 2.3 JSON — covering
// every shipped component (Dart/Flutter packages direct + transitive, vendored
// JS/CSS export bundles, vendored plugin forks, bundled fonts, and the pinned
// build SDKs). This is the artefact the EU Cyber Resilience Act (Regulation
// (EU) 2024/2847), Annex I, Part II §1, requires manufacturers to draw up.
//
//   dart run tool/generate_sbom.dart            (or: make sbom)
//       Regenerate sbom/ocideck.cdx.json and sbom/ocideck.spdx.json.
//
//   dart run tool/generate_sbom.dart --check    (or: make sbom-verify)
//       Do NOT write. Compare a freshly generated SBOM (with the volatile
//       timestamp/serial fields normalised out) against the committed files and
//       exit non-zero if they drifted — i.e. dependencies changed but the SBOM
//       was not regenerated. Wired into CI so the SBOM can never go stale.
//
// The inventory is derived entirely from files already under version control
// (pubspec.lock, MANIFEST.json, pubspec.yaml, .tool-versions); see
// tool/lib/sbom_build.dart. Run `flutter pub get` first so the resolved package
// graph and licences are available.
//
// Exit codes:  0 = written / up to date   1 = drift (in --check)   2 = setup error

import 'dart:io';

import 'sbom_build.dart';

Future<void> main(List<String> args) async {
  final check = args.contains('--check');

  final Inventory inv;
  try {
    inv = buildInventory();
  } on StateError catch (e) {
    stderr.writeln(e.message);
    exit(2);
  }

  final timestamp = DateTime.now().toUtc().toIso8601String();
  final cdx = toCycloneDx(inv, timestamp);
  final spdx = toSpdx(inv, timestamp);
  final md = toMarkdown(inv);

  if (check) {
    _verify(cdx, spdx, md);
    return;
  }

  Directory('sbom').createSync(recursive: true);
  File(cdxOutputPath).writeAsStringSync('$cdx\n');
  File(spdxOutputPath).writeAsStringSync('$spdx\n');
  File(mdOutputPath).writeAsStringSync('$md\n');

  stdout.writeln('Wrote SBOM (${inv.all.length} components):');
  stdout.writeln('  $cdxOutputPath   (CycloneDX 1.6)');
  stdout.writeln('  $spdxOutputPath  (SPDX 2.3)');
  stdout.writeln('  $mdOutputPath   (human-readable)');
  _summary(inv);
}

/// Compare freshly generated SBOMs against the committed files, ignoring the
/// volatile timestamp/serial fields. Exits 1 on any drift.
void _verify(String cdx, String spdx, String md) {
  final drift = <String>[];
  _compare(cdxOutputPath, cdx, stripVolatileCdx, drift);
  _compare(spdxOutputPath, spdx, stripVolatileSpdx, drift);
  _compare(mdOutputPath, '$md\n', (s) => s, drift);

  if (drift.isEmpty) {
    stdout.writeln(
      'SBOM up to date — $cdxOutputPath, $spdxOutputPath and $mdOutputPath '
      'match the current dependency set.',
    );
    exit(0);
  }

  stderr.writeln('SBOM OUT OF DATE:');
  for (final d in drift) {
    stderr.writeln('  - $d');
  }
  stderr.writeln(
    '\nDependencies changed but the SBOM was not regenerated. '
    'Run `make sbom` and commit the result.',
  );
  exit(1);
}

void _compare(
  String path,
  String fresh,
  String Function(String) strip,
  List<String> drift,
) {
  final file = File(path);
  if (!file.existsSync()) {
    drift.add('$path is missing — run `make sbom`.');
    return;
  }
  if (strip(file.readAsStringSync()) != strip(fresh)) {
    drift.add('$path differs from the current dependency set.');
  }
}

void _summary(Inventory inv) {
  final byGroup = <String, int>{};
  for (final c in inv.components) {
    byGroup[c.group] = (byGroup[c.group] ?? 0) + 1;
  }
  final keys = byGroup.keys.toList()..sort();
  stdout.writeln('Components by group:');
  for (final k in keys) {
    stdout.writeln('  ${byGroup[k].toString().padLeft(4)}  $k');
  }
}
