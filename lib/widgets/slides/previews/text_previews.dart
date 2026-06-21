// Part of the slide_preview library — see ../slide_preview.dart.
// Split out for navigability; all imports live in the main library file.
part of '../slide_preview.dart';

class _TitlePreview extends StatelessWidget {
  final Slide slide;
  final double w;
  final String? projectPath;
  final String font;
  final ThemeProfile profile;

  const _TitlePreview({
    required this.slide,
    required this.w,
    this.projectPath,
    required this.font,
    required this.profile,
  });

  Widget _content(BuildContext context) {
    final pad = w * 0.08;
    final link = _hexColor(profile.accentColor);
    return FittedBox(
      fit: BoxFit.scaleDown,
      alignment: Alignment.center,
      child: SizedBox(
        width: w,
        child: Padding(
          padding: EdgeInsets.all(pad),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (slide.title.isNotEmpty)
                _md(
                  context,
                  slide.title,
                  _applyFont(
                    font,
                    TextStyle(
                      color: _hexColor(profile.titleTextColor),
                      fontSize: w * 0.055,
                      fontWeight: FontWeight.bold,
                      height: 1.2,
                    ),
                  ),
                  linkColor: link,
                ),
              if (slide.subtitle.isNotEmpty) ...[
                SizedBox(height: w * 0.02),
                _md(
                  context,
                  slide.subtitle,
                  _applyFont(
                    font,
                    TextStyle(
                      color: _hexColor(
                        profile.titleTextColor,
                      ).withValues(alpha: 0.72),
                      fontSize: w * 0.03,
                      height: 1.3,
                    ),
                  ),
                  linkColor: link,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final hasBg = slide.imagePath.isNotEmpty;

    if (!hasBg) {
      return Container(
        color: _hexColor(profile.titleBackgroundColor),
        child: SizedBox.expand(child: _content(context)),
      );
    }

    return Stack(
      fit: StackFit.expand,
      children: [
        _zoomedImage(
          context,
          slide.imagePath,
          projectPath,
          slide.imageSize,
          bgColor: _hexColor(profile.titleBackgroundColor),
        ),
        if (slide.titleImageOverlay)
          Container(
            color: _hexColor(
              profile.titleBackgroundColor,
            ).withValues(alpha: 0.62),
          ),
        _content(context),
        _captionOverlay(context, slide.imageCaption, w),
      ],
    );
  }
}

class _SectionPreview extends StatelessWidget {
  final Slide slide;
  final double w;
  final String font;
  final ThemeProfile profile;

  const _SectionPreview({
    required this.slide,
    required this.w,
    required this.font,
    required this.profile,
  });

  @override
  Widget build(BuildContext context) {
    final pad = w * 0.08;
    return Container(
      color: _hexColor(profile.sectionBackgroundColor),
      child: SizedBox.expand(
        child: FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.center,
          child: SizedBox(
            width: w,
            child: Padding(
              padding: EdgeInsets.all(pad),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (slide.title.isNotEmpty)
                    _md(
                      context,
                      slide.title,
                      _applyFont(
                        font,
                        TextStyle(
                          color: _hexColor(profile.titleTextColor),
                          fontSize: w * 0.05,
                          fontWeight: FontWeight.bold,
                          height: 1.2,
                        ),
                      ),
                      linkColor: _hexColor(profile.accentColor),
                    ),
                  if (slide.subtitle.isNotEmpty) ...[
                    SizedBox(height: w * 0.015),
                    _md(
                      context,
                      slide.subtitle,
                      _applyFont(
                        font,
                        TextStyle(
                          color: _hexColor(
                            profile.titleTextColor,
                          ).withValues(alpha: 0.72),
                          fontSize: w * 0.025,
                        ),
                      ),
                      linkColor: _hexColor(profile.accentColor),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _QuotePreview extends StatelessWidget {
  final Slide slide;
  final double w;
  final String font;
  final String? projectPath;
  final ThemeProfile profile;

  const _QuotePreview({
    required this.slide,
    required this.w,
    required this.font,
    this.projectPath,
    required this.profile,
  });

  @override
  Widget build(BuildContext context) {
    final pad = w * 0.08;
    final hasBg = slide.imagePath.isNotEmpty;
    final textColor = hasBg ? Colors.white : _hexColor(profile.textColor);
    final authorColor = hasBg ? Colors.white70 : Colors.grey[600]!;
    final accentColor = hasBg ? Colors.white : _hexColor(profile.accentColor);

    final content = FittedBox(
      fit: BoxFit.scaleDown,
      alignment: Alignment.center,
      child: SizedBox(
        width: w,
        child: Padding(
          padding: EdgeInsets.all(pad),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: w * 0.008,
                    height: w * 0.12,
                    color: accentColor,
                    margin: EdgeInsets.only(right: pad * 0.4),
                  ),
                  Expanded(
                    child: _md(
                      context,
                      slide.quote.isEmpty ? '' : '"${slide.quote}"',
                      _applyFont(
                        font,
                        TextStyle(
                          fontSize: w * 0.033,
                          fontStyle: FontStyle.italic,
                          color: textColor,
                          height: 1.4,
                        ),
                      ),
                      linkColor: accentColor,
                    ),
                  ),
                ],
              ),
              if (slide.quoteAuthor.isNotEmpty) ...[
                SizedBox(height: pad * 0.6),
                _md(
                  context,
                  '— ${slide.quoteAuthor}',
                  _applyFont(
                    font,
                    TextStyle(
                      fontSize: w * 0.026,
                      color: authorColor,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  linkColor: accentColor,
                ),
              ],
            ],
          ),
        ),
      ),
    );

    if (!hasBg) {
      return Container(
        color: _hexColor(profile.slideBackgroundColor),
        child: SizedBox.expand(child: content),
      );
    }

    return Stack(
      fit: StackFit.expand,
      children: [
        _zoomedImage(
          context,
          slide.imagePath,
          projectPath,
          slide.imageSize,
          bgColor: _hexColor(profile.slideBackgroundColor),
        ),
        Container(color: Colors.black.withValues(alpha: 0.52)),
        content,
        _captionOverlay(context, slide.imageCaption, w),
      ],
    );
  }
}

class _MarkdownPreview extends StatelessWidget {
  final Slide slide;
  final double w;
  final String font;
  final ThemeProfile profile;

  const _MarkdownPreview({
    required this.slide,
    required this.w,
    required this.font,
    required this.profile,
  });

  @override
  Widget build(BuildContext context) {
    final pad = w * 0.07;
    final safe = slide.showLogo ? _logoSafeInsets(w, profile) : EdgeInsets.zero;

    return Container(
      color: Colors.white,
      child: SizedBox.expand(
        child: FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: w,
            child: Padding(
              padding: EdgeInsets.fromLTRB(
                pad,
                pad + safe.top,
                pad,
                _logoAwareBottomPadding(pad, safe.bottom),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: _markdownBodyBlocks(
                  context,
                  markdown: slide.customMarkdown,
                  w: w,
                  font: font,
                  profile: profile,
                  headingColor: AppTheme.navy,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Shared markdown body renderer for free-markdown and bullets rich-text slides.
List<Widget> _markdownBodyBlocks(
  BuildContext context, {
  required String markdown,
  required double w,
  required String font,
  required ThemeProfile profile,
  Color? headingColor,
  double bodyFontSize = 0,
  double? contentWidth,
  double? emptyLineHeight,
  double? heading1Size,
  double? heading2Size,
}) {
  final link = _hexColor(profile.accentColor);
  final bodySize = bodyFontSize > 0 ? bodyFontSize : w * 0.024;
  final lines = normalizeRichTextMarkdown(markdown).split('\n');
  final widgets = <Widget>[];
  var i = 0;
  while (i < lines.length) {
    final line = lines[i];

    final fence = RegExp(r'^\s*```(.*)$').firstMatch(line);
    if (fence != null) {
      final language = fence.group(1)!.trim();
      final code = <String>[];
      i++;
      while (i < lines.length && !RegExp(r'^\s*```\s*$').hasMatch(lines[i])) {
        code.add(lines[i]);
        i++;
      }
      if (i < lines.length) i++;
      widgets.add(
        _fullWidthBlock(
          contentWidth,
          _markdownCodeBlock(code.join('\n'), language, w, font),
        ),
      );
      continue;
    }

    if (line.trim() == r'$$') {
      final tex = <String>[];
      i++;
      while (i < lines.length && lines[i].trim() != r'$$') {
        tex.add(lines[i]);
        i++;
      }
      if (i < lines.length) i++;
      widgets.add(
        _fullWidthBlock(
          contentWidth,
          _markdownMathBlock(tex.join('\n'), w, font),
        ),
      );
      continue;
    }
    final oneLine = RegExp(r'^\s*\$\$(.+)\$\$\s*$').firstMatch(line);
    if (oneLine != null) {
      widgets.add(
        _fullWidthBlock(
          contentWidth,
          _markdownMathBlock(oneLine.group(1)!.trim(), w, font),
        ),
      );
      i++;
      continue;
    }

    widgets.add(
      _fullWidthBlock(
        contentWidth,
        _markdownTextLine(
          context,
          line: line,
          w: w,
          font: font,
          profile: profile,
          linkColor: link,
          bodySize: bodySize,
          headingColor: headingColor,
          emptyLineHeight: emptyLineHeight,
          heading1Size: heading1Size,
          heading2Size: heading2Size,
        ),
      ),
    );
    i++;
  }
  return widgets;
}

Widget _fullWidthBlock(double? contentWidth, Widget child) {
  if (contentWidth == null) {
    return SizedBox(width: double.infinity, child: child);
  }
  return SizedBox(width: contentWidth, child: child);
}

Widget _markdownTextLine(
  BuildContext context, {
  required String line,
  required double w,
  required String font,
  required ThemeProfile profile,
  required Color linkColor,
  required double bodySize,
  Color? headingColor,
  double? emptyLineHeight,
  double? heading1Size,
  double? heading2Size,
}) {
  final textColor = headingColor ?? _hexColor(profile.textColor);
  final bodyStyle = _applyFont(
    font,
    TextStyle(
      fontSize: bodySize,
      height: kRichTextBodyLineHeight,
      color: textColor,
    ),
  );
  if (line.startsWith('# ')) {
    return _md(
      context,
      line.substring(2),
      _applyFont(
        font,
        TextStyle(
          fontSize: heading1Size ?? w * 0.04,
          fontWeight: FontWeight.bold,
          color: textColor,
        ),
      ),
      linkColor: linkColor,
    );
  } else if (line.startsWith('## ')) {
    return _md(
      context,
      line.substring(3),
      _applyFont(
        font,
        TextStyle(
          fontSize: heading2Size ?? w * 0.03,
          fontWeight: FontWeight.w600,
          color: headingColor ?? _hexColor(profile.accentColor),
        ),
      ),
      linkColor: linkColor,
    );
  } else if (line.startsWith('- ')) {
    return _md(
      context,
      '• ${line.substring(2)}',
      bodyStyle,
      linkColor: linkColor,
    );
  } else if (line.isEmpty) {
    return SizedBox(height: emptyLineHeight ?? w * 0.01);
  }
  return _md(context, line, bodyStyle, linkColor: linkColor);
}

Widget _markdownCodeBlock(String code, String language, double w, String font) {
  if (language.toLowerCase() == 'mermaid') {
    return MermaidDiagram(source: code, width: w);
  }
  _ensureHighlightLanguages();
  final mono = TextStyle(
    fontFamily: 'monospace',
    fontSize: w * 0.02,
    height: 1.3,
    color: const Color(0xFF24292E),
  );
  final known = language.isNotEmpty && allLanguages.containsKey(language);
  final Widget content = known
      ? HighlightView(
          code,
          language: language,
          theme: githubTheme,
          padding: EdgeInsets.zero,
          textStyle: mono,
        )
      : Text(code, style: mono);
  return Container(
    width: double.infinity,
    margin: EdgeInsets.symmetric(vertical: w * 0.008),
    padding: EdgeInsets.all(w * 0.018),
    decoration: BoxDecoration(
      color: const Color(0xFFF6F8FA),
      borderRadius: BorderRadius.circular(w * 0.008),
      border: Border.all(color: const Color(0xFFE1E4E8)),
    ),
    child: content,
  );
}

Widget _markdownMathBlock(String tex, double w, String font) {
  return Padding(
    padding: EdgeInsets.symmetric(vertical: w * 0.012),
    child: Math.tex(
      tex,
      textStyle: _applyFont(font, TextStyle(fontSize: w * 0.032)),
      onErrorFallback: (err) => Text(
        '\$\$$tex\$\$',
        style: TextStyle(
          fontFamily: 'monospace',
          fontSize: w * 0.022,
          color: Colors.red,
        ),
      ),
    ),
  );
}
