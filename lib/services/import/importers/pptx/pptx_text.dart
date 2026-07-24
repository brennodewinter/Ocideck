import 'package:xml/xml.dart';

import '../../models/body_block.dart';
import 'pptx_context.dart';

/// Result of parsing a DrawingML text body.
class ParsedText {
  const ParsedText({
    required this.blocks,
    required this.links,
    this.maxFontSize = 0,
  });

  final List<BodyBlock> blocks;
  final List<({String text, String url})> links;

  /// Largest font size found in this text body, in hundredths of a point.
  /// `0` means no explicit size was found.
  final int maxFontSize;
}

/// Parse a DrawingML `a:txBody` element into [BodyBlock]s and hyperlinks.
///
/// [defaultBullet] is true when the owning placeholder is a body placeholder
/// (PowerPoint renders those as bullets unless `a:buNone` is set); false for
/// title/other placeholders. [resolveLink] turns an `r:id` on an `a:hlinkClick`
/// into a URL (using the slide's relationships), returning `null` to drop it.
ParsedText parseTxBody(
  XmlElement txBody, {
  required bool defaultBullet,
  required String? Function(String rId) resolveLink,
}) {
  final blocks = <BodyBlock>[];
  final links = <({String text, String url})>[];
  var order = 0;

  for (final p in descendantsLocal(txBody, 'p')) {
    final pPr = childLocal(p, 'pPr');
    final level = int.tryParse(pPr?.getAttribute('lvl') ?? '') ?? 0;
    final isBullet = _decideBullet(pPr, defaultBullet);

    final text = StringBuffer();
    final runLinks = <({String text, String rId})>[];
    for (final child in p.children.whereType<XmlElement>()) {
      switch (child.name.local) {
        case 'r':
          final t = childLocal(child, 't')?.innerText ?? '';
          text.write(t);
          final hlink = child.children
              .whereType<XmlElement>()
              .where((e) => e.name.local == 'rPr')
              .expand((rPr) => childrenLocal(rPr, 'hlinkClick'));
          for (final h in hlink) {
            final rId =
                h.getAttribute('id', namespaceUri: relsNs) ??
                h.getAttribute('id');
            if (rId != null && t.isNotEmpty) runLinks.add((text: t, rId: rId));
          }
        case 'br':
          text.write('\n');
        case 'fld':
          final t = childLocal(child, 't')?.innerText ?? '';
          if (t.isNotEmpty) text.write(t);
      }
    }

    final value = text.toString().trim();
    if (value.isEmpty) continue;

    blocks.add(
      BodyBlock(
        kind: isBullet ? BodyBlockKind.bullet : BodyBlockKind.paragraph,
        text: value,
        level: level,
        order: order++,
      ),
    );

    for (final rl in runLinks) {
      final url = resolveLink(rl.rId);
      if (url != null) links.add((text: rl.text, url: url));
    }
  }

  var maxFontSize = 0;
  for (final el in txBody.descendants.whereType<XmlElement>()) {
    if (const {'rPr', 'endParaRPr', 'defRPr'}.contains(el.name.local)) {
      final s = el.getAttribute('sz');
      if (s != null) {
        final v = int.tryParse(s);
        if (v != null && v > maxFontSize) maxFontSize = v;
      }
    }
  }

  return ParsedText(blocks: blocks, links: links, maxFontSize: maxFontSize);
}

bool _decideBullet(XmlElement? pPr, bool defaultBullet) {
  if (pPr == null) return defaultBullet;
  // An explicit buNone turns bullets off; buChar/buAutoNum turns them on.
  if (childLocal(pPr, 'buNone') != null) return false;
  if (childLocal(pPr, 'buChar') != null) return true;
  if (childLocal(pPr, 'buAutoNum') != null) return true;
  return defaultBullet;
}
