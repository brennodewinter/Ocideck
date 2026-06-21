import 'package:flutter_quill/flutter_quill.dart';
import 'package:markdown/markdown.dart' as md;
import 'package:markdown_quill/markdown_quill.dart';

import 'markdown_paste_cleanup.dart';

/// Round-trip conversion between stored markdown and a Quill document.
class MarkdownQuillCodec {
  MarkdownQuillCodec._();

  static final _mdDocument = md.Document(
    encodeHtml: false,
    extensionSet: md.ExtensionSet.gitHubFlavored,
  );

  static final _mdToDelta = MarkdownToDelta(markdownDocument: _mdDocument);
  static final _deltaToMd = DeltaToMarkdown(
    customTextAttrsHandlers: {
      Attribute.italic.key: CustomAttributeHandler(
        beforeContent: (attribute, node, output) {
          if (!_nodeHasAttr(node.previous, attribute.key)) {
            output.write('*');
          }
        },
        afterContent: (attribute, node, output) {
          if (!_nodeHasAttr(node.next, attribute.key)) {
            output.write('*');
          }
        },
      ),
    },
  );

  static Document documentFromMarkdown(String markdown) {
    if (markdown.isEmpty) {
      return Document();
    }
    return Document.fromDelta(_mdToDelta.convert(markdown));
  }

  static String markdownFromDocument(Document document) {
    final raw = _deltaToMd.convert(document.toDelta()).trimRight();
    return normalizeRichTextMarkdown(raw);
  }
}

bool _nodeHasAttr(Node? node, String attributeKey) {
  if (node == null) return false;
  return node.style.attributes.containsKey(attributeKey);
}
