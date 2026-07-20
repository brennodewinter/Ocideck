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
///
/// Alleen op de regels waar [escapeDeckMarkdownDashLines] iets heeft ingevoegd:
/// een regel die zónder de tekens een kale streepjesregel is. Een kaal
/// `replaceAll` over de hele tekst haalde óók de zero-width spaces weg die de
/// auteur zelf had staan — geplakte web- en CJK-tekst zit er vol mee, en hij
/// wordt gebruikt als expliciete afbreekhint. Die verdwenen dan bij elke keer
/// laden, zonder dat er iets van te zien was.
String unescapeDeckMarkdownDashLines(String text) {
  if (!text.contains(_zwsp)) return text;
  return text.split('\n').map(_unescapeDashLine).join('\n');
}

String _unescapeDashLine(String line) {
  if (!line.contains(_zwsp)) return line;
  final bare = line.replaceAll(_zwsp, '');
  return _standaloneDashLine.hasMatch(bare) ? bare : line;
}
