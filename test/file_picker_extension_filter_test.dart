import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Guards the file pickers that open OciDeck's own content against a macOS
/// greying regression (#927).
///
/// `file_picker` on macOS greys the native panel entries that match a
/// `FileType.custom` + `allowedExtensions` filter as soon as the extension has
/// no UTI registered with the system — and `.ocideck` / `.ocideckstyle` are
/// invented extensions, so the very files the user wants become unpickable.
/// The fix is to open with `FileType.any` and validate the chosen bytes
/// afterwards (a package by its zip header, a style profile by its JSON
/// `ocideck` marker). Op macOS gaat [pickMarkdownFile] / [pickPackageFile]
/// bovendien via `pickUnfilteredMacFile` (eigen NSOpenPanel die filters
/// expliciet wist), zodat een *onthouden* UTI-filter `.md` niet opnieuw grijs
/// maakt.
///
/// This lives as a source-level check because the native panel cannot be driven
/// under `flutter test`: `FilePicker` is a static call with no seam to observe
/// which `FileType` it was handed. So we assert the source of these three
/// methods instead — the two that regressed plus [pickMarkdownFile], which was
/// fixed the same way earlier and must not slide back.
void main() {
  const targets = <String, List<String>>{
    'lib/services/file_service.dart': ['pickMarkdownFile', 'pickPackageFile'],
    'lib/services/file/file_service_style_profile.dart': ['importStyleProfile'],
  };

  /// The *code* of [method] in [source] — its declaration up to the first
  /// 2-space-indented closing brace, with `//` comment lines stripped.
  ///
  /// Comments are dropped on purpose: these methods explain in prose *why* they
  /// avoid an `allowedExtensions` filter, so the word appears in the comment
  /// even though the code no longer passes it. The gate asserts on the code, not
  /// the explanation of the code.
  String codeOf(String source, String method) {
    final start = source.indexOf('$method(');
    expect(start, isNot(-1), reason: 'method $method not found in source');
    final end = source.indexOf('\n  }\n', start);
    expect(end, isNot(-1), reason: 'no method end found for $method');
    return source
        .substring(start, end)
        .split('\n')
        .where((line) => !line.trimLeft().startsWith('//'))
        .join('\n');
  }

  targets.forEach((path, methods) {
    final source = File(path).readAsStringSync();
    for (final method in methods) {
      test('$method opens with FileType.any and no extension filter', () {
        final body = codeOf(source, method);
        expect(
          body,
          contains('FileType.any'),
          reason:
              '$method must open with FileType.any — an allowedExtensions '
              'filter greys out OciDeck\'s invented extensions on macOS (#927).',
        );
        expect(
          body,
          isNot(contains('allowedExtensions')),
          reason:
              '$method must not pass allowedExtensions — that filter is exactly '
              'what greys the pickable files out on macOS (#927). Validate the '
              'chosen bytes after picking instead.',
        );
      });
    }
  });

  test('_pickPathGated uses the filterless macOS panel for FileType.any', () {
    final source = File(
      'lib/services/file/file_service_import.dart',
    ).readAsStringSync();
    // Hele part-bestand: de poort moet de native kiezer aanroepen. Geen
    // methode-snipper — `indexOf('\n}')` snijdt te vroeg af op geneste `}`.
    final code = source
        .split('\n')
        .where((line) => !line.trimLeft().startsWith('//'))
        .join('\n');
    expect(
      code,
      contains('pickUnfilteredMacFile'),
      reason:
          '_pickPathGated must call pickUnfilteredMacFile on macOS so an '
          'onthouden UTI-filter cannot grey out .md files.',
    );
    expect(
      code,
      contains('Platform.isMacOS'),
      reason:
          'the native panel is macOS-only; the gate must stay platform-aware',
    );
  });
}
