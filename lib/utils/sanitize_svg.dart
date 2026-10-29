import 'dart:convert';
import 'dart:typed_data';

import 'package:xml/xml.dart';

import 'log.dart';

/// Strip everything from Mermaid SVG output that the renderer does not read,
/// before display. Returns null when the markup is empty or cannot be parsed.
///
/// Dit is een allow-list, en de lijst is niet geraden: hij is afgelezen van de
/// enige lezer die deze SVG ooit krijgt, `flutter_svg` (zie [_allowedElements]).
/// Daarmee vervalt het bezwaar dat hier stond — dat een allow-list op gevoel de
/// eerste de beste sequentiediagram half zou renderen zonder foutmelding. Wat
/// hier wegvalt, viel bij de renderer óók al weg.
String? sanitizeMermaidSvg(String svg) {
  return _sanitizeSvg(svg, 'sanitizeMermaidSvg');
}

/// Validate and sanitise an SVG selected as a slide or Library image.
///
/// Unlike raster formats, SVG has no useful magic-byte signature: it is XML
/// and may start with whitespace, a BOM or an XML declaration. Parsing the
/// complete, size-bounded document is therefore its content check. The output
/// contains only the root `<svg>` tree, so processing instructions, comments
/// and a possible doctype do not travel into the deck.
Uint8List? sanitizeImportedSvgBytes(List<int> bytes) {
  if (bytes.isEmpty) return null;
  final String source;
  try {
    source = utf8.decode(bytes);
  } on FormatException catch (e) {
    logWarning('sanitizeImportedSvgBytes: SVG is not UTF-8', e);
    return null;
  }
  final safe = _sanitizeSvg(
    source,
    'sanitizeImportedSvgBytes',
    allowExternalUrls: false,
    allowEmbeddedPng: true,
  );
  return safe == null ? null : Uint8List.fromList(utf8.encode(safe));
}

/// Maximum stored size for a custom bullet SVG. Bullet artwork is deliberately
/// small; bounding it also keeps imported style profiles from turning into an
/// unbounded XML parsing input.
const int kMaxCustomBulletSvgChars = 256 * 1024;

/// Sanitise user-supplied SVG artwork used as a bullet marker.
///
/// The result is safe for both `flutter_svg` and the inline data URI used by
/// HTML export. External/data URLs, event handlers, scripts, animation and
/// unsupported elements are removed by the same allow-list as Mermaid output.
String? sanitizeCustomBulletSvg(String svg) {
  if (svg.length > kMaxCustomBulletSvgChars) {
    logWarning('sanitizeCustomBulletSvg: SVG exceeds the size limit');
    return null;
  }
  return _sanitizeSvg(svg, 'sanitizeCustomBulletSvg', allowExternalUrls: false);
}

String? _sanitizeSvg(
  String svg,
  String logName, {
  bool allowExternalUrls = true,
  bool allowEmbeddedPng = false,
}) {
  if (svg.trim().isEmpty || !svg.contains('<svg')) return null;

  final XmlDocument document;
  try {
    document = XmlDocument.parse(svg);
  } catch (e) {
    logWarning('$logName: SVG parse failed', e);
    return null;
  }

  final root = document.rootElement;
  if (root.name.local != 'svg') return null;
  if (root.getAttribute('xmlns') == null) {
    root.setAttribute('xmlns', 'http://www.w3.org/2000/svg');
  }

  final dropped = _Dropped();
  _keepOnlyAllowed(
    root,
    dropped,
    allowExternalUrls: allowExternalUrls,
    allowEmbeddedPng: allowEmbeddedPng,
  );
  if (!dropped.isEmpty) {
    // Geweigerd, niet stil verdwenen. Een allow-list die zwijgt is niet te
    // onderhouden: gaat Mermaid ooit iets uitsturen dat hier niet in staat, dan
    // hoort dat op te vallen en niet te eindigen in een half getekend diagram.
    //
    // Het AANTAL, nooit de namen — de regel uit de kop van `log.dart`. Een
    // elementnaam voelt als structuur en niet als inhoud, maar hij komt uit een
    // document dat de gebruiker heeft geschreven, en een attribuutnaam is in
    // een gemaakt diagram vrij te kiezen. Wie wil weten wát er wegviel, heeft
    // het diagram zelf; het logbestand hoeft er niet nog een kopie van te
    // dragen.
    logWarning(
      '$logName: dropped ${dropped.elements} element(s) and '
      '${dropped.attributes} attribute(s) the renderer does not read',
    );
  }

  // Serialize the SVG root only. Processing instructions and doctypes outside
  // it are not drawing content and may carry stylesheet or entity URLs.
  return root.toXmlString(pretty: false);
}

/// De elementen die `flutter_svg` werkelijk tekent.
///
/// Afgelezen van `vector_graphics_compiler`, de parser achter `flutter_svg`:
/// `_svgElementParsers` (containers en verwijzingen), `_svgPathFuncs` (de
/// vormen), plus `defs` en `stop`, die de parser in hun eigen tak afhandelt.
/// Alles daarbuiten gooit die parser zélf al weg — `_discardSubtree()` — dus
/// hier weghalen kost geen enkele pixel. Dát is wat deze lijst afdwingbaar
/// maakt in plaats van een gok: hij is niet strenger dan de lezer.
///
/// Wat er zo vanzelf uit valt is precies de lijst waar de vorige deny-list
/// achteraan liep: `script`, `style`, `foreignObject`, `iframe`, `object`,
/// `embed`, en de SMIL-animatie-elementen (`set`, `animate`, `animateTransform`,
/// `animateMotion`) waarmee een `attributeName="onload"` een handler installeert
/// die geen enkele attribuutcontrole op de ouder ooit ziet.
const _allowedElements = {
  // Containers en verwijzingen.
  'svg', 'g', 'a', 'defs', 'use', 'symbol', 'mask', 'pattern', 'clipPath',
  'linearGradient', 'radialGradient', 'stop', 'image', 'text', 'tspan',
  // Vormen.
  'circle', 'ellipse', 'line', 'path', 'polygon', 'polyline', 'rect',
};

/// De attributen die diezelfde parser uitleest.
///
/// Ook afgelezen, en wel uit twee plekken: de directe `attribute('…')`-aanroepen
/// (vorm- en verloopgeometrie) en de sleutels waarmee `_createAttributeMap` de
/// presentatie-eigenschappen opzoekt. `style` staat erbij omdat diezelfde
/// functie een `style="fill:red;…"` uit elkaar haalt en de onderdelen in
/// dezelfde map legt — de CSS-dialect-vrees gold het `<style>`-elémént, dat
/// stylesheets en `@import` draagt, en dat staat hierboven niet in de lijst.
///
/// `on…`-handlers, `attributeName` en alles wat Mermaid verder aan opsmuk
/// meestuurt (`class`, `role`, `aria-…`) staan er niet in en verdwijnen dus,
/// zonder dat er iets aan het beeld verandert: de renderer las ze toch niet.
const _allowedAttributes = {
  // Geometrie en verlopen.
  'cx', 'cy', 'd', 'fx', 'fy', 'gradientTransform', 'gradientUnits', 'height',
  'offset', 'points', 'r', 'rx', 'ry', 'spreadMethod', 'transform', 'viewBox',
  'width', 'x', 'y', 'x1', 'x2', 'y1', 'y2',
  // Presentatie.
  'clip-path', 'clip-rule', 'color', 'display', 'dx', 'dy', 'fill',
  'fill-opacity', 'fill-rule', 'font-family', 'font-size', 'font-weight',
  'mask', 'mix-blend-mode', 'opacity', 'stop-color', 'stop-opacity', 'stroke',
  'stroke-dasharray', 'stroke-dashoffset', 'stroke-linecap', 'stroke-linejoin',
  'stroke-miterlimit', 'stroke-opacity', 'stroke-width', 'style',
  'text-anchor', 'text-decoration', 'text-decoration-color',
  'text-decoration-style', 'visibility',
  // Verwijzingen. `href` haalt bij `<image>` alleen een `data:`-URI binnen —
  // een externe URL negeert de parser — maar de waardecontrole hieronder blijft
  // erop staan: dit is het enige attribuut hier dat een URL draagt.
  'href', 'id',
};

/// Namespace-verklaringen blijven staan.
///
/// Ze dragen een URI maar halen niets op, en weghalen is juist riskant: laat je
/// `xmlns:xlink` vallen terwijl er een `xlink:href` overblijft, dan is het
/// document niet meer geldig te heropenen.
bool _isNamespaceDeclaration(XmlAttribute attr) =>
    attr.name.qualified == 'xmlns' || attr.name.prefix == 'xmlns';

/// Hoeveel er wegviel, gesplitst naar soort — zonder één naam te bewaren.
class _Dropped {
  int elements = 0;
  int attributes = 0;

  bool get isEmpty => elements == 0 && attributes == 0;
}

void _keepOnlyAllowed(
  XmlElement element,
  _Dropped dropped, {
  required bool allowExternalUrls,
  required bool allowEmbeddedPng,
}) {
  for (final child in element.childElements.toList()) {
    if (!_allowedElements.contains(child.name.local)) {
      // Met subboom en al, net als de renderer: een `<foreignObject>` waarvan
      // alleen de schil verdwijnt laat zijn HTML-inhoud achter op een plek waar
      // niemand die meer keurt.
      dropped.elements++;
      child.remove();
      continue;
    }
    _keepOnlyAllowed(
      child,
      dropped,
      allowExternalUrls: allowExternalUrls,
      allowEmbeddedPng: allowEmbeddedPng,
    );
    if (_isEmptyDefs(child)) child.remove();
  }
  _keepOnlyAllowedAttributes(
    element,
    dropped,
    allowExternalUrls: allowExternalUrls,
    allowEmbeddedPng: allowEmbeddedPng,
  );
}

/// Een `<defs>` waar na het opschonen niets meer in zit.
///
/// Mermaid vult zijn `defs` met `<marker>` en `<style>`, en allebei gaan ze
/// hierboven weg omdat de renderer ze toch niet leest. Wat overblijft schrijft
/// de serializer als `<defs/>` — en juist die zelfsluitende vorm handelt
/// `vector_graphics_compiler` níet af: `defs` gaat daar alleen door
/// `addGroup` heen als er een sluittag bij hoort, anders valt het door naar de
/// vormen en meldt de parser `unhandled element <defs/>`. Er ging niets
/// verloren (de `defs` was al leeg), maar de melding staat in elke debug-run.
/// Weghalen scheelt tevens de bytes.
///
/// Niet geteld als "weggegooid": er zat niets meer in om te verliezen, en de
/// telling hierboven is er om echte verliezen op te laten vallen.
bool _isEmptyDefs(XmlElement element) =>
    element.name.local == 'defs' &&
    element.childElements.isEmpty &&
    element.children.every(
      (node) => node is XmlText && node.value.trim().isEmpty,
    );

void _keepOnlyAllowedAttributes(
  XmlElement element,
  _Dropped dropped, {
  required bool allowExternalUrls,
  required bool allowEmbeddedPng,
}) {
  for (final attr in element.attributes.toList()) {
    if (_isNamespaceDeclaration(attr)) continue;
    if (!_allowedAttributes.contains(attr.name.local)) {
      dropped.attributes++;
      element.attributes.remove(attr);
      continue;
    }
    // Tweede slot op de toegelaten waarden. De allow-list zegt welke attributen
    // gelezen worden, niet wat erin staat, en `href` en `style` dragen allebei
    // iets wat op een URL lijkt.
    final value = attr.value.trim();
    final safeEmbeddedPng =
        allowEmbeddedPng &&
        element.name.local == 'image' &&
        attr.name.local == 'href' &&
        _isSafeEmbeddedPngDataUrl(value);
    if ((!safeEmbeddedPng && _hasUnsafeUrl(value)) ||
        (!allowExternalUrls &&
            ((attr.name.local == 'href' &&
                    !value.startsWith('#') &&
                    !safeEmbeddedPng) ||
                _hasExternalUrlReference(value)))) {
      dropped.attributes++;
      element.attributes.remove(attr);
      continue;
    }
    // Een `style` opschonen tot enkel geldige `prop:waarde`-delen.
    if (attr.name.local == 'style') {
      final cleaned = _sanitizeStyleValue(attr.value);
      if (cleaned != attr.value) attr.value = cleaned;
    }
  }
}

/// Whether [value] is a small, dimension-bounded PNG embedded in an SVG
/// `<image>` element.
///
/// Inkscape and LibreOffice commonly save a raster logo inside an SVG wrapper.
/// Rejecting every `data:` URL made those otherwise valid files import as an
/// empty canvas. Keep this exception deliberately narrow: PNG only, base64
/// only, at most 8 MiB decoded, and no dimension above 8192 pixels. Nested SVG,
/// HTML and all other data URL types remain blocked by [_hasUnsafeUrl].
bool _isSafeEmbeddedPngDataUrl(String value) {
  return _decodeSafeEmbeddedPngDataUrl(value) != null;
}

Uint8List? _decodeSafeEmbeddedPngDataUrl(String value) {
  final match = RegExp(
    r'^data:image/png;base64,([A-Za-z0-9+/=\s]+)$',
    caseSensitive: false,
    dotAll: true,
  ).firstMatch(value);
  if (match == null) return null;
  final payload = match.group(1)!.replaceAll(RegExp(r'\s'), '');
  // Base64 expands input by roughly 4/3. Check before decoding so a very large
  // attribute never needs a second equally large allocation.
  const maxDecodedBytes = 8 * 1024 * 1024;
  if (payload.length > ((maxDecodedBytes + 2) ~/ 3) * 4) return null;

  final List<int> png;
  try {
    png = base64.decode(payload);
  } on FormatException {
    return null;
  }
  if (png.length < 24 || png.length > maxDecodedBytes) return null;
  const signature = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A];
  for (var i = 0; i < signature.length; i++) {
    if (png[i] != signature[i]) return null;
  }
  // The first PNG chunk must be IHDR; its first eight bytes are width/height.
  if (png[12] != 0x49 ||
      png[13] != 0x48 ||
      png[14] != 0x44 ||
      png[15] != 0x52) {
    return null;
  }
  int uint32(int offset) =>
      (png[offset] << 24) |
      (png[offset + 1] << 16) |
      (png[offset + 2] << 8) |
      png[offset + 3];
  final width = uint32(16);
  final height = uint32(20);
  if (width <= 0 || width > 8192 || height <= 0 || height > 8192) {
    return null;
  }
  return Uint8List.fromList(png);
}

/// Extract the image bytes when a sanitised SVG is only a wrapper around one
/// embedded PNG.
///
/// Some Inkscape/LibreOffice exports use SVG purely as a positioned container
/// for a base64 PNG. Feeding that wrapper to the vector compiler makes image
/// decoding part of vector compilation and can leave the widget unresolved.
/// Rendering the already validated PNG through Flutter's normal bounded raster
/// path is both more reliable and visually equivalent. Mixed vector/raster SVGs
/// return null and remain on the vector renderer.
Uint8List? extractSoleEmbeddedPng(String sanitizedSvg) {
  final XmlDocument document;
  try {
    document = XmlDocument.parse(sanitizedSvg);
  } on XmlParserException {
    return null;
  }

  XmlElement? image;
  var hasOtherPaint = false;
  const paintedElements = {
    'circle',
    'ellipse',
    'line',
    'path',
    'polygon',
    'polyline',
    'rect',
    'text',
    'use',
  };

  void visit(XmlElement element) {
    if (element.name.local == 'defs') return;
    if (element.name.local == 'image') {
      if (image != null) {
        hasOtherPaint = true;
      } else {
        image = element;
      }
    } else if (paintedElements.contains(element.name.local)) {
      hasOtherPaint = true;
    }
    for (final child in element.childElements) {
      visit(child);
    }
  }

  visit(document.rootElement);
  if (image == null || hasOtherPaint) return null;
  String? href;
  for (final attribute in image!.attributes) {
    if (attribute.name.local == 'href') {
      href = attribute.value.trim();
      break;
    }
  }
  return href == null ? null : _decodeSafeEmbeddedPngDataUrl(href);
}

bool _hasExternalUrlReference(String value) {
  final references = RegExp(
    r'''url\(\s*['"]?([^'")\s]+)''',
    caseSensitive: false,
  ).allMatches(value);
  return references.any((match) => !match.group(1)!.startsWith('#'));
}

/// Houdt alleen de `prop:waarde`-delen van een `style` over.
///
/// `vector_graphics` (de parser achter flutter_svg) splitst een `style` op `;`,
/// splitst elk deel op `:` en pakt daarna blind het tweede stuk. Een deel zónder
/// `:` laat het crashen met een `RangeError` — en dan blijft het HÉLE diagram
/// blanco, niet alleen dat ene stukje. Mermaid zet op ER-relatie-paden
/// bijvoorbeeld `style="undefined;;;undefined;fill:none;…"` (een eigen bug in de
/// relatie-styling); die `undefined`-delen zijn precies zulke crashers. We laten
/// ze hier vallen — wat overblijft leest de renderer gewoon, en zonder de crash
/// verschijnt het diagram weer.
String _sanitizeStyleValue(String style) {
  final kept = <String>[];
  for (final part in style.split(';')) {
    final trimmed = part.trim();
    if (trimmed.isEmpty || !trimmed.contains(':')) continue;
    kept.add(trimmed);
  }
  return kept.isEmpty ? '' : '${kept.join(';')};';
}

/// Whether [value] carries an unsafe URL **anywhere**, not just at its start.
///
/// CSS in een `style`-attribuut gebruikt puntkomma-lijsten, dus een payload kan
/// in de tweede regel staan terwijl de eerste onschuldig is. Alleen naar het
/// begin van de hele string kijken las `a;javascript:alert(1)` als veilig.
bool _hasUnsafeUrl(String value) {
  for (final part in value.split(';')) {
    if (_isUnsafeUrl(part)) return true;
  }
  return false;
}

bool _isUnsafeUrl(String value) {
  // A URL parser ignores ASCII whitespace and control characters while reading
  // the scheme, so `java\tscript:`, `java\nscript:` and a leading NUL all still
  // resolve to `javascript:`. XML normalisation and numeric character
  // references (`java&#10;script:`) let an attacker plant exactly those bytes.
  // Strip every C0 control and space before matching so the scheme can't be
  // split apart — this only ever makes the check stricter.
  final lower = value.replaceAll(RegExp(r'[\x00-\x20]'), '').toLowerCase();
  return lower.startsWith('javascript:') ||
      lower.startsWith('vbscript:') ||
      lower.startsWith('data:');
}
