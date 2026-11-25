import 'dart:io';

import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/token.dart';

const _directional = [
  'EdgeInsetsDirectional',
  'AlignmentDirectional',
  'BorderDirectional',
];
const _physicalInsets = 'EdgeInsets.only(left: / right:)';
const _start = '<!-- BEGIN RTL INVENTORY -->';
const _end = '<!-- END RTL INVENTORY -->';

void main(List<String> args) {
  final write = args.contains('--write');
  final counts = {
    for (final type in _directional) type: 0,
    _physicalInsets: 0,
    'TextDirection': 0,
    'TextDirection.ltr': 0,
  };
  final relevant = RegExp(
    r'\b(?:EdgeInsets\w*|\w+Directional|TextDirection)\b',
  );
  for (final file in Directory(
    'lib',
  ).listSync(recursive: true).whereType<File>()) {
    if (!file.path.endsWith('.dart')) continue;
    final source = file.readAsStringSync();
    if (!relevant.hasMatch(source)) continue;
    final unit = parseString(content: source, path: file.path).unit;
    for (var token = unit.beginToken; !token.isEof; token = token.next!) {
      final name = token.lexeme;
      if (counts.containsKey(name)) counts[name] = counts[name]! + 1;
      if (name == 'TextDirection' &&
          token.next?.lexeme == '.' &&
          token.next?.next?.lexeme == 'ltr') {
        counts['TextDirection.ltr'] = counts['TextDirection.ltr']! + 1;
      }
      if (name == 'EdgeInsets' &&
          token.next?.lexeme == '.' &&
          token.next?.next?.lexeme == 'only' &&
          _hasPhysicalArgument(token.next?.next?.next)) {
        counts[_physicalInsets] = counts[_physicalInsets]! + 1;
      }
    }
  }

  for (final type in _directional) {
    if (counts[type] == 0) continue;
    stderr.writeln('$type komt ${counts[type]} keer voor. De lay-out is LTR.');
    exitCode = 1;
  }

  final block = RegExp('^$_start\$[\\s\\S]*?^$_end\$', multiLine: true);
  for (final (path, heading) in [
    ('docs/ACCESSIBILITY.md', '| Dart source | Occurrences |'),
    ('docs/ACCESSIBILITY.nl.md', '| Dart-broncode | Aantal |'),
  ]) {
    final file = File(path);
    final source = file.readAsStringSync();
    final matches = block.allMatches(source).toList();
    if (matches.length != 1) {
      stderr.writeln('$path moet precies één RTL-inventaris bevatten.');
      exitCode = 1;
      continue;
    }
    final expected = [
      _start,
      '',
      heading,
      '| --- | ---: |',
      for (final entry in counts.entries) '| `${entry.key}` | ${entry.value} |',
      '',
      _end,
    ].join('\n');
    if (matches.single.group(0) == expected) continue;
    if (write) {
      file.writeAsStringSync(source.replaceFirst(block, expected));
      stdout.writeln('$path bijgewerkt.');
    } else {
      stderr.writeln('$path: inventaris wijkt af. Draai $script --write.');
      exitCode = 1;
    }
  }
  if (exitCode == 0) stdout.writeln('RTL-inventaris komt overeen met lib/.');
}

const script = 'dart run tool/check_rtl_inventory.dart';

bool _hasPhysicalArgument(Token? opening) {
  if (opening?.lexeme != '(') return false;
  final closing = opening!.endGroup;
  for (
    var token = opening.next;
    token != null && !token.isEof && token != closing;
    token = (token.endGroup ?? token).next
  ) {
    if ((token.lexeme == 'left' || token.lexeme == 'right') &&
        (token.previous == opening || token.previous?.lexeme == ',') &&
        token.next?.lexeme == ':') {
      return true;
    }
  }
  return false;
}
