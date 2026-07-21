// Guards against dead (orphaned) Dart files in lib/.
//
// The Dart analyzer already fails the build (via `flutter analyze
// --fatal-infos`) on unreachable statements, unused imports/locals/fields and
// unused *private* elements. Its blind spot is whole files and public symbols
// it can't see across libraries: a `.dart` file that no longer imports anywhere
// stays green forever. This is where dead code actually accumulates — a file is
// detached but left behind.
//
// This check builds the static import graph of lib/ and walks it from the real
// entrypoint(s) (any file with a top-level `main(`). Every file reachable via
// `import` / `export` / `part` — including BOTH branches of a conditional
// (`import 'x.dart' if (dart.library.io) 'y.dart'`) — is alive. Anything left
// over is dead: exit non-zero with the offending paths.
//
// Direction of safety: an unparsed or comment URI can only ADD an edge (mark a
// file alive), so the check errs toward missing a dead file, never toward
// failing CI on a live one.
//
// A file that is reachable only through a mechanism this static walk can't see
// (a deliberate dynamic entrypoint) goes in [deadCodeAllowlist] with a reason.

import 'dart:io';

/// Files to treat as alive regardless of the import graph — deliberate dynamic
/// entrypoints the static walk can't follow. Add an entry only with a reason;
/// the goal is to keep this empty. Paths are lib-relative, forward-slash.
const Set<String> deadCodeAllowlist = {
  // Empty on purpose — keep it that way. An entry here is a promise that the
  // file is reached by a mechanism the static walk cannot follow; it is not a
  // parking spot for "not wired up yet". `services/cvss/cvss4.dart` sat here
  // from the day the CVSS 4.0 engine shipped ahead of its consumer, and stayed
  // long after the finding wizard, the severity palette and the audit dossier
  // started importing it — an exemption that outlives its reason hides the
  // very thing this check exists to see.
};

/// Matches a whole `import` / `export` / `part` directive up to its `;`. The
/// body may span lines (multi-line conditional imports), so it runs over the
/// full source with `[^;]` spanning newlines. `part of` is filtered out below —
/// it points back at a parent, it doesn't pull a file in.
final _directive = RegExp(
  r'''^[ \t]*(import|export|part)\b([^;]*);''',
  multiLine: true,
);

/// Every quoted URI inside a directive body — the base plus each conditional
/// alternative all count as edges.
final _uri = RegExp('''['"]([^'"]+)['"]''');

/// A top-level entrypoint: `void main(` or `Future<void> main(` at line start.
final _mainFn = RegExp(
  r'''^(void|Future<void>|Future)\s+main\s*\(''',
  multiLine: true,
);

void main() {
  final files = _dartFiles(Directory('lib')).map((f) => _norm(f.path)).toSet();

  final edges = <String, Set<String>>{};
  final roots = <String>{};

  for (final path in files) {
    final source = File(path).readAsStringSync();
    if (_mainFn.hasMatch(source)) roots.add(path);

    final targets = <String>{};
    for (final m in _directive.allMatches(source)) {
      final keyword = m.group(1)!;
      final body = m.group(2)!;
      // `part of <parent>` is a back-reference, not an edge.
      if (keyword == 'part' && body.trimLeft().startsWith('of')) continue;
      for (final u in _uri.allMatches(body)) {
        final resolved = _resolve(u.group(1)!, path);
        if (resolved != null && files.contains(resolved)) targets.add(resolved);
      }
    }
    edges[path] = targets;
  }

  // BFS from the entrypoints plus any deliberate dynamic roots.
  final alive = <String>{};
  final queue = <String>[
    ...roots,
    ...deadCodeAllowlist.map((p) => 'lib/$p').where(files.contains),
  ];
  while (queue.isNotEmpty) {
    final path = queue.removeLast();
    if (!alive.add(path)) continue;
    for (final t in edges[path] ?? const <String>{}) {
      if (!alive.contains(t)) queue.add(t);
    }
  }

  final dead = (files.difference(alive)).toList()..sort();

  if (roots.isEmpty) {
    stderr.writeln(
      'Dead-code check FAILED: no entrypoint (top-level `main(`) found under '
      'lib/ — the reachability walk has no root, so every file would look '
      'dead. Check the _mainFn pattern in tool/check_dead_code.dart.',
    );
    exit(1);
  }

  if (dead.isEmpty) {
    stdout.writeln(
      'Dead-code OK: all ${files.length} file(s) under lib/ are reachable from '
      '${roots.length} entrypoint(s) via import/export/part.',
    );
    exit(0);
  }

  stderr.writeln('Dead-code check FAILED:');
  stderr.writeln(
    '  - ${dead.length} orphaned file(s) under lib/ — reachable from no '
    'entrypoint via import/export/part. Delete them, or wire them in; if one is '
    'a deliberate dynamic entrypoint, add it (with a reason) to '
    'deadCodeAllowlist in tool/check_dead_code.dart:',
  );
  for (final d in dead) {
    stderr.writeln('      $d');
  }
  exit(1);
}

/// Resolves a directive URI to a lib-relative path, or null if it's external
/// (`dart:`, another `package:`) and so outside our graph.
String? _resolve(String uri, String fromPath) {
  if (uri.startsWith('dart:')) return null;
  if (uri.startsWith('package:')) {
    const prefix = 'package:ocideck/';
    if (!uri.startsWith(prefix)) return null;
    return 'lib/${uri.substring(prefix.length)}';
  }
  // Relative to the importing file's directory.
  final dir = fromPath.substring(0, fromPath.lastIndexOf('/'));
  final parts = dir.split('/');
  for (final seg in uri.split('/')) {
    if (seg == '..') {
      if (parts.isNotEmpty) parts.removeLast();
    } else if (seg != '.' && seg.isNotEmpty) {
      parts.add(seg);
    }
  }
  return parts.join('/');
}

String _norm(String path) => path.replaceAll(r'\', '/');

Iterable<File> _dartFiles(Directory dir) sync* {
  for (final e in dir.listSync(recursive: true, followLinks: false)) {
    if (e is File && e.path.endsWith('.dart')) yield e;
  }
}
