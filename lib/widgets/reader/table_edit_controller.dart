import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../models/slide.dart' show TableAlign;
import '../../utils/table_cell_navigation.dart';
import '../../utils/table_clipboard.dart';

/// De bewerkstaat van één tabel die *in de weergave zelf* wordt ingevuld —
/// cel voor cel, op de plek waar de tabel straks ook staat, zoals in een
/// rekenblad.
///
/// De aanleiding: een tabel bewerken ging via een dialoog met losse velden van
/// gelijke breedte. Je zag daar niet wat je kreeg, en juist bij een tabel is de
/// vorm de helft van de leesbaarheid. Deze controller houdt de tekstvelden en
/// de focus vast; het tékenen blijft van `DocumentMarkdownView`, zodat de
/// bewerkbare tabel per definitie dezelfde kolomverdeling, randen, zebrastrepen
/// en huisstijl heeft als de gelezen tabel. Eén renderwereld, geen drift.
///
/// De eigenaar (de embed-bouwer of de editor) maakt hem, luistert op
/// [addListener] voor structuurwijzigingen, en ruimt hem op met [dispose].
class TableEditController extends ChangeNotifier {
  TableEditController({
    required List<List<String>> rows,
    required List<TableAlign> alignments,
    required this.onChanged,
  }) : _alignments = List<TableAlign>.from(alignments) {
    _adopt(rows);
  }

  /// Aangeroepen bij elke inhoudelijke wijziging — één keer per toetsaanslag,
  /// met het volledige raster. De aanroeper serialiseert dat terug naar GFM.
  final void Function(List<List<String>> rows, List<TableAlign> alignments)
  onChanged;

  late List<List<TextEditingController>> _cells;
  late List<List<FocusNode>> _nodes;
  List<TableAlign> _alignments;

  /// Cel die na de volgende opbouw focus moet pakken — nodig wanneer de cel
  /// zelf pas bij die opbouw ontstaat (Tab op de laatste cel maakt een rij bij).
  ({int row, int col})? _pendingFocus;

  /// De cel waar de cursor staat, of `null` als de tabel geen focus heeft. De
  /// werkbalk hangt hieraan: hij handelt op de cel waar je staat, zoals de
  /// rij-/kolomknoppen van een rekenblad.
  ({int row, int col})? _activeCell;
  ({int row, int col})? get activeCell => _activeCell;

  void setActiveCell(int r, int c, {required bool focused}) {
    if (focused) {
      _activeCell = (row: r, col: c);
    } else if (_activeCell == (row: r, col: c)) {
      _activeCell = null;
    } else {
      return;
    }
    notifyListeners();
  }

  int get rowCount => _cells.length;
  int get colCount => _cells.isEmpty ? 0 : _cells.first.length;
  List<TableAlign> get alignments => List<TableAlign>.unmodifiable(_alignments);

  /// Het raster als platte tekst — de bron voor serialisatie.
  List<List<String>> get rows => [
    for (final row in _cells) [for (final cell in row) cell.text],
  ];

  TextEditingController cellController(int r, int c) => _cells[r][c];
  FocusNode focusNode(int r, int c) => _nodes[r][c];

  /// Neemt [raw] over als raster, rechthoekig gemaakt op de langste rij. Een
  /// lege tabel krijgt een 2×2-start: iets om in te typen.
  void _adopt(List<List<String>> raw) {
    final source = raw.isEmpty
        ? <List<String>>[
            ['', ''],
            ['', ''],
          ]
        : raw;
    final cols = source.fold<int>(1, (m, r) => r.length > m ? r.length : m);
    _cells = [
      for (final row in source)
        [
          for (var c = 0; c < cols; c++)
            _makeController(c < row.length ? row[c] : ''),
        ],
    ];
    _nodes = [
      for (var r = 0; r < _cells.length; r++)
        [for (var c = 0; c < cols; c++) FocusNode()],
    ];
  }

  TextEditingController _makeController(String text) =>
      TextEditingController(text: text)..addListener(_emit);

  /// Wat er het laatst is doorgegeven, om een melding zonder wijziging te
  /// kunnen overslaan. Een [TextEditingController] meldt namelijk óók bij een
  /// verschuiving van de cursor of de selectie, en zo'n loze melding schreef
  /// de tabel opnieuw weg — met de vorige inhoud, want er was niets getypt.
  String? _lastEmitted;

  /// Meldt de wijziging én laat de tabel opnieuw tekenen. Dat tweede is geen
  /// luxe: de kolombreedtes worden uit de celinhoud berekend, dus zonder
  /// hertekenen zou de tabel pas ná het typen de goede vorm aannemen. Juist het
  /// meebewegen tijdens het typen is wat invullen-in-de-tabel oplevert.
  void _emit() {
    final current = rows;
    final fingerprint =
        '${alignments.map((a) => a.name).join(',')}'
        '\u0000${current.map((r) => r.join('\u0001')).join('\u0002')}';
    if (fingerprint == _lastEmitted) return;
    _lastEmitted = fingerprint;
    onChanged(current, alignments);
    notifyListeners();
  }

  void _emitAndRebuild() => _emit();

  /// Vraagt de opbouw om cel ([r], [c]) te focussen zodra ze bestaat. De
  /// weergave haalt dit op met [takePendingFocus].
  void _focusAfterRebuild(int r, int c) => _pendingFocus = (row: r, col: c);

  /// De cel die focus moet pakken na deze opbouw, of `null`. Eenmalig: een
  /// tweede aanroep geeft `null`, zodat een latere opbouw de focus niet opnieuw
  /// wegtrekt onder de cursor vandaan.
  ({int row, int col})? takePendingFocus() {
    final pending = _pendingFocus;
    _pendingFocus = null;
    return pending;
  }

  void focusCell(int r, int c, {TableCaret caret = TableCaret.selectAll}) {
    if (r < 0 || r >= _nodes.length || c < 0 || c >= _nodes[r].length) return;
    _nodes[r][c].requestFocus();
    final text = _cells[r][c].text;
    // Hele celinhoud selecteren bij het binnenkomen, zoals een rekenblad doet:
    // doortypen vervangt, een pijltje zet de cursor. Kom je met ← of → binnen,
    // dan is het juist tekst die doorloopt en hoort de cursor aan de kant te
    // staan waar je vandaan komt — daar zou selecteren je vorige woord wissen
    // zodra je verder typt.
    _cells[r][c].selection = switch (caret) {
      TableCaret.selectAll => TextSelection(
        baseOffset: 0,
        extentOffset: text.length,
      ),
      TableCaret.start => const TextSelection.collapsed(offset: 0),
      TableCaret.end => TextSelection.collapsed(offset: text.length),
    };
  }

  /// Toetsafhandeling op cel ([r], [c]). Tab loopt door de cellen en maakt op de
  /// laatste cel een rij bij; Enter springt naar dezelfde kolom een rij lager;
  /// de pijltjes lopen als in een rekenblad door de tabel (zie
  /// [tableArrowTarget]); plakken vult vanaf deze cel een heel raster.
  KeyEventResult handleCellKey(int r, int c, KeyEvent event) {
    final keys = HardwareKeyboard.instance;
    final meta = keys.isControlPressed || keys.isMetaPressed;
    final arrow = _arrowOf(event.logicalKey);
    // De pijltjes luisteren ook naar een ingehouden toets: een rij doorlopen
    // hoort niet per cel een nieuwe aanslag te kosten. De rest niet — een Tab
    // die rijen blijft bijmaken zolang je hem vasthoudt is geen dienst.
    if (arrow != null && (event is KeyDownEvent || event is KeyRepeatEvent)) {
      // Shift = selecteren, Ctrl/Cmd = per woord of naar het uiteinde: allebei
      // bewegingen bínnen de cel, die het tekstveld zelf hoort af te handelen.
      if (keys.isShiftPressed || meta) return KeyEventResult.ignored;
      return _moveByArrow(r, c, arrow);
    }
    if (event is! KeyDownEvent) return KeyEventResult.ignored;

    if (event.logicalKey == LogicalKeyboardKey.keyV && meta) {
      Clipboard.getData(Clipboard.kTextPlain).then((data) {
        final text = data?.text;
        if (text == null || text.isEmpty) return;
        pasteAt(r, c, text);
      });
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.keyC && meta) {
      final selection = _cells[r][c].selection;
      // Staat er tekst geselecteerd binnen de cel, dan is het kopiëren van díe
      // tekst bedoeld — cel en veld mogen niet om dezelfde Cmd+C vechten.
      if (selection.isValid && !selection.isCollapsed) {
        return KeyEventResult.ignored;
      }
      final tsv = encodeClipboardTable(rows);
      if (tsv.isNotEmpty) Clipboard.setData(ClipboardData(text: tsv));
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.tab) {
      if (keys.isShiftPressed) {
        final prev = prevTableCell(r, c, colCount);
        if (prev != null) focusCell(prev.row, prev.col);
        return KeyEventResult.handled;
      }
      final next = nextTableCell(r, c, rowCount, colCount);
      if (next == null) {
        insertRowAt(rowCount);
        _focusAfterRebuild(rowCount - 1, 0);
      } else {
        focusCell(next.row, next.col);
      }
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.enter && !keys.isShiftPressed) {
      // Enter = een rij lager, zoals in een rekenblad; onderaan groeit de
      // tabel mee. Een regeleinde binnen de cel maak je met Shift+Enter, dat
      // hier bewust doorgelaten wordt.
      if (r + 1 >= rowCount) {
        insertRowAt(rowCount);
        _focusAfterRebuild(rowCount - 1, c);
      } else {
        focusCell(r + 1, c);
      }
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  static TableArrow? _arrowOf(LogicalKeyboardKey key) => switch (key) {
    LogicalKeyboardKey.arrowLeft => TableArrow.left,
    LogicalKeyboardKey.arrowRight => TableArrow.right,
    LogicalKeyboardKey.arrowUp => TableArrow.up,
    LogicalKeyboardKey.arrowDown => TableArrow.down,
    _ => null,
  };

  /// Springt naar de buurcel wanneer de cursor aan de rand van de celinhoud
  /// staat, en laat de toets anders door naar het tekstveld.
  KeyEventResult _moveByArrow(int r, int c, TableArrow arrow) {
    final controller = _cells[r][c];
    final text = controller.text;
    final selection = controller.selection;
    // Zonder geldige selectie weet niemand waar de cursor staat; dan is
    // doorlaten het veilige antwoord.
    if (!selection.isValid) return KeyEventResult.ignored;
    final offset = selection.baseOffset.clamp(0, text.length);
    // Staat er iets geselecteerd, dan collabeert het pijltje die selectie —
    // dat is een beweging binnen de cel, niet eruit.
    final collapsed = selection.isCollapsed;
    final target = tableArrowTarget(
      arrow: arrow,
      row: r,
      col: c,
      rowCount: rowCount,
      colCount: colCount,
      atTextStart: collapsed && offset <= 0,
      atTextEnd: collapsed && offset >= text.length,
      onFirstLine: collapsed && !text.substring(0, offset).contains('\n'),
      onLastLine: collapsed && !text.substring(offset).contains('\n'),
    );
    return switch (target.move) {
      // Binnen de cel: het tekstveld zet de cursor zelf.
      TableArrowMove.inCell => KeyEventResult.ignored,
      TableArrowMove.toCell => () {
        focusCell(target.row, target.col, caret: target.caret);
        return KeyEventResult.handled;
      }(),
      // Aan de rand van de tabel gebeurt er niets — en dat "niets" moet hier
      // eindigen. Doorlaten betekende: door naar Quill, dat de cursor van het
      // document verzette terwijl de tekstinvoer aan deze cel hing (#1565).
      TableArrowMove.atEdge => KeyEventResult.handled,
    };
  }

  /// Plakt [text] vanaf cel ([r], [c]). Herkent de tekst zich als tabel (een
  /// rekenbladselectie, CSV, een Markdown-tabel), dan groeit het raster mee en
  /// wordt hij cel voor cel gevuld; anders is het gewoon tekst in deze cel.
  void pasteAt(int r, int c, String text) {
    final table = parseClipboardTable(text);
    if (table == null) {
      final ctrl = _cells[r][c];
      final value = ctrl.text;
      final sel = ctrl.selection;
      final start = sel.isValid ? sel.start : value.length;
      final end = sel.isValid ? sel.end : value.length;
      ctrl.value = TextEditingValue(
        text: value.replaceRange(start, end, text),
        selection: TextSelection.collapsed(offset: start + text.length),
      );
      return;
    }
    while (colCount < c + table.first.length) {
      insertColumnAt(colCount, silent: true);
    }
    while (rowCount < r + table.length) {
      insertRowAt(rowCount, silent: true);
    }
    for (var i = 0; i < table.length; i++) {
      for (var j = 0; j < table[i].length; j++) {
        final ctrl = _cells[r + i][c + j];
        // Zonder tussentijdse melding; één [_emitAndRebuild] sluit het af.
        ctrl.removeListener(_emit);
        ctrl.text = table[i][j];
        ctrl.addListener(_emit);
      }
    }
    _emitAndRebuild();
  }

  void insertRowAt(int at, {bool silent = false}) {
    final index = at.clamp(0, rowCount);
    _cells.insert(index, [
      for (var c = 0; c < colCount; c++) _makeController(''),
    ]);
    _nodes.insert(index, [for (var c = 0; c < colCount; c++) FocusNode()]);
    if (!silent) _emitAndRebuild();
  }

  /// Verwijdert rij [r]. De koprij blijft staan: een GFM-tabel zonder kop
  /// bestaat niet, en de laatste body-rij weghalen zou de tabel leegmaken.
  void removeRowAt(int r) {
    if (rowCount <= 2 || r <= 0 || r >= rowCount) return;
    for (final cell in _cells.removeAt(r)) {
      cell
        ..removeListener(_emit)
        ..dispose();
    }
    for (final node in _nodes.removeAt(r)) {
      node.dispose();
    }
    _emitAndRebuild();
  }

  void insertColumnAt(int at, {bool silent = false}) {
    final index = at.clamp(0, colCount);
    for (var r = 0; r < rowCount; r++) {
      _cells[r].insert(index, _makeController(''));
      _nodes[r].insert(index, FocusNode());
    }
    _alignments = [..._alignments]
      ..insert(index.clamp(0, _alignments.length), TableAlign.left);
    if (!silent) _emitAndRebuild();
  }

  void removeColumnAt(int c) {
    if (colCount <= 1 || c < 0 || c >= colCount) return;
    for (var r = 0; r < rowCount; r++) {
      _cells[r].removeAt(c)
        ..removeListener(_emit)
        ..dispose();
      _nodes[r].removeAt(c).dispose();
    }
    if (c < _alignments.length) _alignments = [..._alignments]..removeAt(c);
    _emitAndRebuild();
  }

  /// Verplaatst rij [r] met [delta] (−1 omhoog, +1 omlaag). De koprij blijft de
  /// kop: ze verplaatst niet en een body-rij komt er niet bovenuit.
  void moveRow(int r, int delta) {
    final target = r + delta;
    if (r <= 0 || target <= 0 || target >= rowCount) return;
    _cells.insert(target, _cells.removeAt(r));
    _nodes.insert(target, _nodes.removeAt(r));
    _emitAndRebuild();
  }

  void moveColumn(int c, int delta) {
    final target = c + delta;
    if (c < 0 || target < 0 || target >= colCount) return;
    for (var r = 0; r < rowCount; r++) {
      _cells[r].insert(target, _cells[r].removeAt(c));
      _nodes[r].insert(target, _nodes[r].removeAt(c));
    }
    if (c < _alignments.length && target < _alignments.length) {
      _alignments = [..._alignments]..insert(target, _alignments.removeAt(c));
    }
    _emitAndRebuild();
  }

  void setAlignment(int c, TableAlign align) {
    final next = [..._alignments];
    while (next.length <= c) {
      next.add(TableAlign.left);
    }
    next[c] = align;
    _alignments = next;
    _emitAndRebuild();
  }

  @override
  void dispose() {
    for (final row in _cells) {
      for (final cell in row) {
        cell
          ..removeListener(_emit)
          ..dispose();
      }
    }
    for (final row in _nodes) {
      for (final node in row) {
        node.dispose();
      }
    }
    super.dispose();
  }
}
