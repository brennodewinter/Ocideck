import 'dart:convert';
import 'package:characters/characters.dart';
import 'package:uuid/uuid.dart';
import '../models/chart.dart';
import '../models/deck.dart';
import '../models/settings.dart';
import '../models/slide.dart';
import '../utils/deck_markdown_dashes.dart';
import '../utils/log.dart';

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
        if (n == '|') {
          out.write('|');
          i++;
          continue;
        }
        if (n == r'\'[0]) {
          out.write(r'\');
          i++;
          continue;
        }
      }
      out.write(s[i]);
    }
    return out.toString().replaceAll('<br>', '\n');
  }

  String generateSlide(
    Slide slide, {
    ThemeProfile? themeProfile,
    bool inlineChartData = false,
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
    ];

    if (classes.isNotEmpty) {
      buf.writeln('<!-- _class: ${classes.join(' ')} -->');
      buf.writeln();
    }

    switch (slide.type) {
      case SlideType.title:
        // Background image before headings so Marp treats it as a bg directive
        if (slide.imagePath.isNotEmpty) {
          final sizeSpec = slide.imageSize > 0 ? '${slide.imageSize}% ' : '';
          buf.writeln('![bg ${sizeSpec}opacity:.45](${slide.imagePath})');
          _writeImageCaption(buf, slide.imageCaption);
          buf.writeln();
        }
        if (slide.title.isNotEmpty) buf.writeln('# ${slide.title}');
        if (slide.subtitle.isNotEmpty) buf.writeln('## ${slide.subtitle}');

      case SlideType.section:
        if (slide.title.isNotEmpty) buf.writeln('# ${slide.title}');
        if (slide.subtitle.isNotEmpty) {
          buf.writeln();
          buf.writeln(slide.subtitle);
        }

      case SlideType.bullets:
        if (slide.title.isNotEmpty) buf.writeln('# ${slide.title}');
        if (slide.subtitle.isNotEmpty) buf.writeln('## ${slide.subtitle}');
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
          if (slide.listStyle != ListStyle.bullets) {
            buf.writeln('<!-- ocideck_list_style: ${slide.listStyle.name} -->');
          }
          _writeChecklistProgress(buf, slide);
          buf.writeln();
          _writeList(buf, slide.bullets, slide.listStyle);
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
          if (slide.listStyle != ListStyle.bullets) {
            buf.writeln('<!-- ocideck_list_style: ${slide.listStyle.name} -->');
          }
          _writeChecklistProgress(buf, slide);
          buf.writeln();
          _writeList(buf, slide.bullets, slide.listStyle);
        }

      case SlideType.twoImages:
        final splitPct = slide.imageSize > 0 ? slide.imageSize : 50;
        if (slide.imagePath.isNotEmpty) {
          buf.writeln('![bg left:$splitPct%](${slide.imagePath})');
        }
        if (slide.imagePath2.isNotEmpty) {
          buf.writeln('![bg right:${100 - splitPct}%](${slide.imagePath2})');
        }
        _writeImageCaption(
          buf,
          [
            slide.imageCaption,
            slide.imageCaption2,
          ].where((caption) => caption.trim().isNotEmpty).join(' | '),
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
          final autoplay = slide.videoAutoplay ? ' autoplay muted loop' : '';
          buf.writeln(
            '<video src="${slide.videoPath}" controls$autoplay style="width:100%; max-height:72vh;"></video>',
          );
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
      buf.writeln(slide.notes);
      buf.writeln('-->');
    }

    buf.writeln();
    return buf.toString();
  }

  static void _writeList(
    StringBuffer buf,
    List<String> items,
    ListStyle style,
  ) {
    final counters = <int>[];
    for (final item in items) {
      int level = 0;
      while (level < item.length && item[level] == '\t') {
        level++;
      }
      final text = item.substring(level);
      if (text.isEmpty) continue;
      while (counters.length <= level) {
        counters.add(0);
      }
      counters[level]++;
      if (counters.length > level + 1) {
        counters.removeRange(level + 1, counters.length);
      }
      final marker = switch (style) {
        ListStyle.numbered => '${counters[level]}.',
        ListStyle.bullets || ListStyle.checklist => '-',
        ListStyle.richText => '-',
      };
      final body = style == ListStyle.checklist
          ? '[${checklistItemChecked(item) ? 'x' : ' '}] '
                '${checklistItemText(item)}'
          : text;
      buf.writeln('${'  ' * level}$marker $body');
    }
  }

  static void _writeTwoBulletColumns(
    StringBuffer buf,
    List<String> left,
    List<String> right,
    String leftTitle,
    String rightTitle,
    ListStyle listStyle,
    bool showChecklistProgress,
    ThemeProfile themeProfile,
  ) {
    buf.writeln('<!-- ocideck_two_bullets_left: ${_encodeBullets(left)} -->');
    buf.writeln('<!-- ocideck_two_bullets_right: ${_encodeBullets(right)} -->');
    if (listStyle != ListStyle.bullets) {
      buf.writeln('<!-- ocideck_list_style: ${listStyle.name} -->');
    }
    if (showChecklistProgress) {
      buf.writeln('<!-- ocideck_checklist_progress: true -->');
    }
    if (leftTitle.isNotEmpty) {
      buf.writeln(
        '<!-- ocideck_two_bullets_left_title: ${_encodeText(leftTitle)} -->',
      );
    }
    if (rightTitle.isNotEmpty) {
      buf.writeln(
        '<!-- ocideck_two_bullets_right_title: ${_encodeText(rightTitle)} -->',
      );
    }
    buf.writeln(
      '<div class="ocideck-two-bullets" style="display:grid; grid-template-columns:1fr 1fr; gap:3rem; align-items:start;">',
    );
    _writeBulletColumn(buf, left, leftTitle, listStyle, themeProfile);
    _writeBulletColumn(buf, right, rightTitle, listStyle, themeProfile);
    buf.writeln('</div>');
  }

  static void _writeChecklistProgress(StringBuffer buf, Slide slide) {
    if (slide.showChecklistProgress) {
      buf.writeln('<!-- ocideck_checklist_progress: true -->');
    }
  }

  static void _writeBulletColumn(
    StringBuffer buf,
    List<String> bullets,
    String columnTitle,
    ListStyle listStyle,
    ThemeProfile themeProfile,
  ) {
    buf.writeln('<div>');
    if (columnTitle.isNotEmpty) {
      buf.writeln(
        '<h3 style="margin:0 0 .5rem;">${_escapeHtml(columnTitle)}</h3>',
      );
    }
    final tag = listStyle == ListStyle.numbered ? 'ol' : 'ul';
    buf.writeln('<$tag style="margin:0; padding-left:1.3em;">');
    _writeHtmlBulletItems(buf, bullets, listStyle, themeProfile);
    buf.writeln('</$tag>');
    buf.writeln('</div>');
  }

  static String _encodeBullets(List<String> bullets) {
    return base64Url.encode(utf8.encode(jsonEncode(bullets)));
  }

  static String _encodeText(String value) =>
      base64Url.encode(utf8.encode(value));

  static String _decodeText(String encoded) {
    try {
      return utf8.decode(base64Url.decode(encoded.trim()));
    } catch (e, s) {
      logError('MarkdownService._decodeText: base64/utf8 decode', e, s);
      return '';
    }
  }

  static List<String> _decodeBullets(String encoded) {
    try {
      final decoded = utf8.decode(base64Url.decode(encoded.trim()));
      final raw = jsonDecode(decoded);
      if (raw is List) return raw.map((v) => v.toString()).toList();
    } catch (e, s) {
      logError('MarkdownService._decodeBullets: base64/utf8/json decode', e, s);
    }
    return const [];
  }

  static void _writeHtmlBulletItems(
    StringBuffer buf,
    List<String> bullets,
    ListStyle listStyle,
    ThemeProfile themeProfile,
  ) {
    final counters = <int>[];
    for (final b in bullets) {
      int level = 0;
      while (level < b.length && b[level] == '\t') {
        level++;
      }
      final text = listStyle == ListStyle.checklist
          ? checklistItemText(b).trim()
          : b.substring(level).trim();
      if (text.isEmpty) continue;
      while (counters.length <= level) {
        counters.add(0);
      }
      counters[level]++;
      if (counters.length > level + 1) {
        counters.removeRange(level + 1, counters.length);
      }
      final style = level == 0 ? '' : ' style="margin-left:${level * 1.4}em;"';
      final value = listStyle == ListStyle.numbered
          ? ' value="${counters[level]}"'
          : '';
      final checkbox = listStyle == ListStyle.checklist
          ? '${checklistItemChecked(b) ? '☑' : '☐'} '
          : '';
      final decoration = listStyle == ListStyle.checklist
          ? ' style="${level == 0 ? '' : 'margin-left:${level * 1.4}em;'}'
                '${checklistItemChecked(b) && themeProfile.checklistStrikeThrough ? 'text-decoration:line-through;opacity:.7;' : ''}"'
          : style;
      buf.writeln('<li$value$decoration>${_escapeHtml(checkbox + text)}</li>');
    }
  }

  static String _escapeHtml(String value) {
    return value
        .replaceAll('&', '&amp;')
        .replaceAll('<', '&lt;')
        .replaceAll('>', '&gt;')
        .replaceAll('"', '&quot;');
  }

  static double _splitTextScale(Slide slide) {
    final bullets = slide.bullets
        .map((b) => b.trimLeft())
        .where((b) => b.isNotEmpty)
        .toList();
    if (bullets.isEmpty) return 1.2;
    final maxChars = bullets.fold<int>(
      0,
      (max, bullet) => bullet.length > max ? bullet.length : max,
    );
    final count = bullets.length;
    var scale = 1.0;
    if (count <= 4) {
      scale = 2.35;
    } else if (count <= 5) {
      scale = 2.10;
    } else if (count <= 7) {
      scale = 1.85;
    } else if (count <= 9) {
      scale = 1.55;
    } else if (count <= 12) {
      scale = 1.30;
    }
    if (maxChars > 115) {
      scale -= 0.16;
    } else if (maxChars > 90) {
      scale -= 0.08;
    }
    return scale.clamp(1.0, 2.45);
  }

  static void _writeImageCaption(StringBuffer buf, String caption) {
    final text = caption.trim();
    if (text.isEmpty) return;
    buf.writeln(
      '<div class="image-caption">${const HtmlEscape().convert(text)}</div>',
    );
  }

  static String _decodeImageCaption(String line) {
    return line
        .replaceFirst('<div class="image-caption">', '')
        .replaceFirst('</div>', '')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&quot;', '"')
        .replaceAll('&#39;', "'")
        .replaceAll('&amp;', '&')
        .trim();
  }

  // ── Parsing ─────────────────────────────────────────────────────────────────

  /// Best-effort parse of Marp markdown into a Deck. Returns null if the
  /// content cannot be parsed at all.
  Deck? parseDeck(String markdown, {String? filePath}) {
    try {
      return _doParse(markdown, filePath: filePath);
    } catch (e, s) {
      logError('MarkdownService.parseDeck: parse markdown', e, s);
      return null;
    }
  }

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

    // Strip front matter
    if (content.startsWith('---\n')) {
      final end = content.indexOf('\n---\n', 4);
      if (end != -1) {
        final frontMatter = content.substring(4, end);
        for (final line in frontMatter.split('\n')) {
          if (line.startsWith('theme:')) {
            theme = line.substring(6).trim();
          } else if (line.startsWith('paginate:')) {
            paginate = line.substring(9).trim() == 'true';
          } else if (line.startsWith('title:')) {
            presentationTitle = _parseScalar(line.substring(6));
          } else if (line.startsWith('author:')) {
            author = _parseScalar(line.substring(7));
          } else if (line.startsWith('organization:')) {
            organization = _parseScalar(line.substring(13));
          } else if (line.startsWith('version:')) {
            version = _parseScalar(line.substring(8));
          } else if (line.startsWith('date:')) {
            date = _parseScalar(line.substring(5));
          } else if (line.startsWith('description:')) {
            description = _parseScalar(line.substring(12));
          } else if (line.startsWith('keywords:')) {
            keywords = _parseScalar(line.substring(9));
          } else if (line.startsWith('tlp:')) {
            tlp = TlpLevelX.fromKey(line.substring(4));
          } else if (line.startsWith('ocideck_style_profile:')) {
            // Best-effort: a corrupt profile token must not fail the whole
            // parse (which would blank the audience window). Keep the default.
            try {
              final encoded = line.substring(22).trim();
              final decoded = utf8.decode(base64Url.decode(encoded));
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

    final blocks = content.split(RegExp(r'\n---\n'));
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
    );
  }

  Slide? _parseBlock(String block) {
    if (block.isEmpty) return null;

    String cssClass = '';
    String remaining = block;

    final classMatch = RegExp(
      r'<!--\s*_class:\s*([^>]+?)\s*-->',
    ).firstMatch(block);
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
    var showChecklistProgress = false;
    var columnTitle1 = '';
    var columnTitle2 = '';
    // bulletsImage slides store their panel width in `<!-- _style:
    // --image-width: N%; -->`; capture it before the comment is stripped.
    int styleImageWidth = 0;
    remaining = remaining.replaceAllMapped(
      RegExp(r'<!--([\s\S]*?)-->', multiLine: true),
      (m) {
        final content = m.group(1)!.trim();
        if (content.startsWith('advance:')) {
          advanceDuration = double.tryParse(content.substring(8).trim()) ?? 0;
        } else if (content == 'skip') {
          skipped = true;
        } else if (content.startsWith('tlp:')) {
          slideTlp = TlpLevelX.fromKey(content.substring(4));
        } else if (content.startsWith('_style:')) {
          final w = RegExp(r'--image-width:\s*(\d+)%').firstMatch(content);
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
        } else if (!content.startsWith('_')) {
          notesBuffer.write(notesBuffer.isEmpty ? content : '\n$content');
        }
        return '';
      },
    ).trim();
    final notes = notesBuffer.toString().trim();

    // Code slides carry a fenced block that the generic line parser below would
    // mangle (the body lines aren't markdown). Handle them up front.
    if (cssClass.split(RegExp(r'\s+')).contains('code')) {
      return _parseCodeBlock(
        remaining: remaining,
        cssClass: cssClass,
        notes: notes,
        advanceDuration: advanceDuration,
        skipped: skipped,
        tlp: slideTlp,
      );
    }

    // Chart slides carry a fenced ```chart JSON block; handle up front too.
    if (cssClass.split(RegExp(r'\s+')).contains('chart')) {
      return _parseChartBlock(
        remaining: remaining,
        cssClass: cssClass,
        notes: notes,
        advanceDuration: advanceDuration,
        skipped: skipped,
        tlp: slideTlp,
      );
    }

    final lines = remaining.split('\n');
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
    String audioPath = '';
    bool audioAutoplay = false;
    String quote = '';
    String quoteAuthor = '';
    final tableLines = <String>[];
    final richTextLines = <String>[];
    var richTextHeaderPhase = listStyle == ListStyle.richText;

    for (final line in lines) {
      if (listStyle == ListStyle.richText) {
        final t = line.trim();
        if (richTextHeaderPhase) {
          if (t.isEmpty) continue;
          if (t.startsWith('# ') && h1.isEmpty) {
            h1 = t.substring(2);
            continue;
          }
          if (t.startsWith('## ') && h2.isEmpty && h1.isNotEmpty) {
            h2 = t.substring(3);
            continue;
          }
          richTextHeaderPhase = false;
        }
        if (t.startsWith('|')) {
          tableLines.add(t);
        } else if (t.startsWith('<video')) {
          final m = RegExp(r'src="([^"]+)"').firstMatch(t);
          if (m != null) videoPath = m.group(1) ?? '';
          videoAutoplay = t.contains('autoplay');
        } else if (t.startsWith('<audio')) {
          final m = RegExp(r'src="([^"]+)"').firstMatch(t);
          if (m != null) audioPath = m.group(1) ?? '';
          audioAutoplay = t.contains('autoplay');
        } else {
          richTextLines.add(line);
        }
        continue;
      }

      final t = line.trim();
      if (t.startsWith('|')) {
        tableLines.add(t);
      } else if (t.startsWith('# ')) {
        h1 = t.substring(2);
      } else if (t.startsWith('## ')) {
        h2 = t.substring(3);
      } else if (t.startsWith('- ')) {
        // Count leading spaces (2 per level)
        int spaces = 0;
        for (final ch in line.characters) {
          if (ch == ' ') {
            spaces++;
          } else {
            break;
          }
        }
        final level = spaces ~/ 2;
        final body = t.substring(2);
        bullets.add('\t' * level + body);
        if (RegExp(r'^\[[ xX]\]\s*').hasMatch(body)) {
          listStyle = ListStyle.checklist;
        }
      } else if (RegExp(r'^\d+\.\s+').hasMatch(t)) {
        int spaces = 0;
        for (final ch in line.characters) {
          if (ch == ' ') {
            spaces++;
          } else {
            break;
          }
        }
        final level = spaces ~/ 2;
        bullets.add('\t' * level + t.replaceFirst(RegExp(r'^\d+\.\s+'), ''));
        listStyle = ListStyle.numbered;
      } else if (t.startsWith('> ')) {
        quote = t.substring(2);
      } else if (t.startsWith('— ')) {
        quoteAuthor = t.substring(2);
      } else if (RegExp(r'!\[bg').hasMatch(t)) {
        final m = RegExp(r'!\[bg[^\]]*\]\(([^)]+)\)').firstMatch(t);
        if (m != null) {
          if (imagePath.isEmpty) {
            imagePath = m.group(1) ?? '';
          } else {
            imagePath2 = m.group(1) ?? ''; // tweede afbeelding
          }
        }
        // Parse size: ![bg 50%](...) or ![bg left:42%](...)
        final sizeMatch = RegExp(r'!\[bg[^\]]*?(\d+)%[^\]]*\]').firstMatch(t);
        if (sizeMatch != null && imageSize == 0) {
          imageSize = int.tryParse(sizeMatch.group(1)!) ?? 0;
        }
      } else if (cssClass.split(RegExp(r'\s+')).contains('split') &&
          RegExp(r'!\[[^\]]*\]\(([^)]+)\)').hasMatch(t)) {
        // Plain markdown image, e.g. the `![](path)` used inside a
        // bulletsImage `split-image` panel. Restricted to split slides so a
        // plain image inside free markdown is not mistaken for an image slide.
        final m = RegExp(r'!\[[^\]]*\]\(([^)]+)\)').firstMatch(t);
        if (m != null) {
          if (imagePath.isEmpty) {
            imagePath = m.group(1) ?? '';
          } else {
            imagePath2 = m.group(1) ?? '';
          }
        }
      } else if (t.startsWith('<div class="image-caption">')) {
        final captionParts = _decodeImageCaption(t).split(' | ');
        imageCaption = captionParts.isNotEmpty ? captionParts.first : '';
        imageCaption2 = captionParts.length > 1
            ? captionParts.sublist(1).join(' | ')
            : '';
      } else if (t.startsWith('<video')) {
        final m = RegExp(r'src="([^"]+)"').firstMatch(t);
        if (m != null) videoPath = m.group(1) ?? '';
        videoAutoplay = t.contains('autoplay');
      } else if (t.startsWith('<audio')) {
        final m = RegExp(r'src="([^"]+)"').firstMatch(t);
        if (m != null) audioPath = m.group(1) ?? '';
        audioAutoplay = t.contains('autoplay');
      } else if (t.isNotEmpty && h1.isNotEmpty && paragraph.isEmpty) {
        paragraph = t;
      }
    }

    if (imageSize == 0 && styleImageWidth > 0) imageSize = styleImageWidth;

    final tableRows = <List<String>>[];
    for (final line in tableLines) {
      final cells = _splitTableRow(line);
      // Skip the GFM separator row (e.g. | --- | :---: |).
      if (cells.isNotEmpty &&
          cells.every((c) => RegExp(r'^:?-+:?$').hasMatch(c.trim()))) {
        continue;
      }
      tableRows.add(cells);
    }

    SlideType type;
    switch (cssClass) {
      case final c when c.split(RegExp(r'\s+')).contains('title'):
        type = SlideType.title;
      case final c when c.split(RegExp(r'\s+')).contains('section'):
        type = SlideType.section;
      case final c when c.split(RegExp(r'\s+')).contains('two-bullets'):
        type = SlideType.twoBullets;
      case final c when c.split(RegExp(r'\s+')).contains('split'):
        type = SlideType.bulletsImage;
      case final c when c.split(RegExp(r'\s+')).contains('quote'):
        type = SlideType.quote;
      case final c when c.split(RegExp(r'\s+')).contains('video'):
        type = SlideType.video;
      case final c when c.split(RegExp(r'\s+')).contains('table'):
        type = SlideType.table;
      default:
        if (quote.isNotEmpty) {
          type = SlideType.quote;
        } else if (imagePath.isNotEmpty && imagePath2.isNotEmpty) {
          type = SlideType.twoImages;
        } else if (bullets.isNotEmpty && imagePath.isNotEmpty) {
          type = SlideType.bulletsImage;
        } else if (listStyle == ListStyle.richText) {
          type = SlideType.bullets;
        } else if (bullets.isNotEmpty) {
          type = SlideType.bullets;
        } else if (videoPath.isNotEmpty) {
          type = SlideType.video;
        } else if (imagePath.isNotEmpty) {
          type = SlideType.image;
        } else if (tableRows.isNotEmpty &&
            bullets.isEmpty &&
            h2.isEmpty &&
            paragraph.isEmpty) {
          type = SlideType.table;
        } else if (h1.isEmpty && h2.isEmpty && bullets.isEmpty) {
          type = SlideType.freeMarkdown;
        } else {
          type = SlideType.bullets;
        }
    }

    final classTokens = cssClass.split(RegExp(r'\s+'));
    final showLogo = !classTokens.contains('no-logo');
    final showFooter = !classTokens.contains('no-footer');

    final effectiveClass = classTokens
        .where(
          (c) =>
              c.isNotEmpty &&
              c != type.marpClass &&
              c != 'logo-safe' &&
              c != 'no-logo' &&
              c != 'no-footer',
        )
        .join(' ');

    return Slide(
      id: _uuid.v4(),
      type: type,
      title: h1,
      subtitle: type == SlideType.section ? paragraph : h2,
      bullets: bullets,
      bullets2: bullets2,
      listStyle: listStyle,
      showChecklistProgress: showChecklistProgress,
      columnTitle1: columnTitle1,
      columnTitle2: columnTitle2,
      imagePath: imagePath,
      imagePath2: imagePath2,
      imageCaption: imageCaption,
      imageCaption2: imageCaption2,
      imageSize: imageSize,
      videoPath: videoPath,
      videoAutoplay: videoAutoplay,
      audioPath: audioPath,
      audioAutoplay: audioAutoplay,
      quote: quote,
      quoteAuthor: quoteAuthor,
      customMarkdown: type == SlideType.freeMarkdown
          ? unescapeDeckMarkdownDashLines(remaining)
          : listStyle == ListStyle.richText
          ? unescapeDeckMarkdownDashLines(richTextLines.join('\n').trim())
          : '',
      cssClass: effectiveClass,
      notes: notes,
      advanceDuration: advanceDuration,
      showLogo: showLogo,
      showFooter: showFooter,
      skipped: skipped,
      tlp: slideTlp,
      tableRows: type == SlideType.table ? tableRows : const [],
    );
  }

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
        final m = RegExp(r'src="([^"]+)"').firstMatch(t);
        if (m != null) audioPath = m.group(1) ?? '';
        audioAutoplay = t.contains('autoplay');
      }
    }

    final classTokens = cssClass.split(RegExp(r'\s+'));
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
      if (t.startsWith('<audio')) {
        final m = RegExp(r'src="([^"]+)"').firstMatch(t);
        if (m != null) audioPath = m.group(1) ?? '';
        audioAutoplay = t.contains('autoplay');
      }
    }

    final classTokens = cssClass.split(RegExp(r'\s+'));
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
}
