// Generates a plain-text licence file from LICENSE.md for the Windows installer
// (#1600). Inno Setup's `LicenseFile` directive shows the file content verbatim
// on the first page every Windows user sees — feeding it the Markdown source
// renders the HTML comment, `#`/`**`/`>` markers and `---` rules literally.
// This tool strips that Markdown to readable plain text and writes
// `packaging/windows/LICENSE.txt`, which the `.iss` references instead.
//
// The generated file is committed (the installer build is offline and reads it
// from disk). `test/windows_packaging_test.dart` regenerates it in a temp file
// and compares, so a LICENSE.md edit without a re-run fails the gate — the
// "poort die hem vers houdt" the issue asks for.
//
// Usage: dart run tool/generate_license_txt.dart

import 'dart:io';

/// Strips Markdown formatting from [markdown] to produce readable plain text.
///
/// Removes: HTML comments (`<!-- … -->`), ATX headers (`#`, `##`), bold
/// (`**`), blockquotes (`> `), and horizontal rules (`---`). List markers
/// (`- `) are kept — they are readable in a plain-text scroll. Paragraph
/// breaks are preserved.
String markdownToPlainText(String markdown) {
  final lines = markdown.replaceAll('\r\n', '\n').split('\n');
  final out = <String>[];
  var inHtmlComment = false;

  for (final line in lines) {
    // Multi-line HTML comment blocks: skip every line until the closing -->.
    if (inHtmlComment) {
      if (line.contains('-->')) inHtmlComment = false;
      continue;
    }
    // Single-line or opening HTML comment.
    final commentStart = line.indexOf('<!--');
    if (commentStart >= 0) {
      if (!line.contains('-->')) {
        inHtmlComment = true;
        continue;
      }
      // Single-line comment: strip it, keep any text outside it (rare).
      final stripped = line.replaceAll(RegExp(r'<!--.*?-->'), '').trim();
      if (stripped.isNotEmpty) out.add(stripped);
      continue;
    }

    // Horizontal rules — a line of only dashes (3+).
    if (RegExp(r'^-{3,}\s*$').hasMatch(line)) {
      out.add('');
      continue;
    }

    var l = line;
    // ATX headers: strip leading #'s and the space after.
    l = l.replaceFirst(RegExp(r'^#{1,6}\s+'), '');
    // Bold markers.
    l = l.replaceAll('**', '');
    // Blockquote markers (only at line start, with optional space).
    l = l.replaceFirst(RegExp(r'^>\s?'), '');

    out.add(l);
  }

  // Collapse 3+ consecutive blank lines to 2 (Markdown paragraphs → one gap).
  var result = out.join('\n');
  result = result.replaceAll(RegExp(r'\n{3,}'), '\n\n');
  // Trim leading/trailing whitespace but keep a trailing newline.
  return '${result.trim()}\n';
}

void main() {
  final source = File('LICENSE.md');
  if (!source.existsSync()) {
    stderr.writeln(
      'generate_license_txt: LICENSE.md not found — run from '
      'the repository root.',
    );
    exit(2);
  }

  final output = File('packaging/windows/LICENSE.txt');
  final outputDir = output.parent;
  if (!outputDir.existsSync()) {
    stderr.writeln('generate_license_txt: ${outputDir.path} does not exist.');
    exit(2);
  }

  final plain = markdownToPlainText(source.readAsStringSync());
  output.writeAsStringSync(plain);
  stdout.writeln('Wrote ${output.path} (${plain.length} bytes).');
}
