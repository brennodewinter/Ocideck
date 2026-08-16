import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_quill/flutter_quill.dart';

import '../../utils/markdown_paste_cleanup.dart';
import '../../utils/markdown_quill_codec.dart';
import 'divider_embed_builder.dart';
import 'markdown_editor_theme.dart';
import 'table_embed_builder.dart';
import 'toc_embed_builder.dart';

/// The Quill [DefaultStyles] for the document/notes WYSIWYG surface, derived
/// entirely from [theme] so every block honours the app theme.
///
/// Every block type we render **must** be listed here. Quill merges these over
/// its own `DefaultStyles.getInstance(context)`, so any field left unset falls
/// back to that ambient default — and the ambient default colours text from the
/// surrounding `DefaultTextStyle`, which on the document surface reads as a
/// brand/link-like colour in the light theme (EU-blue under the Europa theme).
/// That is exactly how bullet-list items once rendered blue while headings and
/// prose stayed on-surface: `lists` was simply absent here.
///
/// A list has **two** coloured parts and Quill colours them from **two** style
/// fields: the item text follows `lists.style`, but the marker (bullet dot /
/// number) follows `leading.style` — the leading builder does
/// `leading.style.copyWith(color: fontColor)` and `fontColor` is null unless the
/// line carries an explicit colour attribute, so `copyWith` keeps
/// `leading.style.color`. Setting `lists` alone fixed the text but left the
/// marker on the ambient blue; both must be pinned to [MarkdownEditorTheme.bodyStyle]
/// so item text *and* marker match a paragraph in light and dark.
@visibleForTesting
DefaultStyles defaultStylesFor(MarkdownEditorTheme theme) {
  final body = theme.bodyStyle;
  DefaultTextBlockStyle block(TextStyle style) => DefaultTextBlockStyle(
    style,
    HorizontalSpacing.zero,
    const VerticalSpacing(6, 0),
    VerticalSpacing.zero,
    null,
  );

  return DefaultStyles(
    paragraph: block(body),
    // Bullet/numbered list **item text**: the body colour, not Quill's ambient
    // default (a link/brand colour in the light theme). Spacing mirrors Quill's
    // own list defaults.
    lists: DefaultListBlockStyle(
      body,
      HorizontalSpacing.zero,
      const VerticalSpacing(6, 0),
      const VerticalSpacing(0, 6),
      null,
      null,
    ),
    // The list **marker** (bullet dot / number) is coloured from `leading`, not
    // `lists`. Pin it to the body colour too, else the dot stays on the ambient
    // blue while its own item text is on-surface (visible under Europa).
    leading: DefaultTextBlockStyle(
      body,
      HorizontalSpacing.zero,
      VerticalSpacing.zero,
      VerticalSpacing.zero,
      null,
    ),
    h1: block(
      body.copyWith(
        fontSize: theme.fontSize + 8,
        fontWeight: FontWeight.bold,
        color: theme.heading,
      ),
    ),
    h2: block(
      body.copyWith(
        fontSize: theme.fontSize + 4,
        fontWeight: FontWeight.bold,
        color: theme.subheading,
      ),
    ),
    h3: block(
      body.copyWith(
        fontSize: theme.fontSize + 2,
        fontWeight: FontWeight.bold,
        color: theme.subheading,
      ),
    ),
    bold: body.copyWith(fontWeight: FontWeight.bold),
    italic: body.copyWith(fontStyle: FontStyle.italic),
    strikeThrough: body.copyWith(decoration: TextDecoration.lineThrough),
    inlineCode: InlineCodeStyle(
      style: body.copyWith(
        fontFamily: 'monospace',
        fontFamilyFallback: const ['Menlo', 'Consolas', 'Courier New'],
      ),
      backgroundColor: theme.codeBackground,
      radius: const Radius.circular(3),
    ),
    link: body.copyWith(
      color: theme.link,
      decoration: TextDecoration.underline,
      decorationColor: theme.link,
    ),
    placeHolder: DefaultTextBlockStyle(
      theme.hintStyle,
      HorizontalSpacing.zero,
      VerticalSpacing.zero,
      VerticalSpacing.zero,
      null,
    ),
  );
}

class WysiwygNotesField extends StatefulWidget {
  final QuillController controller;
  final ScrollController scrollController;
  final FocusNode focusNode;
  final MarkdownEditorTheme editorTheme;
  final String hintText;
  final bool expand;
  final EdgeInsetsGeometry contentPadding;
  final bool bordered;

  /// Optioneel: vang Cmd/Ctrl+V af vóór de standaard plak. Geeft `true` terug
  /// wanneer de plak is afgehandeld (bijv. klembord-afbeelding → markdown).
  final Future<bool> Function()? tryConsumePaste;

  const WysiwygNotesField({
    super.key,
    required this.controller,
    required this.scrollController,
    required this.focusNode,
    required this.editorTheme,
    required this.hintText,
    this.expand = false,
    this.contentPadding = const EdgeInsets.all(10),
    this.bordered = true,
    this.tryConsumePaste,
  });

  @override
  State<WysiwygNotesField> createState() => _WysiwygNotesFieldState();
}

class _WysiwygNotesFieldState extends State<WysiwygNotesField> {
  Future<void> _pasteSanitized() async {
    if (widget.tryConsumePaste != null && await widget.tryConsumePaste!()) {
      return;
    }
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final raw = data?.text;
    if (raw == null || raw.isEmpty) return;
    final text = sanitizeMarkdownPaste(raw);
    final index = widget.controller.selection.baseOffset;
    final length = widget.controller.selection.extentOffset - index;
    widget.controller.replaceText(
      index,
      length,
      text,
      TextSelection.collapsed(offset: index + text.length),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: widget.editorTheme.surface,
        borderRadius: BorderRadius.circular(6),
        border: widget.bordered
            ? Border.all(color: widget.editorTheme.border)
            : null,
      ),
      clipBehavior: Clip.antiAlias,
      child: Shortcuts(
        shortcuts: const {
          SingleActivator(LogicalKeyboardKey.keyV, control: true):
              _SanitizedPasteIntent(),
          SingleActivator(LogicalKeyboardKey.keyV, meta: true):
              _SanitizedPasteIntent(),
        },
        child: Actions(
          actions: {
            _SanitizedPasteIntent: CallbackAction<_SanitizedPasteIntent>(
              onInvoke: (_) {
                _pasteSanitized();
                return null;
              },
            ),
          },
          child: DocumentStyleScope(
            profile: widget.editorTheme.profile,
            child: QuillEditor.basic(
              controller: widget.controller,
              focusNode: widget.focusNode,
              scrollController: widget.scrollController,
              config: QuillEditorConfig(
                expands: widget.expand,
                padding: widget.contentPadding,
                placeholder: widget.hintText,
                customStyles: defaultStylesFor(widget.editorTheme),
                // GFM-tabellen komen als `x-embed-table`-embed binnen (zie
                // MarkdownQuillCodec) en worden hier als gerenderde, bewerkbare
                // tabel getekend i.p.v. losse woorden. Een `---`-scheiding komt als
                // `divider`-embed binnen en wordt een horizontale lijn — zonder deze
                // builder tekent Quill er een RenderErrorBox voor. De
                // `<!-- toc -->`-marker komt als `x-embed-toc`-embed binnen en
                // wordt de inhoudsopgave-voorbeeldweergave.
                embedBuilders: const [
                  TableEmbedBuilder(),
                  DividerEmbedBuilder(),
                  TocEmbedBuilder(),
                ],
                autoFocus: false,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SanitizedPasteIntent extends Intent {
  const _SanitizedPasteIntent();
}

/// Inserts sanitized plain text at the cursor in a Quill document.
void insertSanitizedPlainText(QuillController controller, String raw) {
  final text = sanitizeMarkdownPaste(raw);
  final index = controller.selection.baseOffset;
  final length = controller.selection.extentOffset - index;
  controller.replaceText(
    index,
    length,
    text,
    TextSelection.collapsed(offset: index + text.length),
  );
}

/// Reloads the Quill document from sanitized markdown.
void loadSanitizedMarkdown(QuillController controller, String markdown) {
  controller.document = MarkdownQuillCodec.documentFromMarkdown(
    normalizeRichTextMarkdown(markdown),
  );
}
