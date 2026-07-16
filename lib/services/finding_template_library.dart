import '../models/finding_template.dart';
import 'finding_templates/all.dart';

/// The reusable finding-template library (PENTEST_MIAUW §17). This first
/// increment ships a small set of **bundled** starter templates and a search;
/// the importable community/team packs (through the existing import
/// sanitisation + limits) and CWE-keyed autofill extend this later.
///
/// Templates are authored as plain Markdown with front matter (the exact on-disk
/// form a user can export, diff and re-import), kept as source strings in
/// `finding_templates/<code>.dart` so they need no asset wiring; each is parsed
/// once, lazily, per language.
///
/// **A template is picked by the language of the report** (`Deck.language`,
/// MIAUW EIS 2.3), not the interface language: a Dutch tester writing for an
/// international client wants an English skeleton from a Dutch UI
/// (PENTEST_MIAUW §12.3). Unlike the CWE/WSTG catalogs — citations that keep
/// their standard's language — a template is *our* content, meant to be
/// rewritten, so it follows the reader (§12.1).
class FindingTemplateLibrary {
  FindingTemplateLibrary._();

  static final FindingTemplateLibrary instance = FindingTemplateLibrary._();

  /// The language every template is guaranteed to exist in, and therefore the
  /// fallback for anything else.
  static const fallbackLanguage = 'en';

  final Map<String, List<FindingTemplate>> _cache = {};

  /// The bundled starter templates in [languageCode], parsed on first use.
  ///
  /// Resolution is **per template**, not per language: a slug missing from a
  /// language falls back to [fallbackLanguage] on its own, so a half-translated
  /// language still offers the full set rather than silently going short. An
  /// unknown or empty code resolves entirely to the fallback — the same rule the
  /// rendered finding headings follow, so a deck with no recorded language is
  /// English throughout rather than English in one place and translated in
  /// another.
  List<FindingTemplate> bundledFor(String languageCode) {
    return _cache.putIfAbsent(languageCode, () {
      final fallback = findingTemplateSources[fallbackLanguage]!;
      final requested = findingTemplateSources[languageCode] ?? const {};
      return [
        for (final slug in fallback.keys)
          FindingTemplate.parse(requested[slug] ?? fallback[slug]!, id: slug),
      ];
    });
  }

  /// How many templates the library can serve, for the reference inventory. The
  /// count is language-independent (every language carries the full set).
  int get count => findingTemplateSources[fallbackLanguage]!.length;

  /// Templates in [languageCode] whose title/CWE/severity contain every
  /// whitespace-separated term in [query] (case-insensitive). An empty query
  /// returns all templates.
  List<FindingTemplate> search(String query, {required String languageCode}) {
    final all = bundledFor(languageCode);
    final terms = query.toLowerCase().split(RegExp(r'\s+'))
      ..removeWhere((t) => t.isEmpty);
    if (terms.isEmpty) return all;
    return all
        .where((t) => terms.every((term) => t.searchText.contains(term)))
        .toList();
  }
}
