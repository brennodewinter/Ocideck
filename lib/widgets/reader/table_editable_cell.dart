import 'package:flutter/material.dart';

import 'table_edit_controller.dart';

/// Eén invulbare cel binnen de gerenderde tabel.
///
/// Bewust chroomloos: geen kader, geen achtergrond, geen eigen marge. De cel
/// gebruikt exact de tekststijl en celmarge van de gelezen tabel, zodat je bij
/// het typen ziet wat je krijgt — inclusief de kolombreedte die de tabel op dat
/// moment kiest. Dat laatste is precies wat een tabel in Markdown boven een
/// dialoog met losse velden uittilt: hij herschikt terwijl je typt.
class TableEditableCell extends StatelessWidget {
  const TableEditableCell({
    super.key,
    required this.editor,
    required this.row,
    required this.column,
    required this.style,
    required this.pad,
    required this.caretColor,
    this.textAlign = TextAlign.start,
  });

  final TableEditController editor;
  final int row;
  final int column;
  final TextStyle style;
  final TextAlign textAlign;
  final double pad;
  final Color caretColor;

  @override
  Widget build(BuildContext context) {
    final focus = editor.focusNode(row, column);
    return Focus(
      // De toetsen die een cel tot cel maken (Tab, Enter, plakken van een heel
      // raster) worden hier afgevangen vóór het tekstveld ze ziet.
      onKeyEvent: (_, event) => editor.handleCellKey(row, column, event),
      onFocusChange: (has) => editor.setActiveCell(row, column, focused: has),
      child: TextField(
        controller: editor.cellController(row, column),
        focusNode: focus,
        style: style,
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
          contentPadding: EdgeInsets.symmetric(
            horizontal: pad + 4,
            vertical: pad * 0.6,
          ),
        ),
      ),
    );
  }
}
