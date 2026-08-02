import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart';

import 'markdown_editor_theme.dart';

class WysiwygNotesToolbar extends StatelessWidget {
  final QuillController controller;
  final FocusNode focusNode;
  final MarkdownEditorTheme theme;
  final bool compact;

  const WysiwygNotesToolbar({
    super.key,
    required this.controller,
    required this.focusNode,
    required this.theme,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    final iconSize = compact ? 16.0 : 18.0;
    void refocusEditor() {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (focusNode.canRequestFocus) focusNode.requestFocus();
      });
    }

    return DecoratedBox(
      decoration: BoxDecoration(
        color: theme.surface,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: theme.border),
      ),
      child: QuillSimpleToolbar(
        controller: controller,
        config: QuillSimpleToolbarConfig(
          multiRowsDisplay: !compact,
          showDividers: false,
          toolbarSize: iconSize * 1.4,
          decoration: const BoxDecoration(),
          buttonOptions: QuillSimpleToolbarButtonOptions(
            base: QuillToolbarBaseButtonOptions(
              afterButtonPressed: refocusEditor,
            ),
          ),
          iconTheme: QuillIconTheme(
            iconButtonUnselectedData: IconButtonData(
              iconSize: iconSize,
              color: theme.toolbarIcon,
            ),
            iconButtonSelectedData: IconButtonData(
              iconSize: iconSize,
              color: theme.accent,
            ),
          ),
          showFontFamily: false,
          showFontSize: false,
          showUnderLineButton: false,
          showColorButton: false,
          showBackgroundColorButton: false,
          showClearFormat: !compact,
          showListCheck: false,
          showCodeBlock: !compact,
          showQuote: !compact,
          showIndent: false,
          showUndo: !compact,
          showRedo: !compact,
          showSearchButton: false,
          showSubscript: false,
          showSuperscript: false,
          showSmallButton: false,
          showLineHeightButton: false,
          showAlignmentButtons: false,
          headerStyleType: HeaderStyleType.buttons,
        ),
      ),
    );
  }
}
