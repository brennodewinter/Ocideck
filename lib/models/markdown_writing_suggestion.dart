enum MarkdownWritingSuggestionKind { repeatedWord, longSentence, placeholder }

class MarkdownWritingSuggestion {
  final MarkdownWritingSuggestionKind kind;
  final int line;
  final String message;

  const MarkdownWritingSuggestion({
    required this.kind,
    required this.line,
    required this.message,
  });
}

/// Fast, language-independent checks that can run on every source edit. This is
/// intentionally not a grammar oracle: it reports objective editing smells and
/// leaves spelling/grammar to a language-specific provider later.
List<MarkdownWritingSuggestion> inspectMarkdownWriting(String markdown) {
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
            message:
                'Het woord “${words[word]}” staat twee keer achter elkaar.',
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
          message:
              'Deze regel bevat ${words.length} woorden; overweeg hem op te splitsen.',
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
          message:
              'Vervang de tijdelijke voorbeeldtekst voordat je publiceert.',
        ),
      );
    }
  }
  return suggestions;
}

String _plainWord(String word) =>
    word.toLowerCase().replaceAll(RegExp(r'^[^a-z0-9À-ž]+|[^a-z0-9À-ž]+$'), '');
