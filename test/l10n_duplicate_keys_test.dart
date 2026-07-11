import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Guards every translation map (`lib/l10n/translations/*.dart`) against
/// **duplicate keys**. The `_strings*` and `_dutchSource*` maps are `const`, so a
/// real duplicate is a compile error today — but that safety net is (a) reported
/// as a diffuse analyzer error per map and (b) silently lost the moment a map
/// stops being `const` (a duplicate then just overwrites, dropping a translation
/// without a trace). Duplicates otherwise sneak in exactly where we keep hitting
/// them: merging two feature branches that each added the same Dutch source
/// string to all ~30 language files.
///
/// This test names the offending file, map and key directly. It parses Dart
/// string literals properly (respecting `\'` escapes) so a value that itself
/// contains `:` or `,` — e.g. a Klingon translation — is never mistaken for a
/// key.
void main() {
  test('no translation map has duplicate keys', () {
    final dir = Directory('lib/l10n/translations');
    final files =
        dir
            .listSync()
            .whereType<File>()
            .where((f) => f.path.endsWith('.dart'))
            .toList()
          ..sort((a, b) => a.path.compareTo(b.path));
    expect(files, isNotEmpty, reason: 'no translation files found');

    final problems = <String>[];
    for (final file in files) {
      final src = file.readAsStringSync();
      for (final block in _mapBlocks(src)) {
        final seen = <String>{};
        for (final key in _mapKeys(block.body)) {
          if (!seen.add(key)) {
            problems.add('${file.path}: ${block.name} has duplicate key $key');
          }
        }
      }
    }

    expect(
      problems,
      isEmpty,
      reason:
          'Duplicate translation keys (remove the redundant entry — this is the '
          'l10n merge-union collision):\n${problems.join('\n')}',
    );
  });

  group('key extraction is robust (self-test of the guard)', () {
    test('catches a duplicate; values with :/, are not read as keys', () {
      const body = r'''
      'a': 'x',
      'b': 'value: with, punctuation',
      'a': 'again',
      'c': '\'quoted\': tricky, value',
''';
      // Only the four real keys are extracted; the duplicate 'a' shows twice.
      expect(_mapKeys(body), ["'a'", "'b'", "'a'", "'c'"]);
      final seen = <String>{};
      final dups = _mapKeys(body).where((k) => !seen.add(k)).toList();
      expect(dups, ["'a'"]);
    });

    test('handles multi-line entries and escaped quotes in the value', () {
      // Mirrors the real tlh.dart shape: a Dutch key containing ": " whose
      // Klingon value (on the next line) also contains ": " and escaped quotes.
      const body = r'''
      'Veel tekst: verkleind tot ':
          '\'echletHomvamDaq mu\'ghom law\': value ',
      'ander': 'iets',
''';
      expect(_mapKeys(body), ["'Veel tekst: verkleind tot '", "'ander'"]);
    });
  });
}

class _MapBlock {
  _MapBlock(this.name, this.body);
  final String name;
  final String body;
}

final _mapStart = RegExp(r'(_\w+)\s*=\s*\{');

/// The body (between the braces) of every `const _name = { … }` map in [src].
Iterable<_MapBlock> _mapBlocks(String src) sync* {
  for (final match in _mapStart.allMatches(src)) {
    final open = match.end - 1; // the '{'
    final close = _matchingBrace(src, open);
    if (close > open) {
      yield _MapBlock(match.group(1)!, src.substring(open + 1, close));
    }
  }
}

/// Index of the `}` matching the `{` at [open], skipping over string literals
/// and line comments so a brace inside a translation is not miscounted.
int _matchingBrace(String s, int open) {
  var depth = 0;
  var i = open;
  while (i < s.length) {
    final c = s[i];
    if (c == "'" || c == '"') {
      i = _endOfString(s, i);
      continue;
    }
    if (c == '/' && i + 1 < s.length && s[i + 1] == '/') {
      final nl = s.indexOf('\n', i);
      i = nl < 0 ? s.length : nl;
      continue;
    }
    if (c == '{') {
      depth++;
    } else if (c == '}') {
      depth--;
      if (depth == 0) return i;
    }
    i++;
  }
  return -1;
}

/// The key literals of a map body. A key is the string literal that opens each
/// entry; the value (and any `:`/`,` inside it) is skipped until the next
/// top-level comma.
List<String> _mapKeys(String body) {
  final keys = <String>[];
  var i = 0;
  var expectKey = true;
  while (i < body.length) {
    final c = body[i];
    if (c == '/' && i + 1 < body.length && body[i + 1] == '/') {
      final nl = body.indexOf('\n', i);
      i = nl < 0 ? body.length : nl;
      continue;
    }
    if (c == "'" || c == '"') {
      final end = _endOfString(body, i);
      if (expectKey) {
        keys.add(body.substring(i, end));
        expectKey = false;
      }
      i = end;
      continue;
    }
    if (c == ',') expectKey = true;
    i++;
  }
  return keys;
}

/// Index just past the closing quote of the string literal starting at [start]
/// (whose char is the opening quote). Handles `\\`-escapes.
int _endOfString(String s, int start) {
  final quote = s[start];
  var i = start + 1;
  while (i < s.length) {
    final c = s[i];
    if (c == r'\') {
      i += 2;
      continue;
    }
    if (c == quote) return i + 1;
    i++;
  }
  return i;
}
