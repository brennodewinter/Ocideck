import 'dart:io';

import 'package:yaml/yaml.dart';

const _start = '<!-- BEGIN PAWPRINT WORKFLOW TRIGGERS -->';
const _end = '<!-- END PAWPRINT WORKFLOW TRIGGERS -->';

/// Geeft true terug wanneer de gedocumenteerde trekkers afwijken.
bool checkWorkflowTriggers({bool write = false}) {
  final doc = File('docs/CHECKS.md');
  final source = doc.readAsStringSync();
  final block = RegExp('^$_start\$[\\s\\S]*?^$_end\$', multiLine: true);
  final matches = block.allMatches(source).toList();
  if (matches.length != 1) {
    stderr.writeln('${doc.path}: verwacht precies één Pawprint-workflowtabel.');
    return true;
  }
  final workflows =
      Directory('.forgejo/workflows')
          .listSync()
          .whereType<File>()
          .where((file) => RegExp(r'\.ya?ml$').hasMatch(file.path))
          .toList()
        ..sort((a, b) => a.path.compareTo(b.path));
  final expected = [
    _start,
    '',
    '| Workflow | Trigger on Pawprint | When it runs |',
    '| --- | --- | --- |',
    for (final file in workflows) ..._rows(file),
    '',
    _end,
  ].join('\n');
  if (matches.single.group(0) == expected) return false;
  if (write) {
    doc.writeAsStringSync(source.replaceFirst(block, expected));
    return false;
  }
  stderr.writeln(
    '${doc.path}: workflowtrekkers wijken af. '
    'Draai dart run tool/check_dated_claims.dart --write-workflows '
    'en controleer de borgingstekst.',
  );
  return true;
}

Iterable<String> _rows(File file) sync* {
  final workflow = loadYaml(file.readAsStringSync()) as YamlMap;
  final triggers = switch (workflow['on']) {
    final YamlMap events => Map<Object?, Object?>.from(events),
    final YamlList events => {for (final event in events) event: null},
    final String event => {event: null},
    _ => throw FormatException('Geen geldige trekkers in ${file.path}'),
  };
  final name = file.uri.pathSegments.last;
  for (final MapEntry(:key, :value) in triggers.entries) {
    final filters = value is YamlMap
        ? [
            for (final name in [
              'branches',
              'branches-ignore',
              'tags',
              'tags-ignore',
              'types',
              'paths',
              'paths-ignore',
            ])
              if (value[name] case final YamlList items)
                '`$name` ${items.map((item) => '`$item`').join(', ')}',
          ]
        : [
            if (key == 'schedule' && value is YamlList)
              for (final entry in value)
                if (entry is YamlMap && entry['cron'] != null)
                  '`${entry['cron']}`',
          ];
    final trigger = ['`$key`', ...filters].join(' · ');
    final moment = switch (key) {
      'pull_request' || 'pull_request_target' => 'Automatic before merge',
      'push'
          when value is YamlMap &&
              value['branches'] is YamlList &&
              (value['branches'] as YamlList).length == 1 &&
              (value['branches'] as YamlList).single == 'main' &&
              !value.containsKey('tags') =>
        'Automatic on push to main',
      'push' => 'Automatic on matching push',
      'schedule' => 'Automatic on the default branch, on schedule',
      'workflow_dispatch' => 'On demand',
      _ => 'Automatic on event',
    };
    yield '| [`$name`](../.forgejo/workflows/$name) | $trigger | $moment |';
  }
}
