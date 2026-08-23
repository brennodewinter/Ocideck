import 'package:material_ui/material_ui.dart';

import '../../l10n/app_localizations.dart';
import 'markdown_editor_theme.dart';
import 'notes_editor_mode.dart';
import '../../theme/app_theme.dart';

enum NotesModeToggleStyle { standard, compact }

class NotesModeToggle extends StatelessWidget {
  final NotesEditorMode mode;
  final ValueChanged<NotesEditorMode> onModeChanged;
  final NotesModeToggleStyle style;
  final Color? foregroundColor;
  final Color? accentColor;

  const NotesModeToggle({
    super.key,
    required this.mode,
    required this.onModeChanged,
    this.style = NotesModeToggleStyle.standard,
    this.foregroundColor,
    this.accentColor,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final fg = foregroundColor ?? AppTheme.slate500;
    final accent = accentColor ?? AppTheme.accentFg;
    final compact = style == NotesModeToggleStyle.compact;
    final fontSize = compact ? 11.0 : 12.0;
    final padding = compact
        ? const EdgeInsets.symmetric(horizontal: 8, vertical: 4)
        : const EdgeInsets.symmetric(horizontal: 10, vertical: 6);

    Widget chip({
      required String label,
      required NotesEditorMode value,
      required IconData icon,
    }) {
      final selected = mode == value;
      return Tooltip(
        message: label,
        child: Material(
          color: selected ? accent.withValues(alpha: 0.12) : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
          child: InkWell(
            onTap: () => onModeChanged(value),
            borderRadius: BorderRadius.circular(6),
            child: Padding(
              padding: padding,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    icon,
                    size: compact ? 14 : 16,
                    color: selected ? accent : fg,
                  ),
                  if (!compact) ...[
                    const SizedBox(width: 4),
                    Text(
                      label,
                      style: TextStyle(
                        fontSize: fontSize,
                        fontWeight: selected
                            ? FontWeight.w600
                            : FontWeight.w500,
                        color: selected ? accent : fg,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      );
    }

    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: fg.withValues(alpha: 0.25)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(2),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            chip(
              label: l10n.t('visualMode'),
              value: NotesEditorMode.visual,
              icon: Icons.visibility_outlined,
            ),
            chip(
              label: l10n.t('markdownMode'),
              value: NotesEditorMode.markdown,
              icon: Icons.code,
            ),
          ],
        ),
      ),
    );
  }
}

/// Panel chrome for the mode toggle above the notes editor toolbar.
class NotesModeToggleBar extends StatelessWidget {
  final NotesEditorMode mode;
  final ValueChanged<NotesEditorMode> onModeChanged;
  final MarkdownEditorTheme theme;

  const NotesModeToggleBar({
    super.key,
    required this.mode,
    required this.onModeChanged,
    required this.theme,
  });

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: NotesModeToggle(
        mode: mode,
        onModeChanged: onModeChanged,
        foregroundColor: theme.toolbarIcon,
        accentColor: theme.accent,
      ),
    );
  }
}
