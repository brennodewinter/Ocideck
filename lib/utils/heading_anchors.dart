// Eén documentbrede naamruimte voor inhoudsopgave, lezer en export.
import 'dart:collection';
import 'dart:convert';

import 'package:markdown/markdown.dart' as md;
import 'package:html/parser.dart' as html;

import 'inline_markdown.dart' show stripInlineMarkdown;

/// Unicodeletters blijven staan; leestekens verdwijnen en witruimte en
/// koppeltekens worden samengevoegd. Lege titels krijgen een stabiele basis.
String headingAnchorBase(String title) => title
    .toLowerCase()
    .replaceAll(RegExp(r'[^\p{L}\p{N}\p{M}_\s-]', unicode: true), '')
    .replaceAll(RegExp(r'[\s-]+'), '-')
    .replaceAll(RegExp(r'^-|-$'), '');

/// Het oude ASCII-lezeranker blijft een alias voor handgeschreven links.
String legacyHeadingSlug(String title) => stripInlineMarkdown(
  title,
).toLowerCase().replaceAll(RegExp(r'[^a-z0-9_ -]'), '').replaceAll(' ', '-');

String _legacyTocSlug(String title) => title
    .toLowerCase()
    .replaceAll(RegExp(r'[^\w\s-]'), '')
    .replaceAll(RegExp(r'\s+'), '-')
    .replaceAll(RegExp(r'-+'), '-')
    .replaceAll(RegExp(r'^-|-$'), '');

class HeadingAnchor {
  HeadingAnchor(this.title, this.id, this._aliases, this.legacyId);
  final String title;
  final String id;
  final List<String> _aliases;
  late final List<String> aliases = UnmodifiableListView(_aliases);
  final String legacyId;

  Map<String, Object> toJson() => {
    'title': title,
    'id': id,
    'aliases': aliases,
  };
}

/// Canonieke namen hebben voorrang op historische aliassen. Bij historisch
/// dubbelzinnige links wint de eerste kop; nieuwe links zijn altijd uniek.
class HeadingAnchorIndex {
  // Begrensde cache op de kopreeks, zodat herhaalde navigatie geen nieuwe
  // inline-/HTML-parse doet en een gewone bodybewerking de index niet ongeldig maakt.
  static final _cache = <String, HeadingAnchorIndex>{};

  factory HeadingAnchorIndex(
    Iterable<String> titles, {
    bool plainText = false,
  }) {
    final values = titles.toList(growable: false);
    final key = jsonEncode([plainText, values]);
    final index =
        _cache.remove(key) ??
        HeadingAnchorIndex._(values, plainText: plainText);
    _cache[key] = index;
    if (_cache.length > 16) _cache.remove(_cache.keys.first);
    return index;
  }

  HeadingAnchorIndex._(Iterable<String> titles, {required bool plainText}) {
    final taken = <String>{};
    for (final title in titles) {
      final plain = plainText
          ? title
          : html
                .parseFragment(
                  md.markdownToHtml(
                    title,
                    inlineOnly: true,
                    extensionSet: md.ExtensionSet.gitHubFlavored,
                  ),
                )
                .text!;
      final normalized = headingAnchorBase(plain);
      final base = normalized.isEmpty ? 'section' : normalized;
      var id = base;
      var suffix = 0;
      while (!taken.add(id)) {
        id = '$base-${++suffix}';
      }
      _entries.add(
        HeadingAnchor(
          plain,
          id,
          [],
          plainText
              ? plain
                    .toLowerCase()
                    .replaceAll(RegExp(r'[^a-z0-9_ -]'), '')
                    .replaceAll(' ', '-')
              : legacyHeadingSlug(title),
        ),
      );
    }
    for (var i = 0; i < entries.length; i++) {
      _targets[entries[i].id] = i;
    }
    final legacyTaken = <String>{};
    for (var i = 0; i < entries.length; i++) {
      final entry = entries[i];
      final legacyBase = _legacyTocSlug(entry.title);
      var legacyUnique = legacyBase;
      var suffix = 0;
      while (!legacyTaken.add(legacyUnique)) {
        legacyUnique = '$legacyBase-${++suffix}';
      }
      for (final alias in {
        legacyUnique,
        entry.legacyId,
        legacyHeadingSlug(entry.title),
        _legacyTocSlug(entry.title),
      }) {
        if (alias.isEmpty || _targets.containsKey(alias)) continue;
        _targets[alias] = i;
        entry._aliases.add(alias);
      }
    }
  }

  final List<HeadingAnchor> _entries = [];
  late final List<HeadingAnchor> entries = UnmodifiableListView(_entries);
  final Map<String, int> _targets = {};

  int resolve(String fragment, {int occurrence = 0}) {
    if (occurrence == 0) return _targets[fragment] ?? -1;
    // De bestaande outline-API kan een later gelijknamig lezeranker vragen.
    for (var i = 0; i < entries.length; i++) {
      if (entries[i].legacyId == fragment && occurrence-- == 0) {
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
    encodeHtml: true,
    extensionSet: md.ExtensionSet.gitHubFlavored,
  ).parse(source);
  return [
    for (final node in nodes)
      if (node is md.Element && RegExp(r'^h[1-6]$').hasMatch(node.tag))
        MarkdownHeading(
          int.parse(node.tag.substring(1)),
          html.parseFragment(md.renderToHtml([node])).text!.trim(),
        ),
  ];
}
