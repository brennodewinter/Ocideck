// De huisstijl uit een `.docx`: letters, kleuren, kop- en voettekst, en het
// beeld dat op elke bladzijde staat (#2119).
//
// Waar Word het bewaart, en dus waar dit leest:
//
// - `word/theme/theme1.xml` — de *major*- (koppen) en *minor*-letter (lopende
//   tekst) en de themakleuren (`accent1`…). Stijlen verwijzen ernaar met
//   `w:asciiTheme="majorHAnsi"` in plaats van een naam te noemen.
// - `word/styles.xml` — `docDefaults` en de stijl `heading 1`: letter, kleur,
//   met een `basedOn`-keten die opgelost moet worden.
// - `word/header*.xml` / `footer*.xml` — de koptekst is hoe Word "een beeld
//   op iedere bladzijde" doet: één keer, in het deel dat de sectie als
//   `default` aanwijst. Het `first`-deel geldt alleen voor het titelblad
//   (`w:titlePg`) en telt daarom niet als logo.
//
// Een beeld dat iemand met de hand op elke bladzijde plakte staat wél in de
// body, als `wp:anchor` ten opzichte van de pagina; dat is de tweede route.

part of 'docx_document_importer.dart';

/// EMU per millimeter (OOXML meet in English Metric Units).
const _emuPerMm = 36000.0;

/// EMU per twip (de eenheid van `w:pgSz`).
const _emuPerTwip = 635.0;

/// A4-breedte in EMU: de terugval wanneer een sectie geen `w:pgSz` draagt.
const _defaultPageWidthEmu = 210 * _emuPerMm;
const _defaultPageHeightEmu = 297 * _emuPerMm;

/// Dezelfde grens als `FileService.maxStyleProfileLogoBytes` (8 MiB); hier
/// als eigen constante omdat deze laag geen `dart:io` mag importeren.
const _maxLogoBytes = 8 * 1024 * 1024;

/// Leest de huisstijl uit het archief. Elk onderdeel dat ontbreekt levert
/// `null` op in het resultaat; niets hier werpt op een kaal document.
SourceDocumentStyle _extractDocxStyle(_DocxContext ctx) {
  final theme = _DocxTheme.load(ctx);
  final styles = ctx.readXml('word/styles.xml');
  final fonts = _DocxFontResolver(ctx, styles, theme);
  final losses = <DocumentStyleLoss>[];

  final bodyFont = fonts.bodyFont();
  final headingStyle = fonts.headingStyle(1);
  final headingFont = headingStyle == null
      ? null
      : fonts.styleFont(headingStyle) ?? theme?.majorFont;
  final textColor = fonts.bodyColor();
  final headingColor = headingStyle == null
      ? null
      : fonts.styleColor(headingStyle);
  _noteOtherHeadingColors(fonts, headingColor, losses);

  final sections = _DocxSections.read(ctx);
  final logos = <DocumentLogoCandidate>[];
  final seen = <String>{};
  String? headerText;
  String? footerText;
  var pageNumbers = false;
  var vectorOnly = 0;
  for (final part in sections.defaultHeaders) {
    final read = _readChromePart(ctx, part, sections, isHeader: true);
    headerText ??= read.text;
    pageNumbers = pageNumbers || read.hasPageNumber;
    vectorOnly += read.vectorOnly;
    _addLogos(read.logos, logos, seen);
  }
  for (final part in sections.defaultFooters) {
    final read = _readChromePart(ctx, part, sections, isHeader: false);
    footerText ??= read.text;
    pageNumbers = pageNumbers || read.hasPageNumber;
    vectorOnly += read.vectorOnly;
    _addLogos(read.logos, logos, seen);
  }
  var titlePageImages = 0;
  for (final part in sections.titlePageParts) {
    final read = _readChromePart(ctx, part, sections, isHeader: true);
    titlePageImages += read.logos.length + read.vectorOnly;
  }
  _addLogos(_repeatedBodyImages(ctx, sections), logos, seen);
  if (titlePageImages > 0) {
    losses.add(const DocumentStyleLoss(DocumentStyleLossKind.titlePageImage));
  }
  if (vectorOnly > 0) {
    losses.add(const DocumentStyleLoss(DocumentStyleLossKind.vectorOnlyLogo));
  }
  if (logos.any((logo) => logo.centred)) {
    losses.add(const DocumentStyleLoss(DocumentStyleLossKind.centredLogo));
  }

  return SourceDocumentStyle(
    title: _packageTitle(ctx),
    bodyFontFamily: bodyFont,
    headingFontFamily: headingFont,
    textColor: textColor,
    headingColor: headingColor,
    accentColor: theme?.accent1,
    headerText: headerText,
    footerText: footerText,
    showPageNumbers: pageNumbers,
    logoCandidates: logos,
    losses: losses,
  );
}

/// De titel uit `docProps/core.xml` (`dc:title`), of `null` als die leeg is.
String? _packageTitle(_DocxContext ctx) {
  final doc = ctx.readXml('docProps/core.xml');
  if (doc == null) return null;
  final title = _findLocal(doc, 'title')?.innerText.trim();
  return title == null || title.isEmpty ? null : title;
}

void _addLogos(
  List<DocumentLogoCandidate> found,
  List<DocumentLogoCandidate> into,
  Set<String> seen,
) {
  for (final logo in found) {
    if (seen.add('${logo.sha256}:${logo.position}')) into.add(logo);
  }
}

/// Een subkop met een andere kleur dan Heading 1 komt niet mee: het profiel
/// kent één kopkleur. Eén melding per afwijkende kleur, niet per niveau.
void _noteOtherHeadingColors(
  _DocxFontResolver fonts,
  String? headingColor,
  List<DocumentStyleLoss> losses,
) {
  final noted = <String>{};
  for (var level = 2; level <= 6; level++) {
    final style = fonts.headingStyle(level);
    if (style == null) continue;
    final color = fonts.styleColor(style);
    if (color == null || color == headingColor || !noted.add(color)) continue;
    losses.add(
      DocumentStyleLoss(
        DocumentStyleLossKind.perLevelHeadingColor,
        detail: '$level:$color',
      ),
    );
  }
}

// --- Thema ---------------------------------------------------------------------

class _DocxTheme {
  const _DocxTheme({this.majorFont, this.minorFont, this.accent1});

  final String? majorFont;
  final String? minorFont;
  final String? accent1;

  static _DocxTheme? load(_DocxContext ctx) {
    final path =
        ctx.partPathForRelationshipType('theme') ?? 'word/theme/theme1.xml';
    final doc = ctx.readXml(path);
    if (doc == null) return null;
    String? typeface(String scheme) {
      final font = _findLocal(doc, scheme);
      final latin = font == null ? null : _child(font, 'latin');
      return _cleanFontName(latin == null ? null : _attr(latin, 'typeface'));
    }

    return _DocxTheme(
      majorFont: typeface('majorFont'),
      minorFont: typeface('minorFont'),
      accent1: _themeColor(doc, 'accent1'),
    );
  }

  static String? _themeColor(XmlDocument doc, String name) {
    final el = _findLocal(doc, name);
    if (el == null) return null;
    final srgb = _child(el, 'srgbClr');
    if (srgb != null) return _hexColor(_attr(srgb, 'val'));
    final sys = _child(el, 'sysClr');
    if (sys != null) return _hexColor(_attr(sys, 'lastClr'));
    return null;
  }
}

/// `#RRGGBB` uit een OOXML-kleurwaarde, of `null` voor `auto` en rommel.
String? _hexColor(String? raw) {
  if (raw == null) return null;
  final v = raw.trim().toUpperCase();
  if (!RegExp(r'^[0-9A-F]{6}$').hasMatch(v)) return null;
  return '#$v';
}

/// Een lettertypenaam zoals Word hem schrijft, of `null` als hij leeg is of
/// alleen een thema-tijdelijke aanduiding (`+mj-lt`) bevat.
String? _cleanFontName(String? raw) {
  if (raw == null) return null;
  final name = raw.trim();
  if (name.isEmpty || name.startsWith('+')) return null;
  return name;
}

// --- Letters en kleuren uit styles.xml ---------------------------------------

class _DocxFontResolver {
  _DocxFontResolver(this.ctx, this.styles, this.theme);

  final _DocxContext ctx;
  final XmlDocument? styles;
  final _DocxTheme? theme;

  /// De stijl met kopniveau [level], via dezelfde herkenning als de body.
  XmlElement? headingStyle(int level) {
    if (styles == null) return null;
    for (final style in _descendants(styles!, 'style')) {
      final id = _attr(style, 'styleId');
      if (id != null && ctx.headingLevel(id) == level) return style;
    }
    return null;
  }

  /// De standaardalinea-stijl (`w:default="1"`), waar `Normal` meestal is.
  XmlElement? _defaultParagraphStyle() {
    if (styles == null) return null;
    for (final style in _descendants(styles!, 'style')) {
      if (_attr(style, 'type') == 'paragraph' &&
          (_attr(style, 'default') == '1' ||
              _attr(style, 'default') == 'true')) {
        return style;
      }
    }
    return null;
  }

  XmlElement? _styleById(String id) {
    if (styles == null) return null;
    for (final style in _descendants(styles!, 'style')) {
      if (_attr(style, 'styleId') == id) return style;
    }
    return null;
  }

  /// De letter van de lopende tekst: de standaardalinea-stijl, anders
  /// `docDefaults`, anders de minor-letter van het thema.
  String? bodyFont() {
    final normal = _defaultParagraphStyle();
    return (normal == null ? null : styleFont(normal)) ??
        _docDefaultFont() ??
        theme?.minorFont;
  }

  String? bodyColor() {
    final normal = _defaultParagraphStyle();
    return (normal == null ? null : styleColor(normal)) ?? _docDefaultColor();
  }

  /// De letter van [style], de `basedOn`-keten omhoog tot er een staat.
  String? styleFont(XmlElement style) {
    for (final s in _chain(style)) {
      final rPr = _child(s, 'rPr');
      final font = rPr == null ? null : _runFont(_child(rPr, 'rFonts'));
      if (font != null) return font;
    }
    return null;
  }

  String? styleColor(XmlElement style) {
    for (final s in _chain(style)) {
      final rPr = _child(s, 'rPr');
      final color = rPr == null ? null : _hexColor(_val(_child(rPr, 'color')));
      if (color != null) return color;
    }
    return null;
  }

  /// [style] gevolgd door zijn `basedOn`-voorouders; begrensd tegen een lus.
  Iterable<XmlElement> _chain(XmlElement style) sync* {
    var current = style;
    for (var hop = 0; hop < 8; hop++) {
      yield current;
      final parentId = _val(_child(current, 'basedOn'));
      final parent = parentId == null ? null : _styleById(parentId);
      if (parent == null || identical(parent, current)) return;
      current = parent;
    }
  }

  String? _docDefaultFont() {
    final defaults = styles == null ? null : _findLocal(styles!, 'rPrDefault');
    final rPr = defaults == null ? null : _child(defaults, 'rPr');
    return rPr == null ? null : _runFont(_child(rPr, 'rFonts'));
  }

  String? _docDefaultColor() {
    final defaults = styles == null ? null : _findLocal(styles!, 'rPrDefault');
    final rPr = defaults == null ? null : _child(defaults, 'rPr');
    return rPr == null ? null : _hexColor(_val(_child(rPr, 'color')));
  }

  /// De letter uit een `w:rFonts`: een naam (`w:ascii`) wint, anders de
  /// thema-verwijzing (`w:asciiTheme="majorHAnsi"` → de major-letter).
  String? _runFont(XmlElement? rFonts) {
    if (rFonts == null) return null;
    final named =
        _cleanFontName(_attr(rFonts, 'ascii')) ??
        _cleanFontName(_attr(rFonts, 'hAnsi'));
    if (named != null) return named;
    final themed = _attr(rFonts, 'asciiTheme') ?? _attr(rFonts, 'hAnsiTheme');
    if (themed == null) return null;
    if (themed.startsWith('major')) return theme?.majorFont;
    if (themed.startsWith('minor')) return theme?.minorFont;
    return null;
  }
}

// --- Secties: welke kop- en voettekstdelen op elke bladzijde staan -----------

class _DocxSections {
  const _DocxSections({
    required this.defaultHeaders,
    required this.defaultFooters,
    required this.titlePageParts,
    required this.pageWidthEmu,
    required this.pageHeightEmu,
    required this.leftMarginEmu,
    required this.estimatedPages,
  });

  /// Archiefpaden (`word/header2.xml`) van de `default`-koptekstdelen.
  final List<String> defaultHeaders;
  final List<String> defaultFooters;

  /// De `first`-delen van secties met `w:titlePg`: alleen het titelblad.
  final List<String> titlePageParts;
  final double pageWidthEmu;
  final double pageHeightEmu;
  final double leftMarginEmu;

  /// Bladzijden die zeker bestaan: harde pagina-einden plus één. De
  /// werkelijke telling ligt hoger; dit is de ondergrens die de body-route
  /// nodig heeft om "op elke bladzijde" te toetsen.
  final int estimatedPages;

  static _DocxSections read(_DocxContext ctx) {
    final doc = ctx.readXml('word/document.xml');
    final headers = <String>[];
    final footers = <String>[];
    final titleParts = <String>[];
    var width = _defaultPageWidthEmu;
    var height = _defaultPageHeightEmu;
    var leftMargin = 0.0;
    var pages = 1;
    if (doc == null) {
      return _DocxSections(
        defaultHeaders: headers,
        defaultFooters: footers,
        titlePageParts: titleParts,
        pageWidthEmu: width,
        pageHeightEmu: height,
        leftMarginEmu: leftMargin,
        estimatedPages: pages,
      );
    }
    final sectPrs = _descendants(doc, 'sectPr').toList();
    // Elke alinea-sectPr sluit een sectie af en begint dus een bladzijde.
    pages += sectPrs.length > 1 ? sectPrs.length - 1 : 0;
    for (final br in _descendants(doc, 'br')) {
      if (_attr(br, 'type') == 'page') pages++;
    }
    pages += _descendants(doc, 'pageBreakBefore').length;
    for (final sectPr in sectPrs) {
      final titlePg = _child(sectPr, 'titlePg') != null;
      for (final ref in sectPr.children.whereType<XmlElement>()) {
        final local = ref.name.local;
        if (local != 'headerReference' && local != 'footerReference') continue;
        final rid = _attr(ref, 'id');
        final target = rid == null ? null : ctx.relationship(rid);
        final path = target == null ? null : _resolveWordPath(target);
        if (path == null) continue;
        switch (_attr(ref, 'type')) {
          case 'default':
            (local == 'headerReference' ? headers : footers).add(path);
          case 'first':
            if (titlePg) titleParts.add(path);
          default:
            break;
        }
      }
      final pgSz = _child(sectPr, 'pgSz');
      if (pgSz != null) {
        width = _twipsToEmu(_attr(pgSz, 'w')) ?? width;
        height = _twipsToEmu(_attr(pgSz, 'h')) ?? height;
      }
      final pgMar = _child(sectPr, 'pgMar');
      if (pgMar != null) {
        leftMargin = _twipsToEmu(_attr(pgMar, 'left')) ?? leftMargin;
      }
    }
    return _DocxSections(
      defaultHeaders: headers.toSet().toList(),
      defaultFooters: footers.toSet().toList(),
      titlePageParts: titleParts.toSet().toList(),
      pageWidthEmu: width,
      pageHeightEmu: height,
      leftMarginEmu: leftMargin,
      estimatedPages: pages,
    );
  }
}

double? _twipsToEmu(String? twips) {
  final n = double.tryParse(twips ?? '');
  return n == null ? null : n * _emuPerTwip;
}

/// Een relatiedoel (`header2.xml`, `media/image1.png`, `/word/x.xml`) naar
/// een archiefpad onder `word/`, of `null` voor een doel dat het pakket wil
/// verlaten: `..` of een schema (`http:`, `file:`) — dezelfde grens als
/// `imagePartPath` voor de beelden in de tekst.
String? _resolveWordPath(String target) {
  if (target.contains(':') || target.contains('..')) return null;
  final path = target.startsWith('/')
      ? target.replaceFirst(RegExp('^/+'), '')
      : 'word/$target';
  return path.isEmpty || path == 'word/' ? null : path;
}

// --- Kop- en voettekst lezen ---------------------------------------------------

class _ChromePartRead {
  const _ChromePartRead({
    required this.text,
    required this.hasPageNumber,
    required this.logos,
    required this.vectorOnly,
  });

  final String? text;
  final bool hasPageNumber;
  final List<DocumentLogoCandidate> logos;

  /// Beelden zonder rasterterugval (alleen SVG) — die kan het profiel niet
  /// dragen.
  final int vectorOnly;
}

/// Leest één kop- of voettekstdeel: de tekst zonder velden en tekstkaders,
/// of er een paginanummerveld in staat, en de beelden erin als logokandidaat.
_ChromePartRead _readChromePart(
  _DocxContext ctx,
  String partPath,
  _DocxSections sections, {
  required bool isHeader,
}) {
  final doc = ctx.readXml(partPath);
  if (doc == null) {
    return const _ChromePartRead(
      text: null,
      hasPageNumber: false,
      logos: [],
      vectorOnly: 0,
    );
  }
  final root = doc.rootElement;
  final text = _chromeText(ctx, root);
  final hasPageNumber = _hasPageNumberField(root);
  final logos = <DocumentLogoCandidate>[];
  var vectorOnly = 0;
  for (final drawing in _descendants(root, 'drawing')) {
    if (_insideFallback(drawing)) continue;
    final read = _readDrawing(
      ctx,
      drawing,
      partPath,
      sections,
      edgeDefault: isHeader ? DocumentLogoEdge.top : DocumentLogoEdge.bottom,
      origin: isHeader ? DocumentLogoOrigin.header : DocumentLogoOrigin.footer,
    );
    if (read == null) {
      if (_hasAnyImage(drawing)) vectorOnly++;
      continue;
    }
    logos.add(read);
  }
  return _ChromePartRead(
    text: text,
    hasPageNumber: hasPageNumber,
    logos: logos,
    vectorOnly: vectorOnly,
  );
}

/// Of de tekening überhaupt een beeld draagt (raster óf vector). Een tekening
/// mét beeld die geen kandidaat oplevert is er dus een zonder rasterterugval.
bool _hasAnyImage(XmlElement drawing) => drawing.descendants
    .whereType<XmlElement>()
    .any((e) => e.name.local == 'blip' || e.name.local == 'svgBlip');

/// Of [el] in een `mc:Fallback` staat: de tweede, gelijkwaardige uitvoering
/// van dezelfde inhoud, die anders dubbel telt.
bool _insideFallback(XmlNode el) {
  for (var p = el.parent; p != null; p = p.parent) {
    if (p is XmlElement && p.name.local == 'Fallback') return true;
  }
  return false;
}

/// Of [el] in een tekstkader staat: een los geplaatst object (vaak een
/// classificatielabel), geen deel van de lopende kop- of voettekst.
bool _insideTextBox(XmlNode el) {
  for (var p = el.parent; p != null; p = p.parent) {
    if (p is XmlElement && p.name.local == 'txbxContent') return true;
  }
  return false;
}

/// De platte tekst van een kop- of voettekst: alinea's zonder tekstkaders,
/// zonder veldwaarden (het paginanummer zelf), tabs als spatie.
String? _chromeText(_DocxContext ctx, XmlElement root) {
  final lines = <String>[];
  for (final p in _descendants(root, 'p')) {
    if (_insideFallback(p) || _insideTextBox(p)) continue;
    final buf = StringBuffer();
    var inField = false;
    // Een complex veld loopt van `fldChar begin` tot `fldChar end`; wat
    // ertussen staat (de instructie én de laatst berekende waarde, zoals
    // het paginanummer "2") hoort niet in de tekst. Een `fldSimple` draagt
    // zijn waarde als kinderen; die worden apart overgeslagen.
    for (final node in p.descendants) {
      if (node is! XmlElement) continue;
      switch (node.name.local) {
        case 'fldChar':
          final type = _attr(node, 'fldCharType');
          if (type == 'begin') inField = true;
          if (type == 'end') inField = false;
        case 't':
          // Een tekstkader in deze alinea is zelf ook een nazaat; zijn
          // tekst hoort bij het kader, niet bij de kop- of voettekst.
          if (inField ||
              _insideFieldSimple(node) ||
              _insideTextBox(node) ||
              _insideFallback(node)) {
            break;
          }
          buf.write(node.innerText);
        case 'tab':
          buf.write(' ');
        default:
          break;
      }
    }
    final line = buf.toString().replaceAll(RegExp(r'\s+'), ' ').trim();
    if (line.isNotEmpty) lines.add(line);
  }
  if (lines.isEmpty) return null;
  return lines.join('\n');
}

bool _insideFieldSimple(XmlNode el) {
  for (var p = el.parent; p != null; p = p.parent) {
    if (p is XmlElement && p.name.local == 'fldSimple') return true;
  }
  return false;
}

/// Of het deel een `PAGE`-veld draagt, simpel (`w:fldSimple w:instr`) of
/// complex (`w:instrText`).
bool _hasPageNumberField(XmlElement root) {
  bool isPage(String? instr) =>
      instr != null && RegExp(r'^\s*PAGE\b').hasMatch(instr);
  for (final f in _descendants(root, 'fldSimple')) {
    if (!_insideFallback(f) && isPage(_attr(f, 'instr'))) return true;
  }
  for (final f in _descendants(root, 'instrText')) {
    if (!_insideFallback(f) && isPage(f.innerText)) return true;
  }
  return false;
}

// --- Eén tekening lezen ------------------------------------------------------

/// Leest een `w:drawing` als logokandidaat, of `null` wanneer er geen
/// rasterbeeld in zit of het beeld te groot is om een logo te zijn.
DocumentLogoCandidate? _readDrawing(
  _DocxContext ctx,
  XmlElement drawing,
  String partPath,
  _DocxSections sections, {
  required DocumentLogoEdge edgeDefault,
  required DocumentLogoOrigin origin,
  int? occurrences,
}) {
  // Alleen `a:blip`, niet `asvg:svgBlip`: Word schrijft naast een SVG altijd
  // een rasterterugval, en dat is wat het profiel kan dragen.
  XmlElement? blip;
  for (final el in _descendants(drawing, 'blip')) {
    if (el.name.local == 'blip') {
      blip = el;
      break;
    }
  }
  if (blip == null) return null;
  final rid = _attr(blip, 'embed');
  final target = rid == null ? null : ctx.relationshipOf(partPath, rid);
  final mediaPath = target == null ? null : _resolveWordPath(target);
  if (mediaPath == null) return null;
  final bytes = ctx.readPartBytes(mediaPath);
  if (bytes == null || bytes.length > _maxLogoBytes) return null;
  final mime = imageMimeFromBytes(bytes);
  if (mime == null) return null;
  // Het profiel gebruikte historisch `jpeg`; houd dat opgeslagen contract
  // stabiel terwijl de magic-byteherkenning centraal staat.
  final ext = mime == 'image/jpeg' ? 'jpeg' : extensionForImageMime(mime);

  final extent = _findLocal(drawing, 'extent');
  final cx = double.tryParse(extent == null ? '' : _attr(extent, 'cx') ?? '');
  final cy = double.tryParse(extent == null ? '' : _attr(extent, 'cy') ?? '');
  if (cx == null || cy == null || cx <= 0 || cy <= 0) return null;
  // Een beeld breder dan het halve blad is illustratie of merkstrook, geen
  // hoeklogo — dezelfde grens als bij de presentatie-import.
  if (cx > sections.pageWidthEmu * 0.5) return null;

  final anchor = _findLocal(drawing, 'anchor');
  final placement = anchor == null
      ? _inlinePlacement(drawing)
      : _anchorPlacement(anchor, cx, sections);
  final edge = anchor == null
      ? edgeDefault
      : _anchorEdge(anchor, cy, sections) ?? edgeDefault;

  return DocumentLogoCandidate(
    bytes: Uint8List.fromList(bytes),
    ext: ext,
    sha256: sha256Hex(bytes),
    edge: edge,
    side: placement.side,
    centred: placement.centred,
    widthMm: cx / _emuPerMm,
    origin: origin,
    name: mediaPath.split('/').last,
    occurrences: occurrences,
  );
}

/// Links of rechts, plus of het beeld eigenlijk gecentreerd stond — dat kent
/// het profiel niet, dus het wordt links, met een melding.
typedef _Placement = ({DocumentLogoSide side, bool centred});

/// De kant van een inline beeld volgt de uitlijning van zijn alinea.
_Placement _inlinePlacement(XmlElement drawing) {
  XmlElement? paragraph;
  for (var p = drawing.parent; p != null; p = p.parent) {
    if (p is XmlElement && p.name.local == 'p') {
      paragraph = p;
      break;
    }
  }
  final pPr = paragraph == null ? null : _child(paragraph, 'pPr');
  final jc = pPr == null ? null : _val(_child(pPr, 'jc'));
  return switch (jc) {
    'right' || 'end' => (side: DocumentLogoSide.right, centred: false),
    'center' => (side: DocumentLogoSide.left, centred: true),
    _ => (side: DocumentLogoSide.left, centred: false),
  };
}

/// De kant van een verankerd beeld: de uitlijning als die er is, anders het
/// midden van het beeld ten opzichte van het midden van het blad. Een beeld
/// waarvan het midden binnen een tiende van het bladmidden valt, staat
/// gecentreerd.
_Placement _anchorPlacement(
  XmlElement anchor,
  double cx,
  _DocxSections sections,
) {
  const left = (side: DocumentLogoSide.left, centred: false);
  final posH = _child(anchor, 'positionH');
  if (posH == null) return left;
  final align = _child(posH, 'align')?.innerText.trim();
  if (align != null) {
    return switch (align) {
      'right' || 'outside' => (side: DocumentLogoSide.right, centred: false),
      'center' => (side: DocumentLogoSide.left, centred: true),
      _ => left,
    };
  }
  final offset = double.tryParse(
    _child(posH, 'posOffset')?.innerText.trim() ?? '',
  );
  if (offset == null) return left;
  final relative = _attr(posH, 'relativeFrom');
  final origin = relative == 'page' ? 0.0 : sections.leftMarginEmu;
  final centre = origin + offset + cx / 2;
  final half = sections.pageWidthEmu / 2;
  if ((centre - half).abs() < sections.pageWidthEmu * 0.1) {
    return (side: DocumentLogoSide.left, centred: true);
  }
  return centre < half ? left : (side: DocumentLogoSide.right, centred: false);
}

/// De rand van een verankerd beeld, alleen wanneer het ten opzichte van de
/// bladzijde staat; anders beslist het deel (kop of voet).
DocumentLogoEdge? _anchorEdge(
  XmlElement anchor,
  double cy,
  _DocxSections sections,
) {
  final posV = _child(anchor, 'positionV');
  if (posV == null || _attr(posV, 'relativeFrom') != 'page') return null;
  final align = _child(posV, 'align')?.innerText.trim();
  if (align != null) {
    return switch (align) {
      'bottom' || 'outside' => DocumentLogoEdge.bottom,
      _ => DocumentLogoEdge.top,
    };
  }
  final offset = double.tryParse(
    _child(posV, 'posOffset')?.innerText.trim() ?? '',
  );
  if (offset == null) return null;
  return offset + cy / 2 < sections.pageHeightEmu / 2
      ? DocumentLogoEdge.top
      : DocumentLogoEdge.bottom;
}

// --- De tweede route: een beeld dat per bladzijde in de body herhaald is -----

/// Beelden die met de hand op elke bladzijde geplakt zijn: verankerd ten
/// opzichte van de bladzijde, inhoudelijk identiek, op dezelfde plek, en
/// minstens zo vaak als er bladzijden zijn (het titelblad mag ontbreken).
List<DocumentLogoCandidate> _repeatedBodyImages(
  _DocxContext ctx,
  _DocxSections sections,
) {
  final doc = ctx.readXml('word/document.xml');
  if (doc == null) return const [];
  final groups = <String, List<DocumentLogoCandidate>>{};
  for (final drawing in _descendants(doc, 'drawing')) {
    if (_insideFallback(drawing) || _findLocal(drawing, 'anchor') == null) {
      continue;
    }
    final read = _readDrawing(
      ctx,
      drawing,
      'word/document.xml',
      sections,
      edgeDefault: DocumentLogoEdge.top,
      origin: DocumentLogoOrigin.body,
    );
    if (read == null) continue;
    groups.putIfAbsent('${read.sha256}:${read.position}', () => []).add(read);
  }
  final result = <DocumentLogoCandidate>[];
  final needed = sections.estimatedPages - 1;
  for (final group in groups.values) {
    final count = group.length;
    if (count < 2 || count < needed) continue;
    final first = group.first;
    result.add(
      DocumentLogoCandidate(
        bytes: first.bytes,
        ext: first.ext,
        sha256: first.sha256,
        edge: first.edge,
        side: first.side,
        widthMm: first.widthMm,
        origin: DocumentLogoOrigin.body,
        name: first.name,
        occurrences: count,
      ),
    );
  }
  return result;
}
