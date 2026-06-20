import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart';

import 'markdown_editor_theme.dart';

class WysiwygNotesToolbar extends StatelessWidget {
  final QuillController controller;
  final MarkdownEditorTheme theme;
  final bool compact;

  const WysiwygNotesToolbar({
    super.key,
    required this.controller,
    required this.theme,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    final iconSize = compact ? 16.0 : 18.0;
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
          showClearFormat: false,
          showListCheck: false,
          showCodeBlock: false,
          showQuote: false,
          showIndent: false,
          showUndo: false,
          showRedo: false,
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
