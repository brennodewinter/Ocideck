import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:xml/xml.dart';

import '../../utils/xml_utils.dart';

/// A typed view over an unzipped ODP (OpenDocument Presentation) package.
///
/// Unlike OPC (PPTX), ODP has no per-part `.rels` sidecars: related parts are
/// referenced directly via `xlink:href` attributes (e.g.
/// `Pictures/1000...png`, `ObjectCharts/1`). Targets are relative to the
/// package root and may start with `./`.
class OdpContext {
  OdpContext(this.archive);

  final Archive archive;

  Map<String, (double, double)>? _pageSizes;
  Map<String, XmlElement>? _graphicProperties;
  final _parsed = <String, XmlDocument?>{};

  String? readPart(String path) {
    final bytes = readPartBytes(path);
    // ODF-onderdelen (content.xml, styles.xml, meta.xml) zijn UTF-8. Byte-voor-
    // byte lezen zou een meerbyte-teken als typografische aanhalingstekens of
    // een é uiteentrekken tot mojibake (#1194).
    return bytes == null ? null : utf8.decode(bytes);
  }

  List<int>? readPartBytes(String path) {
    for (final f in archive) {
      if (f.name == path) return f.content as List<int>;
    }
    return null;
  }

  /// Het geparseerde XML-onderdeel op [path], of `null` als het ontbreekt.
  ///
  /// De boom blijft bewaard: `content.xml` wordt tijdens één import door de
  /// dia-lus, de stijlen en het thema opgevraagd, en dat mag geen tweede
  /// volledige parse van het grootste onderdeel kosten.
  XmlDocument? readXml(String path) {
    return _parsed.putIfAbsent(path, () {
      final src = readPart(path);
      if (src == null) return null;
      return parseXmlSafe(src);
    });
  }

  /// De `style:graphic-properties` bij een `draw:style-name`, of `null`.
  ///
  /// Impress zet wat het met een afbeelding doet — spiegelen (`style:mirror`)
  /// en bijsnijden (`fo:clip`) — niet op het `draw:frame` zelf maar in de
  /// grafische stijl waar het frame naar wijst. Die staat als automatische
  /// stijl in `content.xml`, of als benoemde stijl in `styles.xml`.
  XmlElement? graphicProperties(String? styleName) {
    if (styleName == null) return null;
    _graphicProperties ??= _loadGraphicProperties();
    return _graphicProperties![styleName];
  }

  Map<String, XmlElement> _loadGraphicProperties() {
    final result = <String, XmlElement>{};
    for (final part in const ['content.xml', 'styles.xml']) {
      final doc = readXml(part);
      if (doc == null) continue;
      for (final style in descendantsLocal(doc, 'style')) {
        final name = _attr(style, 'name');
        if (name == null || result.containsKey(name)) continue;
        final props = childLocal(style, 'graphic-properties');
        if (props != null) result[name] = props;
      }
    }
    return result;
  }

  /// Normalise an `xlink:href` to a package-root-relative path.
  String resolveHref(String href) {
    var h = href.trim();
    if (h.startsWith('./')) h = h.substring(2);
    while (h.startsWith('/')) {
      h = h.substring(1);
    }
    return h;
  }

  /// Returns the (width, height) in cm for a <draw:page> element.
  ///
  /// First tries the page's own `svg:width`/`svg:height`, then looks up the
  /// master page in `styles.xml` and resolves its `style:page-layout`.
  (double, double) pageSize(XmlElement page) {
    final pageW = _cm(_attr(page, 'width'));
    final pageH = _cm(_attr(page, 'height'));
    if (pageW > 0 && pageH > 0) return (pageW, pageH);

    _pageSizes ??= _loadPageSizes();
    final masterPage = _attr(page, 'master-page-name');
    if (masterPage != null && _pageSizes!.containsKey(masterPage)) {
      return _pageSizes![masterPage]!;
    }

    // Default 16:9 ODP page.
    return (28.0, 15.75);
  }

  Map<String, (double, double)> _loadPageSizes() {
    final result = <String, (double, double)>{};
    final doc = readXml('styles.xml');
    if (doc == null) return result;

    final layoutSizes = <String, (double, double)>{};
    for (final layout in descendantsLocal(doc, 'page-layout')) {
      final props = childLocal(layout, 'page-layout-properties');
      if (props == null) continue;
      final name = _attr(layout, 'name');
      if (name == null) continue;
      final w = _cm(_attr(props, 'page-width'));
      final h = _cm(_attr(props, 'page-height'));
      if (w > 0 && h > 0) layoutSizes[name] = (w, h);
    }

    for (final master in descendantsLocal(doc, 'master-page')) {
      final name = _attr(master, 'name');
      final layoutName = _attr(master, 'page-layout-name');
      if (name == null || layoutName == null) continue;
      final size = layoutSizes[layoutName];
      if (size != null) result[name] = size;
    }

    return result;
  }

  static double _cm(String? value) {
    if (value == null) return 0;
    final num = double.tryParse(value.replaceAll(RegExp(r'[a-z%]'), '')) ?? 0;
    return num;
  }

  static String? _attr(XmlElement el, String local) {
    for (final a in el.attributes) {
      if (a.name.local == local) return a.value;
    }
    return null;
  }
}

// --- Namespace-agnostic XML helpers (local-name based) ----------------------

Iterable<XmlElement> descendantsLocal(XmlNode root, String local) => root
    .descendants
    .whereType<XmlElement>()
    .where((e) => e.name.local == local);

XmlElement? childLocal(XmlElement parent, String local) {
  for (final node in parent.children.whereType<XmlElement>()) {
    if (node.name.local == local) return node;
  }
  return null;
}

Iterable<XmlElement> childrenLocal(XmlElement parent, String local) =>
    parent.children.whereType<XmlElement>().where((e) => e.name.local == local);

/// The `xlink:href` attribute value on [el], or `null`.
String? xlinkHref(XmlElement el) {
  for (final attr in el.attributes) {
    if (attr.name.local == 'href') return attr.value;
  }
  return null;
}
