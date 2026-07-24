import 'package:xml/xml.dart';

import '../../models/source_theme.dart';
import 'odp_context.dart';

/// Salvage a [SourceTheme] from `styles.xml`.
///
/// ODP does not expose a structured theme like PPTX's `theme1.xml`; colours and
/// fonts are spread across style definitions:
/// - slide background: `<style:page-layout-properties fo:background-color=...>`
///   inside a `<style:page-layout>`.
/// - text colour + font: the default paragraph style's
///   `<style:text-properties fo:color=... fo:font-family=...>`.
/// - accent: the first non-transparent graphic fill colour
///   (`<style:graphic-properties draw:fill-color=...>`).
///
/// Every field is optional; `null` falls back to OciDeck defaults downstream.
SourceTheme? parseOdpTheme(OdpContext ctx) {
  final doc = ctx.readXml('styles.xml');
  if (doc == null) return null;

  final slideBackground = _pageBackground(doc);
  final accent = _accentColor(doc);
  final (textColor, fontFamily) = _textProps(doc);

  final hasAny = [
    slideBackground,
    accent,
    textColor,
    fontFamily,
  ].any((v) => v != null && v.isNotEmpty);
  if (!hasAny) return null;

  return SourceTheme(
    slideBackgroundColor: slideBackground,
    accentColor: accent,
    textColor: textColor,
    fontFamily: fontFamily,
  );
}

String? _pageBackground(XmlDocument doc) {
  for (final el in doc.descendants.whereType<XmlElement>()) {
    if (el.name.local == 'page-layout-properties') {
      final color = _attr(el, 'background-color');
      if (color != null && color != 'none' && color != 'transparent') {
        return _normalizeHex(color);
      }
    }
  }
  return null;
}

String? _accentColor(XmlDocument doc) {
  for (final el in doc.descendants.whereType<XmlElement>()) {
    if (el.name.local == 'graphic-properties') {
      final fill = _attr(el, 'fill');
      if (fill == 'solid') {
        final color = _attr(el, 'fill-color');
        if (color != null && color != 'none' && color != 'transparent') {
          return _normalizeHex(color);
        }
      }
    }
  }
  return null;
}

(String?, String?) _textProps(XmlDocument doc) {
  String? color;
  String? font;
  // Prefer the default paragraph style, then any "Standard"/"Title" style.
  for (final style in doc.descendants.whereType<XmlElement>().where(
    (e) => e.name.local == 'style' || e.name.local == 'default-style',
  )) {
    final family = _attr(style, 'family');
    if (family != 'paragraph') continue;
    final props = _child(style, 'text-properties');
    if (props == null) continue;
    color ??= _attr(props, 'color');
    font ??= _attr(props, 'font-family');
  }
  return (
    color != null ? _normalizeHex(color) : null,
    font != null ? _normalizeFont(font) : null,
  );
}

String _normalizeHex(String value) {
  final v = value.trim();
  if (v.startsWith('#')) return v;
  // ODP may write hex without '#', or as 'rgb(r,g,b)'.
  final rgb = RegExp(
    r'rgb\(\s*(\d+)\s*,\s*(\d+)\s*,\s*(\d+)\s*\)',
  ).firstMatch(v);
  if (rgb != null) {
    final r = int.parse(rgb.group(1)!).toRadixString(16).padLeft(2, '0');
    final g = int.parse(rgb.group(2)!).toRadixString(16).padLeft(2, '0');
    final b = int.parse(rgb.group(3)!).toRadixString(16).padLeft(2, '0');
    return '#$r$g$b';
  }
  if (RegExp(r'^[0-9A-Fa-f]{6}$').hasMatch(v)) return '#$v';
  return value;
}

String _normalizeFont(String value) {
  // ODP may quote the family with single quotes; strip them.
  return value.replaceAll("'", '').trim();
}

XmlElement? _child(XmlElement parent, String local) {
  for (final node in parent.children.whereType<XmlElement>()) {
    if (node.name.local == local) return node;
  }
  return null;
}

String? _attr(XmlElement el, String local) {
  for (final a in el.attributes) {
    if (a.name.local == local) return a.value;
  }
  return null;
}
