// Build-time assembler for the Informatieveiligheid module data pack
// (PENTEST_MIAUW.md §6).
//
//   dart run tool/build_secmodule_pack.dart
//
// Assembles the reference datasets into pre-normalised JSON, writes an inner
// MANIFEST.json (per-file sha256 + upstream version + licence + source —
// mirroring assets/web_export/MANIFEST.json), zips it deterministically, writes
// the pack, and PRINTS the outer sha256 to pin into the app
// (lib/services/secmodule/sec_pack_config.dart → `secPackSha256`).
//
// SKELETON STATUS: this packages a MINIMAL PLACEHOLDER dataset so the mechanism
// is verifiable end-to-end. The real CWE 4.20 / WSTG / CVSS 4.0 lookup / MIAUW
// 92-EIS content is wired in by later steps — swap [_datasets] for the real
// normalisers then, rebuild, and re-pin the printed hash + committed fixture in
// the same commit.
//
// The pack is BUNDLED with the app (declared under `assets/secmodule/` in
// pubspec.yaml) so the Informatieveiligheid module provisions from it offline,
// with no mirror and no outbound traffic — the provisioner verifies the bundled
// bytes against the pinned hash exactly like a manual import. Rebuild + re-pin
// the printed hash here in the same commit whenever the datasets change.

import 'dart:convert';
import 'dart:io';

import 'package:ocideck/services/secmodule/sec_pack_codec.dart';
import 'package:ocideck/services/secmodule/sec_pack_config.dart';

/// Where the built pack is written — the bundled app asset (see pubspec.yaml).
const _outDir = 'assets/secmodule';

void main(List<String> args) {
  final version = secPackVersion;
  final files = _datasets(version);
  final packBytes = buildSecPack(packVersion: version, files: files);
  final outerHash = secPackSha256Hex(packBytes);

  final outPath = '$_outDir/secmodule_pack_$version.zip';
  Directory(_outDir).createSync(recursive: true);
  File(outPath).writeAsBytesSync(packBytes, flush: true);

  stdout.writeln('== OciDeck build: Informatieveiligheid module data pack ==');
  stdout.writeln('pack version : $version');
  stdout.writeln('files        : ${files.length} + MANIFEST.json');
  stdout.writeln('bytes        : ${packBytes.length}');
  stdout.writeln('written      : $outPath');
  stdout.writeln('');
  stdout.writeln('outer sha256 : $outerHash');
  stdout.writeln('');
  if (outerHash == secPackSha256) {
    stdout.writeln(
      'OK — matches the pinned secPackSha256 in sec_pack_config.dart.',
    );
  } else {
    stdout.writeln(
      'Pin this in lib/services/secmodule/sec_pack_config.dart:\n'
      "  const secPackSha256 = '$outerHash';\n"
      'and commit the regenerated fixture in the same commit.',
    );
  }
}

/// Minimal placeholder datasets, each carrying its upstream version + licence
/// (PENTEST_MIAUW.md §15) so the compliance appendix stays accurate. Content is
/// fixed so the pack bytes — and therefore the outer sha256 — are reproducible.
List<SecPackDataFile> _datasets(String version) {
  SecPackDataFile file(
    String name,
    Object? json, {
    required String upstreamVersion,
    required String licence,
    required String source,
  }) {
    final bytes = utf8.encode(const JsonEncoder.withIndent('  ').convert(json));
    return SecPackDataFile(
      name: name,
      bytes: bytes,
      upstreamVersion: upstreamVersion,
      licence: licence,
      source: source,
    );
  }

  return [
    file(
      'cwe/cwe.json',
      {
        '_note': 'PLACEHOLDER — real MITRE CWE 4.20 list wired in later (P3).',
        'weaknesses': [
          {
            'id': 'CWE-89',
            'name': 'Improper Neutralization of SQL',
            'url': 'https://cwe.mitre.org/data/definitions/89.html',
          },
        ],
      },
      upstreamVersion: 'CWE 4.20 (placeholder)',
      licence: 'MITRE Terms of Use',
      source: 'https://cwe.mitre.org/',
    ),
    file(
      'wstg/wstg.json',
      {
        '_note':
            'PLACEHOLDER — real OWASP WSTG stable checklist wired in later.',
        'categories': [
          {
            'id': 'WSTG-ATHN',
            'tests': [
              {
                'id': 'WSTG-ATHN-07',
                'title': 'Testing for Weak Password Policy',
              },
            ],
          },
        ],
      },
      upstreamVersion: 'WSTG stable (placeholder)',
      licence: 'CC-BY-SA-4.0',
      source: 'https://owasp.org/www-project-web-security-testing-guide/',
    ),
    file(
      'cvss/cvss_lookup.json',
      {
        '_note':
            'PLACEHOLDER — real CVSS 4.0 MacroVector lookup wired in later.',
        'lookup': {'000000000000': 10.0},
      },
      upstreamVersion: 'CVSS 4.0 (placeholder)',
      licence: 'FIRST.Org attribution',
      source: 'https://www.first.org/cvss/',
    ),
    file(
      'miauw/schema.json',
      {
        '_note': 'PLACEHOLDER — real MIAUW 92-EIS schema wired in later.',
        'requirements': [
          {'id': '1.1', 'title': 'Digitale aanlevering + hash'},
        ],
      },
      upstreamVersion: 'MIAUW 1.00 (placeholder)',
      licence: 'EUPL-1.2',
      source:
          'https://github.com/brennodewinter/Informatiebeveiligingsonderzoek',
    ),
  ];
}
