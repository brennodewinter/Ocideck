// Part of the markdown_service library — see markdown_service.dart.
// Split out for navigability (fenced-block parsers: code/chart/cockpit/question); all imports live in the main library
// file. These private MarkdownService parse methods relocate verbatim into
// an extension — same library, same members, no behaviour change.
part of 'markdown_service.dart';

extension _MarkdownFenced on MarkdownService {
  /// Parse a `<!-- _class: code -->` slide: an optional `# title`, the fenced
  /// code block (its info string is the language) and an optional `<audio>`.
  Slide _parseCodeBlock({
    required String remaining,
    required String cssClass,
    required String notes,
    required double advanceDuration,
    required bool skipped,
    TlpLevel tlp = TlpLevel.none,
  }) {
    final lines = remaining.split('\n');
    String title = '';
    String language = '';
    String audioPath = '';
    bool audioAutoplay = false;
    final code = <String>[];
    bool inFence = false;

    for (final line in lines) {
      final fence = RegExp(r'^\s*```(.*)$').firstMatch(line);
      if (fence != null) {
        if (!inFence) {
          inFence = true;
          language = fence.group(1)!.trim();
        } else {
          inFence = false;
        }
        continue;
      }
      if (inFence) {
        code.add(line);
        continue;
      }
      final t = line.trim();
      if (t.startsWith('# ') && title.isEmpty) {
        title = t.substring(2);
      } else if (t.startsWith('<audio')) {
        (audioPath, audioAutoplay) = _parseAudioAttrs(t);
      }
    }

    final classTokens = cssClass.split(_reWhitespace);
    final effectiveClass = classTokens
        .where(
          (c) =>
              c.isNotEmpty &&
              c != 'code' &&
              c != 'logo-safe' &&
              c != 'no-logo' &&
              c != 'no-footer',
        )
        .join(' ');

    return Slide(
      id: _uuid.v4(),
      type: SlideType.code,
      title: title,
      customMarkdown: code.join('\n'),
      codeLanguage: language,
      audioPath: audioPath,
      audioAutoplay: audioAutoplay,
      cssClass: effectiveClass,
      notes: notes,
      advanceDuration: advanceDuration,
      showLogo: !classTokens.contains('no-logo'),
      showFooter: !classTokens.contains('no-footer'),
      skipped: skipped,
      tlp: tlp,
    );
  }

  /// Parse a `<!-- _class: chart -->` slide: the fenced ```chart JSON block and
  /// an optional `<audio>`. The JSON is kept verbatim in [Slide.customMarkdown].
  Slide _parseChartBlock({
    required String remaining,
    required String cssClass,
    required String notes,
    required double advanceDuration,
    required bool skipped,
    TlpLevel tlp = TlpLevel.none,
  }) {
    final lines = remaining.split('\n');
    final json = <String>[];
    String title = '';
    String audioPath = '';
    bool audioAutoplay = false;
    bool inFence = false;

    for (final line in lines) {
      final fence = RegExp(r'^\s*```').hasMatch(line);
      if (fence) {
        inFence = !inFence;
        continue;
      }
      if (inFence) {
        json.add(line);
        continue;
      }
      final t = line.trim();
      if (t.startsWith('# ') && title.isEmpty) {
        title = t.substring(2);
      } else if (t.startsWith('<audio')) {
        (audioPath, audioAutoplay) = _parseAudioAttrs(t);
      }
    }

    final classTokens = cssClass.split(_reWhitespace);
    final effectiveClass = classTokens
        .where(
          (c) =>
              c.isNotEmpty &&
              c != 'chart' &&
              c != 'logo-safe' &&
              c != 'no-logo' &&
              c != 'no-footer',
        )
        .join(' ');

    return Slide(
      id: _uuid.v4(),
      type: SlideType.chart,
      customMarkdown: json.join('\n').trim(),
      audioPath: audioPath,
      audioAutoplay: audioAutoplay,
      cssClass: effectiveClass,
      notes: notes,
      advanceDuration: advanceDuration,
      showLogo: !classTokens.contains('no-logo'),
      showFooter: !classTokens.contains('no-footer'),
      skipped: skipped,
      tlp: tlp,
    );
  }

  /// Parse a `<!-- _class: cockpit -->` slide: the fenced ```cockpit JSON block
  /// and an optional `<audio>`. The JSON is kept in [Slide.customMarkdown].
  Slide _parseCockpitBlock({
    required String remaining,
    required String cssClass,
    required String notes,
    required double advanceDuration,
    required bool skipped,
    TlpLevel tlp = TlpLevel.none,
  }) {
    final lines = remaining.split('\n');
    final json = <String>[];
    String title = '';
    String audioPath = '';
    bool audioAutoplay = false;
    bool inFence = false;

    for (final line in lines) {
      final fence = RegExp(r'^\s*```').hasMatch(line);
      if (fence) {
        inFence = !inFence;
        continue;
      }
      if (inFence) {
        json.add(line);
        continue;
      }
      final t = line.trim();
      if (t.startsWith('# ') && title.isEmpty) {
        title = t.substring(2).trim();
      } else if (t.startsWith('<audio')) {
        (audioPath, audioAutoplay) = _parseAudioAttrs(t);
      }
    }

    final classTokens = cssClass.split(_reWhitespace);
    final effectiveClass = classTokens
        .where(
          (c) =>
              c.isNotEmpty &&
              c != 'cockpit' &&
              c != 'logo-safe' &&
              c != 'no-logo' &&
              c != 'no-footer',
        )
        .join(' ');

    return Slide(
      id: _uuid.v4(),
      type: SlideType.cockpit,
      title: title,
      customMarkdown: CockpitSpec.parse(json.join('\n').trim()).toBlock(),
      audioPath: audioPath,
      audioAutoplay: audioAutoplay,
      cssClass: effectiveClass,
      notes: notes,
      advanceDuration: advanceDuration,
      showLogo: !classTokens.contains('no-logo'),
      showFooter: !classTokens.contains('no-footer'),
      skipped: skipped,
      tlp: tlp,
    );
  }

  /// Parse a `<!-- _class: question -->` slide: an optional `# title`, an
  /// optional `![](image)` with caption, and the fenced ```` ```question ````
  /// JSON block (kept in [Slide.customMarkdown]).
  Slide _parseQuestionBlock({
    required String remaining,
    required String cssClass,
    required String notes,
    required double advanceDuration,
    required bool skipped,
    TlpLevel tlp = TlpLevel.none,
    int imageSize = 0,
  }) {
    final lines = remaining.split('\n');
    final json = <String>[];
    String title = '';
    String imagePath = '';
    String imageCaption = '';
    String audioPath = '';
    bool audioAutoplay = false;
    bool inFence = false;

    for (final line in lines) {
      final fence = RegExp(r'^\s*```').hasMatch(line);
      if (fence) {
        inFence = !inFence;
        continue;
      }
      if (inFence) {
        json.add(line);
        continue;
      }
      final t = line.trim();
      if (t.startsWith('# ') && title.isEmpty) {
        title = t.substring(2).trim();
      } else if (t.startsWith('![')) {
        final m = RegExp(r'!\[[^\]]*\]\(([^)]*)\)').firstMatch(t);
        if (m != null) imagePath = m.group(1) ?? '';
      } else if (t.startsWith('<div class="image-caption">')) {
        imageCaption = _decodeCaption(_decodeImageCaption(t));
      } else if (t.startsWith('<audio')) {
        (audioPath, audioAutoplay) = _parseAudioAttrs(t);
      }
    }

    final classTokens = cssClass.split(_reWhitespace);
    final effectiveClass = classTokens
        .where(
          (c) =>
              c.isNotEmpty &&
              c != 'question' &&
              c != 'logo-safe' &&
              c != 'no-logo' &&
              c != 'no-footer',
        )
        .join(' ');

    return Slide(
      id: _uuid.v4(),
      type: SlideType.question,
      title: title,
      imagePath: imagePath,
      imageCaption: imageCaption,
      imageSize: imageSize,
      audioPath: audioPath,
      audioAutoplay: audioAutoplay,
      customMarkdown: QuestionSpec.parse(json.join('\n').trim()).toBlock(),
      cssClass: effectiveClass,
      notes: notes,
      advanceDuration: advanceDuration,
      showLogo: !classTokens.contains('no-logo'),
      showFooter: !classTokens.contains('no-footer'),
      skipped: skipped,
      tlp: tlp,
    );
  }

  String _stripInlineHtml(String value) {
    return value
        .replaceAll(RegExp(r'<[^>]+>'), ' ')
        .replaceAll(_reWhitespace, ' ');
  }
}
