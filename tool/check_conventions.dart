// Guards project conventions in lib/ (see CONTRIBUTING / the logger in
// lib/utils/log.dart):
//
//   * No `print(` — diagnostics go through the logger, never stdout.
//   * No bare `catch (_)` — swallowing errors silently hides failures; catch a
//     named error and route it through `logError`/`logWarning`. This is a
//     RATCHET: the count may not grow. It is currently 0 — keep it there.
//   * No plain `.writeAsString(`/`.writeAsBytes(` — those truncate the target
//     first, so a crash midway corrupts the file. Use `writeStringAtomic`/
//     `writeBytesAtomic` (lib/utils/atomic_file.dart), which alone is exempt.
//   * File-size RATCHET — a file may not exceed [maxFileLines], except the
//     baselined files below whose ceiling is their size at ratchet time. A
//     ceiling may shrink (split the file) but never grow, so big files trend
//     smaller instead of creeping bigger. Translation data is exempt.
//
// Exits non-zero (with the offending locations) when a rule is violated.

import 'dart:io';

/// Bare `catch (_)` sites allowed in lib/. Ratchet only downwards (now 0).
const int catchUnderscoreBaseline = 0;

/// Raw `Color(0x…)` literals allowed in lib/ outside the palette homes (see
/// [_isPaletteHome]). This is a RATCHET: prefer a semantic `AppTheme` token so a
/// palette change — and a future dark mode — touches one place. The count may
/// SHRINK (migrate a literal to a token, then lower this number — the run prints
/// a tip) but never grow. A self-contained non-theme palette (like a
/// deliberately-dark component) may move into its own file that [_isPaletteHome]
/// exempts.
const int rawColorBaseline = 0;

/// A non-baselined `lib/` file may not exceed this many lines — split it first.
const int maxFileLines = 1000;

/// Files already above [maxFileLines] when the ratchet was introduced. Each
/// value is the file's ceiling: it may SHRINK (split the file, then lower the
/// number — the run prints a tip) but never grow. Add a new entry only with a
/// deliberate reason; the goal is fewer and smaller entries over time.
/// `lib/l10n/translations/*` is exempt — those files grow with every UI string.
const Map<String, int> fileSizeBaseline = {};

final _print = RegExp(r'(?<![\w.])print\(');
final _catchUnderscore = RegExp(r'catch\s*\(\s*_\s*\)');
final _plainWrite = RegExp(r'\.writeAs(String|Bytes)(Sync)?\(');
final _rawColor = RegExp(r'Color\(0x[0-9A-Fa-f]{6,8}\)');

/// The token/palette homes, exempt from the raw-colour ratchet: the app theme
/// and the deliberately-dark image-picker palette (its own dark chrome, not
/// part of the light theme).
bool _isPaletteHome(String path) {
  final p = path.replaceAll(r'\', '/');
  return p == 'lib/theme/app_theme.dart' ||
      p == 'lib/theme/image_picker_palette.dart' ||
      p == 'lib/theme/presenter_palette.dart';
}

/// The atomic-write helpers themselves are the only place a plain write may
/// live: everything else goes through them.
bool _isAtomicFileLib(String path) =>
    path.replaceAll(r'\', '/') == 'lib/utils/atomic_file.dart';

bool _isTranslationData(String path) =>
    path.replaceAll(r'\', '/').contains('lib/l10n/translations/');

void main() {
  final printHits = <String>[];
  final plainWriteHits = <String>[];
  var catchCount = 0;
  var rawColorCount = 0;
  final oversize = <String>[];
  final shrunk = <String>[];

  for (final file in _dartFiles(Directory('lib'))) {
    final lines = file.readAsLinesSync();
    final countColors =
        !_isPaletteHome(file.path) && !_isTranslationData(file.path);
    for (var i = 0; i < lines.length; i++) {
      final line = lines[i];
      // Skip full-line comments — the patterns are referenced in docs/comments
      // (e.g. the logger's own docstring) but never appear as real code there.
      if (line.trimLeft().startsWith('//')) continue;
      if (_print.hasMatch(line)) printHits.add('${file.path}:${i + 1}');
      if (_catchUnderscore.hasMatch(line)) catchCount++;
      if (_plainWrite.hasMatch(line) && !_isAtomicFileLib(file.path)) {
        plainWriteHits.add('${file.path}:${i + 1}');
      }
      if (countColors) rawColorCount += _rawColor.allMatches(line).length;
    }

    final path = file.path.replaceAll(r'\', '/');
    if (!_isTranslationData(path)) {
      final count = lines.length;
      final ceiling = fileSizeBaseline[path];
      if (ceiling != null) {
        if (count > ceiling) {
          oversize.add('$path: $count lines (ceiling $ceiling)');
        } else if (count < ceiling) {
          shrunk.add('$path: $count (ceiling $ceiling)');
        }
      } else if (count > maxFileLines) {
        oversize.add('$path: $count lines (max $maxFileLines)');
      }
    }
  }

  final failures = <String>[];

  if (printHits.isNotEmpty) {
    failures.add(
      'Found ${printHits.length} `print(` call(s) — use the logger '
      '(lib/utils/log.dart):\n    ${printHits.join('\n    ')}',
    );
  }

  if (plainWriteHits.isNotEmpty) {
    failures.add(
      'Found ${plainWriteHits.length} plain `.writeAsString`/`.writeAsBytes` '
      'call(s) — a crash midway leaves a truncated file. Use '
      'writeStringAtomic/writeBytesAtomic (lib/utils/atomic_file.dart):\n'
      '    ${plainWriteHits.join('\n    ')}',
    );
  }

  if (catchCount > catchUnderscoreBaseline) {
    failures.add(
      'Bare `catch (_)` count rose to $catchCount (baseline '
      '$catchUnderscoreBaseline). Catch a typed error and call logError, '
      'or lower the baseline if you removed one.',
    );
  }

  if (rawColorCount > rawColorBaseline) {
    failures.add(
      'Raw `Color(0x…)` literal count rose to $rawColorCount (baseline '
      '$rawColorBaseline). Use a semantic AppTheme token '
      '(lib/theme/app_theme.dart), or lower the baseline if you removed one.',
    );
  }

  if (oversize.isNotEmpty) {
    failures.add(
      '${oversize.length} file(s) over their size ceiling — split the file, or '
      '(deliberately) raise its entry in fileSizeBaseline '
      '(tool/check_conventions.dart):\n    ${oversize.join('\n    ')}',
    );
  }

  if (failures.isEmpty) {
    stdout.writeln(
      'Conventions OK: no print(); no plain writeAs*; bare catch (_) at '
      '$catchCount (baseline $catchUnderscoreBaseline); raw Color(0x…) at '
      '$rawColorCount (baseline $rawColorBaseline); file sizes within ceilings.',
    );
    if (rawColorCount < rawColorBaseline) {
      stdout.writeln(
        'Tip: raw Color(0x…) dropped to $rawColorCount — lower rawColorBaseline '
        'in tool/check_conventions.dart to lock in the win.',
      );
    }
    if (catchCount < catchUnderscoreBaseline) {
      stdout.writeln(
        'Tip: bare catch (_) dropped to $catchCount — lower '
        'catchUnderscoreBaseline in tool/check_conventions.dart to lock it in.',
      );
    }
    if (shrunk.isNotEmpty) {
      stdout.writeln(
        'Tip: ${shrunk.length} baselined file(s) shrank — lower their '
        'fileSizeBaseline to lock in the win:\n    ${shrunk.join('\n    ')}',
      );
    }
    exit(0);
  }

  stderr.writeln('Convention check FAILED:');
  for (final f in failures) {
    stderr.writeln('  - $f');
  }
  exit(1);
}

Iterable<File> _dartFiles(Directory dir) sync* {
  for (final e in dir.listSync(recursive: true, followLinks: false)) {
    if (e is File && e.path.endsWith('.dart')) yield e;
  }
}
