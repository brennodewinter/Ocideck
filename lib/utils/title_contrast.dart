import 'package:flutter/material.dart';

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

const Color _lightText = Color(0xFFFFFFFF);
const Color _darkText = Color(0xFF111827);

Color _effectiveTextColor(ThemeProfile theme, Slide slide) {
  final hex = slide.titleTextColorOverride.isNotEmpty
      ? slide.titleTextColorOverride
      : theme.titleTextColor;
  return parseHexColor(hex) ?? const Color(0xFFFFFFFF);
}

Color _background(Color avgImage, ThemeProfile theme, bool overlay) {
  if (!overlay) return avgImage;
  final wash =
      parseHexColor(theme.titleBackgroundColor) ?? const Color(0xFF1C2B47);
  return Color.alphaBlend(wash.withValues(alpha: kTitleOverlayAlpha), avgImage);
}

class _Candidate {
  final TitleContrastFix fix;
  final double ratio;
  const _Candidate(this.fix, this.ratio);
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
  final current = contrastRatio(text, _background(avgImage, theme, overlayOn));

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
      _Candidate(
        TitleContrastFix.enableOverlay,
        contrastRatio(text, _background(avgImage, theme, true)),
      ),
    _Candidate(
      TitleContrastFix.lightText,
      contrastRatio(_lightText, _background(avgImage, theme, overlayOn)),
    ),
    _Candidate(
      TitleContrastFix.darkText,
      contrastRatio(_darkText, _background(avgImage, theme, overlayOn)),
    ),
    if (!overlayOn) ...[
      _Candidate(
        TitleContrastFix.overlayLightText,
        contrastRatio(_lightText, _background(avgImage, theme, true)),
      ),
      _Candidate(
        TitleContrastFix.overlayDarkText,
        contrastRatio(_darkText, _background(avgImage, theme, true)),
      ),
    ],
  ];

  _Candidate? chosen;
  for (final c in candidates) {
    if (c.ratio >= threshold) {
      chosen = c;
      break;
    }
  }
  chosen ??= candidates.reduce((a, b) => b.ratio > a.ratio ? b : a);

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
