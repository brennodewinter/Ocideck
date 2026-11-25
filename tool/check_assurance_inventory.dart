import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

const _scope = 'assurance/ASVS-5.0.0-scope.md';
const _model = 'docs/SECURITY_DESIGN.md';
const _dated = [
  _scope,
  'assurance/ASVS-5.0.0-afwijkingen.md',
  'assurance/risicoafweging.md',
];

/// Signaleert gewijzigde modules, netwerksinks en verlopen dossierherzieningen.
bool checkAssuranceInventory({
  required DateTime now,
  bool write = false,
  bool checkAge = false,
}) {
  final modules = Directory('lib/services').listSync().where(
    (entry) =>
        entry is Directory ||
        (entry is File &&
            entry.path.endsWith('.dart') &&
            !entry.path.endsWith('.g.dart') &&
            !RegExp(
              r'^part of ',
              multiLine: true,
            ).hasMatch(entry.readAsStringSync())),
  );
  final sinks = <String>[
    ...RegExp(r"'(lib/[^']+\.dart)'")
        .allMatches(
          File('test/network_sink_guard_test.dart').readAsStringSync(),
        )
        .map((match) => 'allow:${match.group(1)}')
        .toSet(),
  ];
  final client = RegExp(r'\bHttpClient\s*\(');
  for (final file in Directory(
    'lib',
  ).listSync(recursive: true).whereType<File>()) {
    if (!file.path.endsWith('.dart')) continue;
    final code = file.readAsStringSync().replaceAll(
      RegExp(r'^\s*//[^\n]*', multiLine: true),
      '',
    );
    final count = client.allMatches(code).length;
    if (count > 0) sinks.add('${file.path.replaceAll(r'\', '/')}:$count');
  }
  final scopeMatches = _check(
    _scope,
    'service-modules',
    modules.map((entry) => entry.path.replaceAll(r'\', '/')),
    write,
  );
  final modelMatches = _check(_model, 'network-sinks', sinks, write);
  var current = true;
  if (checkAge) {
    for (final path in _dated) {
      final status = RegExp(
        r'^> \*\*Herzien:\*\* (\d{4}-\d{2}-\d{2})',
        multiLine: true,
      ).firstMatch(File(path).readAsStringSync());
      final reviewed = DateTime.tryParse(status?.group(1) ?? '');
      if (reviewed == null || now.difference(reviewed).inDays > 180) {
        stderr.writeln(
          '$path: dossierherziening ontbreekt of is ouder dan 180 dagen.',
        );
        current = false;
      }
    }
  }
  return !(scopeMatches && modelMatches && current);
}

bool _check(String path, String name, Iterable<String> entries, bool write) {
  final sorted = entries.toList()..sort();
  final hash = sha256.convert(utf8.encode(sorted.join('\n')));
  final expected = '<!-- assurance-inventory $name: ${sorted.length} $hash -->';
  final pattern = RegExp(
    '^<!-- assurance-inventory $name: .* -->\$',
    multiLine: true,
  );
  final file = File(path);
  final source = file.readAsStringSync();
  final matches = pattern.allMatches(source).toList();
  if (matches.length != 1) {
    stderr.writeln('$path: verwacht precies één inventaris voor $name.');
    return false;
  }
  if (matches.single.group(0) == expected) return true;
  if (write) {
    file.writeAsStringSync(source.replaceFirst(pattern, expected));
    return true;
  }
  stderr.writeln(
    '$path: $name is gewijzigd. Herzie de grens en werk de inventaris bij met '
    'dart run tool/check_dated_claims.dart --write-assurance-inventory.',
  );
  return false;
}
