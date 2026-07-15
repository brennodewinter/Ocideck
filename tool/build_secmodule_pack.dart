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
// STATUS: this packages the REAL datasets from their in-repo sources of truth —
// CWE 4.20, OWASP WSTG v4.2, FIRST CVSS 4.0 MacroVector, and the full MIAUW
// 88-EIS schema (parsed from the authoritative workbook). Rebuild + re-pin the
// printed hash + the committed fixture in the same commit whenever the datasets
// change.
//
// The pack is BUNDLED with the app (declared under `assets/secmodule/` in
// pubspec.yaml) so the Informatieveiligheid module provisions from it offline,
// with no mirror and no outbound traffic — the provisioner verifies the bundled
// bytes against the pinned hash exactly like a manual import.

import 'dart:convert';
import 'dart:io';

import 'package:ocideck/models/eis_entry.dart';
import 'package:ocideck/services/cvss/cvss4.dart';
import 'package:ocideck/services/miauw_eis_catalog.dart';
import 'package:ocideck/services/secmodule/sec_pack_codec.dart';
import 'package:ocideck/services/secmodule/sec_pack_config.dart';
import 'package:ocideck/services/wstg_catalog.dart';

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

/// The bundled reference datasets, each carrying its upstream version + licence
/// (PENTEST_MIAUW.md §15) so the compliance appendix stays accurate. Content is
/// derived deterministically from the in-repo sources of truth so the pack bytes
/// — and therefore the outer sha256 — are reproducible.
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
      _cweDataset(),
      upstreamVersion: 'CWE 4.20',
      licence: 'MITRE Terms of Use',
      source: 'https://cwe.mitre.org/',
    ),
    file(
      'wstg/wstg.json',
      _wstgDataset(),
      upstreamVersion: 'WSTG $wstgVersion',
      licence: 'CC-BY-SA-4.0',
      source: 'https://owasp.org/www-project-web-security-testing-guide/',
    ),
    file(
      'cvss/cvss_lookup.json',
      _cvssDataset(),
      upstreamVersion: 'CVSS 4.0',
      licence: 'BSD-2-Clause',
      source: 'https://www.first.org/cvss/',
    ),
    file(
      'miauw/schema.json',
      _miauwDataset(),
      upstreamVersion: 'MIAUW 1.00',
      licence: 'EUPL-1.2',
      source:
          'https://github.com/brennodewinter/Informatiebeveiligingsonderzoek',
    ),
  ];
}

/// The MIAUW compliance schema, serialised from the in-repo [MiauwEisCatalog]
/// (parsed from the authoritative workbook).
Object _miauwDataset() => {
  'schemaSize': kMiauwFullSchemaSize,
  'eis': [
    for (final e in MiauwEisCatalog.instance.entries)
      {
        'id': e.id,
        'part': e.part.name,
        'title': e.title,
        'derivation': e.derivation.name,
        if (e.check != null) 'check': e.check!.name,
      },
  ],
};

/// The full MITRE CWE list, read from the bundled asset (the same source
/// [CweCatalog] loads at runtime), normalised to `{id, name, description}`.
Object _cweDataset() {
  final raw = File('assets/cwe/cwe_full.json').readAsStringSync();
  final list = (jsonDecode(raw) as List).cast<Map<String, dynamic>>();
  return [
    for (final m in list)
      {
        'id': (m['id'] as num).toInt(),
        'name': (m['name'] as String?) ?? '',
        'description': (m['description'] as String?) ?? '',
      },
  ];
}

/// The OWASP WSTG v4.2 checklist, serialised from the in-repo [WstgCatalog].
Object _wstgDataset() => {
  'version': wstgVersion,
  'tests': [
    for (final t in WstgCatalog.instance.tests)
      {'id': t.id, 'title': t.title, 'category': t.category},
  ],
};

/// The FIRST CVSS 4.0 MacroVector→score lookup, from the in-repo [cvss4LookupTable].
Object _cvssDataset() => {'lookup': cvss4LookupTable};
