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
//   * No raw control bytes — write the escape (\u0000), never the
//     byte itself. See [controlByteBaseline]: this is a review hazard, not a
//     nitpick.
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

/// Raw control bytes (NUL, SOH, …) allowed in `lib/` sources. Keep at 0.
///
/// A control character written as the BYTE ITSELF inside a string literal — a
/// separator like `'\u0000'` typed raw — makes the whole file look BINARY to
/// every byte-oriented tool, even though Dart compiles it fine:
///
///   * `grep` silently skips the file. Not "no matches": *no output at all*.
///     A 900-line source file becomes invisible to any grep-based audit — a
///     file-sized blind spot in a tool whose job is security review.
///   * `git diff` renders it as `Bin 11326 -> 11331 bytes`, so a change to it
///     can never be read as a diff in review.
///
/// The fix is free: write the escape (`\u0000`), which produces a byte-identical
/// string. Only tab, LF and CR may appear raw.
const int controlByteBaseline = 0;

/// UI imports inside `lib/services/`. RATCHET: may shrink, never grow.
///
/// A service is the headless core: usable without a widget tree, testable
/// without pumping one. Eight import lines across four services reach into
/// Flutter's UI layer or into `lib/widgets/` today. One has a real reason —
/// slide_rasterizer paints actual widgets into an image — but text_measurement,
/// slide_quality_analyzer and mermaid_render_service pull in widget code for
/// layout helpers, which pins the core to the UI. Lower this as they are
/// untangled; never raise it.
const int serviceUiImportBaseline = 8;

/// UI imports inside `lib/models/`. Hard zero — do not raise. A model that
/// imports Flutter cannot be reused, tested, or reasoned about on its own.
const int modelUiImportBaseline = 0;

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

/// An import that drags the UI layer in: Flutter's widget/painting libraries,
/// or anything under `lib/widgets/`. `foundation.dart` and `services.dart` are
/// deliberately NOT here — they carry no widget tree (kIsWeb, rootBundle,
/// compute), so a headless service may use them.
final _uiImport = RegExp(
  r"^import 'package:flutter/(material|widgets|cupertino|rendering)\.dart'"
  r"|^import '[^']*widgets/",
);

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

/// Tab, LF and CR are the only control bytes a source file may contain raw.
bool _isAllowedControlByte(int b) => b == 0x09 || b == 0x0a || b == 0x0d;

/// Every raw control byte in [file], as `path:line (0xNN)`. Scans BYTES, not
/// decoded lines: the point is exactly what the byte-oriented tools choke on.
Iterable<String> _controlBytesIn(File file) sync* {
  final bytes = file.readAsBytesSync();
  var line = 1;
  for (final b in bytes) {
    if (b == 0x0a) {
      line++;
      continue;
    }
    if ((b < 0x20 && !_isAllowedControlByte(b)) || b == 0x7f) {
      final hex = b.toRadixString(16).padLeft(2, '0');
      yield '${file.path}:$line (0x$hex)';
    }
  }
}

void main() {
  final printHits = <String>[];
  final plainWriteHits = <String>[];
  var catchCount = 0;
  var rawColorCount = 0;
  final oversize = <String>[];
  final shrunk = <String>[];
  final controlByteHits = <String>[];
  final serviceUiImports = <String>[];
  final modelUiImports = <String>[];

  for (final file in _dartFiles(Directory('lib'))) {
    controlByteHits.addAll(_controlBytesIn(file));
    final path = file.path.replaceAll(r'\', '/');
    final isService = path.startsWith('lib/services/');
    final isModel = path.startsWith('lib/models/');
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
      if ((isService || isModel) && _uiImport.hasMatch(line)) {
        (isModel ? modelUiImports : serviceUiImports).add('$path:${i + 1}');
      }
    }

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

  // A control byte hides a file from grep wherever it lives, so this one rule
  // reaches beyond lib/ — the size and colour ratchets deliberately do not.
  for (final dir in ['test', 'tool']) {
    for (final file in _dartFiles(Directory(dir))) {
      controlByteHits.addAll(_controlBytesIn(file));
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

  if (modelUiImports.length > modelUiImportBaseline) {
    failures.add(
      'lib/models/ imports the UI layer in ${modelUiImports.length} place(s). A '
      'model must stay plain Dart — move the widget/painting code into '
      'lib/widgets/ and keep the model free of it:\n'
      '    ${modelUiImports.join('\n    ')}',
    );
  }

  if (serviceUiImports.length > serviceUiImportBaseline) {
    failures.add(
      'UI imports in lib/services/ rose to ${serviceUiImports.length} (baseline '
      '$serviceUiImportBaseline). A service should run headless — without a '
      'widget tree, and testable without pumping one. Keep the widget code in '
      'lib/widgets/, or lower the baseline if you removed one:\n'
      '    ${serviceUiImports.join('\n    ')}',
    );
  }

  if (controlByteHits.length > controlByteBaseline) {
    failures.add(
      'Found ${controlByteHits.length} raw control byte(s) — the file now reads '
      'as BINARY to grep and git diff, so it is invisible to a grep audit and '
      'unreviewable in a PR. Write the escape instead (e.g. the six characters '
      r'\u0000'
      ') — the resulting string is byte-identical:\n'
      '    ${controlByteHits.join('\n    ')}',
    );
  }

  if (failures.isEmpty) {
    stdout.writeln(
      'Conventions OK: no print(); no plain writeAs*; no raw control bytes; '
      'bare catch (_) at $catchCount (baseline $catchUnderscoreBaseline); raw '
      'Color(0x…) at $rawColorCount (baseline $rawColorBaseline); UI imports in '
      'lib/services at ${serviceUiImports.length} (baseline '
      '$serviceUiImportBaseline) and in lib/models at '
      '${modelUiImports.length}; file sizes within ceilings.',
    );
    if (serviceUiImports.length < serviceUiImportBaseline) {
      stdout.writeln(
        'Tip: UI imports in lib/services dropped to ${serviceUiImports.length} '
        '— lower serviceUiImportBaseline in tool/check_conventions.dart to lock '
        'in the win.',
      );
    }
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
