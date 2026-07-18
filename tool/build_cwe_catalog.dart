// Generates the offline full-CWE dataset `assets/cwe/cwe_full.json` from MITRE's
// published CWE list, so the finding editor's CWE picker can find every weakness
// (not only the curated 40-entry offline floor in lib/services/cwe_catalog.dart).
//
// Input: the "Comprehensive" CWE CSV from cwe.mitre.org
//   curl -fsSL https://cwe.mitre.org/data/csv/2000.csv.zip -o cwe.zip && unzip cwe.zip
// then:
//   dart run tool/build_cwe_catalog.dart 2000.csv
//
// Output is one compact JSON object per line (`[{"id":..,"name":..,
// "description":..}, …]`), so a regenerated list diffs one row per CWE. The
// dataset is bundled (no runtime network); every entry still links back to
// cwe.mitre.org via CweEntry.url.
import 'dart:convert';
import 'dart:io';

import 'package:ocideck/utils/csv.dart';

void main(List<String> args) {
  if (args.isEmpty) {
    stderr.writeln('usage: dart run tool/build_cwe_catalog.dart <cwe.csv>');
    exit(2);
  }
  final rows = parseCsvRows(File(args.first).readAsStringSync());
  if (rows.isEmpty) {
    stderr.writeln('empty CSV');
    exit(1);
  }
  final header = rows.first;
  final idI = header.indexOf('CWE-ID');
  final nameI = header.indexOf('Name');
  final descI = header.indexOf('Description');
  if (idI < 0 || nameI < 0 || descI < 0) {
    stderr.writeln('missing expected columns (CWE-ID/Name/Description)');
    exit(1);
  }

  final entries = <Map<String, Object>>[];
  for (final r in rows.skip(1)) {
    if (r.length <= descI) continue;
    final id = int.tryParse(r[idI].trim());
    final name = _clean(r[nameI]);
    if (id == null || name.isEmpty) continue;
    entries.add({'id': id, 'name': name, 'description': _clean(r[descI])});
  }
  entries.sort((a, b) => (a['id'] as int).compareTo(b['id'] as int));

  final out = File('assets/cwe/cwe_full.json');
  out.parent.createSync(recursive: true);
  final buf = StringBuffer('[\n');
  for (var i = 0; i < entries.length; i++) {
    buf.write('  ');
    buf.write(jsonEncode(entries[i]));
    buf.write(i == entries.length - 1 ? '\n' : ',\n');
  }
  buf.write(']\n');
  out.writeAsStringSync(buf.toString());
  stdout.writeln('Wrote ${entries.length} CWE entries to ${out.path}');
}

/// Collapse runs of whitespace (the CSV has newlines inside quoted fields).
String _clean(String s) => s.replaceAll(RegExp(r'\s+'), ' ').trim();
