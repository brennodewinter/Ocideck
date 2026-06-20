import 'package:xml/xml.dart';

/// Strip dangerous elements/attributes from Mermaid SVG output before display.
/// Returns null when the markup is empty or cannot be parsed safely.
String? sanitizeMermaidSvg(String svg) {
  if (svg.trim().isEmpty || !svg.contains('<svg')) return null;

  final XmlDocument document;
  try {
    document = XmlDocument.parse(svg);
  } catch (_) {
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
    if (_isUnsafeUrl(value)) {
      element.attributes.remove(attr);
    }
  }
  for (final child in element.childElements) {
    _stripUnsafeAttributes(child);
  }
}

bool _isUnsafeUrl(String value) {
  final lower = value.toLowerCase();
  return lower.startsWith('javascript:') || lower.startsWith('data:');
}
