import 'package:xml/xml.dart';

import '../../models/body_block.dart';
import 'odp_context.dart';

/// Result of parsing an ODP text box.
class OdpParsedText {
  const OdpParsedText({required this.blocks, required this.links});
  final List<BodyBlock> blocks;
  final List<({String text, String url})> links;
}

/// Parse an ODP text container (`draw:text-box` or notes body) into
/// [BodyBlock]s and hyperlinks.
///
/// ODP models text as `text:p` paragraphs, `text:h` headings (with
/// `text:outline-level`), and `text:list`/`text:list-item` for bullets. List
/// nesting depth becomes the bullet level. Hyperlinks are `text:a` with an
/// `xlink:href`.
OdpParsedText parseTextBox(XmlElement box) {
  final blocks = <BodyBlock>[];
  final links = <({String text, String url})>[];
  var order = 0;

  void walkParagraph(XmlElement p, {required bool bullet, required int level}) {
    final text = _innerText(p).trim();
    if (text.isEmpty) return;
    blocks.add(
      BodyBlock(
        kind: bullet ? BodyBlockKind.bullet : BodyBlockKind.paragraph,
        text: text,
        level: level,
        order: order++,
      ),
    );
    for (final a in descendantsLocal(p, 'a')) {
      final href = xlinkHref(a);
      if (href != null) {
        links.add((text: _innerText(a).trim(), url: href));
      }
    }
  }

  void walkList(XmlElement list, {int level = 0}) {
    for (final item in childrenLocal(list, 'list-item')) {
      // A list item's direct paragraphs are bullets at this level.
      for (final p in childrenLocal(item, 'p')) {
        walkParagraph(p, bullet: true, level: level);
      }
      for (final h in childrenLocal(item, 'h')) {
        final lvl = int.tryParse(_attr(h, 'outline-level') ?? '') ?? 1;
        blocks.add(
          BodyBlock(
            kind: BodyBlockKind.heading,
            text: _innerText(h).trim(),
            level: lvl - 1,
            order: order++,
          ),
        );
      }
      // Nested list -> deeper level.
      for (final nested in childrenLocal(item, 'list')) {
        walkList(nested, level: level + 1);
      }
    }
  }

  for (final child in box.children.whereType<XmlElement>()) {
    switch (child.name.local) {
      case 'p':
        walkParagraph(child, bullet: false, level: 0);
      case 'h':
        final lvl = int.tryParse(_attr(child, 'outline-level') ?? '') ?? 1;
        blocks.add(
          BodyBlock(
            kind: BodyBlockKind.heading,
            text: _innerText(child).trim(),
            level: lvl - 1,
            order: order++,
          ),
        );
      case 'list':
        walkList(child);
    }
  }

  return OdpParsedText(blocks: blocks, links: links);
}

String _innerText(XmlElement el) {
  final buf = StringBuffer();
  for (final node in el.descendants) {
    if (node is XmlText) {
      buf.write(node.value);
    } else if (node is XmlElement) {
      final local = node.name.local;
      if (local == 'line-break') {
        buf.write('\n');
      } else if (local == 's') {
        buf.write(' ');
      }
    }
  }
  return buf.toString();
}

String? _attr(XmlElement el, String local) {
  for (final a in el.attributes) {
    if (a.name.local == local) return a.value;
  }
  return null;
}
