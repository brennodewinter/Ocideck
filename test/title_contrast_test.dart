import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/models/settings.dart';
import 'package:ocideck/models/slide.dart';
import 'package:ocideck/utils/title_contrast.dart';

void main() {
  const theme = ThemeProfile(); // white title text on dark navy wash
  final titleSlide = Slide.create(SlideType.title).copyWith(title: 'Hallo');

  test('white text over a bright image fails and is fixed by the grey wash', () {
    final eval = evaluateTitleContrast(
      avgImage: const Color(0xFFF2F2F2),
      theme: theme,
      slide: titleSlide.copyWith(titleImageOverlay: false),
    );
    expect(eval.passes, isFalse);
    expect(eval.fix, TitleContrastFix.enableOverlay);
    expect(eval.fixedRatio, greaterThanOrEqualTo(3.0));
  });

  test('white text over a dark image already passes', () {
    final eval = evaluateTitleContrast(
      avgImage: const Color(0xFF1A1A1A),
      theme: theme,
      slide: titleSlide.copyWith(titleImageOverlay: false),
    );
    expect(eval.passes, isTrue);
    expect(eval.fix, TitleContrastFix.none);
  });

  test('dark theme text over a dark image is fixed by switching to light', () {
    const darkTextTheme = ThemeProfile(titleTextColor: '#111827');
    final eval = evaluateTitleContrast(
      avgImage: const Color(0xFF222222),
      theme: darkTextTheme,
      slide: titleSlide.copyWith(titleImageOverlay: false),
    );
    expect(eval.passes, isFalse);
    // The navy wash would only darken an already-dark image, so the fix flips
    // the text light rather than enabling the overlay.
    expect(eval.fix, TitleContrastFix.lightText);
    expect(eval.fixedRatio, greaterThanOrEqualTo(3.0));
  });

  test('applyTitleContrastFix sets the expected slide fields', () {
    expect(
      applyTitleContrastFix(titleSlide, TitleContrastFix.enableOverlay)
          .titleImageOverlay,
      isTrue,
    );
    expect(
      applyTitleContrastFix(titleSlide, TitleContrastFix.lightText)
          .titleTextColorOverride,
      '#FFFFFF',
    );
    expect(
      applyTitleContrastFix(titleSlide, TitleContrastFix.darkText)
          .titleTextColorOverride,
      '#111827',
    );
  });
}
