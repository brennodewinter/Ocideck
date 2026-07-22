import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Holds `docs/SOURCE_MAP.md` against the tree it claims to index.
///
/// The map used to promise a line per file under `lib/` while 156 files had
/// none, and twenty-four files had two or three lines with different
/// descriptions — parallel branches enriching the same entry, the merge keeping
/// both copies. A silently partial map is worse than one that says what it
/// covers, so the claim was narrowed (see § *What this map covers*) and is
/// checked here. The rules mirror that section one for one; changing one means
/// changing both.
void main() {
  const mapPath = 'docs/SOURCE_MAP.md';

  // A `part` file has no entry of its own to promise: it is covered by the
  // library it belongs to.
  final partOf = RegExp(r'^part of ', multiLine: true);

  // The platform halves of one conditional-import subject. Describing each half
  // separately from its selector would say the same thing three times.
  const halfSuffixes = ['_io', '_web', '_stub', '_factory', '_api'];

  /// The section heading a group of entries sits under decides what directory a
  /// bare filename in that group resolves to.
  final headingLine = RegExp(r'^#{2,3}\s');
  final headingDir = RegExp(r'`(lib/[^`]*)`');

  /// An entry is a list item that *starts* with a backticked `.dart` path.
  /// Files named inside the prose of another entry are cross-references, not
  /// claims, so they deliberately do not count.
  final entryLine = RegExp(r'^- `([^`]+\.dart)`');

  late final List<String> mapLines;
  late final Map<String, List<int>> entries; // path -> 1-based line numbers
  late final Map<String, int> groups; // glob -> 1-based line number
  late final List<String> libFiles;

  setUpAll(() {
    mapLines = File(mapPath).readAsLinesSync();
    entries = {};
    groups = {};
    var dir = 'lib/';
    for (var i = 0; i < mapLines.length; i++) {
      final line = mapLines[i];
      if (headingLine.hasMatch(line)) {
        final m = headingDir.firstMatch(line);
        dir = m == null ? 'lib/' : m.group(1)!;
        if (!dir.endsWith('/')) dir = '$dir/';
        continue;
      }
      final m = entryLine.firstMatch(line);
      if (m == null) continue;
      final raw = m.group(1)!;
      final path = raw.startsWith('lib/') ? raw : '$dir$raw';
      if (path.contains('*')) {
        groups[path] = i + 1;
      } else {
        entries.putIfAbsent(path, () => []).add(i + 1);
      }
    }

    libFiles =
        Directory('lib')
            .listSync(recursive: true)
            .whereType<File>()
            .map((f) => f.path.replaceAll('\\', '/'))
            .where((p) => p.endsWith('.dart'))
            .toList()
          ..sort();
  });

  bool matchesGroup(String path) => groups.keys.any((glob) {
    final pattern = RegExp(
      '^${RegExp.escape(glob).replaceAll(r'\*', '[^/]*')}\$',
    );
    return pattern.hasMatch(path);
  });

  /// `x_io.dart` is covered by the entry for `x.dart` — or, where the contract
  /// itself is the `_api` file and there is no plain `x.dart`, by that.
  bool coveredByFacade(String path) {
    final dir = path.substring(0, path.lastIndexOf('/') + 1);
    final name = path.substring(dir.length, path.length - '.dart'.length);
    for (final suffix in halfSuffixes) {
      if (!name.endsWith(suffix)) continue;
      final stem = name.substring(0, name.length - suffix.length);
      if (stem.isEmpty) continue;
      if (entries.containsKey('$dir$stem.dart')) return true;
      if (entries.containsKey('$dir${stem}_api.dart')) return true;
    }
    return false;
  }

  test('every library under lib/ has a line in the source map', () {
    final missing = <String>[];
    for (final path in libFiles) {
      if (entries.containsKey(path)) continue;
      if (partOf.hasMatch(File(path).readAsStringSync())) continue;
      if (matchesGroup(path)) continue;
      if (coveredByFacade(path)) continue;
      missing.add(path);
    }
    expect(
      missing,
      isEmpty,
      reason:
          'These libraries have no line in $mapPath. Add one (a short line '
          'saying what the file is for), or — if it belongs to a uniform '
          'family — cover it with a declared group glob:\n'
          '${missing.join('\n')}',
    );
  });

  test('no file is described twice', () {
    final doubled = [
      for (final e in entries.entries)
        if (e.value.length > 1) '${e.key} (lines ${e.value.join(', ')})',
    ]..sort();
    expect(
      doubled,
      isEmpty,
      reason:
          'These files have more than one line in $mapPath. Two descriptions '
          'of one file leave the reader without a way to tell which one holds '
          '— keep the one that describes the code of today:\n'
          '${doubled.join('\n')}',
    );
  });

  test('no line points at a file that is gone', () {
    final stale = [
      for (final e in entries.entries)
        if (!File(e.key).existsSync()) '${e.key} (line ${e.value.first})',
    ]..sort();
    expect(
      stale,
      isEmpty,
      reason:
          'These lines in $mapPath name a file that does not exist. A renamed '
          'or removed file takes its line with it:\n${stale.join('\n')}',
    );
  });

  test('every declared group still matches files', () {
    final empty = [
      for (final g in groups.entries)
        if (!libFiles.any((f) {
          final pattern = RegExp(
            '^${RegExp.escape(g.key).replaceAll(r'\*', '[^/]*')}\$',
          );
          return pattern.hasMatch(f);
        }))
          '${g.key} (line ${g.value})',
    ]..sort();
    expect(
      empty,
      isEmpty,
      reason:
          'These group globs in $mapPath match no file at all. A group that '
          'outlives its family hides the next gap:\n${empty.join('\n')}',
    );
  });
}
