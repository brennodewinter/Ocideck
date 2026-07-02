// Security gate for the vendored JavaScript bundles that get inlined into the
// offline HTML export (marked, highlight.js, DOMPurify, mermaid, MathJax — see
// lib/services/marp_html_service.dart). Unlike Dart packages, these are checked
// into the repo by hand and are not covered by `flutter pub outdated`, so this
// tool is their dedicated safety net.
//
//   dart run tool/check_bundled_js.dart     (or: make deps-check)
//
// It does two independent things, both of which can fail the build:
//
//   1. Integrity (offline, deterministic): every file listed in
//      assets/web_export/MANIFEST.json must still hash to the recorded sha256.
//      Catches a bundle that was swapped, truncated, or edited without the
//      manifest (and therefore this review) being updated.
//
//   2. Known vulnerabilities (online): each pinned package@version is queried
//      against the OSV database (https://osv.dev). Any advisory fails the gate
//      so we learn a vendored bundle needs upgrading the moment a CVE lands —
//      not at the next manual audit.
//
// Exit codes:  0 = clean   1 = integrity mismatch or known vulnerability
//              2 = could not run the check (missing manifest / no network)
//
// Run it routinely (it is wired into `make deps-check` and CI). When it flags a
// vulnerability, upgrade the bundle, refresh its version + sha256 in
// MANIFEST.json, and update THIRD_PARTY_NOTICES.md in the same commit.

import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

const _manifestPath = 'assets/web_export/MANIFEST.json';
const _assetDir = 'assets/web_export';
const _osvUrl = 'https://api.osv.dev/v1/query';

Future<void> main(List<String> args) async {
  final offline = args.contains('--offline');

  final manifestFile = File(_manifestPath);
  if (!manifestFile.existsSync()) {
    stderr.writeln('No $_manifestPath — cannot check the bundled JS.');
    exit(2);
  }

  final manifest =
      jsonDecode(manifestFile.readAsStringSync()) as Map<String, dynamic>;
  final ecosystem = (manifest['ecosystem'] as String?) ?? 'npm';
  final bundles = (manifest['bundles'] as List).cast<Map<String, dynamic>>();

  stdout.writeln('== OciDeck check: bundled JavaScript ==');
  stdout.writeln('Manifest: $_manifestPath  (${bundles.length} bundles)\n');

  final integrityProblems = <String>[];
  final vulnProblems = <String>[];
  var networkFailed = false;

  for (final b in bundles) {
    final file = b['file'] as String;
    // A bundle without an `npm` package (e.g. a CSS theme file) is
    // integrity-only: hash-pinned here but not something OSV can query.
    final npm = b['npm'] as String?;
    final version = b['version'] as String?;
    final expected = (b['sha256'] as String).toLowerCase();
    final path = '$_assetDir/$file';

    // --- 1. Integrity -------------------------------------------------------
    final f = File(path);
    String integrity;
    if (!f.existsSync()) {
      integrity = 'MISSING FILE';
      integrityProblems.add('$file — file not found at $path');
    } else {
      final actual = sha256.convert(f.readAsBytesSync()).toString();
      if (actual == expected) {
        integrity = 'sha256 ok';
      } else {
        integrity = 'SHA256 MISMATCH';
        integrityProblems.add(
          '$file — sha256 differs from manifest\n'
          '      expected $expected\n'
          '      actual   $actual',
        );
      }
    }

    // --- 2. Known vulnerabilities (OSV) ------------------------------------
    String vulnStatus;
    if (npm == null || version == null) {
      vulnStatus = 'n/a (integrity-only, no npm package)';
    } else if (offline) {
      vulnStatus = 'skipped (--offline)';
    } else {
      final r = await _queryOsv(ecosystem, npm, version);
      if (r == null) {
        vulnStatus = 'OSV UNREACHABLE';
        networkFailed = true;
      } else if (r.isEmpty) {
        vulnStatus = 'no known CVEs';
      } else {
        vulnStatus = '${r.length} ADVISORY(IES): ${r.join(', ')}';
        vulnProblems.add('$npm@$version → ${r.join(', ')}');
      }
    }

    final label = npm == null ? file : '$npm@$version  ($file)';
    stdout.writeln('  $label');
    stdout.writeln('      integrity : $integrity');
    stdout.writeln('      osv       : $vulnStatus');
  }

  stdout.writeln('');

  if (integrityProblems.isEmpty && vulnProblems.isEmpty && !networkFailed) {
    stdout.writeln(
      'OK — all bundles match the manifest and have no known CVEs.',
    );
    exit(0);
  }

  if (integrityProblems.isNotEmpty) {
    stderr.writeln('INTEGRITY — ${integrityProblems.length} problem(s):');
    for (final p in integrityProblems) {
      stderr.writeln('  $p');
    }
    stderr.writeln(
      '  A mismatch means a bundle changed without MANIFEST.json being updated.\n'
      '  If the change was intentional, refresh the version + sha256 there.',
    );
  }

  if (vulnProblems.isNotEmpty) {
    stderr.writeln('\nVULNERABILITIES — ${vulnProblems.length} bundle(s):');
    for (final p in vulnProblems) {
      stderr.writeln('  $p');
    }
    stderr.writeln(
      '  Upgrade the bundle, then update MANIFEST.json + THIRD_PARTY_NOTICES.md.\n'
      '  Advisory detail: https://osv.dev/<ID>',
    );
  }

  if (integrityProblems.isNotEmpty || vulnProblems.isNotEmpty) exit(1);

  // Only network trouble, nothing actually wrong with the bundles.
  stderr.writeln(
    'COULD NOT VERIFY CVEs — OSV was unreachable. Integrity passed.\n'
    '  Re-run with network access, or `--offline` to check integrity only.',
  );
  exit(2);
}

/// Returns the list of OSV advisory IDs affecting [name]@[version], an empty
/// list if there are none, or null if the database could not be reached.
Future<List<String>?> _queryOsv(
  String ecosystem,
  String name,
  String version,
) async {
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 15);
  try {
    final req = await client.postUrl(Uri.parse(_osvUrl));
    req.headers.contentType = ContentType.json;
    req.write(
      jsonEncode({
        'package': {'name': name, 'ecosystem': ecosystem},
        'version': version,
      }),
    );
    final resp = await req.close().timeout(const Duration(seconds: 20));
    if (resp.statusCode != 200) return null;
    final body = await resp.transform(utf8.decoder).join();
    final data = jsonDecode(body) as Map<String, dynamic>;
    final vulns = (data['vulns'] as List?) ?? const [];
    return vulns
        .map((v) => (v as Map<String, dynamic>)['id'] as String)
        .toList();
  } on Object {
    return null;
  } finally {
    client.close(force: true);
  }
}
