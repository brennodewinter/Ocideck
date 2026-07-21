part of 'markdown_service.dart';

// Low-level Marp read/write helpers, split out of markdown_service.dart for
// navigability. These were `static` members of MarkdownService; as top-level
// private functions they share the library's imports and are called by bare
// name from the service's generate/parse methods.

// Hoisted hot-path regexes (zie markdown_service_parse.dart); [_attrRegexes]
// cachet de per-attribuutnaam gebouwde patronen van [_parseEmbedLine].
final _reSrcAttr = RegExp(r'src="([^"]+)"');
final _reTrailingZeros = RegExp(r'0+$');
final _attrRegexes = <String, RegExp>{};

void _writeList(StringBuffer buf, List<String> items, ListStyle style) {
  final counters = <int>[];
  for (final item in items) {
    // A group heading rides through the ordinary bullet path: written verbatim
    // as `- <marker><label>` (never a checkbox or a number, and it does not
    // advance the list counters) and read back by the plain `- body` parser, so
    // the marker survives round-trips with no parser change. See
    // [kGroupHeadingMarker].
    if (isGroupHeading(item)) {
      buf.writeln('- $item');
      continue;
    }
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

void _writeTwoBulletColumns(
  StringBuffer buf,
  List<String> left,
  List<String> right,
  String leftTitle,
  String rightTitle,
  ListStyle listStyle,
  bool showChecklistProgress,
  ThemeProfile themeProfile,
) {
  // De inhoud van beide kolommen stond hier tot 0.1.0 in vier
  // base64-richtlijnen, met de zichtbare `<ul><li>` eronder als decor. Nu draagt
  // die opmaak de inhoud zelf: de ontsnapping in [_writeHtmlBulletItems] maakt
  // een bullet met HTML of een pipe erin veilig, en [_parseTwoColumnBullets]
  // leest hem weer terug. Wat overblijft aan commentaar is leesbaar.
  if (listStyle != ListStyle.bullets) {
    buf.writeln('<!-- ocideck_list_style: ${listStyle.name} -->');
  }
  if (showChecklistProgress) {
    buf.writeln('<!-- ocideck_checklist_progress: true -->');
  }
  buf.writeln(
    '<div class="ocideck-two-bullets" style="display:grid; grid-template-columns:1fr 1fr; gap:3rem; align-items:start;">',
  );
  _writeBulletColumn(buf, left, leftTitle, listStyle, themeProfile);
  _writeBulletColumn(buf, right, rightTitle, listStyle, themeProfile);
  buf.writeln('</div>');
}

void _writeChecklistProgress(StringBuffer buf, Slide slide) {
  if (slide.showChecklistProgress) {
    buf.writeln('<!-- ocideck_checklist_progress: true -->');
  }
}

/// Per-slide bullet-marker comment (dot/paw).
///
/// On a normal save, only an explicit per-slide override is written; absence
/// means "inherit the theme default", keeping the override semantics intact.
///
/// For [forExport], the *effective* paw marker (override **or** theme default)
/// is pinned on plain bullet slides as well, so the static HTML export can
/// match the app exactly without re-deriving the slide type — a free-markdown
/// slide that merely contains a `-` list never reaches this code, so it never
/// gets a paw. The hint is export-only and never written to saved files.
void _writeBulletMarkerOverride(
  StringBuffer buf,
  Slide slide,
  ThemeProfile? theme,
  bool forExport,
) {
  final override = slide.bulletMarkerOverride;
  if (override != null) {
    buf.writeln('<!-- ocideck_bullet_marker: ${override.name} -->');
    return;
  }
  if (forExport &&
      slide.listStyle == ListStyle.bullets &&
      theme?.bulletMarker == BulletMarker.paw) {
    buf.writeln('<!-- ocideck_bullet_marker: paw -->');
  }
}

void _writeBulletColumn(
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

// Alleen nog lezen: de base64-tegenhangers zijn weg. Deze twee blijven bestaan
// om een bestand dat OciDeck vóór 0.1.0 schreef te kunnen openen; bij het
// opslaan gaat het naar de zichtbare vorm en komen ze niet meer terug.

String _decodeText(String encoded) {
  try {
    return utf8.decode(base64Url.decode(encoded.trim()));
  } catch (e, s) {
    logError('MarkdownService._decodeText: base64/utf8 decode', e, s);
    return '';
  }
}

List<String> _decodeBullets(String encoded) {
  try {
    final decoded = utf8.decode(base64Url.decode(encoded.trim()));
    final raw = jsonDecode(decoded);
    if (raw is List) return raw.map((v) => v.toString()).toList();
  } catch (e, s) {
    logError('MarkdownService._decodeBullets: base64/utf8/json decode', e, s);
  }
  return const [];
}

void _writeHtmlBulletItems(
  StringBuffer buf,
  List<String> bullets,
  ListStyle listStyle,
  ThemeProfile themeProfile,
) {
  final counters = <int>[];
  for (final b in bullets) {
    // A group heading is a markerless section label (empty = a divider rule),
    // not a list entry, so it renders as an <li> with no bullet and never
    // advances the counters. See [kGroupHeadingMarker].
    if (isGroupHeading(b)) {
      final label = groupHeadingText(b).trim();
      buf.writeln(
        label.isEmpty
            ? '<li style="list-style:none; border-top:1px solid currentColor; '
                  'opacity:.4; margin:.5em 0; height:0;"></li>'
            : '<li style="list-style:none; font-weight:bold; margin:.6em 0 .2em;">'
                  '${_escapeHtml(label)}</li>',
      );
      continue;
    }
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

String _escapeHtml(String value) {
  return value
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;');
}

/// De omkering van [_escapeHtml], en de reden dat de zichtbare `<li>` de inhoud
/// mág dragen: een bullet die zelf HTML of een pipe bevat overleeft de rondgang
/// omdat hij ontsnapt wordt geschreven en hier weer heel terugkomt. Het paar
/// staat bewust naast elkaar — gaan ze uit de pas lopen, dan is dat hier te zien
/// en niet pas in een deck waarin `&amp;lt;` in beeld staat.
///
/// `&amp;` gaat als laatste, anders wordt een letterlijk getypte `&lt;` na twee
/// stappen alsnog een `<`.
String _unescapeHtml(String value) {
  return value
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&quot;', '"')
      .replaceAll('&amp;', '&');
}

double _splitTextScale(Slide slide) {
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

void _writeImageCaption(StringBuffer buf, String caption) {
  _writeCaptionDiv(buf, _encodeCaption(caption.trim()));
}

/// Writes an already pipe-encoded caption body as the shared
/// `<div class="image-caption">`. The single-caption and two-caption paths
/// both end here so the markup is produced in exactly one place.
void _writeCaptionDiv(StringBuffer buf, String body) {
  if (body.isEmpty) return;
  buf.writeln(
    '<div class="image-caption">${const HtmlEscape().convert(body)}</div>',
  );
}

/// Serialiseert een videoslide. Lokale/online bestanden worden een `<video>`
/// met een `#t=start,end` media-fragment (de standaard, ook door browsers en
/// Marp begrepen). YouTube/Vimeo worden een `<iframe class="ocideck-embed">`
/// met de speler-URL; start/eind reizen mee in `data-start`/`data-end` zodat
/// het knippen verliesvrij round-trippt. Bij [forExport] krijgt een online
/// bron óók een aanklikbare letterlijke URL eronder.
void _writeVideo(StringBuffer buf, Slide slide, {required bool forExport}) {
  final source = VideoSource.parse(slide.videoPath);
  // Decimal seconds so the trim window round-trips losslessly: flooring the
  // start and ceiling the end widened the segment by up to a second on every
  // save, eventually overlapping the neighbouring split. `_secToMs` already
  // parses fractional seconds back to milliseconds.
  final startSec = _msToSec(slide.videoStartMs);
  final endSec = _msToSec(slide.videoEndMs);

  if (source.isEmbed) {
    final embed =
        source
            .embedUri(
              startMs: slide.videoStartMs,
              endMs: slide.videoEndMs,
              autoplay: slide.videoAutoplay,
            )
            ?.toString() ??
        slide.videoPath;
    const attr = HtmlEscape(HtmlEscapeMode.attribute);
    final data = StringBuffer()
      ..write(' data-src="${attr.convert(slide.videoPath)}"');
    if (slide.videoStartMs > 0) data.write(' data-start="$startSec"');
    if (slide.videoEndMs > 0) data.write(' data-end="$endSec"');
    buf.writeln(
      '<iframe class="ocideck-embed"$data src="${attr.convert(embed)}" '
      'style="width:100%; aspect-ratio:16/9; border:0;" '
      'allow="autoplay; fullscreen; picture-in-picture" allowfullscreen></iframe>',
    );
  } else {
    // Lokaal pad of directe online videobestand-URL.
    var frag = '';
    if (slide.videoStartMs > 0 || slide.videoEndMs > 0) {
      frag = slide.videoEndMs > 0 ? '#t=$startSec,$endSec' : '#t=$startSec';
    }
    final autoplay = slide.videoAutoplay ? ' autoplay muted loop' : '';
    const attr = HtmlEscape(HtmlEscapeMode.attribute);
    buf.writeln(
      '<video src="${attr.convert(slide.videoPath)}$frag" controls$autoplay style="width:100%; max-height:72vh;"></video>',
    );
  }

  // Bij export een aanklikbare letterlijke URL voor online bronnen (de bron
  // zelf is dan ook buiten de presentatie te bereiken).
  if (forExport && source.isRemote) {
    buf.writeln();
    buf.writeln('[${slide.videoPath}](${slide.videoPath})');
  }
}

/// Parseert een `<video …>`-regel: splitst het `#t=start,end` media-fragment
/// van de bron af en leest de trim-grenzen (in ms).
({String path, int startMs, int endMs, bool autoplay}) _parseVideoLine(
  String t,
) {
  final m = _reSrcAttr.firstMatch(t);
  var src = _unescapeAttr(m?.group(1) ?? '');
  var startMs = 0;
  var endMs = 0;
  final hash = src.indexOf('#t=');
  if (hash >= 0) {
    final frag = src.substring(hash + 3);
    src = src.substring(0, hash);
    final parts = frag.split(',');
    startMs = _secToMs(parts.isNotEmpty ? parts[0] : '');
    endMs = parts.length > 1 ? _secToMs(parts[1]) : 0;
  }
  return (
    path: src,
    startMs: startMs,
    endMs: endMs,
    autoplay: t.contains('autoplay'),
  );
}

/// Parseert een `<iframe class="ocideck-embed" …>`-regel terug naar de bron en
/// trim-grenzen. `data-src` (de originele URL) gaat vóór `src`; `data-start`/
/// `data-end` (seconden) bevatten de knip-grenzen.
({String path, int startMs, int endMs}) _parseEmbedLine(String t) {
  String attr(String name) => _unescapeAttr(
    _attrRegexes
            .putIfAbsent(name, () => RegExp('$name="([^"]*)"'))
            .firstMatch(t)
            ?.group(1) ??
        '',
  );
  final dataSrc = attr('data-src');
  final src = dataSrc.isNotEmpty ? dataSrc : attr('src');
  return (
    path: src,
    startMs: _secToMs(attr('data-start')),
    endMs: _secToMs(attr('data-end')),
  );
}

/// Keert de attribuut-escaping van [_writeVideo] om (`&amp;`/`&quot;`/…).
String _unescapeAttr(String s) => s
    .replaceAll('&quot;', '"')
    .replaceAll('&#47;', '/')
    .replaceAll('&#39;', "'")
    .replaceAll('&lt;', '<')
    .replaceAll('&gt;', '>')
    .replaceAll('&amp;', '&');

/// Parses an `<audio src="…" [autoplay]>` line into `(path, autoplay)`. The
/// same `<audio>` attachment markup is read by every slide-type parser (the
/// element is written by a common block), so they share this instead of
/// repeating the regex.
(String, bool) _parseAudioAttrs(String t) {
  final m = _reSrcAttr.firstMatch(t);
  return (m?.group(1) ?? '', t.contains('autoplay'));
}

int _secToMs(String s) {
  final v = double.tryParse(s.trim());
  if (v == null || v <= 0) return 0;
  return (v * 1000).round();
}

/// Milliseconds → a compact seconds string for a `#t=`/`data-start` value:
/// whole seconds stay integer (`5`), otherwise up to millisecond precision
/// with no trailing zeros (`1.5`, `1.234`). The inverse of [_secToMs].
String _msToSec(int ms) {
  final seconds = ms / 1000;
  if (seconds == seconds.roundToDouble()) return seconds.toStringAsFixed(0);
  return seconds.toStringAsFixed(3).replaceFirst(_reTrailingZeros, '');
}

/// Captions live in a `<div class="image-caption">`; a split-image slide puts
/// two of them in one div joined by `" | "`. A literal pipe in a caption would
/// otherwise be mistaken for that separator on parse (truncating a single
/// caption or shifting text between two), so EVERY caption's pipes are swapped
/// for a private-use sentinel before serialisation — single and two-caption
/// alike — leaving the real `" | "` separator unambiguous. The sentinel cannot
/// occur in real caption text and passes through the HTML (un)escaping
/// untouched. Both write paths funnel through [_writeCaptionDiv].
const String _captionSeparator = ' | ';
const String _captionPipeSentinel = '\u{E000}';

/// Escapes a real (private-use) [_captionPipeSentinel] that the user actually
/// typed, so it survives the round-trip instead of being mistaken for an
/// encoded pipe on decode. U+E001 is likewise reserved.
const String _captionLiteralSentinel = '\u{E001}';

String _encodeCaption(String caption) => caption
    // Protect a user-typed sentinel FIRST (now no bare sentinels remain)…
    .replaceAll(_captionPipeSentinel, _captionLiteralSentinel)
    // …then stand in for real pipes with the sentinel.
    .replaceAll('|', _captionPipeSentinel);

String _decodeCaption(String caption) => caption
    // Undo in reverse: sentinels are decoded pipes…
    .replaceAll(_captionPipeSentinel, '|')
    // …and the literal marker restores a user-typed sentinel. Files written by
    // the older single-sentinel scheme have no literal marker, so they still
    // decode correctly.
    .replaceAll(_captionLiteralSentinel, _captionPipeSentinel);

String _joinTwoCaptions(String first, String second) => [first, second]
    .where((caption) => caption.trim().isNotEmpty)
    .map((caption) => _encodeCaption(caption.trim()))
    .join(_captionSeparator);

List<String> _splitTwoCaptions(String decoded) =>
    decoded.split(_captionSeparator).map(_decodeCaption).toList();

/// An HTML comment cannot contain `-->`; a speaker note that does would be
/// truncated there on parse (the comment closes early and the tail leaks into
/// the slide body). Escape the token on write and restore it on read. A note
/// containing the literal escape `--\>` is the only (negligible) collision.
String _escapeNotes(String notes) => notes.replaceAll('-->', r'--\>');
String _unescapeNotes(String notes) => notes.replaceAll(r'--\>', '-->');

// Deelt de unescape-tabel met [_unescapeAttr]: de caption wordt geschreven
// met HtmlEscape (unknown-mode), die ook `/` naar `&#47;` escapet — de eigen
// (gekopieerde) tabel hier miste die entry, waardoor een bijschrift met een
// slash niet round-tripte.
String _decodeImageCaption(String line) {
  return _unescapeAttr(
    line
        .replaceFirst('<div class="image-caption">', '')
        .replaceFirst('</div>', ''),
  ).trim();
}
