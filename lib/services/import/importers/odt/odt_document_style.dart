// De huisstijl uit een `.odt`: letters, kleuren, kop- en voettekst en het
// beeld dat op elke bladzijde staat (#2119) — het ODF-spiegelbeeld van
// `docx_document_style.dart`.
//
// Waar LibreOffice het bewaart, en dus waar dit leest (alles in `styles.xml`):
//
// - `office:font-face-decls` — de lettertypenamen; een stijl noemt een
//   `style:font-name` die hier naar een `svg:font-family` verwijst.
// - `office:styles` — `style:default-style` (familie `paragraph`), `Standard`
//   en de kopstijlen (`style:default-outline-level="1"`), met een
//   `style:parent-style-name`-keten. Een thema met accentkleuren kent ODF niet;
//   het accent blijft dus leeg.
// - `office:master-styles` — per `style:master-page` een `style:header` en
//   `style:footer`. Een master die een `style:next-style-name` noemt is een
//   éénbladsmaster (het titelblad); de rest geldt voor elke bladzijde.

part of 'odt_document_importer.dart';

/// Dezelfde grens als `FileService.maxStyleProfileLogoBytes` (8 MiB); hier
/// als eigen constante omdat deze laag geen `dart:io` mag importeren.
const _maxLogoBytes = 8 * 1024 * 1024;

/// A4, de terugval wanneer de paginaopmaak geen maat draagt.
const _defaultPageWidthMm = 210.0;
const _defaultPageHeightMm = 297.0;

SourceDocumentStyle _extractOdtStyle(_OdtContext ctx) {
  final styles = ctx.readXml('styles.xml');
  if (styles == null) return SourceDocumentStyle.empty;
  final resolver = _OdtStyleResolver(styles, ctx.readXml('content.xml'));
  final losses = <DocumentStyleLoss>[];

  final bodyStyle = resolver.paragraphStyle('Standard');
  final bodyFont =
      (bodyStyle == null ? null : resolver.fontOf(bodyStyle)) ??
      resolver.defaultFont();
  final textColor =
      (bodyStyle == null ? null : resolver.colorOf(bodyStyle)) ??
      resolver.defaultColor();
  final headingStyle = resolver.headingStyle(1);
  final headingFont = headingStyle == null
      ? null
      : resolver.fontOf(headingStyle) ?? resolver.defaultFont();
  final headingColor = headingStyle == null
      ? null
      : resolver.colorOf(headingStyle);
  _noteOtherOdtHeadingColors(resolver, headingColor, losses);

  final logos = <DocumentLogoCandidate>[];
  final seen = <String>{};
  String? headerText;
  String? footerText;
  var pageNumbers = false;
  var vectorOnly = 0;
  var titlePageImages = 0;
  for (final master in descendantsLocal(styles, 'master-page')) {
    final onePage = _attr(master, 'next-style-name') != null;
    final page = resolver.pageOf(master);
    for (final isHeader in const [true, false]) {
      final part = childLocal(master, isHeader ? 'header' : 'footer');
      if (part == null) continue;
      final read = _readOdtChrome(
        ctx,
        resolver,
        part,
        page,
        isHeader: isHeader,
      );
      if (onePage) {
        titlePageImages += read.logos.length + read.vectorOnly;
        continue;
      }
      if (isHeader) {
        headerText ??= read.text;
      } else {
        footerText ??= read.text;
      }
      pageNumbers = pageNumbers || read.hasPageNumber;
      vectorOnly += read.vectorOnly;
      for (final logo in read.logos) {
        if (seen.add('${logo.sha256}:${logo.position}')) logos.add(logo);
      }
    }
  }
  for (final logo in _repeatedOdtBodyImages(ctx, resolver)) {
    if (seen.add('${logo.sha256}:${logo.position}')) logos.add(logo);
  }
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
    bodyFontFamily: bodyFont,
    headingFontFamily: headingFont,
    textColor: textColor,
    headingColor: headingColor,
    headerText: headerText,
    footerText: footerText,
    showPageNumbers: pageNumbers,
    logoCandidates: logos,
    losses: losses,
  );
}

void _noteOtherOdtHeadingColors(
  _OdtStyleResolver resolver,
  String? headingColor,
  List<DocumentStyleLoss> losses,
) {
  final noted = <String>{};
  for (var level = 2; level <= 6; level++) {
    final style = resolver.headingStyle(level);
    if (style == null) continue;
    final color = resolver.colorOf(style);
    if (color == null || color == headingColor || !noted.add(color)) continue;
    losses.add(
      DocumentStyleLoss(
        DocumentStyleLossKind.perLevelHeadingColor,
        detail: '$level:$color',
      ),
    );
  }
}

/// De maat van een bladzijde, in millimeter.
typedef _OdtPage = ({double widthMm, double heightMm});

class _OdtStyleResolver {
  _OdtStyleResolver(this.styles, this.content) {
    for (final face in descendantsLocal(styles, 'font-face')) {
      final name = _attr(face, 'name');
      final family = _attr(face, 'font-family');
      if (name != null && family != null) {
        _fontFaces[name] = family.replaceAll(RegExp('["\']'), '').trim();
      }
    }
    for (final doc in [styles, ?content]) {
      for (final style in descendantsLocal(doc, 'style')) {
        final name = _attr(style, 'name');
        if (name != null) _styles.putIfAbsent(name, () => style);
      }
    }
  }

  final XmlDocument styles;
  final XmlDocument? content;
  final _fontFaces = <String, String>{};
  final _styles = <String, XmlElement>{};

  XmlElement? paragraphStyle(String name) {
    final style = _styles[name];
    return style != null && _attr(style, 'family') == 'paragraph'
        ? style
        : null;
  }

  /// De kopstijl van [level]: op `default-outline-level`, anders op de
  /// standaardnaam (`Heading_20_1` toont als `Heading 1`).
  XmlElement? headingStyle(int level) {
    for (final style in _styles.values) {
      if (_attr(style, 'family') != 'paragraph') continue;
      if (_attr(style, 'default-outline-level') == '$level') return style;
    }
    return paragraphStyle('Heading_20_$level') ??
        _byDisplayName('Heading $level');
  }

  XmlElement? _byDisplayName(String displayName) {
    for (final style in _styles.values) {
      if (_attr(style, 'display-name') == displayName) return style;
    }
    return null;
  }

  /// [style] gevolgd door zijn `parent-style-name`-voorouders.
  Iterable<XmlElement> _chain(XmlElement style) sync* {
    var current = style;
    for (var hop = 0; hop < 8; hop++) {
      yield current;
      final parentName = _attr(current, 'parent-style-name');
      final parent = parentName == null ? null : _styles[parentName];
      if (parent == null || identical(parent, current)) return;
      current = parent;
    }
  }

  String? fontOf(XmlElement style) {
    for (final s in _chain(style)) {
      final font = _fontFromProps(childLocal(s, 'text-properties'));
      if (font != null) return font;
    }
    return null;
  }

  String? colorOf(XmlElement style) {
    for (final s in _chain(style)) {
      final props = childLocal(s, 'text-properties');
      final color = props == null ? null : _odfColor(_attr(props, 'color'));
      if (color != null) return color;
    }
    return null;
  }

  /// De `style:default-style` van de alineafamilie.
  XmlElement? _defaultParagraphStyle() {
    for (final style in descendantsLocal(styles, 'default-style')) {
      if (_attr(style, 'family') == 'paragraph') return style;
    }
    return null;
  }

  String? defaultFont() {
    final def = _defaultParagraphStyle();
    return def == null
        ? null
        : _fontFromProps(childLocal(def, 'text-properties'));
  }

  String? defaultColor() {
    final def = _defaultParagraphStyle();
    final props = def == null ? null : childLocal(def, 'text-properties');
    return props == null ? null : _odfColor(_attr(props, 'color'));
  }

  String? _fontFromProps(XmlElement? props) {
    if (props == null) return null;
    final name = _attr(props, 'font-name');
    if (name != null) {
      final family = _fontFaces[name] ?? name;
      return family.trim().isEmpty ? null : family.trim();
    }
    final family = _attr(props, 'font-family');
    if (family == null) return null;
    final clean = family.replaceAll(RegExp('["\']'), '').trim();
    return clean.isEmpty ? null : clean;
  }

  /// De uitlijning van de alinea met stijl [styleName], de keten omhoog.
  String? textAlign(String? styleName) {
    if (styleName == null) return null;
    final style = _styles[styleName];
    if (style == null) return null;
    for (final s in _chain(style)) {
      final props = childLocal(s, 'paragraph-properties');
      final align = props == null ? null : _attr(props, 'text-align');
      if (align != null) return align;
    }
    return null;
  }

  /// De horizontale positie van een kader (`style:horizontal-pos`) uit zijn
  /// grafische stijl.
  String? horizontalPos(String? styleName) {
    if (styleName == null) return null;
    final style = _styles[styleName];
    final props = style == null
        ? null
        : childLocal(style, 'graphic-properties');
    return props == null ? null : _attr(props, 'horizontal-pos');
  }

  /// De bladmaat van [master], via zijn `page-layout`.
  _OdtPage pageOf(XmlElement master) {
    final layoutName = _attr(master, 'page-layout-name');
    for (final layout in descendantsLocal(styles, 'page-layout')) {
      if (_attr(layout, 'name') != layoutName) continue;
      final props = childLocal(layout, 'page-layout-properties');
      if (props == null) break;
      return (
        widthMm:
            _odfLengthMm(_attr(props, 'page-width')) ?? _defaultPageWidthMm,
        heightMm:
            _odfLengthMm(_attr(props, 'page-height')) ?? _defaultPageHeightMm,
      );
    }
    return (widthMm: _defaultPageWidthMm, heightMm: _defaultPageHeightMm);
  }
}

/// `#RRGGBB` uit een ODF-kleur (`#00464f`), of `null`.
String? _odfColor(String? raw) {
  if (raw == null) return null;
  final v = raw.trim().toUpperCase();
  if (!RegExp(r'^#[0-9A-F]{6}$').hasMatch(v)) return null;
  return v;
}

/// Een ODF-lengte (`2.5cm`, `12mm`, `1in`, `36pt`) in millimeter, of `null`.
double? _odfLengthMm(String? raw) {
  if (raw == null) return null;
  final m = RegExp(r'^\s*(-?[\d.]+)\s*(cm|mm|in|pt|pc)?\s*$').firstMatch(raw);
  if (m == null) return null;
  final n = double.tryParse(m.group(1)!);
  if (n == null) return null;
  return switch (m.group(2)) {
    'cm' => n * 10,
    'in' => n * 25.4,
    'pt' => n * 25.4 / 72,
    'pc' => n * 25.4 / 6,
    _ => n,
  };
}

class _OdtChromeRead {
  const _OdtChromeRead({
    required this.text,
    required this.hasPageNumber,
    required this.logos,
    required this.vectorOnly,
  });

  final String? text;
  final bool hasPageNumber;
  final List<DocumentLogoCandidate> logos;
  final int vectorOnly;
}

/// Leest een `style:header` of `style:footer`.
_OdtChromeRead _readOdtChrome(
  _OdtContext ctx,
  _OdtStyleResolver resolver,
  XmlElement part,
  _OdtPage page, {
  required bool isHeader,
}) {
  final lines = <String>[];
  var hasPageNumber = false;
  for (final p in descendantsLocal(part, 'p')) {
    if (_insideFrame(p)) continue;
    final buf = StringBuffer();
    for (final node in p.descendants) {
      if (node is XmlText) {
        if (!_insideFrame(node) && !_insideField(node)) buf.write(node.value);
      } else if (node is XmlElement) {
        if (node.name.local == 'page-number') hasPageNumber = true;
        if (node.name.local == 'tab' || node.name.local == 's') buf.write(' ');
      }
    }
    final line = buf.toString().replaceAll(RegExp(r'\s+'), ' ').trim();
    if (line.isNotEmpty) lines.add(line);
  }

  final logos = <DocumentLogoCandidate>[];
  var vectorOnly = 0;
  for (final frame in descendantsLocal(part, 'frame')) {
    final read = _readOdtFrame(
      ctx,
      resolver,
      frame,
      page,
      edgeDefault: isHeader ? DocumentLogoEdge.top : DocumentLogoEdge.bottom,
      origin: isHeader ? DocumentLogoOrigin.header : DocumentLogoOrigin.footer,
    );
    if (read == null) {
      if (descendantsLocal(frame, 'image').isNotEmpty) vectorOnly++;
      continue;
    }
    logos.add(read);
  }
  return _OdtChromeRead(
    text: lines.isEmpty ? null : lines.join('\n'),
    hasPageNumber: hasPageNumber,
    logos: logos,
    vectorOnly: vectorOnly,
  );
}

bool _insideFrame(XmlNode el) {
  for (var p = el.parent; p != null; p = p.parent) {
    if (p is XmlElement && p.name.local == 'frame') return true;
  }
  return false;
}

/// Velden waarvan de laatst berekende waarde in de tekst staat (het
/// paginanummer "2", het aantal bladzijden) horen niet in de voettekst.
bool _insideField(XmlNode el) {
  for (var p = el.parent; p != null; p = p.parent) {
    if (p is XmlElement &&
        (p.name.local == 'page-number' || p.name.local == 'page-count')) {
      return true;
    }
  }
  return false;
}

/// Leest een `draw:frame` als logokandidaat, of `null` zonder rasterbeeld.
DocumentLogoCandidate? _readOdtFrame(
  _OdtContext ctx,
  _OdtStyleResolver resolver,
  XmlElement frame,
  _OdtPage page, {
  required DocumentLogoEdge edgeDefault,
  required DocumentLogoOrigin origin,
  int? occurrences,
}) {
  List<int>? bytes;
  String? ext;
  String? name;
  for (final image in descendantsLocal(frame, 'image')) {
    final href = xlinkHref(image);
    if (href == null) continue;
    final candidate = ctx.readPartBytes(href);
    if (candidate == null || candidate.length > _maxLogoBytes) continue;
    final raster = _rasterExtension(candidate);
    if (raster == null) continue;
    bytes = candidate;
    ext = raster;
    name = href.split('/').last;
    break;
  }
  if (bytes == null || ext == null) return null;

  final widthMm = _odfLengthMm(_attr(frame, 'width'));
  final heightMm = _odfLengthMm(_attr(frame, 'height'));
  if (widthMm == null || heightMm == null || widthMm <= 0 || heightMm <= 0) {
    return null;
  }
  if (widthMm > page.widthMm * 0.5) return null;

  final placement = _odtPlacement(resolver, frame, widthMm, page);
  final edge = _odtEdge(frame, heightMm, page) ?? edgeDefault;

  return DocumentLogoCandidate(
    bytes: Uint8List.fromList(bytes),
    ext: ext,
    sha256: sha256Hex(bytes),
    edge: edge,
    side: placement.side,
    centred: placement.centred,
    widthMm: widthMm,
    origin: origin,
    name: name,
    occurrences: occurrences,
  );
}

typedef _OdtPlacement = ({DocumentLogoSide side, bool centred});

/// Links of rechts: de horizontale positie van het kader als die er is,
/// anders zijn `svg:x` ten opzichte van het blad, anders de uitlijning van
/// de alinea waarin het staat.
_OdtPlacement _odtPlacement(
  _OdtStyleResolver resolver,
  XmlElement frame,
  double widthMm,
  _OdtPage page,
) {
  const left = (side: DocumentLogoSide.left, centred: false);
  const right = (side: DocumentLogoSide.right, centred: false);
  const centre = (side: DocumentLogoSide.left, centred: true);
  final pos = resolver.horizontalPos(_attr(frame, 'style-name'));
  switch (pos) {
    case 'right':
    case 'outside':
      return right;
    case 'center':
      return centre;
    case 'left':
    case 'inside':
      return left;
  }
  final anchor = _attr(frame, 'anchor-type');
  final x = _odfLengthMm(_attr(frame, 'x'));
  if (anchor == 'page' && x != null) {
    final mid = x + widthMm / 2;
    if ((mid - page.widthMm / 2).abs() < page.widthMm * 0.1) return centre;
    return mid < page.widthMm / 2 ? left : right;
  }
  XmlElement? paragraph;
  for (var p = frame.parent; p != null; p = p.parent) {
    if (p is XmlElement && p.name.local == 'p') {
      paragraph = p;
      break;
    }
  }
  final align = paragraph == null
      ? null
      : resolver.textAlign(_attr(paragraph, 'style-name'));
  return switch (align) {
    'end' || 'right' => right,
    'center' => centre,
    _ => left,
  };
}

/// Boven of onder, alleen voor een kader dat aan de bladzijde hangt.
DocumentLogoEdge? _odtEdge(XmlElement frame, double heightMm, _OdtPage page) {
  if (_attr(frame, 'anchor-type') != 'page') return null;
  final y = _odfLengthMm(_attr(frame, 'y'));
  if (y == null) return null;
  return y + heightMm / 2 < page.heightMm / 2
      ? DocumentLogoEdge.top
      : DocumentLogoEdge.bottom;
}

/// De bestandsextensie van een rasterbeeld op zijn magische bytes.
String? _rasterExtension(List<int> b) {
  if (b.length < 12) return null;
  if (b[0] == 0x89 && b[1] == 0x50 && b[2] == 0x4E && b[3] == 0x47) {
    return 'png';
  }
  if (b[0] == 0xFF && b[1] == 0xD8 && b[2] == 0xFF) return 'jpeg';
  if (b[0] == 0x47 && b[1] == 0x49 && b[2] == 0x46) return 'gif';
  if (b[0] == 0x42 && b[1] == 0x4D) return 'bmp';
  if (b[0] == 0x52 &&
      b[1] == 0x49 &&
      b[2] == 0x46 &&
      b[3] == 0x46 &&
      b[8] == 0x57 &&
      b[9] == 0x45 &&
      b[10] == 0x42 &&
      b[11] == 0x50) {
    return 'webp';
  }
  return null;
}

/// Beelden die met de hand op elke bladzijde geplakt zijn: aan de bladzijde
/// verankerd, inhoudelijk identiek, op dezelfde plek, minstens zo vaak als
/// er bladzijden zijn (het titelblad mag ontbreken).
List<DocumentLogoCandidate> _repeatedOdtBodyImages(
  _OdtContext ctx,
  _OdtStyleResolver resolver,
) {
  final content = ctx.readXml('content.xml');
  if (content == null) return const [];
  final text = _findOfficeText(content);
  if (text == null) return const [];
  final master = descendantsLocal(resolver.styles, 'master-page').firstOrNull;
  final page = master == null
      ? (widthMm: _defaultPageWidthMm, heightMm: _defaultPageHeightMm)
      : resolver.pageOf(master);

  var pages = 1 + descendantsLocal(text, 'soft-page-break').length;
  for (final p in text.children.whereType<XmlElement>()) {
    if (_breaksBefore(resolver, _attr(p, 'style-name'))) pages++;
  }

  final groups = <String, List<DocumentLogoCandidate>>{};
  for (final frame in descendantsLocal(text, 'frame')) {
    if (_attr(frame, 'anchor-type') != 'page') continue;
    final read = _readOdtFrame(
      ctx,
      resolver,
      frame,
      page,
      edgeDefault: DocumentLogoEdge.top,
      origin: DocumentLogoOrigin.body,
    );
    if (read == null) continue;
    groups.putIfAbsent('${read.sha256}:${read.position}', () => []).add(read);
  }
  final result = <DocumentLogoCandidate>[];
  final needed = pages - 1;
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

/// Of de alineastijl [styleName] een pagina-einde vóór zich afdwingt.
bool _breaksBefore(_OdtStyleResolver resolver, String? styleName) {
  if (styleName == null) return false;
  final style = resolver._styles[styleName];
  final props = style == null
      ? null
      : childLocal(style, 'paragraph-properties');
  return props != null && _attr(props, 'break-before') == 'page';
}
