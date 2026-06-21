import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/models/settings.dart';
import 'package:ocideck/models/slide.dart';
import 'package:ocideck/services/markdown_body_blocks.dart';
import 'package:ocideck/services/rich_text_layout.dart';
import 'package:ocideck/services/slide_layout_metrics.dart';
import 'package:ocideck/utils/markdown_paste_cleanup.dart';

void main() {
  group('normalizeRichTextMarkdown', () {
    test('removes spurious leading hyphen escapes from Quill export', () {
      const input = 'Intro\n\\- Dit is geen lijst\n\\- Nog een regel';
      expect(
        normalizeRichTextMarkdown(input),
        'Intro\n- Dit is geen lijst\n- Nog een regel',
      );
    });

    test('strips soft hyphens copied from news sites', () {
      expect(
        normalizeRichTextMarkdown('woord\u00ADbreuk'),
        'woordbreuk',
      );
    });

    test('unescapes hyphen escapes anywhere in the line', () {
      const input = 'Intro\n\\- regel\nmidden\\-woord';
      expect(
        normalizeRichTextMarkdown(input),
        'Intro\n- regel\nmidden-woord',
      );
    });

    test('unescapes dotted and parenthesis escapes from web paste', () {
      expect(
        normalizeRichTextMarkdown(r'Een zin\. Nog een'),
        'Een zin. Nog een',
      );
    });
  });

  group('planRichTextLayout', () {
    test('grows short text toward max scale on a single page', () {
      const w = kReferenceSlideWidth;
      final plan = planRichTextLayout(
        markdown: 'Korte tekst.',
        availW: w * 0.86,
        availH: w * 9 / 16 * 0.75,
        refW: w,
        hasTitle: false,
        title: '',
        subtitle: '',
        titleSize: w * 0.042,
        subtitleSize: w * 0.03,
        spacing: w * 0.035,
        bodySize: w * 0.026,
        font: 'Inter',
        footerInset: w * 0.055,
        maxScale: 2.5,
      );
      expect(plan.pageCount, 1);
      expect(plan.scale, greaterThan(1.0));
    });

    test('paginates when text exceeds minimum scale on one page', () {
      const w = kReferenceSlideWidth;
      final longBody = List.generate(
        120,
        (i) =>
            'Paragraaf $i met extra tekst over meerdere woorden om de hoogte op te bouwen.',
      ).join('\n\n');
      final plan = planRichTextLayout(
        markdown: longBody,
        availW: w * 0.86,
        availH: w * 9 / 16 * 0.75,
        refW: w,
        hasTitle: true,
        title: 'Lang artikel',
        subtitle: '',
        titleSize: w * 0.042,
        subtitleSize: w * 0.03,
        spacing: w * 0.035,
        bodySize: w * 0.026,
        font: 'Inter',
        footerInset: w * 0.055,
        minScale: kTextDensityCriticalScale,
        maxScale: 1.0,
      );
      expect(plan.pageCount, greaterThan(1));
      expect(plan.pageMarkdown.first, isNot(contains('Lang artikel')));
      expect(plan.pageMarkdown.first.trim(), isNotEmpty);
    });

    test('paginates with a smaller viewport', () {
      const w = kReferenceSlideWidth;
      final longBody = List.generate(
        80,
        (i) => 'Regel $i: ${'woord ' * 12}',
      ).join('\n\n');
      final plan = planRichTextLayout(
        markdown: longBody,
        availW: w * 0.86,
        availH: w * 9 / 16 * 0.35,
        refW: w,
        hasTitle: false,
        title: '',
        subtitle: '',
        titleSize: w * 0.042,
        subtitleSize: w * 0.03,
        spacing: w * 0.035,
        bodySize: w * 0.026,
        font: 'Inter',
        footerInset: w * 0.055,
        minScale: kTextDensityCriticalScale,
        maxScale: 1.0,
      );
      expect(plan.pageCount, greaterThan(1));
    });
  });

  group('planRichTextForSlide', () {
    test('respects footer inset for bullets rich-text slides', () {
      const w = kReferenceSlideWidth;
      final slide = Slide.create(SlideType.bullets).copyWith(
        listStyle: ListStyle.richText,
        customMarkdown: List.generate(
          80,
          (i) => 'Regel $i: ${'woord ' * 14}',
        ).join('\n\n'),
        showFooter: true,
      );
      final profile = ThemeProfile(
        footerText: 'Confidentieel',
        footerShowPageNumbers: true,
      );
      final plan = planRichTextForSlide(
        slide: slide,
        profile: profile,
        w: w,
        availW: w * 0.86,
        availH: w * 9 / 16 * 0.35,
        font: 'Inter',
      );
      expect(plan.pageCount, greaterThan(1));
    });

    test('paginated narrow column grows scale to fill page height', () {
      const w = kReferenceSlideWidth;
      const splitHPad = w * 0.038;
      const imgFraction = 0.40;
      final contentW = w - imgFraction * w - splitHPad * 2;
      final contentH = w * 9 / 16 - w * 0.042 * 2;
      final budget = contentH;
      final longBody = List.generate(
        24,
        (i) =>
            'Paragraaf $i met extra tekst over meerdere woorden om te wrapen in de smalle kolom.',
      ).join('\n\n');
      final plan = planRichTextLayout(
        markdown: longBody,
        availW: contentW,
        availH: contentH,
        refW: w,
        hasTitle: true,
        title: 'Titel',
        subtitle: '',
        titleSize: w * 0.042,
        subtitleSize: w * 0.03,
        spacing: w * 0.042 * 0.32,
        bodySize: w * 0.031,
        font: 'Inter',
        footerInset: 0,
        minScale: kTextDensityWarningScale,
        maxScale: kBulletsMaxScale,
      );
      expect(plan.pageCount, greaterThan(1));
      expect(plan.scale, greaterThanOrEqualTo(kTextDensityWarningScale));

      var tallest = 0.0;
      for (var i = 0; i < plan.pageCount; i++) {
        var h = measureMarkdownBlocksHeight(
          blocks: parseMarkdownBodyBlocks(plan.pageMarkdown[i]),
          scale: plan.scale,
          contentW: contentW,
          refW: w,
          bodySize: w * 0.031,
          font: 'Inter',
        );
        if (i == 0) {
          h += measureTextHeight(
            'Titel',
            w * 0.042 * plan.scale,
            contentW,
            bold: true,
            fontFamily: 'Inter',
          );
          h += w * 0.042 * 0.32 * plan.scale;
        }
        if (h > tallest) tallest = h;
      }
      expect(tallest / budget, greaterThan(0.85));
    });
  });
}
