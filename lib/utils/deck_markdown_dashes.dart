/// Zero-width space inserted between hyphens so deck parsers do not treat
/// user-authored dash lines as slide separators (`\n---\n`) or horizontal rules.
const _zwsp = '\u200B';

final _standaloneDashLine = RegExp(r'^\s*-{2,}\s*$');

/// Escapes standalone lines of two or more hyphens before writing deck markdown.
String escapeDeckMarkdownDashLines(String text) {
  if (text.isEmpty) return text;
  return text.split('\n').map(_escapeDashLine).join('\n');
}

String _escapeDashLine(String line) {
  if (!_standaloneDashLine.hasMatch(line)) return line;
  final trimmed = line.trim();
  return '${line.substring(0, line.indexOf(trimmed))}'
      '${trimmed.split('').join(_zwsp)}'
      '${line.substring(line.indexOf(trimmed) + trimmed.length)}';
}

/// Restores user-visible `--` / `---` lines after loading deck markdown.
String unescapeDeckMarkdownDashLines(String text) {
  return text.replaceAll(_zwsp, '');
}
