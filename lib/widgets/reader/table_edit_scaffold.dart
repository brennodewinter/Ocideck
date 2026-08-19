import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../l10n/app_localizations.dart';
import '../../models/slide.dart' show TableAlign;
import 'table_edit_controller.dart';

enum TableSortIntent { ascending, descending, choose }

/// Zet de invulbare tabel in zijn omhulsel: hij tekent opnieuw wanneer de
/// structuur wijzigt, en toont een werkbalk zodra de cursor in een cel staat.
///
/// De werkbalk handelt op de cel waar je staat — rij erboven/eronder, kolom
/// links/rechts, weghalen, uitlijnen. Dat is de bediening van een rekenblad:
/// geen aparte dialoog met losse velden, maar knoppen die gaan over de plek
/// waar je op dat moment typt. Staat de cursor niet in de tabel, dan is de
/// werkbalk weg en leest de tabel als een gewone tabel.
class TableEditScaffold extends StatelessWidget {
  const TableEditScaffold({
    super.key,
    required this.editor,
    required this.builder,
    this.onSort,
  });

  final TableEditController editor;

  /// De tabel wordt hier *opnieuw opgebouwd* bij elke wijziging, niet als kant
  /// en klare widget doorgegeven: de kolombreedtes volgen uit de celinhoud, dus
  /// een tabel die niet hertekent zou tijdens het typen op de oude maten
  /// blijven staan.
  final WidgetBuilder builder;
  final void Function(int column, TableSortIntent intent)? onSort;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: editor,
      builder: (context, _) {
        final active = editor.activeCell;
        _restorePendingFocus();
        return CallbackShortcuts(
          bindings: active == null || onSort == null
              ? const {}
              : {
                  SingleActivator(
                    LogicalKeyboardKey.arrowUp,
                    alt: true,
                    shift: true,
                  ): () =>
                      onSort!(active.col, TableSortIntent.ascending),
                  SingleActivator(
                    LogicalKeyboardKey.arrowDown,
                    alt: true,
                    shift: true,
                  ): () =>
                      onSort!(active.col, TableSortIntent.descending),
                  SingleActivator(
                    LogicalKeyboardKey.keyS,
                    alt: true,
                    shift: true,
                  ): () =>
                      onSort!(active.col, TableSortIntent.choose),
                },
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (active != null) _toolbar(context, active),
              builder(context),
            ],
          ),
        );
      },
    );
  }

  /// Focus zetten die pas ná deze opbouw kán: de cel die Tab of Enter zojuist
  /// heeft bijgemaakt bestaat nu pas als widget.
  void _restorePendingFocus() {
    final pending = editor.takePendingFocus();
    if (pending == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      editor.focusCell(pending.row, pending.col);
    });
  }

  Widget _toolbar(BuildContext context, ({int row, int col}) at) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      // De werkbalk mag de focus niet uit de cel trekken: anders verdwijnt hij
      // onder je handen vandaan op het moment dat je hem aanklikt.
      child: ExcludeFocus(
        child: Wrap(
          spacing: 0,
          runSpacing: 2,
          children: [
            _button(
              context,
              Icons.keyboard_arrow_up,
              l10n.d('Rij erboven'),
              () => editor.insertRowAt(at.row),
            ),
            _button(
              context,
              Icons.keyboard_arrow_down,
              l10n.d('Rij eronder'),
              () => editor.insertRowAt(at.row + 1),
            ),
            _button(
              context,
              Icons.remove,
              l10n.d('Rij weghalen'),
              // De koprij blijft staan: een GFM-tabel zonder kop bestaat niet.
              at.row == 0 ? null : () => editor.removeRowAt(at.row),
            ),
            // Verplaatsen hoort hier thuis, niet alleen in de tabel-editor:
            // een rij een plek omhoog schuiven is bij het schrijven net zo
            // gewoon als er een bijmaken.
            _button(
              context,
              Icons.arrow_upward,
              l10n.d('Rij omhoog'),
              // De koprij blijft boven; een body-rij komt er niet overheen.
              at.row <= 1 ? null : () => editor.moveRow(at.row, -1),
            ),
            _button(
              context,
              Icons.arrow_downward,
              l10n.d('Rij omlaag'),
              at.row == 0 || at.row >= editor.rowCount - 1
                  ? null
                  : () => editor.moveRow(at.row, 1),
            ),
            _divider(theme),
            _button(
              context,
              Icons.sort_by_alpha,
              l10n.d('Kolom oplopend sorteren'),
              onSort == null
                  ? null
                  : () => onSort!(at.col, TableSortIntent.ascending),
            ),
            _button(
              context,
              Icons.sort_by_alpha,
              l10n.d('Kolom aflopend sorteren'),
              onSort == null
                  ? null
                  : () => onSort!(at.col, TableSortIntent.descending),
              descending: true,
            ),
            _button(
              context,
              Icons.tune,
              l10n.d('Sorteren als…'),
              onSort == null
                  ? null
                  : () => onSort!(at.col, TableSortIntent.choose),
            ),
            _divider(theme),
            _button(
              context,
              Icons.keyboard_arrow_left,
              l10n.d('Kolom links'),
              () => editor.insertColumnAt(at.col),
            ),
            _button(
              context,
              Icons.keyboard_arrow_right,
              l10n.d('Kolom rechts'),
              () => editor.insertColumnAt(at.col + 1),
            ),
            _button(
              context,
              Icons.remove,
              l10n.d('Kolom weghalen'),
              editor.colCount <= 1 ? null : () => editor.removeColumnAt(at.col),
            ),
            _button(
              context,
              Icons.arrow_back,
              l10n.d('Kolom naar links'),
              at.col == 0 ? null : () => editor.moveColumn(at.col, -1),
            ),
            _button(
              context,
              Icons.arrow_forward,
              l10n.d('Kolom naar rechts'),
              at.col >= editor.colCount - 1
                  ? null
                  : () => editor.moveColumn(at.col, 1),
            ),
            _divider(theme),
            _alignButton(
              context,
              at.col,
              TableAlign.left,
              Icons.format_align_left,
              l10n.d('Links uitlijnen'),
            ),
            _alignButton(
              context,
              at.col,
              TableAlign.center,
              Icons.format_align_center,
              l10n.d('Centreren'),
            ),
            _alignButton(
              context,
              at.col,
              TableAlign.right,
              Icons.format_align_right,
              l10n.d('Rechts uitlijnen'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _divider(ThemeData theme) => Container(
    width: 1,
    height: 18,
    margin: const EdgeInsets.symmetric(horizontal: 4),
    color: theme.colorScheme.outlineVariant,
  );

  Widget _alignButton(
    BuildContext context,
    int column,
    TableAlign align,
    IconData icon,
    String tooltip,
  ) {
    final current = column < editor.alignments.length
        ? editor.alignments[column]
        : TableAlign.left;
    return _button(
      context,
      icon,
      tooltip,
      () => editor.setAlignment(column, align),
      selected: current == align,
    );
  }

  Widget _button(
    BuildContext context,
    IconData icon,
    String tooltip,
    VoidCallback? onPressed, {
    bool selected = false,
    bool descending = false,
  }) => IconButton(
    onPressed: onPressed,
    icon: Transform.flip(flipY: descending, child: Icon(icon, size: 16)),
    tooltip: tooltip,
    visualDensity: VisualDensity.compact,
    padding: const EdgeInsets.all(4),
    constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
    color: selected ? Theme.of(context).colorScheme.primary : null,
  );
}
