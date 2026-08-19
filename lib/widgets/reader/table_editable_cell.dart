import 'package:flutter/material.dart';

import '../markdown_editor/embedded_field_actions.dart';
import '../slides/inline_markdown.dart';
import 'table_edit_controller.dart';

/// Eén invulbare cel binnen de gerenderde tabel.
///
/// Bewust chroomloos: geen kader, geen achtergrond, geen eigen marge. De cel
/// gebruikt exact de tekststijl en celmarge van de gelezen tabel, zodat je bij
/// het typen ziet wat je krijgt — inclusief de kolombreedte die de tabel op dat
/// moment kiest. Dat laatste is precies wat een tabel in Markdown boven een
/// dialoog met losse velden uittilt: hij herschikt terwijl je typt.
///
/// De cel waar je niet in staat, **leest** zoals hij gedrukt wordt: `**vet**` is
/// vet en `` `code` `` is code. Alleen de cel waar de cursor in staat toont zijn
/// Markdown, want dat is wat je op dat moment bewerkt. Zonder dat onderscheid
/// bleven de sterretjes in de visuele stand zichtbaar terwijl het voorbeeld bij
/// de bron ze netjes opmaakte — twee weergaven van hetzelfde document die er
/// anders uitzagen (#1567).
class TableEditableCell extends StatelessWidget {
  const TableEditableCell({
    super.key,
    required this.editor,
    required this.row,
    required this.column,
    required this.style,
    required this.pad,
    required this.caretColor,
    required this.linkColor,
    this.codeBackground,
    this.textAlign = TextAlign.start,
  });

  final TableEditController editor;
  final int row;
  final int column;
  final TextStyle style;
  final TextAlign textAlign;
  final double pad;
  final Color caretColor;
  final Color linkColor;
  final Color? codeBackground;

  EdgeInsets get _padding =>
      EdgeInsets.symmetric(horizontal: pad + 4, vertical: pad * 0.6);

  @override
  Widget build(BuildContext context) {
    final focus = editor.focusNode(row, column);
    final editing = editor.activeCell == (row: row, col: column);
    // De cel staat in de visuele editor binnen een Quill-embed; zonder deze
    // wikkel voert Quill de tekstbewerking van deze cel uit, met de inhoud van
    // het hele document. Zie [EmbeddedFieldActions] (#1565).
    return EmbeddedFieldActions(
      child: Focus(
        // De toetsen die een cel tot cel maken (Tab, Enter, plakken van een heel
        // raster) worden hier afgevangen vóór het tekstveld ze ziet.
        onKeyEvent: (_, event) => editor.handleCellKey(row, column, event),
        onFocusChange: (has) => editor.setActiveCell(row, column, focused: has),
        // Het tekstveld staat er altíjd — het draagt de focus, de cursor en de
        // maat van de rij. Alleen zijn tekst wordt onzichtbaar gemaakt zolang je
        // er niet in staat, en dan ligt de opgemaakte lezing eroverheen. Zo
        // verspringt er niets op het moment dat je erin klikt, en blijft
        // klikken, tabben en pijltjes werken zoals ze deden.
        child: Stack(
          // Beide lagen krijgen dezelfde breedte als de cel, en de cel wordt zo
          // hoog als de hoogste van de twee. Zonder dat laatste sneed de rij de
          // staarten van de letters af zodra de opgemaakte lezing een haar
          // hoger uitkwam dan het tekstveld.
          fit: StackFit.passthrough,
          children: [
            _field(focus, hideText: !editing),
            if (!editing)
              // Doorklikbaar: de tik hoort bij het veld eronder, dat er de
              // cursor van krijgt. En onhoorbaar voor de schermlezer, want het
              // veld zegt dit al.
              IgnorePointer(
                child: ExcludeSemantics(
                  child: Padding(
                    padding: _padding,
                    child: InlineMarkdownText(
                      editor.cellController(row, column).text,
                      style: style,
                      linkColor: linkColor,
                      codeBackground: codeBackground,
                      textAlign: textAlign,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _field(FocusNode focus, {required bool hideText}) => TextField(
    controller: editor.cellController(row, column),
    focusNode: focus,
    // Onzichtbaar, niet afwezig: de tekst blijft de kolombreedte en de
    // rijhoogte bepalen zoals ze in de bron staat.
    style: hideText ? style.copyWith(color: Colors.transparent) : style,
    textAlign: textAlign,
    cursorColor: caretColor,
    maxLines: null,
    // Enter navigeert (zie de controller); een regeleinde binnen de cel
    // maak je met Shift+Enter.
    keyboardType: TextInputType.multiline,
    decoration: InputDecoration(
      isDense: true,
      border: InputBorder.none,
      enabledBorder: InputBorder.none,
      focusedBorder: InputBorder.none,
      filled: false,
      contentPadding: _padding,
    ),
  );
}
