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
  final issues = <SlideQualityIssue>[];

  for (var i = 0; i < deck.slides.length; i++) {
    final slide = deck.slides[i];
    if (slide.skipped) continue;
    if (slide.type != SlideType.title || slide.imagePath.isEmpty) continue;
    if (slide.title.isEmpty && slide.subtitle.isEmpty) continue;

    final resolved = resolveSlideAssetPath(slide.imagePath, deck.projectPath);
    final avg = resolved == null ? null : await averageImageColor(resolved);
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
