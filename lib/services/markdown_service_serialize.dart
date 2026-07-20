// Part of the markdown_service library — see markdown_service.dart.
// Split out for navigability: the per-slide-type serialisers that generateSlide
// dispatches to. Each method is the verbatim body of one `case` in the old
// switch, so the dispatch stays exhaustive (the compiler still checks every
// SlideType) and behaviour is unchanged. All imports live in the main file.
part of 'markdown_service.dart';

extension _MarkdownSerialize on MarkdownService {
  /// Emits the image crop focal point(s) as HTML comments Marp ignores, only
  /// when they differ from the centre default. `2` is the twoImages right image;
  /// on single-image slides its focal stays centred, so nothing extra is
  /// written. Round-trips via `ocideck_image_focus` in [_parseBlock].
  void _writeImageFocus(StringBuffer buf, Slide slide) {
    if (slide.imageFocalX != 0.5 || slide.imageFocalY != 0.5) {
      buf.writeln(
        '<!-- ocideck_image_focus: '
        '${_formatFocal(slide.imageFocalX)},${_formatFocal(slide.imageFocalY)}'
        ' -->',
      );
    }
    if (slide.imageFocalX2 != 0.5 || slide.imageFocalY2 != 0.5) {
      buf.writeln(
        '<!-- ocideck_image_focus2: '
        '${_formatFocal(slide.imageFocalX2)},${_formatFocal(slide.imageFocalY2)}'
        ' -->',
      );
    }
  }

  /// Focal points come from drag maths, so trim to 3 decimals and drop trailing
  /// zeros to keep the `.md` tidy (0.5 → `0.5`, not `0.500`).
  String _formatFocal(double value) {
    final rounded = (value.clamp(0.0, 1.0) * 1000).round() / 1000.0;
    return rounded.toString();
  }

  /// Emits the per-usage WCAG alt-text as HTML comments Marp ignores, only when
  /// set (AI_ASSIST §6.1). `2` is the twoImages right image. Round-trips via
  /// `ocideck_image_alt` in [_parseBlock]; `-->` is escaped like presenter notes.
  void _writeImageAlt(StringBuffer buf, Slide slide) {
    if (slide.imageAltText.isNotEmpty) {
      buf.writeln(
        '<!-- ocideck_image_alt: ${_escapeNotes(slide.imageAltText)} -->',
      );
    }
    if (slide.imageAltText2.isNotEmpty) {
      buf.writeln(
        '<!-- ocideck_image_alt2: ${_escapeNotes(slide.imageAltText2)} -->',
      );
    }
  }

  /// The optional full-slide background image, emitted before the headings so
  /// Marp reads it as a `bg` directive. Shared by the title and section dia's —
  /// a tussentitel is a heading slide too, and carries the same fields.
  void _writeSlideBackground(StringBuffer buf, Slide slide) {
    if (slide.imagePath.isEmpty) return;
    final bgOptions = [
      'bg',
      if (slide.imageSize > 0) '${slide.imageSize}%',
      if (slide.titleImageOverlay) 'opacity:.45',
    ].join(' ');
    buf.writeln('![$bgOptions](${slide.imagePath})');
    if (!slide.titleImageOverlay) {
      buf.writeln('<!-- ocideck_title_image_overlay: false -->');
    }
    _writeImageFocus(buf, slide);
    _writeImageAlt(buf, slide);
    _writeImageCaption(buf, slide.imageCaption);
    buf.writeln();
  }

  void _writeTitleSlide(StringBuffer buf, Slide slide) {
    _writeSlideBackground(buf, slide);
    if (slide.title.isNotEmpty) buf.writeln('# ${slide.title}');
    if (slide.subtitle.isNotEmpty) buf.writeln('## ${slide.subtitle}');
    if (slide.titleTextColorOverride.isNotEmpty) {
      buf.writeln(
        '<!-- ocideck_title_text_color: ${slide.titleTextColorOverride} -->',
      );
    }
  }

  void _writeSectionSlide(StringBuffer buf, Slide slide) {
    _writeSlideBackground(buf, slide);
    if (slide.title.isNotEmpty) buf.writeln('# ${slide.title}');
    if (slide.titleTextColorOverride.isNotEmpty) {
      buf.writeln(
        '<!-- ocideck_title_text_color: ${slide.titleTextColorOverride} -->',
      );
    }
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
    _writeBulletBody(buf, slide);
  }

  /// Serialise a bullet slide body: a rich-text markdown block, or a
  /// (possibly checklist/numbered) bullet list with its list-style marker.
  /// Shared by the bullets and bullets+image serialisers.
  void _writeBulletBody(StringBuffer buf, Slide slide) {
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
      if (slide.continueNumbering && slide.listStyle == ListStyle.numbered) {
        buf.writeln('<!-- ocideck_continue_numbering: true -->');
      }
      if (slide.continuesSplit) {
        buf.writeln('<!-- ocideck_continue_split: true -->');
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
    // De parser leest `## ` als ondertitel (ook uit handgeschreven decks);
    // zonder terugschrijven verdween die stilletjes bij de eerste keer opslaan.
    if (slide.subtitle.isNotEmpty) buf.writeln('## ${slide.subtitle}');
    _writeBulletMarkerOverride(buf, slide, themeProfile, forExport);
    if (slide.continuesSplit) {
      buf.writeln('<!-- ocideck_continue_split: true -->');
    }
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
      _writeBulletBody(buf, slide);
      buf.writeln();
      buf.writeln('</div>');
      buf.writeln();
      buf.writeln('<div class="split-image">');
      buf.writeln();
      buf.writeln('![](${slide.imagePath})');
      _writeImageFocus(buf, slide);
      _writeImageAlt(buf, slide);
      _writeImageCaption(buf, slide.imageCaption);
      buf.writeln();
      buf.writeln('</div>');
    } else {
      if (slide.title.isNotEmpty) buf.writeln('# ${slide.title}');
      _writeBulletMarkerOverride(buf, slide, themeProfile, forExport);
      _writeBulletBody(buf, slide);
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
    _writeImageFocus(buf, slide);
    _writeImageAlt(buf, slide);
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
      _writeImageFocus(buf, slide);
      _writeImageAlt(buf, slide);
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
    if (slide.quote.isNotEmpty) {
      // Elke regel zijn eigen `>`. De editor laat vijf regels toe, dus een
      // meerregelig citaat is gewoon te typen; zonder prefix per regel las de
      // parser alleen de eerste terug en verdween de rest bij het opslaan.
      // Een lege regel binnen het citaat wordt een kale `>`, want een regel met
      // alleen `> ` verliest zijn spatie bij het trimmen.
      for (final line in slide.quote.split('\n')) {
        buf.writeln(line.isEmpty ? '>' : '> $line');
      }
    }
    if (slide.quoteAuthor.isNotEmpty) {
      buf.writeln();
      buf.writeln('— ${slide.quoteAuthor}');
    }
  }

  /// Writes an optional heading plus [Slide.tableRows] as a plain Markdown
  /// table — the shared form of every table-backed slide type.
  ///
  /// The reporting types (`scorecard`, `assets`, `discoveries`) use it because a
  /// table is what a generator can write and a human can read without the app;
  /// for a report produced from a scan that is the whole route in. The
  /// informatieveiligheid types (`checklist` §3.2, `scopeMatrix` §4.4,
  /// `findingsSummary` §4.3.4) use it so their content stays reviewable in the
  /// `.md` file. `signOff` (§1.6/§8) carries no slide content of its own beyond
  /// an optional heading — its attestation is deck-level (`ocideck_sig_*`) — and
  /// `finding` (P1-FIND) is the one type still on the free-Markdown scaffold.
  void _writeTableSlide(StringBuffer buf, Slide slide) {
    if (slide.title.isNotEmpty) {
      buf.writeln('# ${slide.title}');
      buf.writeln();
    }
    _writeTable(buf, slide.tableRows);
  }

  /// A `signOff` slide (PENTEST_MIAUW 1.6 / §8 A1) carries no per-slide body of
  /// its own — its attestation is the deck-level visual signature
  /// (`ocideck_sig_*`, written in the front matter) and the seal. Only an
  /// optional heading is stored on the slide.
  void _writeSignOffSlide(StringBuffer buf, Slide slide) {
    if (slide.title.isNotEmpty) {
      buf.writeln('# ${slide.title}');
      buf.writeln();
    }
  }

  void _writeFreeMarkdownSlide(StringBuffer buf, Slide slide) {
    final body = escapeDeckMarkdownDashLines(slide.customMarkdown);
    buf.write(body);
    if (body.isNotEmpty && !body.endsWith('\n')) {
      buf.writeln();
    }
  }

  /// Scaffold serialiser for the Informatieveiligheid slide types (P1-S). Their
  /// body rides in [Slide.customMarkdown] as free Markdown, exactly like a
  /// free-Markdown slide; the type is carried by the `_class` token that
  /// [generateSlide] already wrote. Parse restores it via the same
  /// `d.remaining` path (see `_inferSlideType` + the customMarkdown assignment
  /// in the parser). Per-type serialisers replace this in P1-FIND/CHK/SCOPE/
  /// SUM/SIGN once each type gains structured fields.
  void _writeScaffoldSlide(StringBuffer buf, Slide slide) =>
      _writeFreeMarkdownSlide(buf, slide);

  void _writeCodeSlide(StringBuffer buf, Slide slide) {
    if (slide.title.isNotEmpty) {
      buf.writeln('# ${slide.title}');
      buf.writeln();
    }
    final fence = fenceFor(slide.customMarkdown);
    buf.writeln('$fence${slide.codeLanguage.trim()}');
    buf.write(slide.customMarkdown);
    if (slide.customMarkdown.isNotEmpty &&
        !slide.customMarkdown.endsWith('\n')) {
      buf.writeln();
    }
    buf.writeln(fence);
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
    if (slide.timelineAnimationMs != null) {
      buf.writeln(
        '<!-- ocideck_timeline_duration: ${slide.timelineAnimationMs} -->',
      );
    }
    if (slide.timelineCurrentIndex != null) {
      // Written 1-based so the comment reads as "the Nth event" in the raw .md.
      buf.writeln(
        '<!-- ocideck_timeline_current: ${slide.timelineCurrentIndex! + 1} -->',
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
