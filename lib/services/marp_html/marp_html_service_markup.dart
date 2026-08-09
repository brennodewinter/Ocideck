// Part of the marp_html_service library — see ../marp_html_service.dart.
// Split out for navigability (markdown-commentaren per dia, en het ontsnappen van HTML/JS); all imports live in the main library
// file. These were private MarpHtmlService helpers; as top-level private
// functions they share the library and are called by bare name.
part of '../marp_html_service.dart';

final RegExp _listStyleComment = RegExp(r'<!--\s*ocideck_list_style:\s*(\w+)');
final RegExp _bulletMarkerComment = RegExp(
  r'<!--\s*ocideck_bullet_marker:\s*(\w+)',
);

/// Strict hex so the matched value can never break out of the `style`
/// attribute it is written into (see [_titleColorSectionStyle]).
final RegExp _titleColorComment = RegExp(
  r'<!--\s*ocideck_title_text_color:\s*(#[0-9A-Fa-f]{3,8})',
);

/// Strict slug so the matched value can never break out of the `id` attribute
/// it is written into. Anchors are `[a-z0-9-]` by construction (see
/// `slugifyAnchor`), so anything else is not one of ours and is ignored.
final RegExp _slideAnchorComment = RegExp(
  r'<!--\s*ocideck_slide_anchor:\s*([a-z0-9-]+)',
);

/// The `id` a slide's `<section>` carries so an in-page `#anchor` link — a
/// choice-menu block, a jump-out — actually lands on it in the HTML export, or
/// `''` when the slide has no anchor. marked (v18) generates no heading ids, so
/// without this every `[label](#anchor)` fragment link would scroll nowhere.
String _slideAnchorIdAttr(String slideMarkdown) {
  final anchor = _slideAnchorComment.firstMatch(slideMarkdown)?.group(1);
  return anchor == null ? '' : ' id="$anchor"';
}

final RegExp _safeCssColor = RegExp(
  r'^(?:#[0-9a-fA-F]{3,8}|[a-zA-Z]+|(?:rgb|hsl)a?\([0-9.,%+\- ]+\))$',
);
final RegExp _safeCssGradient = RegExp(
  r'^(?:(?:repeating-)?(?:linear|radial|conic)-gradient)\([#(),.%a-zA-Z0-9+\- ]+\)$',
);
final RegExp _safeCssLocalUrl = RegExp(r'''^url\((['"]?)([^'"\)]+)\1\)$''');

String _marpBackgroundImage(String value) {
  final trimmed = value.trim();
  if (trimmed == 'none' || _safeCssGradient.hasMatch(trimmed)) return trimmed;
  final url = _safeCssLocalUrl.firstMatch(trimmed)?.group(2)?.trim();
  if (url == null || url.isEmpty || url.startsWith('//')) return '';
  if (url.contains(':') && !url.startsWith('data:image/')) return '';
  if (url.contains(';') && !url.startsWith('data:image/')) return '';
  return trimmed;
}

String _marpCssFilters(List<String> filters) {
  final safe = <String>[];
  for (final filter in filters) {
    final parts = filter.toLowerCase().split(':');
    final name = parts.first;
    if ({'grayscale', 'sepia', 'invert'}.contains(name) && parts.length == 1) {
      safe.add('$name(1)');
      continue;
    }
    if (parts.length != 2) continue;
    final value = parts[1];
    final cssValue =
        name == 'blur' && RegExp(r'^\d+(?:\.\d+)?$').hasMatch(value)
        ? '${value}px'
        : value;
    final valid = switch (name) {
      'blur' => RegExp(
        r'^(?:0|\d+(?:\.\d+)?(?:px|em|rem))$',
      ).hasMatch(cssValue),
      'brightness' ||
      'saturate' => RegExp(r'^\d+(?:\.\d+)?%?$').hasMatch(cssValue),
      _ => false,
    };
    if (valid) safe.add('$name($cssValue)');
  }
  return safe.join(' ');
}

({String classes, String attributes}) _marpSectionStyle(
  String slideMarkdown,
  MarpStyle style,
) {
  final css = <String>[];
  final color = style.color.trim();
  final backgroundColor = style.backgroundColor.trim();
  final backgroundImage = _marpBackgroundImage(style.backgroundImage);
  final filter = _marpCssFilters(style.imageFilters);
  final titleColor = _titleColorComment.firstMatch(slideMarkdown)?.group(1);
  if (_safeCssColor.hasMatch(color)) css.add('color:$color');
  if (_safeCssColor.hasMatch(backgroundColor)) {
    css.add('background-color:$backgroundColor');
  }
  if (backgroundImage.isNotEmpty) css.add('background-image:$backgroundImage');
  if (titleColor != null) css.add('--ocideck-title-color:$titleColor');
  final attrs = StringBuffer();
  if (style.imageFit == 'contain') attrs.write(' data-marp-bg-fit="contain"');
  if (filter.isNotEmpty) {
    attrs.write(' data-marp-bg-filter="${MarpHtmlService._htmlAttr(filter)}"');
  }
  if (css.isNotEmpty) {
    attrs.write(' style="${MarpHtmlService._htmlAttr(css.join(';'))}"');
  }
  return (
    classes: style.headingFit ? ' marp-heading-fit' : '',
    attributes: attrs.toString(),
  );
}

String _marpChromeSource(String position, String markdown) {
  if (markdown.isEmpty) return '';
  return '<span hidden class="marp-$position-source" data-markdown="'
      '${MarpHtmlService._htmlAttr(markdown)}"></span>\n';
}

/// Extra `<section>` class that turns this slide's plain bullets into cat-paw
/// markers (` paw-bullets`), or `''`. The decision is taken entirely from the
/// `ocideck_bullet_marker` comment that the *export* markdown carries for
/// every paw-rendering bullet slide (see `MarkdownService`, `forExport`). A
/// free-markdown slide that merely contains a `-` list never carries that
/// comment, so it never gets a paw — keeping HTML, app and PDF/PPTX identical.
/// Numbered, checklist and rich-text slides keep their own markers.
String _bulletMarkerSectionClass(String slideMarkdown) {
  final style = _listStyleComment.firstMatch(slideMarkdown)?.group(1);
  if (style == 'numbered' || style == 'checklist' || style == 'richText') {
    return '';
  }
  final marker = _bulletMarkerComment.firstMatch(slideMarkdown)?.group(1);
  return marker == BulletMarker.paw.name ? ' paw-bullets' : '';
}

/// A self-contained cat-paw as an inline SVG `data:` URI, with [accent] baked
/// in as the fill. Used as the `li::before` marker for paw bullet lists. The
/// whole SVG is percent-encoded, so the (theme-controlled) colour value can
/// never break out of the attribute.
String _pawDataUri(String accent) {
  const path =
      "M8 9.28Q12.64 9.28 10.32 12.4Q8 15.52 5.68 12.4Q3.36 9.28 8 9.28Z";
  final svg =
      "<svg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 16 16'>"
      "<path d='$path' fill='$accent'/>"
      "<ellipse cx='2.56' cy='6.88' rx='1.76' ry='2.4' fill='$accent' transform='rotate(-31.5 2.56 6.88)'/>"
      "<ellipse cx='6.24' cy='3.36' rx='1.92' ry='2.8' fill='$accent' transform='rotate(-10.3 6.24 3.36)'/>"
      "<ellipse cx='9.76' cy='3.36' rx='1.92' ry='2.8' fill='$accent' transform='rotate(10.3 9.76 3.36)'/>"
      "<ellipse cx='13.44' cy='6.88' rx='1.76' ry='2.4' fill='$accent' transform='rotate(31.5 13.44 6.88)'/>"
      "</svg>";
  return 'data:image/svg+xml,${Uri.encodeComponent(svg)}';
}

/// Neutralise any `</script` inside inlined content so it can't break out of
/// the surrounding <script> element. Case-insensitive — `</ScRiPt>` must not
/// slip through. Safe for both JS (string contexts) and the embedded Markdown
/// payloads.
final RegExp _scriptClose = RegExp(r'</(script)', caseSensitive: false);

/// Maakt [s] veilig als inhoud van een `<script type="text/markdown">`.
///
/// `</script` is niet de enige uitgang. De HTML-tokenizer kent binnen een
/// script-element ook *script data escaped*: een `<!--` zet hem in die stand,
/// en een daaropvolgende `<script` in *double escaped* — en dáár sluit een
/// echte `</script>` het element níét meer, hij zet alleen één stand terug.
/// Alles erna wordt scripttekst: de rest van de dia's, én het renderscript dat
/// de markdown-houders pas zichtbaar maakt. De export opende dan als een lege
/// witte pagina, zonder enige foutmelding.
///
/// Dat is geen exotische invoer. Een codedia die kwetsbare paginabron citeert
/// — precies wat een pentestrapport doet — bevat routineus een uitgezette
/// `<script>` in commentaar. In de app, de presenter en de PDF klopte die dia.
///
/// Het renderscript draait de ontsnapping terug vóórdat marked de tekst ziet
/// (zie [_renderScript]). Zonder die terugdraai zou een `<!-- _class: … -->`
/// als zichtbare tekst mét backslash in het document belanden — en dat was al
/// het geval voor `</script`, dat werd ontsnapt maar nooit hersteld.
String _guardMarkdown(String s) => _guardScript(s).replaceAll('<!--', r'<\!--');

/// Strips a leading YAML front-matter block from [markdown] and normalises
/// `\r\n` to `\n`, **without** splitting on `---`. The exact strip that
/// [MarpHtmlService.marpSlides] does before it splits, lifted out so the
/// continuous document mode can reuse it: a document renders this whole body as
/// one flow, so a `---` in the body must survive as text (marked turns it into
/// a real `<hr>`) instead of becoming a page break.
String _stripFrontMatter(String markdown) {
  var text = markdown.replaceAll('\r\n', '\n');
  if (text.startsWith('---\n')) {
    final close = text.indexOf('\n---', 4);
    if (close != -1) {
      final nl = text.indexOf('\n', close + 1);
      text = nl == -1 ? '' : text.substring(nl + 1);
    }
  }
  return text;
}

/// Past de blok-transformaties op één body toe — een losse dia óf de hele
/// documentbody in de doorlopende modus. De omzettingsketen loopt van binnen
/// naar buiten: elke stap laat inhoud die haar niet aangaat onveranderd, dus de
/// volgorde is vrij; het rapportagetype gaat als eerste omdat het de hele body
/// vervangt. Gedeeld zodat dia- en documentmodus door exact dezelfde renderlaag
/// lopen — geen tweede route.
String _renderBodyBlocks(
  String body, {
  required ThemeProfile? theme,
  required CockpitColorScheme cockpitColorScheme,
  required Map<String, String> signature,
  required ImprovementY01Metric exportY01,
}) {
  var out = MarpHtmlService.renderReportingSlide(body, theme: theme);
  out = renderMatrixSlide(out, theme: theme);
  out = renderCanvasSlide(out, theme: theme);
  out = renderTreeSlide(out, theme: theme);
  out = renderFlowSlide(out, theme: theme);
  out = renderMenuSlide(out, theme: theme);
  out = MarpHtmlService.renderChartBlocks(out, theme: theme, y01: exportY01);
  out = MarpHtmlService.renderQuestionBlocks(out);
  out = MarpHtmlService.renderMediaRedacted(out);
  out = MarpHtmlService.renderVideoNotice(out);
  out = MarpHtmlService.renderTimelineBlocks(out);
  out = MarpHtmlService.renderSignOffBlock(
    out,
    signature,
    sealedAt: signature['ocideck_seal_at'] ?? '',
  );
  return MarpHtmlService.renderCockpitBlocks(
    out,
    theme: theme,
    scheme: cockpitColorScheme,
  );
}

/// Rendert [markdown] naar de `<section>`(s) met inerte markdown-payload.
///
/// [continuous] false is het dia-pad: splits op `---`, elke dia een
/// `<section class="slide…">`. [continuous] true is de documentmodus: geen
/// split, de hele front-matter-gestripte body als één `<section class="document">`.
/// Beide leggen hun body als payload in een `<script type="text/markdown">` via
/// [_guardMarkdown] — nooit rechtstreeks gerenderde HTML, zodat de client-side
/// marked+DOMPurify-poort de enige renderroute blijft.
String _renderSections(
  String markdown, {
  ThemeProfile? theme,
  required CockpitColorScheme cockpitColorScheme,
  required Map<String, String> signature,
  bool continuous = false,
  MarpStyle deckMarpStyle = const MarpStyle(),
  List<MarpStyle> slideMarpStyles = const [],
}) {
  final exportY01 = MarpHtmlService._y01FromExportMarkdown(markdown);
  if (continuous) {
    final rendered = _renderBodyBlocks(
      _stripFrontMatter(markdown).trim(),
      theme: theme,
      cockpitColorScheme: cockpitColorScheme,
      signature: signature,
      exportY01: exportY01,
    );
    return '<section class="document">'
        '<script type="text/markdown">'
        '${_guardMarkdown(rendered)}'
        '</script></section>';
  }
  final sections = StringBuffer();
  var slideIndex = 0;
  for (final slide in MarpHtmlService.marpSlides(markdown)) {
    final localStyle = slideIndex < slideMarpStyles.length
        ? slideMarpStyles[slideIndex]
        : const MarpStyle();
    final marpStyle = localStyle.inherit(deckMarpStyle);
    slideIndex++;
    final renderedBlocks = _renderBodyBlocks(
      slide,
      theme: theme,
      cockpitColorScheme: cockpitColorScheme,
      signature: signature,
      exportY01: exportY01,
    );
    final markerClass = _bulletMarkerSectionClass(slide);
    final anchorId = _slideAnchorIdAttr(slide);
    final marpSection = _marpSectionStyle(slide, marpStyle);
    sections
      ..write(
        '<section class="slide$markerClass${marpSection.classes}"'
        '$anchorId${marpSection.attributes}>',
      )
      ..write('<script type="text/markdown">')
      ..write(_guardMarkdown(_marpChromeSource('header', marpStyle.header)))
      ..write(_guardMarkdown(renderedBlocks))
      ..write(_guardMarkdown(_marpChromeSource('footer', marpStyle.footer)))
      ..write('</script></section>');
  }
  return sections.toString();
}

/// Neutraliseert `</script` in échte JavaScript.
///
/// Hier bewust géén `<!--`-behandeling: in JavaScript is `<!--` een geldige
/// (legacy) regelcommentaar en `<\!--` een syntaxfout, dus die ontsnapping
/// zou de gebundelde bibliotheken slopen. Nodig is het ook niet — deze code is
/// vendored en vast, geen inhoud uit een deck.
String _guardScript(String s) =>
    s.replaceAllMapped(_scriptClose, (m) => '<\\/${m.group(1)}');
