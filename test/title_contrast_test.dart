import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/models/settings.dart';
import 'package:ocideck/models/slide.dart';
import 'package:ocideck/utils/title_contrast.dart';

void main() {
  const theme = ThemeProfile(); // white title text on dark navy wash
  final titleSlide = Slide.create(SlideType.title).copyWith(title: 'Hallo');

  test(
    'white text over a bright image fails and is fixed by the grey wash',
    () {
      final eval = evaluateTitleContrast(
        avgImage: const Color(0xFFF2F2F2),
        theme: theme,
        slide: titleSlide.copyWith(titleImageOverlay: false),
      );
      expect(eval.passes, isFalse);
      expect(eval.fix, TitleContrastFix.enableOverlay);
      expect(eval.fixedRatio, greaterThanOrEqualTo(3.0));
    },
  );

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

  test('subtitle (0.72 alpha) is the binding constraint when present', () {
    // A mid-grey background where opaque white text clears 3:1 but the
    // 0.72-alpha subtitle does not. With only a subtitle present the slide
    // must be flagged, even though the opaque title would have passed.
    const grey = Color(0xFF767676);
    final titleOnly = titleSlide.copyWith(
      title: 'Alleen titel',
      subtitle: '',
      titleImageOverlay: false,
    );
    final subtitleOnly = titleSlide.copyWith(
      title: '',
      subtitle: 'Alleen ondertitel',
      titleImageOverlay: false,
    );
    final titleEval = evaluateTitleContrast(
      avgImage: grey,
      theme: theme,
      slide: titleOnly,
    );
    final subtitleEval = evaluateTitleContrast(
      avgImage: grey,
      theme: theme,
      slide: subtitleOnly,
    );
    // The subtitle's effective contrast is strictly lower than the title's.
    expect(subtitleEval.ratio, lessThan(titleEval.ratio));
  });

  test('no fix is offered when none improves on the current contrast', () {
    // Overlay already on and the wash makes a near-black background; the
    // theme text is white and already maximal, so no lever helps.
    const darkOverlayTheme = ThemeProfile(
      titleTextColor: '#FFFFFF',
      titleBackgroundColor: '#000000',
    );
    final eval = evaluateTitleContrast(
      avgImage: const Color(0xFF6E6E6E),
      theme: darkOverlayTheme,
      // Force the failing branch with a high threshold so we exercise the
      // "best lever still doesn't beat current" fallback.
      slide: titleSlide.copyWith(title: 'Hallo', titleImageOverlay: true),
      threshold: 99,
    );
    expect(eval.passes, isFalse);
    expect(eval.fix, TitleContrastFix.none);
    expect(eval.fixedRatio, eval.ratio);
  });

  test('applyTitleContrastFix sets the expected slide fields', () {
    expect(
      applyTitleContrastFix(
        titleSlide,
        TitleContrastFix.enableOverlay,
      ).titleImageOverlay,
      isTrue,
    );
    expect(
      applyTitleContrastFix(
        titleSlide,
        TitleContrastFix.lightText,
      ).titleTextColorOverride,
      '#FFFFFF',
    );
    expect(
      applyTitleContrastFix(
        titleSlide,
        TitleContrastFix.darkText,
      ).titleTextColorOverride,
      '#111827',
    );
  });

  test(
    'a tussentitel washes with its own background colour, not the title\'s',
    () {
      // Twee wassen die tegengesteld werken: de titelwas is wit (zinloos om een
      // fel beeld te temperen), de sectiewas is zwart (dempt juist goed). Boven
      // hetzelfde felle beeld met witte tekst en de waas aan faalt de titeldia
      // dus, maar slaagt de tussentitel — precies omdat de contrastcontrole nu
      // haar eigen achtergrondkleur pakt.
      const split = ThemeProfile(
        titleTextColor: '#FFFFFF',
        titleBackgroundColor: '#FFFFFF',
        sectionBackgroundColor: '#000000',
      );
      const bright = Color(0xFFF2F2F2);
      final titleEval = evaluateTitleContrast(
        avgImage: bright,
        theme: split,
        slide: Slide.create(SlideType.title).copyWith(title: 'Kop'),
      );
      final sectionEval = evaluateTitleContrast(
        avgImage: bright,
        theme: split,
        slide: Slide.create(SlideType.section).copyWith(title: 'Kop'),
      );
      expect(titleEval.passes, isFalse);
      expect(sectionEval.passes, isTrue);
    },
  );
}
