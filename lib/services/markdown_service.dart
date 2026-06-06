import 'dart:convert';
import 'package:characters/characters.dart';
import 'package:uuid/uuid.dart';
import '../models/deck.dart';
import '../models/settings.dart';
import '../models/slide.dart';

const _uuid = Uuid();

class MarkdownService {
  // ── Generation ──────────────────────────────────────────────────────────────

  String generateDeck(Deck deck) {
    final buf = StringBuffer();
    buf.writeln('---');
    buf.writeln('marp: true');
    buf.writeln('theme: ${deck.theme}');
    if (deck.paginate) buf.writeln('paginate: true');
    // General presentation metadata (also picked up by Marp where applicable).
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
    buf.writeln(
      'ocideck_style_profile: ${base64Url.encode(utf8.encode(jsonEncode(deck.themeProfile.toJson())))}',
    );
    buf.writeln('---');
    buf.writeln();

    for (int i = 0; i < deck.slides.length; i++) {
      if (i > 0) {
        buf.writeln('---');
        buf.writeln();
      }
      buf.write(generateSlide(deck.slides[i], themeProfile: deck.themeProfile));
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

  String generateSlide(Slide slide, {ThemeProfile? themeProfile}) {
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
        buf.writeln();
        for (final b in slide.bullets) {
          _writeBullet(buf, b);
        }

      case SlideType.twoBullets:
        if (slide.title.isNotEmpty) buf.writeln('# ${slide.title}');
        buf.writeln();
        _writeTwoBulletColumns(buf, slide.bullets, slide.bullets2);

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
          buf.writeln();
          for (final b in slide.bullets) {
            _writeBullet(buf, b);
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
          buf.writeln();
          for (final b in slide.bullets) {
            _writeBullet(buf, b);
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
        buf.write(slide.customMarkdown);
        if (slide.customMarkdown.isNotEmpty &&
            !slide.customMarkdown.endsWith('\n')) {
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

    if (slide.notes.isNotEmpty) {
      buf.writeln();
      buf.writeln('<!--');
      buf.writeln(slide.notes);
      buf.writeln('-->');
    }

    buf.writeln();
    return buf.toString();
  }

  static void _writeBullet(StringBuffer buf, String bullet) {
    int level = 0;
    while (level < bullet.length && bullet[level] == '\t') {
      level++;
    }
    final text = bullet.substring(level);
    if (text.isNotEmpty) {
      buf.writeln('${'  ' * level}- $text');
    }
  }

  static void _writeTwoBulletColumns(
    StringBuffer buf,
    List<String> left,
    List<String> right,
  ) {
    buf.writeln('<!-- ocideck_two_bullets_left: ${_encodeBullets(left)} -->');
    buf.writeln('<!-- ocideck_two_bullets_right: ${_encodeBullets(right)} -->');
    buf.writeln(
      '<div class="ocideck-two-bullets" style="display:grid; grid-template-columns:1fr 1fr; gap:3rem; align-items:start;">',
    );
    buf.writeln('<ul style="margin:0; padding-left:1.3em;">');
    _writeHtmlBulletItems(buf, left);
    buf.writeln('</ul>');
    buf.writeln('<ul style="margin:0; padding-left:1.3em;">');
    _writeHtmlBulletItems(buf, right);
    buf.writeln('</ul>');
    buf.writeln('</div>');
  }

  static String _encodeBullets(List<String> bullets) {
    return base64Url.encode(utf8.encode(jsonEncode(bullets)));
  }

  static List<String> _decodeBullets(String encoded) {
    try {
      final decoded = utf8.decode(base64Url.decode(encoded.trim()));
      final raw = jsonDecode(decoded);
      if (raw is List) return raw.map((v) => v.toString()).toList();
    } catch (_) {}
    return const [];
  }

  static void _writeHtmlBulletItems(StringBuffer buf, List<String> bullets) {
    for (final b in bullets) {
      int level = 0;
      while (level < b.length && b[level] == '\t') {
        level++;
      }
      final text = b.substring(level).trim();
      if (text.isEmpty) continue;
      final style = level == 0 ? '' : ' style="margin-left:${level * 1.4}em;"';
      buf.writeln('<li$style>${_escapeHtml(text)}</li>');
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
    } catch (_) {
      return null;
    }
  }

  Deck _doParse(String markdown, {String? filePath}) {
    String content = markdown;
    String theme = 'ocideck';
    bool paginate = true;
    ThemeProfile themeProfile = const ThemeProfile();
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
            final encoded = line.substring(22).trim();
            final decoded = utf8.decode(base64Url.decode(encoded));
            themeProfile = ThemeProfile.fromJson(
              Map<String, Object?>.from(jsonDecode(decoded) as Map),
            );
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

    String title = 'Presentatie';
    if (slides.isNotEmpty && slides.first.title.isNotEmpty) {
      title = slides.first.title;
    }

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
    final bullets = <String>[];
    var bullets2 = <String>[];
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
        } else if (content.startsWith('_style:')) {
          final w = RegExp(r'--image-width:\s*(\d+)%').firstMatch(content);
          if (w != null) styleImageWidth = int.tryParse(w.group(1)!) ?? 0;
        } else if (content.startsWith('ocideck_two_bullets_left:')) {
          bullets
            ..clear()
            ..addAll(_decodeBullets(content.substring(25)));
        } else if (content.startsWith('ocideck_two_bullets_right:')) {
          bullets2 = _decodeBullets(content.substring(26));
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

    for (final line in lines) {
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
        bullets.add('\t' * level + t.substring(2));
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
      customMarkdown: type == SlideType.freeMarkdown ? remaining : '',
      cssClass: effectiveClass,
      notes: notes,
      advanceDuration: advanceDuration,
      showLogo: showLogo,
      showFooter: showFooter,
      skipped: skipped,
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
    );
  }
}
