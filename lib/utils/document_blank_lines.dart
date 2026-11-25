import 'package:markdown/markdown.dart' as md;

import '../services/form_document_blocks.dart';
import '../services/pentest_blocks.dart';

/// Eén expliciete lege regel in een OciDeck-document.
const spacerMarker = '<!-- spacer -->';

final spacerMarkerLinePattern = RegExp(r'^[ \t]*<!--\s*spacer\s*-->[ \t]*$');
final _extraBlankLines = RegExp(r'\n[ \t]*\r?\n[ \t]*\r?\n');

/// Houd één gewone alineascheiding en zet elke extra lege regel tussen
/// top-level blokken om in de bestaande witruimtemarker.
String withDocumentBlankLineSpacers(String markdown) {
  final extraLines = extraDocumentBlankLineIndices(markdown);
  if (extraLines.isEmpty) return markdown;

  final lines = markdown.split('\n');
  return [
    for (var i = 0; i < lines.length; i++) ...[
      if (extraLines.contains(i))
        lines[i].endsWith('\r') ? '$spacerMarker\r' : spacerMarker,
      lines[i],
    ],
  ].join('\n');
}

/// The source line indices that become spacer blocks in the visual editor.
Set<int> extraDocumentBlankLineIndices(String markdown) {
  if (!_extraBlankLines.hasMatch(markdown)) return const {};

  final source = markdown.split('\n');
  final lines = [
    for (final line in source)
      md.Line(line.endsWith('\r') ? line.substring(0, line.length - 1) : line),
  ];
  final boundaries = _BlockBoundaries();
  md.BlockParser(
    lines,
    md.Document(
      extensionSet: md.ExtensionSet.gitHubFlavored,
      blockSyntaxes: [boundaries, const _DisplayMathSyntax()],
    ),
  ).parseLines();

  final forms = scanFormBlocks(markdown);
  final pentest = scanPentestBlocks(markdown);
  final extraLines = <int>{};
  var blankStart = 0;
  for (var i = 0; i < lines.length; i++) {
    if (lines[i].isBlankLine) continue;
    if (i - blankStart > 1 &&
        blankStart > 0 &&
        boundaries.starts.contains(lines[i]) &&
        !forms.isAtomicLine(blankStart) &&
        !pentest.isAtomicLine(blankStart) &&
        !_startsWithMetadata(lines[blankStart - 1])) {
      for (var j = blankStart + 1; j < i; j++) {
        extraLines.add(j);
      }
    }
    blankStart = i + 1;
  }
  return extraLines;
}

// A layout comment can still qualify a following block across blank lines.
bool _startsWithMetadata(md.Line line) =>
    line.content.trimLeft().startsWith('<!--') &&
    !spacerMarkerLinePattern.hasMatch(line.content);

/// Observe the Markdown parser's block starts. It consumes fences, lists and
/// HTML with their internal blank lines before another top-level start occurs.
class _BlockBoundaries extends md.BlockSyntax {
  final starts = <md.Line>{};

  @override
  RegExp get pattern => _neverMatches;

  static final _neverMatches = RegExp(r'(?!)');

  @override
  md.Node? parse(md.BlockParser parser) =>
      throw StateError('Block boundaries only observe the parser.');

  @override
  bool canParse(md.BlockParser parser) {
    if (parser.parentSyntax == null && !parser.current.isBlankLine) {
      starts.add(parser.current);
    }
    return false;
  }
}

/// OciDeck also treats standalone display-math fences as opaque blocks.
class _DisplayMathSyntax extends md.BlockSyntax {
  const _DisplayMathSyntax();

  static final _fence = RegExp(r'^ {0,3}\$\$[ \t]*$');

  @override
  RegExp get pattern => _fence;

  @override
  md.Node parse(md.BlockParser parser) {
    parser.advance();
    while (!parser.isDone) {
      final closing = parser.matches(_fence);
      parser.advance();
      if (closing) break;
    }
    return md.Element.empty('math');
  }
}
