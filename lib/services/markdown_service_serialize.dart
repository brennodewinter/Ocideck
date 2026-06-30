// Part of the markdown_service library — see markdown_service.dart.
// Split out for navigability: the per-slide-type serialisers that generateSlide
// dispatches to. Each method is the verbatim body of one `case` in the old
// switch, so the dispatch stays exhaustive (the compiler still checks every
// SlideType) and behaviour is unchanged. All imports live in the main file.
part of 'markdown_service.dart';

extension _MarkdownSerialize on MarkdownService {
  void _writeTitleSlide(StringBuffer buf, Slide slide) {
    // Background image before headings so Marp treats it as a bg directive
    if (slide.imagePath.isNotEmpty) {
      final bgOptions = [
        'bg',
        if (slide.imageSize > 0) '${slide.imageSize}%',
        if (slide.titleImageOverlay) 'opacity:.45',
      ].join(' ');
      buf.writeln('![$bgOptions](${slide.imagePath})');
      if (!slide.titleImageOverlay) {
        buf.writeln('<!-- ocideck_title_image_overlay: false -->');
      }
      _writeImageCaption(buf, slide.imageCaption);
      buf.writeln();
    }
    if (slide.title.isNotEmpty) buf.writeln('# ${slide.title}');
    if (slide.subtitle.isNotEmpty) buf.writeln('## ${slide.subtitle}');
    if (slide.titleTextColorOverride.isNotEmpty) {
      buf.writeln(
        '<!-- ocideck_title_text_color: ${slide.titleTextColorOverride} -->',
      );
    }
  }

  void _writeSectionSlide(StringBuffer buf, Slide slide) {
    if (slide.title.isNotEmpty) buf.writeln('# ${slide.title}');
    if (slide.subtitle.isNotEmpty) {
      buf.writeln();
      buf.writeln(slide.subtitle);
    }
  }

  void _writeBulletsSlide(
    StringBuffer buf,
    Slide slide,
    ThemeProfile? themeProfile,
    bool forExport,
  ) {
    if (slide.title.isNotEmpty) buf.writeln('# ${slide.title}');
    if (slide.subtitle.isNotEmpty) buf.writeln('## ${slide.subtitle}');
    _writeBulletMarkerOverride(buf, slide, themeProfile, forExport);
    if (slide.listStyle == ListStyle.richText) {
      buf.writeln('<!-- ocideck_list_style: richText -->');
      buf.writeln();
      final body = escapeDeckMarkdownDashLines(slide.customMarkdown);
      buf.write(body);
      if (body.isNotEmpty && !body.endsWith('\n')) {
        buf.writeln();
      }
    } else {
      if (slide.listStyle != ListStyle.bullets) {
        buf.writeln('<!-- ocideck_list_style: ${slide.listStyle.name} -->');
      }
      _writeChecklistProgress(buf, slide);
      buf.writeln();
      _writeList(buf, slide.bullets, slide.listStyle);
    }
  }

  void _writeTwoBulletsSlide(
    StringBuffer buf,
    Slide slide,
    ThemeProfile? themeProfile,
    bool forExport,
  ) {
    if (slide.title.isNotEmpty) buf.writeln('# ${slide.title}');
    _writeBulletMarkerOverride(buf, slide, themeProfile, forExport);
    buf.writeln();
    _writeTwoBulletColumns(
      buf,
      slide.bullets,
      slide.bullets2,
      slide.columnTitle1,
      slide.columnTitle2,
      slide.listStyle,
      slide.showChecklistProgress,
      themeProfile ?? const ThemeProfile(),
    );
  }

  void _writeBulletsImageSlide(
    StringBuffer buf,
    Slide slide,
    ThemeProfile? themeProfile,
    bool forExport,
  ) {
    if (slide.imagePath.isNotEmpty) {
      final pct = (slide.imageSize > 0 ? slide.imageSize : 40).clamp(20, 70);
      final textScale = _splitTextScale(slide);
      buf.writeln(
        '<!-- _style: --image-width: $pct%; --split-text-scale: ${textScale.toStringAsFixed(2)}; -->',
      );
      buf.writeln();
      buf.writeln(
        '<div class="split-text" style="font-size: ${textScale.toStringAsFixed(2)}em">',
      );
      buf.writeln();
      if (slide.title.isNotEmpty) buf.writeln('# ${slide.title}');
      _writeBulletMarkerOverride(buf, slide, themeProfile, forExport);
      if (slide.listStyle == ListStyle.richText) {
        buf.writeln('<!-- ocideck_list_style: richText -->');
        buf.writeln();
        final body = escapeDeckMarkdownDashLines(slide.customMarkdown);
        buf.write(body);
        if (body.isNotEmpty && !body.endsWith('\n')) {
          buf.writeln();
        }
      } else {
        if (slide.listStyle != ListStyle.bullets) {
          buf.writeln('<!-- ocideck_list_style: ${slide.listStyle.name} -->');
        }
        _writeChecklistProgress(buf, slide);
        buf.writeln();
        _writeList(buf, slide.bullets, slide.listStyle);
      }
      buf.writeln();
      buf.writeln('</div>');
      buf.writeln();
      buf.writeln('<div class="split-image">');
      buf.writeln();
      buf.writeln('![](${slide.imagePath})');
      _writeImageCaption(buf, slide.imageCaption);
      buf.writeln();
      buf.writeln('</div>');
    } else {
      if (slide.title.isNotEmpty) buf.writeln('# ${slide.title}');
      _writeBulletMarkerOverride(buf, slide, themeProfile, forExport);
      if (slide.listStyle == ListStyle.richText) {
        buf.writeln('<!-- ocideck_list_style: richText -->');
        buf.writeln();
        final body = escapeDeckMarkdownDashLines(slide.customMarkdown);
        buf.write(body);
        if (body.isNotEmpty && !body.endsWith('\n')) {
          buf.writeln();
        }
      } else {
        if (slide.listStyle != ListStyle.bullets) {
          buf.writeln('<!-- ocideck_list_style: ${slide.listStyle.name} -->');
        }
        _writeChecklistProgress(buf, slide);
        buf.writeln();
        _writeList(buf, slide.bullets, slide.listStyle);
      }
    }
  }

  void _writeTwoImagesSlide(StringBuffer buf, Slide slide) {
    final splitPct = slide.imageSize > 0 ? slide.imageSize : 50;
    if (slide.imagePath.isNotEmpty) {
      buf.writeln('![bg left:$splitPct%](${slide.imagePath})');
    }
    if (slide.imagePath2.isNotEmpty) {
      buf.writeln('![bg right:${100 - splitPct}%](${slide.imagePath2})');
    }
    _writeCaptionDiv(
      buf,
      _joinTwoCaptions(slide.imageCaption, slide.imageCaption2),
    );
    if (slide.title.isNotEmpty) {
      buf.writeln();
      buf.writeln('# ${slide.title}');
    }
  }

  void _writeImageSlide(StringBuffer buf, Slide slide) {
    if (slide.imagePath.isNotEmpty) {
      final sizeSpec = slide.imageSize > 0 ? ' ${slide.imageSize}%' : '';
      buf.writeln('![bg$sizeSpec](${slide.imagePath})');
      _writeImageCaption(buf, slide.imageCaption);
    }
    if (slide.title.isNotEmpty) {
      buf.writeln();
      buf.writeln('# ${slide.title}');
    }
  }

  void _writeVideoSlide(StringBuffer buf, Slide slide, bool forExport) {
    if (slide.title.isNotEmpty) {
      buf.writeln('# ${slide.title}');
      buf.writeln();
    }
    if (slide.videoPath.isNotEmpty) {
      _writeVideo(buf, slide, forExport: forExport);
    }
  }

  void _writeQuoteSlide(StringBuffer buf, Slide slide) {
    if (slide.imagePath.isNotEmpty) {
      final sizeSpec = slide.imageSize > 0 ? '${slide.imageSize}% ' : '';
      buf.writeln('![bg ${sizeSpec}opacity:.45](${slide.imagePath})');
      _writeImageCaption(buf, slide.imageCaption);
      buf.writeln();
    }
    if (slide.quote.isNotEmpty) buf.writeln('> ${slide.quote}');
    if (slide.quoteAuthor.isNotEmpty) {
      buf.writeln();
      buf.writeln('— ${slide.quoteAuthor}');
    }
  }

  void _writeTableSlide(StringBuffer buf, Slide slide) {
    if (slide.title.isNotEmpty) {
      buf.writeln('# ${slide.title}');
      buf.writeln();
    }
    _writeTable(buf, slide.tableRows);
  }

  void _writeFreeMarkdownSlide(StringBuffer buf, Slide slide) {
    final body = escapeDeckMarkdownDashLines(slide.customMarkdown);
    buf.write(body);
    if (body.isNotEmpty && !body.endsWith('\n')) {
      buf.writeln();
    }
  }

  void _writeCodeSlide(StringBuffer buf, Slide slide) {
    if (slide.title.isNotEmpty) {
      buf.writeln('# ${slide.title}');
      buf.writeln();
    }
    buf.writeln('```${slide.codeLanguage.trim()}');
    buf.write(slide.customMarkdown);
    if (slide.customMarkdown.isNotEmpty &&
        !slide.customMarkdown.endsWith('\n')) {
      buf.writeln();
    }
    buf.writeln('```');
  }

  void _writeChartSlide(StringBuffer buf, Slide slide, bool inlineChartData) {
    // Re-serialize so inline data is dropped when the chart links a CSV
    // (the .md keeps only the spec + source; the CSV stays the source).
    final spec = ChartSpec.parse(slide.customMarkdown);
    buf.writeln('```chart');
    buf.writeln(spec.toBlock(forStorage: !inlineChartData));
    buf.writeln('```');
  }

  void _writeCockpitSlide(StringBuffer buf, Slide slide) {
    final spec = CockpitSpec.parse(slide.customMarkdown);
    if (slide.title.isNotEmpty) {
      buf.writeln('# ${slide.title}');
      buf.writeln();
    }
    buf.writeln('```cockpit');
    buf.writeln(spec.toBlock());
    buf.writeln('```');
  }

  void _writeTimelineSlide(StringBuffer buf, Slide slide) {
    // Events are a plain Markdown list (`- marker :: title :: desc`), so the
    // slide stays a readable, Marp-compatible list. Layout/animation mode
    // live in the `_class` tokens written above; the (non-default) draw-in
    // duration round-trips in an HTML comment Marp ignores.
    if (slide.title.isNotEmpty) {
      buf.writeln('# ${slide.title}');
      buf.writeln();
    }
    if (slide.timelineAnimationMs != timelineDefaultAnimationDurationMs) {
      buf.writeln(
        '<!-- ocideck_timeline_duration: ${slide.timelineAnimationMs} -->',
      );
    }
    _writeList(buf, slide.bullets, ListStyle.bullets);
  }

  void _writeQuestionSlide(StringBuffer buf, Slide slide) {
    final spec = QuestionSpec.parse(slide.customMarkdown);
    if (slide.title.isNotEmpty) {
      buf.writeln('# ${slide.title}');
      buf.writeln();
    }
    if (slide.imagePath.isNotEmpty) {
      if (slide.imageSize > 0) {
        // Reuse the shared split-width comment so it round-trips via the
        // existing `_style` capture in _parseBlock.
        buf.writeln('<!-- _style: --image-width: ${slide.imageSize}%; -->');
      }
      buf.writeln('![](${slide.imagePath})');
      _writeImageCaption(buf, slide.imageCaption);
      buf.writeln();
    }
    buf.writeln('```question');
    buf.writeln(spec.toBlock());
    buf.writeln('```');
  }
}
