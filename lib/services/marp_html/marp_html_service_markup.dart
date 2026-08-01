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

/// Inline style carrying a title slide's per-slide title-text-colour override
/// (`ocideck_title_text_color`) as a CSS custom property, or `''` when the
/// slide sets none. The title `h1` reads this variable (with the theme's title
/// colour as fallback), so a slide that dims or lightens its title for a busy
/// background image keeps that choice in the HTML export — matching the app
/// preview, presenter and PDF/PPTX, which already honour the override.
String _titleColorSectionStyle(String slideMarkdown) {
  final hex = _titleColorComment.firstMatch(slideMarkdown)?.group(1);
  return hex == null ? '' : ' style="--ocideck-title-color:$hex"';
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

/// Rendert elke dia uit [markdown] naar zijn `<section>` met inerte
/// markdown-payload. De omzettingsketen loopt van binnen naar buiten: elke
/// stap laat een dia die haar niet aangaat onveranderd, dus de volgorde is
/// vrij; het rapportagetype gaat als eerste omdat het de hele body vervangt.
String _renderSections(
  String markdown, {
  ThemeProfile? theme,
  required CockpitColorScheme cockpitColorScheme,
  required Map<String, String> signature,
}) {
  final exportY01 = MarpHtmlService._y01FromExportMarkdown(markdown);
  final sections = StringBuffer();
  for (final slide in MarpHtmlService.marpSlides(markdown)) {
    var body = MarpHtmlService.renderReportingSlide(slide, theme: theme);
    body = renderMatrixSlide(body, theme: theme);
    body = renderCanvasSlide(body, theme: theme);
    body = renderTreeSlide(body, theme: theme);
    body = renderFlowSlide(body, theme: theme);
    body = MarpHtmlService.renderChartBlocks(
      body,
      theme: theme,
      y01: exportY01,
    );
    body = MarpHtmlService.renderQuestionBlocks(body);
    body = MarpHtmlService.renderMediaRedacted(body);
    body = MarpHtmlService.renderVideoNotice(body);
    body = MarpHtmlService.renderTimelineBlocks(body);
    body = MarpHtmlService.renderSignOffBlock(
      body,
      signature,
      sealedAt: signature['ocideck_seal_at'] ?? '',
    );
    final renderedBlocks = MarpHtmlService.renderCockpitBlocks(
      body,
      theme: theme,
      scheme: cockpitColorScheme,
    );
    final markerClass = _bulletMarkerSectionClass(slide);
    final titleColorStyle = _titleColorSectionStyle(slide);
    sections
      ..write('<section class="slide$markerClass"$titleColorStyle>')
      ..write('<script type="text/markdown">')
      ..write(_guardMarkdown(renderedBlocks))
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
