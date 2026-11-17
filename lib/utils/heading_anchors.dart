// Eén documentbrede naamruimte voor inhoudsopgave, lezer en export.
import 'package:markdown/markdown.dart' as md;

import 'inline_markdown.dart' show stripInlineMarkdown;

/// Unicodeletters blijven staan; leestekens verdwijnen en witruimte en
/// koppeltekens worden samengevoegd. Lege titels krijgen een stabiele basis.
String headingAnchorBase(String title) => stripInlineMarkdown(title)
    .toLowerCase()
    .replaceAll(RegExp(r'[^\p{L}\p{N}\p{M}_\s-]', unicode: true), '')
    .replaceAll(RegExp(r'[\s-]+'), '-')
    .replaceAll(RegExp(r'^-|-$'), '');

/// Het oude ASCII-lezeranker blijft een alias voor handgeschreven links.
String legacyHeadingSlug(String title) => stripInlineMarkdown(
  title,
).toLowerCase().replaceAll(RegExp(r'[^a-z0-9_ -]'), '').replaceAll(' ', '-');

String _legacyTocSlug(String title) => stripInlineMarkdown(title)
    .toLowerCase()
    .replaceAll(RegExp(r'[^\w\s-]'), '')
    .replaceAll(RegExp(r'\s+'), '-')
    .replaceAll(RegExp(r'-+'), '-')
    .replaceAll(RegExp(r'^-|-$'), '');

class HeadingAnchor {
  const HeadingAnchor(this.title, this.id, this.aliases);
  final String title;
  final String id;
  final List<String> aliases;

  Map<String, Object> toJson() => {
    'title': title,
    'id': id,
    'aliases': aliases,
  };
}

/// Canonieke namen hebben voorrang op historische aliassen. Bij historisch
/// dubbelzinnige links wint de eerste kop; nieuwe links zijn altijd uniek.
class HeadingAnchorIndex {
  HeadingAnchorIndex(Iterable<String> titles) {
    final taken = <String>{};
    for (final title in titles) {
      final normalized = headingAnchorBase(title);
      final base = normalized.isEmpty ? 'section' : normalized;
      var id = base;
      var suffix = 0;
      while (!taken.add(id)) {
        id = '$base-${++suffix}';
      }
      entries.add(HeadingAnchor(stripInlineMarkdown(title), id, []));
    }
    for (var i = 0; i < entries.length; i++) {
      _targets[entries[i].id] = i;
    }
    for (var i = 0; i < entries.length; i++) {
      final entry = entries[i];
      for (final alias in {
        legacyHeadingSlug(entry.title),
        _legacyTocSlug(entry.title),
      }) {
        if (alias.isEmpty || _targets.containsKey(alias)) continue;
        _targets[alias] = i;
        entry.aliases.add(alias);
      }
    }
  }

  final List<HeadingAnchor> entries = [];
  final Map<String, int> _targets = {};

  int resolve(String fragment, {int occurrence = 0}) {
    if (occurrence == 0) return _targets[fragment] ?? -1;
    // De bestaande outline-API kan een later gelijknamig lezeranker vragen.
    for (var i = 0; i < entries.length; i++) {
      if (legacyHeadingSlug(entries[i].title) == fragment &&
          occurrence-- == 0) {
        return i;
      }
    }
    return -1;
  }

  Map<String, int> get targets => Map.unmodifiable(_targets);
}

class MarkdownHeading {
  const MarkdownHeading(this.level, this.text);
  final int level;
  final String text;
}

/// Dezelfde GFM-AST als de TOC, inclusief setext en inline-opmaak, buiten code.
List<MarkdownHeading> markdownHeadings(String source) {
  final nodes = md.Document(
    encodeHtml: false,
    extensionSet: md.ExtensionSet.gitHubFlavored,
  ).parse(source);
  return [
    for (final node in nodes)
      if (node is md.Element && RegExp(r'^h[1-6]$').hasMatch(node.tag))
        MarkdownHeading(
          int.parse(node.tag.substring(1)),
          node.textContent.trim(),
        ),
  ];
}
