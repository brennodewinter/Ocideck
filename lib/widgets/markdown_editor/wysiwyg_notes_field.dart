import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart';

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

class WysiwygNotesField extends StatelessWidget {
  final QuillController controller;
  final ScrollController scrollController;
  final FocusNode focusNode;
  final MarkdownEditorTheme editorTheme;
  final String hintText;
  final bool expand;
  final EdgeInsetsGeometry contentPadding;
  final bool bordered;

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
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: editorTheme.surface,
        borderRadius: BorderRadius.circular(6),
        border: bordered ? Border.all(color: editorTheme.border) : null,
      ),
      clipBehavior: Clip.antiAlias,
      child: QuillEditor.basic(
        controller: controller,
        focusNode: focusNode,
        scrollController: scrollController,
        config: QuillEditorConfig(
          expands: expand,
          padding: contentPadding,
          placeholder: hintText,
          customStyles: _defaultStylesFor(editorTheme),
          autoFocus: false,
        ),
      ),
    );
  }
}
