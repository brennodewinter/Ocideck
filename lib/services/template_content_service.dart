import 'package:flutter/services.dart' show rootBundle;

import '../models/slide.dart';
import 'markdown_service.dart';

/// Loads the example content of a deck template from its bundled document.
///
/// A template's content is a Markdown file per language
/// (`assets/templates/<id>.nl.md` next to `<id>.en.md`), parsed by the same
/// service that opens any deck — a template is a document, not code. Dutch
/// users get the Dutch file, everyone else the English one; the picker's
/// names and descriptions stay on the l10n route with all languages.
class TemplateContentService {
  TemplateContentService({Future<String> Function(String key)? loadAsset})
    : _loadAsset = loadAsset ?? rootBundle.loadString;

  final Future<String> Function(String key) _loadAsset;

  /// Returns the fresh slides for a new deck from template [templateId], with
  /// the first (title) slide carrying [deckTitle]. Falls back to a bare title
  /// slide when the document is missing or unreadable, so deck creation never
  /// fails on a bad bundle.
  Future<List<Slide>> loadSlides(
    String templateId, {
    required String languageCode,
    required String deckTitle,
  }) async {
    final language = languageCode == 'nl' ? 'nl' : 'en';
    final Slide bareTitle = Slide.create(
      SlideType.title,
    ).copyWith(title: deckTitle);
    String markdown;
    try {
      markdown = await _loadAsset('assets/templates/$templateId.$language.md');
    } catch (_) {
      return [bareTitle];
    }
    final deck = MarkdownService().parseDeck(markdown);
    if (deck == null || deck.slides.isEmpty) return [bareTitle];
    final slides = List<Slide>.of(deck.slides);
    slides[0] = slides[0].copyWith(title: deckTitle);
    return slides;
  }
}
