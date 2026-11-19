import 'dart:convert';
import 'dart:ui' show Color;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/deck.dart';
import '../models/markdown_validation.dart';
import '../models/slide.dart';
import '../models/slide_quality.dart';
import '../utils/color_contrast.dart';
import '../utils/image_luminance.dart';
import '../utils/project_path.dart';
import '../utils/title_contrast.dart';
import 'deck_provider.dart';

// Alleen koppen die op het achtergrondbeeld liggen, hebben deze controle nodig.
Iterable<int> _contrastIndices(Deck deck) sync* {
  for (var i = 0; i < deck.slides.length; i++) {
    final slide = deck.slides[i];
    if (!slide.skipped &&
        (slide.type == SlideType.title || slide.type == SlideType.section) &&
        slide.titleColumnLayout == TitleColumnLayout.none &&
        slide.imagePath.isNotEmpty &&
        slide.imageSize == 0 &&
        (slide.title.isNotEmpty || slide.subtitle.isNotEmpty)) {
      yield i;
    }
  }
}

String? _contrastKey(Deck? deck) {
  if (deck == null) return null;
  return jsonEncode([
    deck.projectPath,
    for (final i in _contrastIndices(deck)) _contrastInput(deck, i),
  ]);
}

List<Object?> _contrastInput(Deck deck, int index) {
  final slide = deck.slides[index];
  final profile = deck.slideProfileAt(index);
  return [
    index,
    slide.imagePath,
    slide.type.name,
    slide.title.isNotEmpty,
    slide.subtitle.isNotEmpty,
    slide.titleImageOverlay,
    slide.titleTextColorOverride,
    imageOverlayStrengthFor(slide),
    profile.titleTextColor,
    profile.titleBackgroundColor,
    profile.sectionBackgroundColor,
  ];
}

/// Computes the title-slide image-contrast issues for the deck in [ref]'s
/// scope, including the per-tab override.
Future<List<SlideQualityIssue>> computeImageContrastIssues(Ref ref) async {
  final key = ref.watch(deckProvider.select((s) => _contrastKey(s.deck)));
  if (key == null) return const [];
  final deck = ref.read(deckProvider).deck!;
  final averages = <String, Color?>{};
  var cancelled = false;
  ref.onDispose(() => cancelled = true);

  final issues = <SlideQualityIssue>[];
  for (final i in _contrastIndices(deck)) {
    if (cancelled) break;
    final slide = deck.slides[i];
    if (!averages.containsKey(slide.imagePath)) {
      final resolved = resolveSlideAssetPath(slide.imagePath, deck.projectPath);
      // Serieel lezen voorkomt een geheugenspiek bij meerdere grote foto's.
      averages[slide.imagePath] = resolved == null
          ? null
          : await averageImageColor(resolved);
    }
    final avg = averages[slide.imagePath];
    if (avg == null) {
      // Couldn't decode — fall back to the "verify visually" informational
      // note instead of a confident pass/fail.
      issues.add(
        SlideQualityIssue(
          slideIndex: i,
          kind: SlideQualityIssueKind.imageContrastUnverified,
          category: SlideQualityCategory.contrast,
          severity: MarkdownValidationSeverity.informational,
          field: 'imagePath',
        ),
      );
      continue;
    }

    final eval = evaluateTitleContrast(
      avgImage: avg,
      theme: deck.slideProfileAt(i),
      slide: slide,
    );
    if (eval.passes) continue;

    issues.add(
      SlideQualityIssue(
        slideIndex: i,
        kind: SlideQualityIssueKind.titleImageContrast,
        category: SlideQualityCategory.contrast,
        severity: MarkdownValidationSeverity.warning,
        field: 'titleImageOverlay',
        args: {
          'ratio': eval.ratio.toStringAsFixed(1),
          'threshold': kWcagAaLargeText.toStringAsFixed(1),
          'fix': eval.fix.name,
        },
      ),
    );
  }
  return issues;
}

/// Asynchronous quality pass that decodes title-slide background images and
/// flags title text with insufficient contrast against them. Kept separate
/// from the synchronous [deckQualityProvider] because image decoding can't run
/// inline; the panel merges both result sets. Overridden per tab in `AppShell`
/// so it reads the active tab's deck.
final imageContrastIssuesProvider = FutureProvider.autoDispose(
  computeImageContrastIssues,
);
