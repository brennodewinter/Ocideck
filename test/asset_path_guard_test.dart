import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Source-scan guard (in the spirit of app_localizations_test.dart) against the
/// exact bug class fixed in "Confine untrusted-deck asset paths to the
/// project": building a filesystem path by interpolating a project/base path
/// directly with a deck-supplied segment (e.g. `'$projectPath/$path'`) and then
/// reading it, which bypasses the containment guard `resolveSlideAssetPath`.
///
/// Deck-supplied asset paths must be resolved through
/// `resolveSlideAssetPath` / `resolveProjectRelative` / `resolveProjectAbsolute`
/// (which reject absolute and `../` escapes), never by raw string
/// interpolation. Interpolating a path var with a *literal* segment (e.g.
/// `'$projectPath/images'` for a browse directory) is fine and not matched.
void main() {
  test('no deck-supplied asset path is built by raw string interpolation', () {
    // A `*Path` variable, a slash, then another interpolation (the
    // deck-controlled segment): `$projectPath/$path`, `${deck.projectPath}/$x`.
    final antiPattern = RegExp(r'\$\{?[A-Za-z_.]*[Pp]ath\}?/\$');

    // Justified exceptions (path is built for writing/scanning, not reading a
    // deck-supplied path). Keep empty unless a reviewed case demands it.
    const allowlist = <String>{};

    final offenders = <String>[];
    for (final file
        in Directory('lib')
            .listSync(recursive: true)
            .whereType<File>()
            .where((f) => f.path.endsWith('.dart'))) {
      final lines = file.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        if (!antiPattern.hasMatch(lines[i])) continue;
        final loc = '${file.path}:${i + 1}';
        if (allowlist.contains(loc)) continue;
        offenders.add('$loc  ${lines[i].trim()}');
      }
    }

    expect(
      offenders,
      isEmpty,
      reason:
          'These lines build a path from a project/base path and a '
          'deck-supplied segment by string interpolation, bypassing the '
          'containment guard. Resolve the path through resolveSlideAssetPath '
          '(or resolveProjectRelative/Absolute) instead:\n${offenders.join('\n')}',
    );
  });
}
