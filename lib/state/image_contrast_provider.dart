import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/markdown_validation.dart';
import '../models/slide.dart';
import '../models/slide_quality.dart';
import '../utils/color_contrast.dart';
import '../utils/image_luminance.dart';
import '../utils/project_path.dart';
import '../utils/title_contrast.dart';
import 'deck_provider.dart';

/// Computes the title-slide image-contrast issues for the deck in [ref]'s
/// scope. Exposed as a function so it can back both the global provider and the
/// per-tab [ProviderScope] override (where `deckProvider` is overridden) — see
/// `AppShell`. Mirrors how `deckQualityProvider` is wired.
Future<List<SlideQualityIssue>> computeImageContrastIssues(Ref ref) async {
  final deck = ref.watch(deckProvider.select((s) => s.deck));
  if (deck == null) return const [];
  final theme = deck.themeProfile;

  // Title slides whose text actually sits on the background image; everything
  // else is irrelevant. A non-full-bleed image (imageSize != 0) is confined to
  // the top zone with the title in a solid band below it, so its text never
  // crosses the picture and the image-contrast check does not apply.
  final indices = [
    for (var i = 0; i < deck.slides.length; i++)
      if (!deck.slides[i].skipped &&
          deck.slides[i].type == SlideType.title &&
          deck.slides[i].imagePath.isNotEmpty &&
          deck.slides[i].imageSize == 0 &&
          (deck.slides[i].title.isNotEmpty ||
              deck.slides[i].subtitle.isNotEmpty))
        i,
  ];

  // Decode the backgrounds in parallel so a deck with many title images
  // doesn't pay the sum of every decode on a cold cache.
  final averages = await Future.wait(
    indices.map((i) async {
      final resolved = resolveSlideAssetPath(
        deck.slides[i].imagePath,
        deck.projectPath,
      );
      return resolved == null ? null : await averageImageColor(resolved);
    }),
  );

  final issues = <SlideQualityIssue>[];
  for (var k = 0; k < indices.length; k++) {
    final i = indices[k];
    final slide = deck.slides[i];
    final avg = averages[k];
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
      theme: theme,
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
