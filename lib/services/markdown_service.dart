import 'dart:convert';
import 'package:characters/characters.dart';
import 'package:uuid/uuid.dart';
import '../models/chart.dart';
import '../models/cockpit.dart';
import '../models/deck.dart';
import '../models/question.dart';
import '../models/settings.dart';
import '../models/slide.dart';
import '../models/timeline.dart';
import '../models/video_source.dart';
import '../utils/deck_markdown_dashes.dart';
import '../utils/log.dart';
import '../utils/markdown_paste_cleanup.dart';

part 'markdown_service_helpers.dart';
part 'markdown_service_parse.dart';
part 'markdown_service_fenced.dart';

const _uuid = Uuid();

class MarkdownService {
  // ── Generation ──────────────────────────────────────────────────────────────

  /// Serialise a deck to Marp markdown.
  ///
  /// The styling (the [ThemeProfile]) is deliberately NOT written to the file:
  /// a saved `.md` holds only the content (the "base"), and the app applies the
  /// active style profile when it opens the deck. [inlineStyleProfile] re-adds
  /// the profile for transient, non-file payloads — currently only the markdown
  /// streamed to the audience (beamer) window, which has no other way to learn
  /// the styling. It must stay false for anything written to disk.
  String generateDeck(
    Deck deck, {
    bool inlineChartData = false,
    bool inlineStyleProfile = false,
    bool forExport = false,
  }) {
    final buf = StringBuffer();
    buf.writeln('---');
    buf.writeln('marp: true');
    buf.writeln('theme: ${deck.theme}');
    if (deck.paginate) buf.writeln('paginate: true');
    // General presentation metadata (also picked up by Marp where applicable).
    if (deck.title.isNotEmpty) {
      buf.writeln('title: ${_yamlScalar(deck.title)}');
    }
    if (deck.author.isNotEmpty) {
      buf.writeln('author: ${_yamlScalar(deck.author)}');
    }
    if (deck.organization.isNotEmpty) {
      buf.writeln('organization: ${_yamlScalar(deck.organization)}');
    }
    if (deck.version.isNotEmpty) {
      buf.writeln('version: ${_yamlScalar(deck.version)}');
    }
    if (deck.date.isNotEmpty) {
      buf.writeln('date: ${_yamlScalar(deck.date)}');
    }
    if (deck.description.isNotEmpty) {
      buf.writeln('description: ${_yamlScalar(deck.description)}');
    }
    if (deck.keywords.isNotEmpty) {
      buf.writeln('keywords: ${_yamlScalar(deck.keywords)}');
    }
    if (deck.tlp != TlpLevel.none) {
      buf.writeln('tlp: ${deck.tlp.key}');
    }
    if (deck.presentationTargetSeconds > 0) {
      buf.writeln('ocideck_target_seconds: ${deck.presentationTargetSeconds}');
    }
    if (inlineStyleProfile) {
      buf.writeln(
        'ocideck_style_profile: ${base64Url.encode(utf8.encode(jsonEncode(deck.themeProfile.toJson())))}',
      );
    }
    buf.writeln('---');
    buf.writeln();

    for (int i = 0; i < deck.slides.length; i++) {
      if (i > 0) {
        buf.writeln('---');
        buf.writeln();
      }
      buf.write(
        generateSlide(
          deck.slides[i],
          themeProfile: deck.themeProfile,
          inlineChartData: inlineChartData,
          forExport: forExport,
        ),
      );
    }
    return buf.toString();
  }

  /// Render a string as a YAML scalar, quoting/escaping only when needed so the
  /// front matter stays readable.
  String _yamlScalar(String v) {
    final needsQuote =
        v.isEmpty ||
        v != v.trim() ||
        RegExp(r'[:#"\n]').hasMatch(v) ||
        RegExp(r'''^[\[\]{}>|*&!%@`,?-]''').hasMatch(v);
    if (!needsQuote) return v;
    final escaped = v
        .replaceAll('\\', r'\\')
        .replaceAll('"', r'\"')
        .replaceAll('\n', r'\n');
    return '"$escaped"';
  }

  /// Inverse of [_yamlScalar] for the simple line-based front matter parser.
  String _parseScalar(String raw) {
    final s = raw.trim();
    if (s.length >= 2 && s.startsWith('"') && s.endsWith('"')) {
      return _unescape(s.substring(1, s.length - 1));
    }
    return s;
  }

  String _unescape(String s) {
    final out = StringBuffer();
    for (var i = 0; i < s.length; i++) {
      if (s[i] == r'\'[0] && i + 1 < s.length) {
        final next = s[i + 1];
        if (next == 'n') {
          out.write('\n');
          i++;
        } else if (next == '"') {
          out.write('"');
          i++;
        } else if (next == r'\'[0]) {
          out.write(r'\');
          i++;
        } else {
          out.write(s[i]);
        }
      } else {
        out.write(s[i]);
      }
    }
    return out.toString();
  }

  /// Write [rows] as a GitHub-flavoured markdown table (first row = header).
  void _writeTable(StringBuffer buf, List<List<String>> rows) {
    if (rows.isEmpty) return;
    final colCount = rows.fold<int>(0, (m, r) => r.length > m ? r.length : m);
    if (colCount == 0) return;

    String cell(List<String> row, int c) {
      final v = c < row.length ? row[c] : '';
      return v
          .replaceAll('\\', r'\\')
          .replaceAll('|', r'\|')
          // Escape an author-typed literal "<br>" before encoding real newlines
          // as "<br>", so the two are distinguishable on parse (otherwise a
          // literal "<br>" silently became a line break every load).
          .replaceAll('<br>', r'\<br>')
          .replaceAll('\n', '<br>');
    }

    String renderRow(List<String> row) =>
        '| ${List.generate(colCount, (c) => cell(row, c)).join(' | ')} |';

    buf.writeln(renderRow(rows.first));
    buf.writeln('| ${List.generate(colCount, (_) => '---').join(' | ')} |');
    for (var i = 1; i < rows.length; i++) {
      buf.writeln(renderRow(rows[i]));
    }
  }

  List<String> _splitTableRow(String line) {
    var s = line.trim();
    if (s.startsWith('|')) s = s.substring(1);
    if (s.endsWith('|')) s = s.substring(0, s.length - 1);
    return s
        .split(RegExp(r'(?<!\\)\|'))
        .map((c) => _unescapeCell(c.trim()))
        .toList();
  }

  String _unescapeCell(String s) {
    final out = StringBuffer();
    for (var i = 0; i < s.length; i++) {
      if (s[i] == r'\'[0] && i + 1 < s.length) {
        final n = s[i + 1];
        // `\|`, `\\` and `\<` unescape to the literal char; a `\<` keeps a
        // following `br>` as literal text rather than an author newline.
        if (n == '|' || n == r'\'[0] || n == '<') {
          out.write(n);
          i++;
          continue;
        }
      }
      // An unescaped `<br>` is an author-inserted line break.
      if (s.startsWith('<br>', i)) {
        out.write('\n');
        i += 3; // skip 'br>'; the loop's i++ steps past the '<'
        continue;
      }
      out.write(s[i]);
    }
    return out.toString();
  }

  String generateSlide(
    Slide slide, {
    ThemeProfile? themeProfile,
    bool inlineChartData = false,
    bool forExport = false,
  }) {
    final buf = StringBuffer();
    final cssClass = slide.cssClass.isNotEmpty
        ? slide.cssClass
        : slide.type.marpClass;
    final hasLogo = themeProfile?.logoPath?.isNotEmpty == true;
    final classes = [
      if (cssClass.isNotEmpty) cssClass,
      // Reserve logo space only when the logo is actually shown on this slide.
      if (hasLogo && slide.showLogo) 'logo-safe',
      // Mark slides that opt out of the logo so the theme can hide it.
      if (hasLogo && !slide.showLogo) 'no-logo',
      // Mark slides that opt out of the footer. Older presentations lack this
      // token and therefore keep the existing default: footer shown.
      if (!slide.showFooter) 'no-footer',
      // Table slides that may be edited live during a presentation. Absent by
      // default, so tables stay read-only unless the author opts in.
      if (slide.type == SlideType.table && slide.tableEditable)
        'table-editable',
      // Timeline layout/animation options ride along as extra class tokens so
      // they round-trip without a JSON block (the base `timeline` token comes
      // from marpClass above).
      if (slide.type == SlideType.timeline)
        ...timelineClassTokens(slide.timelineLayout, slide.timelineReveal),
    ];

    if (classes.isNotEmpty) {
      buf.writeln('<!-- _class: ${classes.join(' ')} -->');
      buf.writeln();
    }

    switch (slide.type) {
      case SlideType.title:
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

      case SlideType.section:
        if (slide.title.isNotEmpty) buf.writeln('# ${slide.title}');
        if (slide.subtitle.isNotEmpty) {
          buf.writeln();
          buf.writeln(slide.subtitle);
        }

      case SlideType.bullets:
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

      case SlideType.twoBullets:
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

      case SlideType.bulletsImage:
        if (slide.imagePath.isNotEmpty) {
          final pct = (slide.imageSize > 0 ? slide.imageSize : 40).clamp(
            20,
            70,
          );
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
              buf.writeln(
                '<!-- ocideck_list_style: ${slide.listStyle.name} -->',
              );
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
              buf.writeln(
                '<!-- ocideck_list_style: ${slide.listStyle.name} -->',
              );
            }
            _writeChecklistProgress(buf, slide);
            buf.writeln();
            _writeList(buf, slide.bullets, slide.listStyle);
          }
        }

      case SlideType.twoImages:
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

      case SlideType.image:
        if (slide.imagePath.isNotEmpty) {
          final sizeSpec = slide.imageSize > 0 ? ' ${slide.imageSize}%' : '';
          buf.writeln('![bg$sizeSpec](${slide.imagePath})');
          _writeImageCaption(buf, slide.imageCaption);
        }
        if (slide.title.isNotEmpty) {
          buf.writeln();
          buf.writeln('# ${slide.title}');
        }

      case SlideType.video:
        if (slide.title.isNotEmpty) {
          buf.writeln('# ${slide.title}');
          buf.writeln();
        }
        if (slide.videoPath.isNotEmpty) {
          _writeVideo(buf, slide, forExport: forExport);
        }

      case SlideType.quote:
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

      case SlideType.table:
        if (slide.title.isNotEmpty) {
          buf.writeln('# ${slide.title}');
          buf.writeln();
        }
        _writeTable(buf, slide.tableRows);

      case SlideType.freeMarkdown:
        final body = escapeDeckMarkdownDashLines(slide.customMarkdown);
        buf.write(body);
        if (body.isNotEmpty && !body.endsWith('\n')) {
          buf.writeln();
        }

      case SlideType.code:
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

      case SlideType.chart:
        // Re-serialize so inline data is dropped when the chart links a CSV
        // (the .md keeps only the spec + source; the CSV stays the source).
        final spec = ChartSpec.parse(slide.customMarkdown);
        buf.writeln('```chart');
        buf.writeln(spec.toBlock(forStorage: !inlineChartData));
        buf.writeln('```');

      case SlideType.cockpit:
        final spec = CockpitSpec.parse(slide.customMarkdown);
        if (slide.title.isNotEmpty) {
          buf.writeln('# ${slide.title}');
          buf.writeln();
        }
        buf.writeln('```cockpit');
        buf.writeln(spec.toBlock());
        buf.writeln('```');

      case SlideType.timeline:
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

      case SlideType.question:
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

    if (slide.audioPath.isNotEmpty) {
      final autoplay = slide.audioAutoplay ? ' autoplay' : '';
      buf.writeln();
      buf.writeln(
        '<audio src="${slide.audioPath}" controls$autoplay style="width:100%;"></audio>',
      );
    }

    if (slide.advanceDuration > 0) {
      buf.writeln();
      buf.writeln(
        '<!-- advance: ${slide.advanceDuration.toStringAsFixed(1)} -->',
      );
    }

    // Slides marked to be skipped during presenting/exporting. Persisted so the
    // skip state survives save/load round-trips.
    if (slide.skipped) {
      buf.writeln();
      buf.writeln('<!-- skip -->');
    }

    // Per-slide TLP classification (used to withhold the slide when sharing at
    // a lower level). Persisted so it survives save/load round-trips.
    if (slide.tlp != TlpLevel.none) {
      buf.writeln();
      buf.writeln('<!-- tlp: ${slide.tlp.key} -->');
    }

    if (slide.notes.isNotEmpty) {
      buf.writeln();
      buf.writeln('<!--');
      buf.writeln(_escapeNotes(slide.notes));
      buf.writeln('-->');
    }

    buf.writeln();
    return buf.toString();
  }

  // ── Parsing ─────────────────────────────────────────────────────────────────

  /// Best-effort parse of Marp markdown into a Deck. Returns null if the
  /// content cannot be parsed at all.
  Deck? parseDeck(String markdown, {String? filePath}) {
    // Normalise line endings up front. A Windows (CRLF) or classic-Mac (CR)
    // file would otherwise miss the `---\n` frontmatter start and the
    // `\n---\n` slide separators, collapsing the whole deck into one block.
    final normalized = markdown.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
    try {
      return _doParse(normalized, filePath: filePath);
    } catch (e, s) {
      logError('MarkdownService.parseDeck: parse markdown', e, s);
      return null;
    }
  }

  /// Cheap frontmatter probe for the disk-wide presentation scan: reads only the
  /// `--- … ---` header (no slide body, no Deck construction) and reports whether
  /// the file declares `marp: true`, plus its `theme`/`title`. [head] may be a
  /// truncated prefix of the file — if the closing `---` is missing we still
  /// parse whatever header lines are present.
  ({bool marp, String? theme, String? title}) sniffFrontmatter(String head) {
    final norm = head.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
    if (!norm.startsWith('---\n')) {
      return (marp: false, theme: null, title: null);
    }
    final end = norm.indexOf('\n---\n', 4);
    final frontMatter = end == -1 ? norm.substring(4) : norm.substring(4, end);

    bool marp = false;
    String? theme;
    String? title;
    for (final rawLine in frontMatter.split('\n')) {
      final line = rawLine.trim();
      final colon = line.indexOf(':');
      if (colon <= 0) continue;
      final key = line.substring(0, colon).trim();
      final value = line.substring(colon + 1).trim();
      switch (key) {
        case 'marp':
          marp = value == 'true';
        case 'theme':
          theme = value;
        case 'title':
          title = _parseScalar(value);
      }
    }
    return (marp: marp, theme: theme, title: title);
  }
}
