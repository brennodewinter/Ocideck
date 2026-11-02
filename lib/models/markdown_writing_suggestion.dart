enum MarkdownWritingSuggestionKind { repeatedWord, longSentence, placeholder }

class MarkdownWritingSuggestion {
  final MarkdownWritingSuggestionKind kind;
  final int line;

  /// Waarden voor de vertaalde melding, bijvoorbeeld `woord` of `aantal`.
  final Map<String, String> args;

  const MarkdownWritingSuggestion({
    required this.kind,
    required this.line,
    this.args = const {},
  });
}

/// Hoe vaak [inspectMarkdownWriting] liep. Tests lezen dit om te zien dat een
/// toetsaanslag de scan niet meteen start (#2681).
int debugMarkdownWritingInspectionCount = 0;

/// Gedeelde patronen: inline `RegExp(...)` in de lus hercompileerde dezelfde
/// uitdrukking per regel — en [_plainWord] deed dat zelfs per wóórd. Op een
/// deck van honderdvijftig dia's kostte de debounced scan dan ~35 ms (#2681).
final _reFence = RegExp(r'^\s*```');
final _reMarkupRun = RegExp(r'!?\[[^\]]*\]\([^)]*\)|[`*_#>|~-]+');
final _reWhitespace = RegExp(r'\s+');
final _reWordEdge = RegExp(r'^[^a-z0-9À-ž]+|[^a-z0-9À-ž]+$');

/// Fast, language-independent checks that can run on every source edit. This is
/// intentionally not a grammar oracle: it reports objective editing smells and
/// leaves spelling/grammar to a language-specific provider later.
List<MarkdownWritingSuggestion> inspectMarkdownWriting(String markdown) {
  debugMarkdownWritingInspectionCount++;
  final suggestions = <MarkdownWritingSuggestion>[];
  final lines = markdown.split('\n');
  var fenced = false;
  for (var index = 0; index < lines.length; index++) {
    final line = lines[index];
    if (_reFence.hasMatch(line)) {
      fenced = !fenced;
      continue;
    }
    if (fenced || line.trimLeft().startsWith('<!--')) continue;
    final prose = line.replaceAll(_reMarkupRun, ' ').trim();
    final words = prose
        .split(_reWhitespace)
        .where((word) => word.isNotEmpty)
        .toList();
    // Het vorige woord is per stap al een keer schoongemaakt — niet twee
    // keer per woord de rand-strip betalen.
    var previous = words.isEmpty ? '' : _plainWord(words.first);
    for (var word = 1; word < words.length; word++) {
      final current = _plainWord(words[word]);
      if (current.length > 1 && current == previous) {
        suggestions.add(
          MarkdownWritingSuggestion(
            kind: MarkdownWritingSuggestionKind.repeatedWord,
            line: index + 1,
            args: {'woord': words[word]},
          ),
        );
        break;
      }
    }
    if (words.length > 35) {
      suggestions.add(
        MarkdownWritingSuggestion(
          kind: MarkdownWritingSuggestionKind.longSentence,
          line: index + 1,
          args: {'aantal': '${words.length}'},
        ),
      );
    }
    if (line.contains('](url)') ||
        line.contains('](pad-of-url)') ||
        line.contains('| Waarde | Waarde |')) {
      suggestions.add(
        MarkdownWritingSuggestion(
          kind: MarkdownWritingSuggestionKind.placeholder,
          line: index + 1,
        ),
      );
    }
  }
  return suggestions;
}

String _plainWord(String word) =>
    word.toLowerCase().replaceAll(_reWordEdge, '');
