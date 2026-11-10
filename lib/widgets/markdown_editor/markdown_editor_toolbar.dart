import 'package:material_ui/material_ui.dart';

import '../../l10n/app_localizations.dart';
import 'markdown_editor_actions.dart';
import 'markdown_editor_theme.dart';

class MarkdownEditorToolbar extends StatelessWidget {
  final TextEditingController controller;
  final FocusNode? focusNode;
  final MarkdownEditorTheme theme;
  final bool compact;

  /// Draws the framed surface around the buttons. Off in the document editor,
  /// where the toolbar sits in a shared header instead of its own boxed strip.
  final bool bordered;

  /// Wanneer gezet: de Afbeelding-knop opent de kiezer i.p.v. een markdown-
  /// placeholder (`![beschrijving](pad-of-url)`) in de bron te dumpen.
  final VoidCallback? onInsertImage;

  /// Alleen de vier inline-opmaakknoppen (vet, cursief, doorhalen,
  /// onderstrepen) — voor de compacte titelbewerking (#2866), waar
  /// blokknoppen als lijst en kop niet bij een enkelregelig veld horen.
  final bool inlineOnly;

  const MarkdownEditorToolbar({
    super.key,
    required this.controller,
    this.focusNode,
    required this.theme,
    this.compact = false,
    this.bordered = true,
    this.onInsertImage,
    this.inlineOnly = false,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final buttons = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      child: Wrap(
        spacing: 2,
        runSpacing: 2,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: _buttons(l10n),
      ),
    );

    if (!bordered) return buttons;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: theme.surface,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: theme.border),
      ),
      child: buttons,
    );
  }

  Widget _button({
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
      iconSize: compact ? 16.0 : 18.0,
      padding: compact
          ? const EdgeInsets.symmetric(horizontal: 2, vertical: 2)
          : const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
      visualDensity: VisualDensity.compact,
      constraints: BoxConstraints(
        minWidth: compact ? 24 : 30,
        minHeight: compact ? 24 : 30,
      ),
    );
  }

  /// De knoppen van de balk. `inlineOnly` (#2866) beperkt de lijst tot de
  /// vier inline-opmaakknoppen die bij een enkelregelige titel horen —
  /// blokknoppen als kop en lijst passen daar niet.
  List<Widget> _buttons(AppLocalizations l10n) {
    return [
      _button(
        tooltip: l10n.d('Vet'),
        icon: Icons.format_bold,
        onPressed: () => MarkdownEditorActions.toggleInlineFormat(
          controller,
          before: '**',
          after: '**',
        ),
      ),
      _button(
        tooltip: l10n.d('Cursief'),
        icon: Icons.format_italic,
        onPressed: () => MarkdownEditorActions.toggleInlineFormat(
          controller,
          before: '*',
          after: '*',
        ),
      ),
      _button(
        tooltip: l10n.d('Doorhalen'),
        icon: Icons.format_strikethrough,
        onPressed: () => MarkdownEditorActions.toggleInlineFormat(
          controller,
          before: '~~',
          after: '~~',
        ),
      ),
      _button(
        tooltip: l10n.d('Onderstrepen'),
        icon: Icons.format_underlined,
        onPressed: () => MarkdownEditorActions.toggleInlineFormat(
          controller,
          before: '<u>',
          after: '</u>',
        ),
      ),
      if (!inlineOnly) ...[
        _button(
          tooltip: l10n.d('Code'),
          icon: Icons.code,
          onPressed: () => MarkdownEditorActions.wrapSelection(
            controller,
            before: '`',
            after: '`',
            placeholder: 'code',
          ),
        ),
        _button(
          tooltip: l10n.d('Link'),
          icon: Icons.link,
          onPressed: () => MarkdownEditorActions.insertLink(controller),
        ),
        _button(
          tooltip: l10n.d('Kop'),
          icon: Icons.title,
          onPressed: () => MarkdownEditorActions.toggleHeading(controller, 2),
        ),
        _button(
          tooltip: l10n.d('Opsomming'),
          icon: Icons.format_list_bulleted,
          onPressed: () => MarkdownEditorActions.toggleBullet(controller),
        ),
        _button(
          tooltip: l10n.d('Nummering'),
          icon: Icons.format_list_numbered,
          onPressed: () => MarkdownEditorActions.toggleNumbered(controller),
        ),
      ],
      if (!compact && !inlineOnly) ...[
        _button(
          tooltip: l10n.d('Citaat'),
          icon: Icons.format_quote,
          onPressed: () => MarkdownEditorActions.toggleQuote(controller),
        ),
        _button(
          tooltip: l10n.d('Code'),
          icon: Icons.data_object,
          onPressed: () => MarkdownEditorActions.insertCodeBlock(controller),
        ),
        _button(
          tooltip: l10n.d('Taak'),
          icon: Icons.check_box_outlined,
          onPressed: () => MarkdownEditorActions.insertTask(controller),
        ),
        _button(
          tooltip: l10n.d('Afbeelding'),
          icon: Icons.image_outlined,
          onPressed:
              onInsertImage ??
              () => MarkdownEditorActions.insertImage(controller),
        ),
        _button(
          tooltip: l10n.d('Tabel'),
          icon: Icons.table_chart_outlined,
          onPressed: () => MarkdownEditorActions.insertTable(controller),
        ),
      ],
    ];
  }
}
