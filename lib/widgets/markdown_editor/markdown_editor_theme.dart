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

  /// Editor for the slide edit panel (speaker / user notes blocks).
  ///
  /// De achtergrond volgt het thema. Hij stond vast op `Colors.white`, en dat
  /// was in donkere modus een wit vlak middenin een donkere interface: de
  /// gebalkte werkbalk boven het notitieveld. De tekst en de iconen komen
  /// mode-afhankelijk binnen (`notesText`/`userNotesText`, licht in donkere
  /// modus), dus ze landden bijna onzichtbaar op dat witte vlak — de tekst op
  /// 1,1:1, de iconen op 1,3:1 (#821). Met `paper` — dezelfde tint als de
  /// `fillColor` van het veld eronder — leest de lichte tekst op ~15:1 en de
  /// werkbalk hoort weer bij de rest.
  factory MarkdownEditorTheme.editorPanel({
    required Color text,
    required Color link,
    required Color accent,
    required Color codeBackground,
    required Color border,
    double fontSize = 12,
  }) {
    return MarkdownEditorTheme(
      surface: AppTheme.paper,
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

  /// Editor chrome derived entirely from the active [ColorScheme], so the
  /// word-processor honours the app theme instead of a hard-coded palette.
  ///
  /// The writing sheet is [ColorScheme.surfaceContainerLowest] and its text is
  /// [ColorScheme.onSurface] — a pair Material guarantees to contrast, in light
  /// and dark and under a custom appearance profile alike. It sits a tone apart
  /// from the dialog's own [ColorScheme.surface] so the page stays visible as a
  /// distinct writing area.
  factory MarkdownEditorTheme.documentSurface({
    required ColorScheme scheme,
    double fontSize = 15,
    String? fontFamily,
  }) {
    return MarkdownEditorTheme(
      surface: scheme.surfaceContainerLowest,
      text: scheme.onSurface,
      hint: scheme.onSurfaceVariant,
      link: scheme.primary,
      codeBackground: scheme.surfaceContainerHigh,
      toolbarIcon: scheme.onSurfaceVariant,
      accent: scheme.primary,
      border: scheme.outlineVariant,
      fontSize: fontSize,
      // Het lettertype van de gekozen documentstijl; `null` = het app-lettertype
      // (dan leest een plat document precies als voorheen).
      fontFamily: fontFamily,
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
      surface: darkPanel ? AppTheme.darkNeutral : Colors.white,
      text: darkPanel ? AppTheme.gray100 : AppTheme.slate800,
      hint: darkPanel ? AppTheme.gray400 : AppTheme.slate400,
      link: accent,
      codeBackground: darkPanel ? AppTheme.gray700 : AppTheme.slate100,
      toolbarIcon: darkPanel ? AppTheme.gray300 : AppTheme.slate500,
      accent: accent,
      border: panelText.withValues(alpha: 0.2),
      fontSize: 15,
      fontFamily: fontFamily,
    );
  }
}
