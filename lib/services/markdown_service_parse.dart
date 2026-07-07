// Part of the markdown_service library — see markdown_service.dart.
// Split out for navigability (deck/block parsing core); all imports live in the main library
// file. These private MarkdownService parse methods relocate verbatim into
// an extension — same library, same members, no behaviour change.
part of 'markdown_service.dart';

// Hoisted hot-path regexes: compiled once at library load instead of on every
// line/slide while parsing (they ran in the per-line body loop and the
// slide-type inference, recompiling the same patterns thousands of times).
final _reWhitespace = RegExp(r'\s+');
final _reImageMd = RegExp(r'!\[[^\]]*\]\(([^)]+)\)');
final _reLiItem = RegExp(r'<li[^>]*>(.*?)</li>', caseSensitive: false);
final _reHtmlList = RegExp(r'^</?(ul|ol)(?:\s[^>]*)?>$', caseSensitive: false);
final _reBullet = RegExp(r'^([-*+•◦▪▫–]|\d+[.)])\s+(.+)$');
final _reChecklistMark = RegExp(r'^\[[ xX]\]\s*');
final _reNumberedMark = RegExp(r'^\d+[.)]$');
// Slide splitting moved to the fence-aware MarkdownService.splitSlideBlocks so a
// `---` inside a code fence no longer tears a slide in two; the old
// `\n---\n`-regex split lived here.
final _reBgImage = RegExp(r'!\[bg');
final _reBgImageUrl = RegExp(r'!\[bg[^\]]*\]\(([^)]+)\)');
final _reBgImageSize = RegExp(r'!\[bg[^\]]*?(\d+)%[^\]]*\]');
final _reSeparatorCell = RegExp(r'^:?-+:?$');
final _reClassDirective = RegExp(r'<!--\s*_class:\s*([^>]+?)\s*-->');
final _reHtmlComment = RegExp(r'<!--([\s\S]*?)-->', multiLine: true);
final _reImageWidthStyle = RegExp(r'--image-width:\s*(\d+)%');

/// Mutable accumulator for [_MarkdownParse._parseBodyLines]: the per-line
/// handlers fill these fields as they walk a slide block's body.
class _BodyParse {
  _BodyParse(this.listStyle)
    : richTextHeaderPhase = listStyle == ListStyle.richText;

  String h1 = '';
  String h2 = '';
  String paragraph = '';
  String imagePath = '';
  String imagePath2 = '';
  String imageCaption = '';
  String imageCaption2 = '';
  int imageSize = 0;
  String videoPath = '';
  bool videoAutoplay = false;
  int videoStartMs = 0;
  int videoEndMs = 0;
  String audioPath = '';
  bool audioAutoplay = false;
  String quote = '';
  String quoteAuthor = '';
  final tableLines = <String>[];
  final richTextLines = <String>[];
  ListStyle listStyle;
  bool richTextHeaderPhase;

  /// Of het blok de `split`-class draagt; één keer bepaald in
  /// [_MarkdownParse._parseBodyLines] zodat de per-regel handlers niet elke
  /// regel opnieuw de cssClass hoeven te splitsen.
  bool isSplit = false;
}

extension _MarkdownParse on MarkdownService {
  Deck _doParse(String markdown, {String? filePath}) {
    String content = markdown;
    String theme = 'ocideck';
    bool paginate = true;
    ThemeProfile themeProfile = const ThemeProfile();
    String? presentationTitle;
    String author = '';
    String organization = '';
    String version = '';
    String date = '';
    String description = '';
    String keywords = '';
    TlpLevel tlp = TlpLevel.none;
    int presentationTargetSeconds = 0;
    bool showRehearsalSummary = true;

    // Strip front matter
    if (content.startsWith('---\n')) {
      final end = content.indexOf('\n---\n', 4);
      if (end != -1) {
        final frontMatter = content.substring(4, end);
        for (final rawLine in frontMatter.split('\n')) {
          // Parse `key: value` generically: split on the first colon and trim,
          // so leading indentation or extra spacing no longer silently drops a
          // field. Splitting on the *first* colon keeps colons in the value
          // (e.g. an ISO date/time).
          final line = rawLine.trim();
          final colon = line.indexOf(':');
          if (colon <= 0) continue;
          final key = line.substring(0, colon).trim();
          final value = line.substring(colon + 1).trim();
          switch (key) {
            case 'theme':
              theme = value;
            case 'paginate':
              paginate = value == 'true';
            case 'title':
              presentationTitle = _parseScalar(value);
            case 'author':
              author = _parseScalar(value);
            case 'organization':
              organization = _parseScalar(value);
            case 'version':
              version = _parseScalar(value);
            case 'date':
              date = _parseScalar(value);
            case 'description':
              description = _parseScalar(value);
            case 'keywords':
              keywords = _parseScalar(value);
            case 'tlp':
              tlp = TlpLevelX.fromKey(value);
            case 'ocideck_target_seconds':
              presentationTargetSeconds = int.tryParse(value) ?? 0;
            case 'ocideck_show_rehearsal_summary':
              showRehearsalSummary = value != 'false';
            case 'ocideck_style_profile':
              // Best-effort: a corrupt profile token must not fail the whole
              // parse (which would blank the audience window). Keep the default.
              try {
                final decoded = utf8.decode(base64Url.decode(value));
                themeProfile = ThemeProfile.fromJson(
                  Map<String, Object?>.from(jsonDecode(decoded) as Map),
                );
              } catch (e, s) {
                logError(
                  'MarkdownService._doParse: decode ocideck_style_profile',
                  e,
                  s,
                );
                // Leave themeProfile at its default.
              }
          }
        }
        content = content.substring(end + 5).trim();
      }
    }

    final blocks = MarkdownService.splitSlideBlocks(content);
    final slides = <Slide>[];
    for (final block in blocks) {
      final slide = _parseBlock(block.trim());
      if (slide != null) slides.add(slide);
    }

    final title =
        presentationTitle ??
        (slides.isNotEmpty && slides.first.title.isNotEmpty
            ? slides.first.title
            : 'Presentatie');

    String? projectPath;
    if (filePath != null) {
      final sep = filePath.contains('/') ? '/' : '\\';
      final parts = filePath.split(sep);
      if (parts.length > 1) {
        projectPath = parts.sublist(0, parts.length - 1).join(sep);
      }
    }

    return Deck(
      title: title,
      theme: theme,
      paginate: paginate,
      slides: slides.isEmpty ? [Slide.create(SlideType.title)] : slides,
      projectPath: projectPath,
      themeProfile: themeProfile,
      author: author,
      organization: organization,
      version: version,
      date: date,
      description: description,
      keywords: keywords,
      tlp: tlp,
      presentationTargetSeconds: presentationTargetSeconds.clamp(0, 86400),
      showRehearsalSummary: showRehearsalSummary,
    );
  }

  Slide? _parseBlock(String block) {
    if (block.isEmpty) return null;

    final d = _parseBlockDirectives(block);

    // Code/chart/cockpit/question slides carry a fenced block the generic line
    // parser below would mangle; they are handled up front.
    final fenced = _tryFencedSlide(
      cssClass: d.cssClass,
      remaining: d.remaining,
      notes: d.notes,
      advanceDuration: d.advanceDuration,
      skipped: d.skipped,
      tlp: d.tlp,
      styleImageWidth: d.styleImageWidth,
    );
    if (fenced != null) return fenced;

    // bullets may already hold the decoded two-column data; the line parser
    // appends to the same list, so pass it through by reference.
    final bullets = d.bullets;
    final body = _parseBodyLines(
      d.remaining.split('\n'),
      d.cssClass,
      d.listStyle,
      bullets,
    );

    var imageSize = body.imageSize;
    if (imageSize == 0 && d.styleImageWidth > 0) imageSize = d.styleImageWidth;
    // 0 stays "auto"; a real value is capped so a crafted `![bg 900000%]`
    // can't blow the layout box up (~maxWidth × 9000) and thrash rendering/
    // rasterisation. 400% is well beyond any legitimate zoom.
    if (imageSize > 400) imageSize = 400;

    final tableRows = <List<String>>[];
    for (final line in body.tableLines) {
      final cells = _splitTableRow(line);
      // Skip the GFM separator row (e.g. | --- | :---: |).
      if (cells.isNotEmpty &&
          cells.every((c) => _reSeparatorCell.hasMatch(c.trim()))) {
        continue;
      }
      tableRows.add(cells);
    }

    final type = _inferSlideType(
      cssClass: d.cssClass,
      quote: body.quote,
      imagePath: body.imagePath,
      imagePath2: body.imagePath2,
      bullets: bullets,
      listStyle: body.listStyle,
      videoPath: body.videoPath,
      tableRows: tableRows,
      h1: body.h1,
      h2: body.h2,
      paragraph: body.paragraph,
    );

    final classTokens = d.cssClass.split(_reWhitespace);
    final showLogo = !classTokens.contains('no-logo');
    final showFooter = !classTokens.contains('no-footer');

    final effectiveClass = classTokens
        .where(
          (c) =>
              c.isNotEmpty &&
              c != type.marpClass &&
              c != 'logo-safe' &&
              c != 'no-logo' &&
              c != 'no-footer' &&
              c != 'table-editable' &&
              !isTimelineOptionToken(c),
        )
        .join(' ');

    return Slide(
      id: _uuid.v4(),
      type: type,
      title: body.h1,
      subtitle: type == SlideType.section ? body.paragraph : body.h2,
      bullets: bullets,
      bullets2: d.bullets2,
      listStyle: body.listStyle,
      showChecklistProgress: d.showChecklistProgress,
      continueNumbering: d.continueNumbering,
      continuesSplit: d.continuesSplit,
      columnTitle1: d.columnTitle1,
      columnTitle2: d.columnTitle2,
      imagePath: body.imagePath,
      imagePath2: body.imagePath2,
      imageCaption: body.imageCaption,
      imageCaption2: body.imageCaption2,
      imageSize: imageSize,
      titleImageOverlay: d.titleImageOverlay,
      titleTextColorOverride: d.titleTextColorOverride,
      bulletMarkerOverride: d.bulletMarkerOverride,
      videoPath: body.videoPath,
      videoAutoplay: body.videoAutoplay,
      videoStartMs: body.videoStartMs,
      videoEndMs: body.videoEndMs,
      audioPath: body.audioPath,
      audioAutoplay: body.audioAutoplay,
      quote: body.quote,
      quoteAuthor: body.quoteAuthor,
      customMarkdown: type == SlideType.freeMarkdown
          ? normalizeRichTextMarkdown(
              unescapeDeckMarkdownDashLines(d.remaining),
            )
          : body.listStyle == ListStyle.richText
          ? normalizeRichTextMarkdown(
              unescapeDeckMarkdownDashLines(
                body.richTextLines.join('\n').trim(),
              ),
            )
          : '',
      cssClass: effectiveClass,
      notes: d.notes,
      advanceDuration: d.advanceDuration,
      showLogo: showLogo,
      showFooter: showFooter,
      skipped: d.skipped,
      tlp: d.tlp,
      tableRows: type == SlideType.table ? tableRows : const [],
      tableEditable:
          type == SlideType.table && classTokens.contains('table-editable'),
      timelineLayout: type == SlideType.timeline
          ? timelineLayoutFromTokens(classTokens)
          : TimelineLayout.auto,
      timelineReveal: type == SlideType.timeline
          ? timelineRevealFromTokens(classTokens)
          : TimelineReveal.onEnter,
      timelineAnimationMs: d.timelineAnimationMs,
      timelineCurrentIndex: d.timelineCurrentIndex,
    );
  }

  /// Parse the leading `<!-- _class -->` marker and every other `<!-- ... -->`
  /// directive comment (advance/skip/tlp/_style/two-bullets/timeline/list-style/
  /// checklist/title-image/title-colour/bullet-marker), accumulating presenter
  /// notes from any non-directive comment. Returns the stripped body plus all
  /// the decoded directive values.
  ({
    String cssClass,
    String remaining,
    String notes,
    double advanceDuration,
    bool skipped,
    TlpLevel tlp,
    List<String> bullets,
    List<String> bullets2,
    ListStyle listStyle,
    int? timelineAnimationMs,
    int? timelineCurrentIndex,
    bool showChecklistProgress,
    bool continueNumbering,
    bool continuesSplit,
    bool titleImageOverlay,
    String titleTextColorOverride,
    BulletMarker? bulletMarkerOverride,
    String columnTitle1,
    String columnTitle2,
    int styleImageWidth,
  })
  _parseBlockDirectives(String block) {
    String cssClass = '';
    String remaining = block;

    final classMatch = _reClassDirective.firstMatch(block);
    if (classMatch != null) {
      cssClass = classMatch.group(1) ?? '';
      remaining = block.replaceFirst(classMatch.group(0)!, '').trim();
    }

    // Extract presenter notes and advance timing from HTML comments
    final notesBuffer = StringBuffer();
    double advanceDuration = 0;
    bool skipped = false;
    TlpLevel slideTlp = TlpLevel.none;
    final bullets = <String>[];
    var bullets2 = <String>[];
    var listStyle = ListStyle.bullets;
    int? timelineAnimationMs;
    int? timelineCurrentIndex;
    var showChecklistProgress = false;
    var continueNumbering = false;
    var continuesSplit = false;
    var titleImageOverlay = true;
    var titleTextColorOverride = '';
    BulletMarker? bulletMarkerOverride;
    var columnTitle1 = '';
    var columnTitle2 = '';
    // bulletsImage slides store their panel width in `<!-- _style:
    // --image-width: N%; -->`; capture it before the comment is stripped.
    int styleImageWidth = 0;
    remaining = remaining.replaceAllMapped(_reHtmlComment, (m) {
      final content = m.group(1)!.trim();
      if (content.startsWith('advance:')) {
        // Clamp fail-closed: double.tryParse accepts Infinity/NaN/overflow
        // literals, and `(Infinity * 1000).round()` throws in the auto-advance
        // timer. Mirror the presentationTargetSeconds clamp (0..86400s).
        final d = double.tryParse(content.substring(8).trim()) ?? 0;
        advanceDuration = (d.isFinite && d > 0) ? d.clamp(0, 86400) : 0;
      } else if (content == 'skip') {
        skipped = true;
      } else if (content.startsWith('tlp:')) {
        slideTlp = TlpLevelX.fromKey(content.substring(4));
      } else if (content.startsWith('_style:')) {
        final w = _reImageWidthStyle.firstMatch(content);
        if (w != null) styleImageWidth = int.tryParse(w.group(1)!) ?? 0;
      } else if (content.startsWith('ocideck_two_bullets_left:')) {
        bullets
          ..clear()
          ..addAll(_decodeBullets(content.substring(25)));
      } else if (content.startsWith('ocideck_two_bullets_left_title:')) {
        columnTitle1 = _decodeText(content.substring(31));
      } else if (content.startsWith('ocideck_two_bullets_right_title:')) {
        columnTitle2 = _decodeText(content.substring(32));
      } else if (content.startsWith('ocideck_two_bullets_right:')) {
        bullets2 = _decodeBullets(content.substring(26));
      } else if (content.startsWith('ocideck_timeline_duration:')) {
        final ms = int.tryParse(content.substring(26).trim());
        if (ms != null) timelineAnimationMs = clampTimelineDuration(ms);
      } else if (content.startsWith('ocideck_timeline_current:')) {
        // The file stores the human-friendly 1-based event number; anything
        // out of range is ignored (fail-safe: no highlight).
        final n = int.tryParse(
          content.substring('ocideck_timeline_current:'.length).trim(),
        );
        if (n != null && n >= 1 && n <= timelineMaxEvents) {
          timelineCurrentIndex = n - 1;
        }
      } else if (content.startsWith('ocideck_list_style:')) {
        final name = content.substring(19).trim();
        listStyle = ListStyle.values.firstWhere(
          (style) => style.name == name,
          orElse: () => ListStyle.bullets,
        );
      } else if (content.startsWith('ocideck_checklist_progress:')) {
        showChecklistProgress =
            content.substring('ocideck_checklist_progress:'.length).trim() ==
            'true';
      } else if (content.startsWith('ocideck_continue_numbering:')) {
        continueNumbering =
            content.substring('ocideck_continue_numbering:'.length).trim() ==
            'true';
      } else if (content.startsWith('ocideck_continue_split:')) {
        continuesSplit =
            content.substring('ocideck_continue_split:'.length).trim() ==
            'true';
      } else if (content.startsWith('ocideck_title_image_overlay:')) {
        titleImageOverlay =
            content.substring('ocideck_title_image_overlay:'.length).trim() !=
            'false';
      } else if (content.startsWith('ocideck_title_text_color:')) {
        titleTextColorOverride = content
            .substring('ocideck_title_text_color:'.length)
            .trim();
      } else if (content.startsWith('ocideck_bullet_marker:')) {
        final name = content.substring('ocideck_bullet_marker:'.length).trim();
        final match = BulletMarker.values.where((m) => m.name == name);
        if (match.isNotEmpty) bulletMarkerOverride = match.first;
      } else if (!content.startsWith('_')) {
        notesBuffer.write(notesBuffer.isEmpty ? content : '\n$content');
      }
      return '';
    }).trim();
    final notes = _unescapeNotes(notesBuffer.toString().trim());

    return (
      cssClass: cssClass,
      remaining: remaining,
      notes: notes,
      advanceDuration: advanceDuration,
      skipped: skipped,
      tlp: slideTlp,
      bullets: bullets,
      bullets2: bullets2,
      listStyle: listStyle,
      timelineAnimationMs: timelineAnimationMs,
      timelineCurrentIndex: timelineCurrentIndex,
      showChecklistProgress: showChecklistProgress,
      continueNumbering: continueNumbering,
      continuesSplit: continuesSplit,
      titleImageOverlay: titleImageOverlay,
      titleTextColorOverride: titleTextColorOverride,
      bulletMarkerOverride: bulletMarkerOverride,
      columnTitle1: columnTitle1,
      columnTitle2: columnTitle2,
      styleImageWidth: styleImageWidth,
    );
  }

  /// Fenced-block slide types (code/chart/cockpit/question) delegate to their
  /// own parsers, which keep the fenced body verbatim. Returns the parsed slide,
  /// or null when [d] is not one of those types.
  Slide? _tryFencedSlide({
    required String cssClass,
    required String remaining,
    required String notes,
    required double advanceDuration,
    required bool skipped,
    required TlpLevel tlp,
    required int styleImageWidth,
  }) {
    final tokens = cssClass.split(_reWhitespace);
    if (tokens.contains('code')) {
      return _parseCodeBlock(
        remaining: remaining,
        cssClass: cssClass,
        notes: notes,
        advanceDuration: advanceDuration,
        skipped: skipped,
        tlp: tlp,
      );
    }
    if (tokens.contains('chart')) {
      return _parseChartBlock(
        remaining: remaining,
        cssClass: cssClass,
        notes: notes,
        advanceDuration: advanceDuration,
        skipped: skipped,
        tlp: tlp,
      );
    }
    if (tokens.contains('cockpit')) {
      return _parseCockpitBlock(
        remaining: remaining,
        cssClass: cssClass,
        notes: notes,
        advanceDuration: advanceDuration,
        skipped: skipped,
        tlp: tlp,
      );
    }
    if (tokens.contains('question')) {
      return _parseQuestionBlock(
        remaining: remaining,
        cssClass: cssClass,
        notes: notes,
        advanceDuration: advanceDuration,
        skipped: skipped,
        tlp: tlp,
        imageSize: styleImageWidth,
      );
    }
    return null;
  }

  /// Walk the (non-fenced) body lines, accumulating headings, bullets, images,
  /// captions, video/audio, quote and table content. [bullets] is appended in
  /// place; [listStyle] may be refined (checklist/numbered) and is returned.
  ({
    String h1,
    String h2,
    String paragraph,
    String imagePath,
    String imagePath2,
    String imageCaption,
    String imageCaption2,
    int imageSize,
    String videoPath,
    bool videoAutoplay,
    int videoStartMs,
    int videoEndMs,
    String audioPath,
    bool audioAutoplay,
    String quote,
    String quoteAuthor,
    List<String> tableLines,
    List<String> richTextLines,
    ListStyle listStyle,
  })
  _parseBodyLines(
    List<String> lines,
    String cssClass,
    ListStyle listStyle,
    List<String> bullets,
  ) {
    final b = _BodyParse(listStyle);
    final classTokens = cssClass.split(_reWhitespace);
    final isTwoBullets = classTokens.contains('two-bullets');
    b.isSplit = classTokens.contains('split');

    for (final line in lines) {
      if (b.listStyle == ListStyle.richText) {
        _consumeRichTextLine(line, b);
        continue;
      }
      final t = line.trim();
      if (isTwoBullets) {
        if (t.startsWith('# ')) {
          b.h1 = t.substring(2);
        } else if (t.startsWith('## ')) {
          b.h2 = t.substring(3);
        }
        continue;
      }
      _consumeContentLine(line, t, bullets, b);
    }

    return (
      h1: b.h1,
      h2: b.h2,
      paragraph: b.paragraph,
      imagePath: b.imagePath,
      imagePath2: b.imagePath2,
      imageCaption: b.imageCaption,
      imageCaption2: b.imageCaption2,
      imageSize: b.imageSize,
      videoPath: b.videoPath,
      videoAutoplay: b.videoAutoplay,
      videoStartMs: b.videoStartMs,
      videoEndMs: b.videoEndMs,
      audioPath: b.audioPath,
      audioAutoplay: b.audioAutoplay,
      quote: b.quote,
      quoteAuthor: b.quoteAuthor,
      tableLines: b.tableLines,
      richTextLines: b.richTextLines,
      listStyle: b.listStyle,
    );
  }

  void _consumeRichTextLine(String line, _BodyParse b) {
    final t = line.trim();
    if (b.richTextHeaderPhase) {
      if (t.isEmpty) return;
      if (t.startsWith('<div') || t == '</div>') {
        return;
      }
      if (t.startsWith('# ') && b.h1.isEmpty) {
        b.h1 = t.substring(2);
        return;
      }
      if (t.startsWith('## ') && b.h2.isEmpty && b.h1.isNotEmpty) {
        b.h2 = t.substring(3);
        return;
      }
      b.richTextHeaderPhase = false;
    }
    // A rich-text body IS markdown: an embedded table or <video> stays in
    // the body verbatim. Lifting those out silently dropped a richText
    // slide's table (kept only for type==table) and would lose user content
    // (those fields aren't re-serialised for a bullets slide). EXCEPTIONS,
    // which must round-trip: an <audio> attachment (written for every slide
    // type by the common block after the type switch, so it is restored
    // here), and the bulletsImage split-image structure (its image and
    // caption). The image-caption check precedes the generic `<div>` skip,
    // which previously shadowed it dead.
    final isSplit = b.isSplit;
    if (isSplit && t.startsWith('<div class="image-caption">')) {
      final captionParts = _splitTwoCaptions(_decodeImageCaption(t));
      b.imageCaption = captionParts.isNotEmpty ? captionParts.first : '';
    } else if (isSplit && _reImageMd.hasMatch(t)) {
      final m = _reImageMd.firstMatch(t);
      if (m != null && b.imagePath.isEmpty) {
        b.imagePath = m.group(1) ?? '';
      }
    } else if (t.startsWith('<audio')) {
      final audio = _parseAudioAttrs(t);
      b.audioPath = audio.$1;
      b.audioAutoplay = audio.$2;
    } else if (t.startsWith('<div') || t == '</div>') {
      // Split-slide structural markup; not part of the rich-text body.
    } else {
      b.richTextLines.add(line);
    }
  }

  void _consumeContentLine(
    String line,
    String t,
    List<String> bullets,
    _BodyParse b,
  ) {
    final htmlItems = _reLiItem.allMatches(t).toList();
    final bulletMatch = _reBullet.firstMatch(t);
    if (htmlItems.isNotEmpty) {
      for (final item in htmlItems) {
        final body = _stripInlineHtml(item.group(1) ?? '');
        if (body.trim().isNotEmpty) bullets.add(body.trim());
      }
    } else if (_reHtmlList.hasMatch(t)) {
      // HTML list container; individual <li> items are handled above.
    } else if (t.startsWith('|')) {
      b.tableLines.add(t);
    } else if (t.startsWith('# ')) {
      b.h1 = t.substring(2);
    } else if (t.startsWith('## ')) {
      b.h2 = t.substring(3);
    } else if (bulletMatch != null) {
      // Count leading spaces (2 per level)
      int spaces = 0;
      for (final ch in line.characters) {
        if (ch == ' ') {
          spaces++;
        } else if (ch == '\t') {
          spaces += 2;
        } else {
          break;
        }
      }
      final level = spaces ~/ 2;
      final marker = bulletMatch.group(1) ?? '';
      final body = bulletMatch.group(2) ?? '';
      bullets.add('\t' * level + body);
      if (_reChecklistMark.hasMatch(body)) {
        b.listStyle = ListStyle.checklist;
      } else if (_reNumberedMark.hasMatch(marker)) {
        b.listStyle = ListStyle.numbered;
      }
    } else if (t.startsWith('> ')) {
      b.quote = t.substring(2);
    } else if (t.startsWith('— ')) {
      b.quoteAuthor = t.substring(2);
    } else if (_reBgImage.hasMatch(t)) {
      final m = _reBgImageUrl.firstMatch(t);
      if (m != null) {
        if (b.imagePath.isEmpty) {
          b.imagePath = m.group(1) ?? '';
        } else {
          b.imagePath2 = m.group(1) ?? ''; // tweede afbeelding
        }
      }
      // Parse size: ![bg 50%](...) or ![bg left:42%](...)
      final sizeMatch = _reBgImageSize.firstMatch(t);
      if (sizeMatch != null && b.imageSize == 0) {
        b.imageSize = int.tryParse(sizeMatch.group(1)!) ?? 0;
      }
    } else if (b.isSplit && _reImageMd.hasMatch(t)) {
      // Plain markdown image, e.g. the `![](path)` used inside a
      // bulletsImage `split-image` panel. Restricted to split slides so a
      // plain image inside free markdown is not mistaken for an image slide.
      final m = _reImageMd.firstMatch(t);
      if (m != null) {
        if (b.imagePath.isEmpty) {
          b.imagePath = m.group(1) ?? '';
        } else {
          b.imagePath2 = m.group(1) ?? '';
        }
      }
    } else if (t.startsWith('<div class="image-caption">')) {
      final captionParts = _splitTwoCaptions(_decodeImageCaption(t));
      b.imageCaption = captionParts.isNotEmpty ? captionParts.first : '';
      b.imageCaption2 = captionParts.length > 1
          ? captionParts.sublist(1).join(' | ')
          : '';
    } else if (t.startsWith('<video')) {
      final v = _parseVideoLine(t);
      b.videoPath = v.path;
      b.videoStartMs = v.startMs;
      b.videoEndMs = v.endMs;
      b.videoAutoplay = v.autoplay;
    } else if (t.startsWith('<iframe') && t.contains('ocideck-embed')) {
      final e = _parseEmbedLine(t);
      b.videoPath = e.path;
      b.videoStartMs = e.startMs;
      b.videoEndMs = e.endMs;
    } else if (t.startsWith('<audio')) {
      final audio = _parseAudioAttrs(t);
      b.audioPath = audio.$1;
      b.audioAutoplay = audio.$2;
    } else if (t.isNotEmpty && b.h1.isNotEmpty && b.paragraph.isEmpty) {
      b.paragraph = t;
    }
  }

  /// Decide the slide type from the class tokens, falling back to content
  /// heuristics (quote/images/bullets/video/table) when no explicit token says.
  SlideType _inferSlideType({
    required String cssClass,
    required String quote,
    required String imagePath,
    required String imagePath2,
    required List<String> bullets,
    required ListStyle listStyle,
    required String videoPath,
    required List<List<String>> tableRows,
    required String h1,
    required String h2,
    required String paragraph,
  }) {
    final tokens = cssClass.split(_reWhitespace).toSet();
    if (tokens.contains('title')) return SlideType.title;
    if (tokens.contains('section')) return SlideType.section;
    if (tokens.contains('timeline')) return SlideType.timeline;
    if (tokens.contains('two-bullets')) return SlideType.twoBullets;
    if (tokens.contains('split')) return SlideType.bulletsImage;
    if (tokens.contains('quote')) return SlideType.quote;
    if (tokens.contains('video')) return SlideType.video;
    if (tokens.contains('table')) return SlideType.table;

    // No explicit class token — fall back to content heuristics.
    if (quote.isNotEmpty) return SlideType.quote;
    if (imagePath.isNotEmpty && imagePath2.isNotEmpty) {
      return SlideType.twoImages;
    }
    if (bullets.isNotEmpty && imagePath.isNotEmpty) {
      return SlideType.bulletsImage;
    }
    if (listStyle == ListStyle.richText) return SlideType.bullets;
    if (bullets.isNotEmpty) return SlideType.bullets;
    if (videoPath.isNotEmpty) return SlideType.video;
    if (imagePath.isNotEmpty) return SlideType.image;
    if (tableRows.isNotEmpty &&
        bullets.isEmpty &&
        h2.isEmpty &&
        paragraph.isEmpty) {
      return SlideType.table;
    }
    if (h1.isEmpty && h2.isEmpty && bullets.isEmpty) {
      return SlideType.freeMarkdown;
    }
    return SlideType.bullets;
  }
}
