import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart';

/// Renders a `divider` block embed — a Markdown thematic break (`---`), which
/// [MarkdownQuillCodec] turns into `BlockEmbed('divider')` — as a horizontal rule
/// in the visual (Quill) editor.
///
/// Without a builder for this embed type Quill draws a `RenderErrorBox`, so any
/// document containing a `---` (most visibly an inserted **page break**) would
/// break the WYSIWYG surface. Registering this keeps the surface intact: on
/// screen a document stays continuous and the rule reads as the page break, while
/// the export turns the same `---` into a real new page.
class DividerEmbedBuilder extends EmbedBuilder {
  const DividerEmbedBuilder();

  /// The embed type `MarkdownToDelta` uses for `<hr>` (`horizontalRuleType`).
  @override
  String get key => 'divider';

  /// A rule is a block, not an inline glyph: it spans the width.
  @override
  bool get expanded => true;

  @override
  Widget build(BuildContext context, EmbedContext embedContext) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Divider(
        height: 1,
        thickness: 1,
        color: Theme.of(context).colorScheme.outlineVariant,
      ),
    );
  }
}
