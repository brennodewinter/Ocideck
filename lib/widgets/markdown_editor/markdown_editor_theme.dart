import 'package:flutter/material.dart';
import '../../theme/app_theme.dart';

/// Readable editor chrome independent of slide/panel background colors.
class MarkdownEditorTheme {
  final Color surface;
  final Color text;
  final Color hint;
  final Color link;
  final Color codeBackground;
  final Color toolbarIcon;
  final Color accent;
  final Color border;
  final double fontSize;
  final double lineHeight;
  final String? fontFamily;

  const MarkdownEditorTheme({
    required this.surface,
    required this.text,
    required this.hint,
    required this.link,
    required this.codeBackground,
    required this.toolbarIcon,
    required this.accent,
    required this.border,
    this.fontSize = 14,
    this.lineHeight = 1.5,
    this.fontFamily,
  });

  TextStyle get bodyStyle => TextStyle(
    fontFamily: fontFamily,
    fontSize: fontSize,
    height: lineHeight,
    color: text,
  );

  TextStyle get hintStyle => bodyStyle.copyWith(color: hint);

  TextStyle get markdownStyle => bodyStyle.copyWith(
    fontFamily: 'monospace',
    fontFamilyFallback: const ['Menlo', 'Consolas', 'Courier New'],
    fontSize: fontSize - 0.5,
  );

  /// Light editor for the slide edit panel (speaker / user notes blocks).
  factory MarkdownEditorTheme.editorPanel({
    required Color text,
    required Color link,
    required Color accent,
    required Color codeBackground,
    required Color border,
    double fontSize = 12,
  }) {
    return MarkdownEditorTheme(
      surface: Colors.white,
      text: text,
      hint: text.withValues(alpha: 0.45),
      link: link,
      codeBackground: codeBackground,
      toolbarIcon: text.withValues(alpha: 0.75),
      accent: accent,
      border: border,
      fontSize: fontSize,
    );
  }

  /// Contrasting surface for notes inside a themed presenter overlay.
  factory MarkdownEditorTheme.presenterOverlay({
    required Color panelBackground,
    required Color panelText,
    required Color accent,
    String? fontFamily,
  }) {
    final darkPanel = panelBackground.computeLuminance() < 0.45;
    return MarkdownEditorTheme(
      surface: darkPanel ? const Color(0xFF242424) : Colors.white,
      text: darkPanel ? const Color(0xFFF3F4F6) : const Color(0xFF1E293B),
      hint: darkPanel ? const Color(0xFF9CA3AF) : AppTheme.slate400,
      link: accent,
      codeBackground: darkPanel
          ? const Color(0xFF374151)
          : const Color(0xFFF1F5F9),
      toolbarIcon: darkPanel ? const Color(0xFFD1D5DB) : AppTheme.slate500,
      accent: accent,
      border: panelText.withValues(alpha: 0.2),
      fontSize: 15,
      fontFamily: fontFamily,
    );
  }
}
