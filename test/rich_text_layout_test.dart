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
      expect(normalizeRichTextMarkdown('woord\u00ADbreuk'), 'woordbreuk');
    });

    test('unescapes hyphen escapes anywhere in the line', () {
      const input = 'Intro\n\\- regel\nmidden\\-woord';
      expect(normalizeRichTextMarkdown(input), 'Intro\n- regel\nmidden-woord');
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

  group('logo-safe geometry', () {
    const w = kReferenceSlideWidth;
    Slide richSlide(int paras) => Slide.create(SlideType.bullets).copyWith(
      title: 'Titel',
      listStyle: ListStyle.richText,
      customMarkdown: List.generate(
        paras,
        (i) => 'Alinea $i met wat tekst om hoogte op te bouwen.',
      ).join('\n\n'),
    );
    const noLogo = ThemeProfile();
    const bottomLogo = ThemeProfile(
      logoPath: 'logo.png',
      logoPosition: 'bottom-right',
      logoSize: 160,
    );
    // #1932: groot logo waarvan de gereduceerde reserve de default-padding
    // overstijgt — zo blijft het effect op de body-hoogte zichtbaar.
    const bigBottomLogo = ThemeProfile(
      logoPath: 'logo.png',
      logoPosition: 'bottom-right',
      logoSize: 480,
    );
    // Top-logo heeft een grotere edge inset (0.42 vs 0.12), dus de gereduceerde
    // reserve is groot genoeg om paginering te beïnvloeden.
    const bigTopLogo = ThemeProfile(
      logoPath: 'logo.png',
      logoPosition: 'top-right',
      logoSize: 480,
    );

    test('logoSafeReserve clears the logo far edge, zero without a logo', () {
      expect(logoSafeReserve(w, noLogo), 0);
      // Bottom logo: size*0.12 + w*0.014 (#1932: reduced from size*1.12).
      const size = w * (160 / 1280);
      expect(
        logoSafeReserve(w, bottomLogo),
        closeTo(size * 0.12 + w * 0.014, 1e-6),
      );
      // Corner mode (panel slides): no vertical reserve.
      expect(logoSafeReserve(w, bottomLogo, corner: true), 0);
    });

    test('a shown logo shrinks the rich-text body height', () {
      final slide = richSlide(6);
      // #1932: de gereduceerde reserve is voor een klein logo kleiner dan de
      // default-padding, dus pas een groot logo (480px) verkleint de body.
      final withLogo = richTextBodyAvailH(
        w,
        slide,
        bigBottomLogo,
        splitWithImage: false,
      );
      final without = richTextBodyAvailH(
        w,
        slide,
        noLogo,
        splitWithImage: false,
      );
      expect(withLogo, lessThan(without));
    });

    test('page count accounts for the logo reserve', () {
      // Content tuned to sit right at the one-page boundary: reserving logo
      // space must push it onto a second page, matching what the preview draws.
      Slide slide(int p) => richSlide(p);
      var paras = 1;
      // Find a paragraph count that still fits on one page without a logo.
      while (paras < 40 &&
          richTextPageCountForSlide(slide: slide(paras), profile: noLogo) ==
              1) {
        paras++;
      }
      final borderline = slide(paras - 1); // fits on one page, no logo
      expect(richTextPageCountForSlide(slide: borderline, profile: noLogo), 1);
      // The same slide with a large logo needs the reserved strip → 2 pages.
      // #1932: gebruikt bigTopLogo (480px, top) want de gereduceerde reserve
      // van een klein of bottom-logo is kleiner dan de default-padding.
      expect(
        richTextPageCountForSlide(slide: borderline, profile: bigTopLogo),
        greaterThan(1),
      );
    });
  });

  group('bulletsSlideBottomInset', () {
    test('reserves the footer band plus a cushion under the text column', () {
      const w = kReferenceSlideWidth;
      final slide = Slide.create(SlideType.bullets).copyWith(showFooter: true);
      final profile = ThemeProfile(
        footerText: 'Confidentieel',
        footerShowPageNumbers: true,
      );
      final footer = footerSafeInset(w: w, slide: slide, profile: profile);
      expect(footer, greaterThan(0));
      final inset = bulletsSlideBottomInset(
        w: w,
        slide: slide,
        profile: profile,
        defaultBottomPad: w * 0.05,
      );
      // De onderste tekstregel moet boven de footerband blijven, niet erachter.
      expect(inset, greaterThan(footer));
    });

    test('a larger bottom-logo reserve wins over the footer band', () {
      const w = kReferenceSlideWidth;
      final slide = Slide.create(SlideType.bullets).copyWith(showFooter: true);
      final profile = ThemeProfile(
        footerText: 'Confidentieel',
        footerShowPageNumbers: true,
      );
      final inset = bulletsSlideBottomInset(
        w: w,
        slide: slide,
        profile: profile,
        defaultBottomPad: w * 0.05,
        safeBottom: w * 0.2,
      );
      expect(inset, w * 0.2);
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
      // Elke pagina houdt de render-marge vrij: een tot op de pixel volle
      // pagina knipt zijn onderste regel af op de logo-/footergrens.
      expect(
        tallest,
        lessThanOrEqualTo(budget - w * kRichTextRenderSlopFraction + 0.5),
      );
    });
  });

  group('expandRichTextForRender', () {
    const profile = ThemeProfile();

    /// Een vrije-tekstslide met [paras] alinea's — genoeg om te pagineren.
    Slide richSlide(int paras) => Slide.create(SlideType.bullets).copyWith(
      title: 'Titel',
      listStyle: ListStyle.richText,
      customMarkdown: List.generate(
        paras,
        (i) => 'Alinea $i met wat tekst om hoogte op te bouwen.',
      ).join('\n\n'),
    );

    test('makes one slide per page, numbered from zero', () {
      final slide = richSlide(40);
      final pages = richTextPageCountForSlide(slide: slide, profile: profile);
      expect(pages, greaterThan(1), reason: 'testopzet: moet pagineren');

      final expanded = expandRichTextForRender([slide], profile);
      expect(expanded, hasLength(pages));
      expect(
        [for (final s in expanded) s.renderPage],
        [for (var i = 0; i < pages; i++) i],
      );
    });

    test('every page keeps the whole body and the slide id', () {
      // De gedeelde lettergrootte is een eigenschap van de héle body: geef je
      // een renderer één pagina los, dan schaalt die pagina op zichzelf en
      // verspringt de tekstgrootte van pagina tot pagina.
      final slide = richSlide(40);
      final expanded = expandRichTextForRender([slide], profile);
      for (final page in expanded) {
        expect(page.customMarkdown, slide.customMarkdown);
        expect(page.id, slide.id);
      }
    });

    test('leaves a slide that fits on one page untouched', () {
      final slide = richSlide(1);
      expect(richTextPageCountForSlide(slide: slide, profile: profile), 1);
      expect(expandRichTextForRender([slide], profile), [slide]);
    });

    test('leaves slides of other types alone', () {
      final table = Slide.create(SlideType.table);
      final bullets = Slide.create(
        SlideType.bullets,
      ).copyWith(bullets: const ['een', 'twee']);
      expect(expandRichTextForRender([table, bullets], profile), [
        table,
        bullets,
      ]);
    });

    test('expands a freeMarkdown slide just like bullets-rich-text', () {
      // Sinds #1409 pagineert free-markdown mee; de export-uitklap hoort elke
      // pagina als eigen slide te rasteriseren, anders tekent hij alleen pagina
      // 1. Eerdere aanname was dat free-markdown geen paginabegrip kende.
      final slide = richSlide(40).copyWith(type: SlideType.freeMarkdown);
      final expanded = expandRichTextForRender([slide], profile);
      expect(expanded.length, greaterThan(1));
      for (final page in expanded) {
        expect(page.customMarkdown, slide.customMarkdown);
        expect(page.id, slide.id);
      }
    });
  });
}
