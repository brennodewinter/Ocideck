import 'dart:math' as math;

import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

import '../models/settings.dart';
import '../models/slide.dart';
import 'color_contrast.dart';

/// A single (possibly combined) lever the "Herstel" action applies to lift a
/// title slide's text above the WCAG large-text contrast threshold against its
/// background image.
enum TitleContrastFix {
  none,
  enableOverlay,
  lightText,
  darkText,
  overlayLightText,
  overlayDarkText,
}

class TitleContrastEval {
  /// Contrast ratio of the title text against the image as it stands now.
  final double ratio;
  final bool passes;

  /// Recommended fix when [passes] is false (least-intrusive that reaches the
  /// threshold; otherwise the highest-contrast option as a best effort).
  final TitleContrastFix fix;

  /// Contrast ratio that [fix] would achieve.
  final double fixedRatio;

  const TitleContrastEval({
    required this.ratio,
    required this.passes,
    required this.fix,
    required this.fixedRatio,
  });
}

/// Grey-wash opacity used by the title preview (`_TitlePreview`).
const double kTitleOverlayAlpha = 0.62;

/// The subtitle is drawn at this opacity in `_TitlePreview`, so it always has
/// lower contrast than the opaque title of the same colour — it is the binding
/// constraint whenever a subtitle is present.
const double kTitleSubtitleAlpha = 0.72;

const Color _lightText = Colors.white;
Color _darkText = AppTheme.gray900;

Color _effectiveTextColor(ThemeProfile theme, Slide slide) {
  final hex = slide.titleTextColorOverride.isNotEmpty
      ? slide.titleTextColorOverride
      : theme.titleTextColor;
  return parseHexColor(hex) ?? Colors.white;
}

Color _background(Color avgImage, ThemeProfile theme, bool overlay) {
  if (!overlay) return avgImage;
  final wash = parseHexColor(theme.titleBackgroundColor) ?? AppTheme.navy;
  return Color.alphaBlend(wash.withValues(alpha: kTitleOverlayAlpha), avgImage);
}

class _Candidate {
  final TitleContrastFix fix;
  final double ratio;
  const _Candidate(this.fix, this.ratio);
}

/// Lowest contrast across the title text actually shown on the slide: the
/// opaque title and/or the 0.72-alpha subtitle, whichever is present and worst.
/// Returns `double.infinity` when neither is present (the caller skips those).
double _bindingRatio(
  Color text,
  Color bg, {
  required bool hasTitle,
  required bool hasSubtitle,
}) {
  var worst = double.infinity;
  if (hasTitle) {
    worst = contrastRatio(text, bg);
  }
  if (hasSubtitle) {
    final subtitle = Color.alphaBlend(
      text.withValues(alpha: kTitleSubtitleAlpha),
      bg,
    );
    worst = math.min(worst, contrastRatio(subtitle, bg));
  }
  return worst;
}

/// Evaluates the title text contrast against [avgImage] (the average colour of
/// the background image), accounting for the grey wash and any per-slide text
/// colour override, and recommends a fix when it falls short.
TitleContrastEval evaluateTitleContrast({
  required Color avgImage,
  required ThemeProfile theme,
  required Slide slide,
  double threshold = kWcagAaLargeText,
}) {
  final text = _effectiveTextColor(theme, slide);
  final overlayOn = slide.titleImageOverlay;
  final hasTitle = slide.title.isNotEmpty;
  final hasSubtitle = slide.subtitle.isNotEmpty;

  double ratioFor(Color textColor, bool overlay) => _bindingRatio(
    textColor,
    _background(avgImage, theme, overlay),
    hasTitle: hasTitle,
    hasSubtitle: hasSubtitle,
  );

  final current = ratioFor(text, overlayOn);
  if (current >= threshold) {
    return TitleContrastEval(
      ratio: current,
      passes: true,
      fix: TitleContrastFix.none,
      fixedRatio: current,
    );
  }

  // Ordered least → most intrusive. The overlay (the designed readability tool)
  // comes first; a per-slide colour flip next; both combined as a last resort.
  final candidates = <_Candidate>[
    if (!overlayOn)
      _Candidate(TitleContrastFix.enableOverlay, ratioFor(text, true)),
    _Candidate(TitleContrastFix.lightText, ratioFor(_lightText, overlayOn)),
    _Candidate(TitleContrastFix.darkText, ratioFor(_darkText, overlayOn)),
    if (!overlayOn) ...[
      _Candidate(TitleContrastFix.overlayLightText, ratioFor(_lightText, true)),
      _Candidate(TitleContrastFix.overlayDarkText, ratioFor(_darkText, true)),
    ],
  ];

  _Candidate? chosen;
  for (final c in candidates) {
    if (c.ratio >= threshold) {
      chosen = c;
      break;
    }
  }
  // No single lever reaches the threshold: fall back to the best one, but only
  // if it actually improves on the current contrast — otherwise report that
  // there is no automatic fix rather than offering one that makes it worse.
  if (chosen == null) {
    final best = candidates.reduce((a, b) => b.ratio > a.ratio ? b : a);
    if (best.ratio <= current) {
      return TitleContrastEval(
        ratio: current,
        passes: false,
        fix: TitleContrastFix.none,
        fixedRatio: current,
      );
    }
    chosen = best;
  }

  return TitleContrastEval(
    ratio: current,
    passes: false,
    fix: chosen.fix,
    fixedRatio: chosen.ratio,
  );
}

/// Returns [slide] with [fix] applied.
Slide applyTitleContrastFix(Slide slide, TitleContrastFix fix) {
  return switch (fix) {
    TitleContrastFix.none => slide,
    TitleContrastFix.enableOverlay => slide.copyWith(titleImageOverlay: true),
    TitleContrastFix.lightText => slide.copyWith(
      titleTextColorOverride: '#FFFFFF',
    ),
    TitleContrastFix.darkText => slide.copyWith(
      titleTextColorOverride: '#111827',
    ),
    TitleContrastFix.overlayLightText => slide.copyWith(
      titleImageOverlay: true,
      titleTextColorOverride: '#FFFFFF',
    ),
    TitleContrastFix.overlayDarkText => slide.copyWith(
      titleImageOverlay: true,
      titleTextColorOverride: '#111827',
    ),
  };
}
