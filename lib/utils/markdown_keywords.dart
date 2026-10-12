/// `keywords:` als komma-gescheiden regel, het vocabulaire dat Pandoc en de
/// presentatie al gebruiken. Geen YAML-lijst en geen eigen sleutel (#2395).
library;

import 'document_front_matter.dart';

/// De trefwoorden in [content], ontdaan van witruimte, in bronvolgorde.
/// Leeg wanneer de sleutel ontbreekt.
List<String> markdownKeywords(String content) {
  final raw = documentFrontMatterMetadata(content).fields['keywords'] ?? '';
  return [
    for (final part in raw.split(','))
      if (part.trim().isNotEmpty) part.trim(),
  ];
}

/// Of [content] álle [required] trefwoorden heeft. Vergelijking is
/// hoofdletterongevoelig en kijkt alleen naar `keywords:`, niet naar de tekst.
bool markdownHasKeywords(String content, Iterable<String> required) {
  final have = {
    for (final word in markdownKeywords(content)) word.toLowerCase(),
  };
  for (final word in required) {
    final needle = word.trim().toLowerCase();
    if (needle.isEmpty) continue;
    if (!have.contains(needle)) return false;
  }
  return true;
}
