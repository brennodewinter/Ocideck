import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_quill/flutter_quill.dart';

import '../../utils/markdown_paste_cleanup.dart';
import '../../utils/markdown_quill_codec.dart';
import 'markdown_editor_theme.dart';

DefaultStyles _defaultStylesFor(MarkdownEditorTheme theme) {
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
    h1: block(
      body.copyWith(fontSize: theme.fontSize + 8, fontWeight: FontWeight.bold),
    ),
    h2: block(
      body.copyWith(fontSize: theme.fontSize + 4, fontWeight: FontWeight.bold),
    ),
    h3: block(
      body.copyWith(fontSize: theme.fontSize + 2, fontWeight: FontWeight.bold),
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
          child: QuillEditor.basic(
            controller: widget.controller,
            focusNode: widget.focusNode,
            scrollController: widget.scrollController,
            config: QuillEditorConfig(
              expands: widget.expand,
              padding: widget.contentPadding,
              placeholder: widget.hintText,
              customStyles: _defaultStylesFor(widget.editorTheme),
              autoFocus: false,
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
