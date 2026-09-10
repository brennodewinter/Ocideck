import 'package:path/path.dart' as p;

import '../models/slide.dart';
import '../services/image_usage.dart';
import '../services/slide_image_refs.dart';
import '../utils/project_path.dart';
import 'deck_provider.dart';
import 'tabs_provider.dart';

/// Alle geopende Markdownbestanden, zodat de afbeeldingsbibliotheek hun
/// verwijzingen niet tegelijk op schijf én in het levende tabmodel behandelt.
List<String> openTabMarkdownFiles(Iterable<TabInfo> tabs) => [
  for (final tab in tabs) ?tab.openFilePath,
];

/// Waar [absolutePath] in geopende presentatie- en documenttabs wordt gebruikt.
List<String> openTabImageUsages(Iterable<TabInfo> tabs, String absolutePath) {
  final target = p.normalize(absolutePath);
  final usages = <String>[];
  for (final tab in tabs) {
    switch (tab.content) {
      case DeckTabContent(:final deckNotifier):
        final deck = deckNotifier.currentState.deck;
        if (deck == null) continue;
        String? resolve(String candidate) =>
            resolveEditorAssetPath(candidate, deck.projectPath);
        for (final index in slideIndexesUsingImage(deck, target, resolve)) {
          usages.add('${tab.label} · slide ${index + 1}');
        }
      case DocumentTabContent(:final documentNotifier):
        final state = documentNotifier.currentState;
        final document = state.document;
        if (document == null) continue;
        final basePath = _documentBasePath(state.projectPath, state.filePath);
        if (inlineImagePaths(document.body).any(
          (path) =>
              p.equals(resolveEditorAssetPath(path, basePath) ?? '', target),
        )) {
          usages.add(tab.label);
        }
    }
  }
  return usages;
}

/// Vervang [fromAbsolute] in iedere geopende tab door [toAbsolute].
///
/// Elke tab krijgt één state-mutatie. Document-frontmatter blijft letterlijk
/// staan; alleen afbeeldingspaden in de body worden herschreven.
Future<void> replaceOpenTabImageUsages(
  Iterable<TabInfo> tabs,
  String fromAbsolute,
  String toAbsolute,
) async {
  final target = p.normalize(fromAbsolute);
  for (final tab in tabs) {
    switch (tab.content) {
      case DeckTabContent(:final deckNotifier):
        final deck = deckNotifier.currentState.deck;
        if (deck == null) continue;
        final basePath = deck.projectPath;
        String? resolve(String candidate) =>
            resolveEditorAssetPath(candidate, basePath);
        final replacements = <String, Slide>{};
        for (final slide in deck.slides) {
          final updated = slideWithImageReplaced(
            slide,
            target,
            resolve,
            (path) => _replacementPath(path, basePath, toAbsolute),
          );
          if (!identical(updated, slide)) {
            replacements[slide.id] = updated;
          }
        }
        deckNotifier.replaceSlidesById(replacements);
      case DocumentTabContent(:final documentNotifier):
        final state = documentNotifier.currentState;
        final document = state.document;
        if (document == null) continue;
        final basePath = _documentBasePath(state.projectPath, state.filePath);
        final body = rewriteInlineImagePaths(document.body, (path) {
          final resolved = resolveEditorAssetPath(path, basePath);
          return resolved != null && p.equals(resolved, target)
              ? _replacementPath(path, basePath, toAbsolute)
              : null;
        });
        if (body != document.body) {
          documentNotifier.edit(
            document.withBody(body).source,
            visualEdit: state.visualEdited,
          );
        }
    }
  }
}

String? _documentBasePath(String? projectPath, String? filePath) =>
    projectPath ?? (filePath == null ? null : p.dirname(filePath));

String _replacementPath(String original, String? basePath, String toAbsolute) {
  if (p.isAbsolute(original) || basePath == null || basePath.isEmpty) {
    return toAbsolute;
  }
  return p.isWithin(basePath, toAbsolute)
      ? p.relative(toAbsolute, from: basePath).replaceAll(r'\', '/')
      : toAbsolute;
}
