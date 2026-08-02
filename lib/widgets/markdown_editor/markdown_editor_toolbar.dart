import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import 'markdown_editor_actions.dart';
import 'markdown_editor_theme.dart';

class MarkdownEditorToolbar extends StatelessWidget {
  final TextEditingController controller;
  final FocusNode? focusNode;
  final MarkdownEditorTheme theme;
  final bool compact;

  const MarkdownEditorToolbar({
    super.key,
    required this.controller,
    this.focusNode,
    required this.theme,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final iconSize = compact ? 16.0 : 18.0;
    final padding = compact
        ? const EdgeInsets.symmetric(horizontal: 2, vertical: 2)
        : const EdgeInsets.symmetric(horizontal: 4, vertical: 4);

    Widget button({
      required String tooltip,
      required IconData icon,
      required VoidCallback onPressed,
    }) {
      return IconButton(
        tooltip: tooltip,
        onPressed: () {
          onPressed();
          final target = focusNode;
          if (target != null) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (target.canRequestFocus) target.requestFocus();
            });
          }
        },
        icon: Icon(icon, color: theme.toolbarIcon),
        iconSize: iconSize,
        padding: padding,
        visualDensity: VisualDensity.compact,
        constraints: BoxConstraints(
          minWidth: compact ? 24 : 30,
          minHeight: compact ? 24 : 30,
        ),
      );
    }

    return DecoratedBox(
      decoration: BoxDecoration(
        color: theme.surface,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: theme.border),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
        child: Wrap(
          spacing: 2,
          runSpacing: 2,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            button(
              tooltip: l10n.d('Vet'),
              icon: Icons.format_bold,
              onPressed: () => MarkdownEditorActions.wrapSelection(
                controller,
                before: '**',
                after: '**',
                placeholder: 'tekst',
              ),
            ),
            button(
              tooltip: l10n.d('Cursief'),
              icon: Icons.format_italic,
              onPressed: () => MarkdownEditorActions.wrapSelection(
                controller,
                before: '*',
                after: '*',
                placeholder: 'tekst',
              ),
            ),
            button(
              tooltip: l10n.d('Doorhalen'),
              icon: Icons.format_strikethrough,
              onPressed: () => MarkdownEditorActions.wrapSelection(
                controller,
                before: '~~',
                after: '~~',
                placeholder: 'tekst',
              ),
            ),
            button(
              tooltip: l10n.d('Code'),
              icon: Icons.code,
              onPressed: () => MarkdownEditorActions.wrapSelection(
                controller,
                before: '`',
                after: '`',
                placeholder: 'code',
              ),
            ),
            button(
              tooltip: l10n.d('Link'),
              icon: Icons.link,
              onPressed: () => MarkdownEditorActions.insertLink(controller),
            ),
            button(
              tooltip: l10n.d('Kop'),
              icon: Icons.title,
              onPressed: () =>
                  MarkdownEditorActions.toggleHeading(controller, 2),
            ),
            button(
              tooltip: l10n.d('Opsomming'),
              icon: Icons.format_list_bulleted,
              onPressed: () => MarkdownEditorActions.toggleBullet(controller),
            ),
            button(
              tooltip: l10n.d('Nummering'),
              icon: Icons.format_list_numbered,
              onPressed: () => MarkdownEditorActions.toggleNumbered(controller),
            ),
            if (!compact) ...[
              button(
                tooltip: l10n.d('Citaat'),
                icon: Icons.format_quote,
                onPressed: () => MarkdownEditorActions.toggleQuote(controller),
              ),
              button(
                tooltip: l10n.d('Code'),
                icon: Icons.data_object,
                onPressed: () =>
                    MarkdownEditorActions.insertCodeBlock(controller),
              ),
              button(
                tooltip: l10n.d('Taak'),
                icon: Icons.check_box_outlined,
                onPressed: () => MarkdownEditorActions.insertTask(controller),
              ),
              button(
                tooltip: l10n.d('Afbeelding'),
                icon: Icons.image_outlined,
                onPressed: () => MarkdownEditorActions.insertImage(controller),
              ),
              button(
                tooltip: l10n.d('Tabel'),
                icon: Icons.table_chart_outlined,
                onPressed: () => MarkdownEditorActions.insertTable(controller),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
