import 'package:xml/xml.dart';

import 'log.dart';

/// Strip dangerous elements/attributes from Mermaid SVG output before display.
/// Returns null when the markup is empty or cannot be parsed safely.
///
/// This is a deny-list, which is the weaker shape — an allow-list cannot be
/// written honestly until we know the element and attribute vocabulary Mermaid
/// actually emits, and the tests here use synthetic SVG rather than real
/// diagram output. Narrowing it by guesswork would silently drop parts of real
/// diagrams. See the note at the bottom of this file and issue #516.
String? sanitizeMermaidSvg(String svg) {
  if (svg.trim().isEmpty || !svg.contains('<svg')) return null;

  final XmlDocument document;
  try {
    document = XmlDocument.parse(svg);
  } catch (e) {
    logWarning('sanitizeMermaidSvg: SVG parse failed', e);
    return null;
  }

  final root = document.rootElement;
  if (root.name.local != 'svg') return null;

  _removeForbiddenElements(root);
  _stripUnsafeAttributes(root);

  return document.toXmlString(pretty: false);
}

const _forbiddenElements = {
  'script',
  'foreignObject',
  'iframe',
  'object',
  'embed',
  // SMIL animation can assign to *any* attribute, including an event handler:
  // `<set attributeName="onload" to="alert(1)"/>` installs a handler that no
  // attribute check on the parent would ever see, because at parse time the
  // parent carries no `on…` attribute at all. The animation elements earn
  // nothing in a Mermaid diagram — Mermaid animates with CSS, not SMIL — so
  // they go entirely rather than being filtered on `attributeName`.
  'set',
  'animate',
  'animateTransform',
  'animateMotion',
  // `<style>` carries CSS, and CSS carries URLs. Nothing here parses that
  // dialect, so a `url(javascript:…)` or an `@import` inside a stylesheet
  // travelled straight through a check that only ever looked at attributes.
  // Dropping the element costs Mermaid's theming inside the SVG; the diagram
  // still renders, because Mermaid also writes presentation attributes.
  'style',
};

void _removeForbiddenElements(XmlElement element) {
  for (final child in element.childElements.toList()) {
    if (_forbiddenElements.contains(child.name.local)) {
      child.remove();
      continue;
    }
    _removeForbiddenElements(child);
  }
}

void _stripUnsafeAttributes(XmlElement element) {
  for (final attr in element.attributes.toList()) {
    final name = attr.name.local;
    final value = attr.value.trim();
    if (name.startsWith('on')) {
      element.attributes.remove(attr);
      continue;
    }
    if (_hasUnsafeUrl(value)) {
      element.attributes.remove(attr);
    }
  }
  for (final child in element.childElements) {
    _stripUnsafeAttributes(child);
  }
}

/// Whether [value] carries an unsafe URL **anywhere**, not just at its start.
///
/// SMIL and CSS both use semicolon-separated lists, so a payload can sit in the
/// second entry of a `values=` list while the first is innocent. Checking only
/// the start of the whole string read `a;javascript:alert(1)` as safe.
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

// ── Waarom dit (nog) geen allow-list is ─────────────────────────────────────
//
// Een allow-list is de juiste vorm: hij weigert wat hij niet kent in plaats van
// te hopen dat de lijst met gevaren volledig is. Deze drie toevoegingen laten
// precies zien waarom — SMIL, CSS en puntkomma-lijsten waren alle drie gaten in
// een lijst waarvan iemand dacht dat hij compleet was.
//
// Wat ervoor nodig is: de werkelijke woordenschat die Mermaid uitstuurt, per
// diagramsoort. Die staat hier nergens — de tests gebruiken met de hand
// geschreven SVG, geen echte Mermaid-uitvoer — en een allow-list op gevoel
// laat de eerste de beste sequentiediagram half renderen zónder foutmelding.
// Dat is een slechtere ruil dan deze deny-list: stil verlies is erger dan een
// bekend gat.
//
// De weg ernaartoe: verzamel de uitvoer van elk diagramtype door de echte
// renderer, leid daar de elementen- en attributenlijst uit af, en laat een
// geweigerd element een waarschuwing loggen in plaats van stil te verdwijnen.
