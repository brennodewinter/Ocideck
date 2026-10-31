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
    if (RegExp(r'^\s*```').hasMatch(line)) {
      fenced = !fenced;
      continue;
    }
    if (fenced || line.trimLeft().startsWith('<!--')) continue;
    final prose = line
        .replaceAll(RegExp(r'!?\[[^\]]*\]\([^)]*\)'), ' ')
        .replaceAll(RegExp(r'[`*_#>|~-]+'), ' ')
        .trim();
    final words = prose
        .split(RegExp(r'\s+'))
        .where((word) => word.isNotEmpty)
        .toList();
    for (var word = 1; word < words.length; word++) {
      final current = _plainWord(words[word]);
      if (current.length > 1 && current == _plainWord(words[word - 1])) {
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
    word.toLowerCase().replaceAll(RegExp(r'^[^a-z0-9À-ž]+|[^a-z0-9À-ž]+$'), '');
