import 'package:flutter/foundation.dart' show FlutterError;
import 'package:flutter/services.dart' show rootBundle;

import '../models/slide.dart';
import '../services/improvement/improvement_project_scaffold.dart';
import '../utils/log.dart';
import '../l10n/app_localizations.dart';
import 'markdown_service.dart';

/// Loads the example content of a deck template from its bundled document.
///
/// A template's content is a Markdown file per language
/// (`assets/templates/<id>.<lang>.md`), parsed by the same service that opens
/// any deck — a template is a document, not code. The requested language is
/// loaded; when no file exists for it, English is the fallback. The picker'
/// names and descriptions stay on the l10n route with all languages.
class TemplateContentService {
  TemplateContentService({Future<String> Function(String key)? loadAsset})
    : _loadAsset = loadAsset ?? rootBundle.loadString;

  final Future<String> Function(String key) _loadAsset;

  /// Languages for which the "content is in English" notice should not be shown.
  ///
  /// This is the set of locales the UI supports. Missing template content falls
  /// back to English through [loadSlides].
  static final Set<String> languagesWithContent = Set.of(
    AppLocalizations.supportedLocales.map((l) => l.languageCode),
  );

  /// Returns the fresh slides for a new deck from template [templateId], with
  /// the first (title) slide carrying [deckTitle]. Falls back to a bare title
  /// slide when the document is missing or unreadable, so deck creation never
  /// fails on a bad bundle.
  Future<List<Slide>> loadSlides(
    String templateId, {
    required String languageCode,
    required String deckTitle,
  }) async {
    if (templateId == 'procesverbetering-dmaic') {
      return buildImprovementProjectSlides(
        projectTitle: deckTitle,
        framework: 'dmaic',
        y01Description: '',
      );
    }

    final Slide bareTitle = Slide.create(
      SlideType.title,
    ).copyWith(title: deckTitle);
    String? markdown;
    for (final lang in [languageCode, 'en']) {
      try {
        markdown = await _loadAsset('assets/templates/$templateId.$lang.md');
        break;
      } on Exception catch (e) {
        logError('template_content_service.loadSlides', e);
      } on FlutterError catch (e) {
        // rootBundle meldt een ontbrekend asset als FlutterError, geen Exception.
        logError('template_content_service.loadSlides', e);
      }
    }
    if (markdown == null) return [bareTitle];
    final deck = MarkdownService().parseDeck(markdown);
    if (deck == null || deck.slides.isEmpty) return [bareTitle];
    final slides = List<Slide>.of(deck.slides);
    slides[0] = slides[0].copyWith(title: deckTitle);
    return slides;
  }
}
