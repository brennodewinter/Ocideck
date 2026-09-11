// Part of the chart_editor library — see chart_editor.dart.
// Split out for navigability (data-grid + cell/field builder widgets); all
// imports live in the main library file. Pure builder methods (no setState),
// relocated verbatim into an extension in the same library.
part of 'chart_editor.dart';

extension _ChartEditorGrid on _ChartEditorState {
  Widget _grid({required bool enabled, required double availableWidth}) {
    final cols = _seriesNames.length;
    const trailingWidth = 40.0;
    final labelWidth = math.max(
      _ChartEditorState._minLabelW,
      availableWidth * 0.28,
    );
    final remaining = availableWidth - labelWidth - trailingWidth;
    final cellWidth = math.max(_ChartEditorState._minCellW, remaining / cols);
    final gridWidth = math.max(
      availableWidth,
      labelWidth + cellWidth * cols + trailingWidth,
    );
    _restoreChartFocus();
    return SizedBox(
      key: const ValueKey('chart-grid'),
      width: gridWidth,
      // Tab volgt de leesvolgorde van het raster (cellen links-naar-rechts,
      // rij voor rij) in plaats van de toevallige focusvolgorde van de tree.
      child: FocusTraversalGroup(
        policy: ReadingOrderTraversalPolicy(),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header row: empty label cell + series name fields.
            Row(
              children: [
                SizedBox(
                  width: labelWidth,
                  child: Row(
                    children: [
                      Expanded(child: _headerHint(context.l10n.d('Label'))),
                      _sortButton(column: null, enabled: enabled),
                    ],
                  ),
                ),
                for (var c = 0; c < cols; c++)
                  Container(
                    key: ValueKey('chart-series-column-$c'),
                    width: cellWidth,
                    color: _isPieLike && c >= 2 ? AppTheme.slate200 : null,
                    child: Row(
                      children: [
                        IconButton(
                          onPressed: enabled ? () => _pickSeriesColor(c) : null,
                          tooltip: context.l10n.d('Kleur van reeks'),
                          icon: Container(
                            width: 16,
                            height: 16,
                            decoration: BoxDecoration(
                              color: Color(
                                _isPieLike && c >= 2
                                    ? 0xFF64748B
                                    : int.parse(
                                            chartSeriesColor(
                                              ChartSeries(
                                                name: '',
                                                data: const [],
                                                color: _seriesColors[c],
                                              ),
                                              c,
                                            ).substring(1),
                                            radix: 16,
                                          ) |
                                          0xFF000000,
                              ),
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: Colors.white,
                                width: 1.5,
                              ),
                              boxShadow: const [
                                BoxShadow(
                                  color: AppTheme.inkOverlay,
                                  blurRadius: 2,
                                ),
                              ],
                            ),
                          ),
                          visualDensity: VisualDensity.compact,
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(
                            minWidth: 24,
                            minHeight: 32,
                          ),
                        ),
                        Expanded(
                          child: _cell(
                            key: ValueKey('s-$_rev-$c'),
                            gridRow: 0,
                            gridCol: c + 1,
                            value: _seriesNames[c],
                            enabled: enabled,
                            onChanged: (v) => _seriesNames[c] = v,
                            bold: true,
                            muted: _isPieLike && c >= 2,
                          ),
                        ),
                        _sortButton(column: c, enabled: enabled),
                        if (enabled && cols > 1)
                          _iconBtn(
                            Icons.close,
                            () => _removeColumn(c),
                            tooltip: context.l10n.d('Kolom verwijderen'),
                          ),
                      ],
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 4),
            // Data rows.
            for (var r = 0; r < _xLabels.length; r++)
              _dataRow(
                r,
                enabled: enabled,
                cols: cols,
                labelWidth: labelWidth,
                cellWidth: cellWidth,
              ),
          ],
        ),
      ),
    );
  }

  Widget _dataRow(
    int r, {
    required bool enabled,
    required int cols,
    required double labelWidth,
    required double cellWidth,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          SizedBox(
            width: labelWidth,
            child: Row(
              children: [
                IconButton(
                  key: ValueKey('chart-row-color-$r'),
                  onPressed: enabled ? () => _pickRowColor(r) : null,
                  tooltip: context.l10n.d('Kleur van rij'),
                  icon: _colorDot(
                    _rowColors[r] ??
                        chartColorPalette[r % chartColorPalette.length],
                  ),
                  visualDensity: VisualDensity.compact,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(
                    minWidth: 26,
                    minHeight: 32,
                  ),
                ),
                Expanded(
                  child: _cell(
                    key: ValueKey('x-$_rev-$r'),
                    gridRow: r + 1,
                    gridCol: 0,
                    value: _xLabels[r],
                    enabled: enabled,
                    onChanged: (v) => _xLabels[r] = v,
                  ),
                ),
                if (enabled) ...[
                  _iconBtn(
                    Icons.keyboard_arrow_up,
                    r == 0 ? null : () => _moveRow(r, r - 1),
                    key: ValueKey('chart-row-up-$r'),
                    tooltip: context.l10n.d('Rij omhoog'),
                  ),
                  _iconBtn(
                    Icons.keyboard_arrow_down,
                    r == _xLabels.length - 1 ? null : () => _moveRow(r, r + 1),
                    key: ValueKey('chart-row-down-$r'),
                    tooltip: context.l10n.d('Rij omlaag'),
                  ),
                ],
              ],
            ),
          ),
          for (var c = 0; c < cols; c++)
            Container(
              width: cellWidth,
              color: _isPieLike && c >= 2 ? AppTheme.slate200 : null,
              child: _cell(
                key: ValueKey('v-$_rev-$r-$c'),
                gridRow: r + 1,
                gridCol: c + 1,
                value: c < _values[r].length ? _values[r][c] : '',
                enabled: enabled,
                number: true,
                muted: _isPieLike && c >= 2,
                onChanged: (v) {
                  while (_values[r].length <= c) {
                    _values[r].add('');
                  }
                  _values[r][c] = v;
                },
              ),
            ),
          if (enabled && _xLabels.length > 1)
            _iconBtn(
              Icons.close,
              () => _removeRow(r),
              tooltip: context.l10n.d('Rij verwijderen'),
            ),
        ],
      ),
    );
  }

  Widget _boundField({
    required Key key,
    required TextEditingController controller,
    required String label,
  }) => TextField(
    key: key,
    controller: controller,
    keyboardType: const TextInputType.numberWithOptions(
      decimal: true,
      signed: true,
    ),
    inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,\-]'))],
    style: const TextStyle(fontSize: 12),
    decoration: InputDecoration(
      labelText: label,
      labelStyle: TextStyle(fontSize: 12, color: AppTheme.slate500),
      hintText: context.l10n.d('geen'),
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
      border: const OutlineInputBorder(),
    ),
  );

  Widget _headerHint(String text) => Padding(
    padding: const EdgeInsets.only(left: 4, bottom: 4),
    child: Text(
      text,
      style: TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w600,
        color: AppTheme.slate500,
      ),
    ),
  );

  Widget _sortButton({required int? column, required bool enabled}) {
    return PopupMenuButton<bool>(
      key: ValueKey('chart-sort-${column ?? 'label'}'),
      enabled: enabled,
      tooltip: context.l10n.d('Sorteren'),
      icon: Icon(Icons.sort, size: 15, color: AppTheme.slate500),
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(minWidth: 24, minHeight: 28),
      itemBuilder: (context) => [
        PopupMenuItem(
          value: true,
          child: Text(context.l10n.d('Oplopend sorteren')),
        ),
        PopupMenuItem(
          value: false,
          child: Text(context.l10n.d('Aflopend sorteren')),
        ),
      ],
      onSelected: (ascending) =>
          _sortRows(column: column, ascending: ascending),
    );
  }

  Widget _colorDot(String hex) => Container(
    width: 16,
    height: 16,
    decoration: BoxDecoration(
      color: Color(int.parse(hex.substring(1), radix: 16) | 0xFF000000),
      shape: BoxShape.circle,
      border: Border.all(color: Colors.white, width: 1.5),
      boxShadow: const [BoxShadow(color: AppTheme.inkOverlay, blurRadius: 2)],
    ),
  );

  Widget _cell({
    required Key key,
    required int gridRow,
    required int gridCol,
    required String value,
    required bool enabled,
    required ValueChanged<String> onChanged,
    bool number = false,
    bool bold = false,
    bool muted = false,
  }) {
    return _ChartGridCell(
      key: key,
      focusNode: _ChartGridKeys.focus(this, gridRow, gridCol),
      value: value,
      enabled: enabled,
      number: number,
      bold: bold,
      muted: muted,
      onChanged: (v) {
        onChanged(v);
        _emit();
      },
      onKey: (event, ctrl) =>
          _ChartGridKeys.onKey(this, gridRow, gridCol, event, ctrl),
    );
  }

  void _restoreChartFocus() => _ChartGridKeys.restore(this);

  Widget _iconBtn(
    IconData icon,
    VoidCallback? onTap, {
    Key? key,
    String? tooltip,
  }) => IconButton(
    key: key,
    onPressed: onTap,
    tooltip: tooltip,
    icon: Icon(icon, size: 14),
    color: AppTheme.slate500,
    visualDensity: VisualDensity.compact,
    padding: EdgeInsets.zero,
    constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
  );
}

/// Toetsen van het grafiekdataraster, buiten [_ChartEditorState]: Tab, Enter,
/// pijlen en plakken horen bij het raster, niet bij de rest van de editor.
class _ChartGridKeys {
  static int rows(_ChartEditorState s) => 1 + s._xLabels.length;
  static int cols(_ChartEditorState s) => 1 + s._seriesNames.length;

  static FocusNode focus(_ChartEditorState s, int row, int col) {
    final id = row == 0
        ? 'h-$col'
        : (col == 0 ? 'x-${row - 1}' : 'v-${row - 1}-${col - 1}');
    return s._gridFocus.putIfAbsent(id, FocusNode.new);
  }

  static void restore(_ChartEditorState s) {
    final pending = s._pendingChartFocus;
    if (pending == null) return;
    s._pendingChartFocus = null;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!s.mounted) return;
      focus(s, pending.row, pending.col).requestFocus();
    });
  }

  static void _focusCell(_ChartEditorState s, int row, int col) {
    if (row == 0 && col == 0) return;
    if (row < 0 || col < 0 || row >= rows(s) || col >= cols(s)) return;
    focus(s, row, col).requestFocus();
  }

  static KeyEventResult onKey(
    _ChartEditorState s,
    int row,
    int col,
    KeyEvent event,
    TextEditingController ctrl,
  ) {
    final keys = HardwareKeyboard.instance;
    final meta = keys.isControlPressed || keys.isMetaPressed;
    final arrow = switch (event.logicalKey) {
      LogicalKeyboardKey.arrowLeft => TableArrow.left,
      LogicalKeyboardKey.arrowRight => TableArrow.right,
      LogicalKeyboardKey.arrowUp => TableArrow.up,
      LogicalKeyboardKey.arrowDown => TableArrow.down,
      _ => null,
    };
    if (arrow != null &&
        (event is KeyDownEvent || event is KeyRepeatEvent) &&
        !keys.isShiftPressed &&
        !meta) {
      return _moveByArrow(s, row, col, arrow, ctrl);
    }
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    return _onDown(s, row, col, event, ctrl, meta: meta, keys: keys);
  }

  static KeyEventResult _onDown(
    _ChartEditorState s,
    int row,
    int col,
    KeyDownEvent event,
    TextEditingController ctrl, {
    required bool meta,
    required HardwareKeyboard keys,
  }) {
    final pasteCombo =
        (event.logicalKey == LogicalKeyboardKey.keyV && meta) ||
        (event.logicalKey == LogicalKeyboardKey.insert && keys.isShiftPressed);
    if (pasteCombo) {
      Clipboard.getData(Clipboard.kTextPlain).then((data) {
        final text = data?.text;
        if (text == null || text.isEmpty) return;
        if (!_pasteAt(s, row, col, text)) {
          _writeCell(s, row, col, text, ctrl);
        }
      });
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.tab) {
      return _onTab(s, row, col, shift: keys.isShiftPressed);
    }
    if (event.logicalKey == LogicalKeyboardKey.enter && !keys.isShiftPressed) {
      if (row + 1 >= rows(s)) {
        s._pendingChartFocus = (row: s._xLabels.length + 1, col: col);
        s._addRow();
      } else {
        _focusCell(s, row + 1, col);
      }
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  static KeyEventResult _onTab(
    _ChartEditorState s,
    int row,
    int col, {
    required bool shift,
  }) {
    if (shift) {
      final prev = prevTableCell(row, col, cols(s));
      if (prev != null && !(prev.row == 0 && prev.col == 0)) {
        _focusCell(s, prev.row, prev.col);
      }
      return KeyEventResult.handled;
    }
    final next = nextTableCell(row, col, rows(s), cols(s));
    if (next == null) {
      s._pendingChartFocus = (row: s._xLabels.length + 1, col: 0);
      s._addRow();
    } else if (!(next.row == 0 && next.col == 0)) {
      _focusCell(s, next.row, next.col);
    }
    return KeyEventResult.handled;
  }

  static KeyEventResult _moveByArrow(
    _ChartEditorState s,
    int row,
    int col,
    TableArrow arrow,
    TextEditingController ctrl,
  ) {
    final text = ctrl.text;
    final selection = ctrl.selection;
    if (!selection.isValid) return KeyEventResult.ignored;
    final offset = selection.baseOffset.clamp(0, text.length);
    final collapsed = selection.isCollapsed;
    final target = tableArrowTarget(
      arrow: arrow,
      row: row,
      col: col,
      rowCount: rows(s),
      colCount: cols(s),
      atTextStart: collapsed && offset <= 0,
      atTextEnd: collapsed && offset >= text.length,
      onFirstLine: collapsed && !text.substring(0, offset).contains('\n'),
      onLastLine: collapsed && !text.substring(offset).contains('\n'),
    );
    return switch (target.move) {
      TableArrowMove.inCell => KeyEventResult.ignored,
      TableArrowMove.toCell => () {
        if (target.row == 0 && target.col == 0) {
          return KeyEventResult.handled;
        }
        _focusCell(s, target.row, target.col);
        return KeyEventResult.handled;
      }(),
      TableArrowMove.atEdge => KeyEventResult.handled,
    };
  }

  /// `false` = geen tabel op het klembord; de aanroeper plakt in de cel.
  static bool _pasteAt(_ChartEditorState s, int row, int col, String text) {
    final table = parseClipboardTable(text);
    if (table == null) return false;
    var startRow = row;
    var startCol = col;
    if (startRow == 0 && startCol == 0) {
      startRow = 1;
      startCol = 0;
    }
    while (cols(s) < startCol + table.first.length) {
      s._seriesNames.add('Reeks ${s._seriesNames.length + 1}');
      s._seriesColors.add(null);
      for (final values in s._values) {
        values.add('');
      }
    }
    while (rows(s) < startRow + table.length) {
      s._xLabels.add('');
      s._rowColors.add(null);
      s._values.add(
        List<String>.filled(s._seriesNames.length, '', growable: true),
      );
    }
    for (var i = 0; i < table.length; i++) {
      for (var j = 0; j < table[i].length; j++) {
        _setValue(s, startRow + i, startCol + j, table[i][j]);
      }
    }
    s._bump();
    s._emit();
    return true;
  }

  static void _writeCell(
    _ChartEditorState s,
    int row,
    int col,
    String text,
    TextEditingController ctrl,
  ) {
    final value = ctrl.text;
    final sel = ctrl.selection;
    final start = sel.isValid ? sel.start : value.length;
    final end = sel.isValid ? sel.end : value.length;
    ctrl.value = TextEditingValue(
      text: value.replaceRange(start, end, text),
      selection: TextSelection.collapsed(offset: start + text.length),
    );
    _setValue(s, row, col, ctrl.text);
    s._emit();
  }

  static void _setValue(_ChartEditorState s, int row, int col, String value) {
    if (row == 0) {
      if (col <= 0) return;
      final i = col - 1;
      if (i >= s._seriesNames.length) return;
      s._seriesNames[i] = value;
      return;
    }
    final r = row - 1;
    if (r < 0 || r >= s._xLabels.length) return;
    if (col == 0) {
      s._xLabels[r] = value;
      return;
    }
    final c = col - 1;
    while (s._values[r].length <= c) {
      s._values[r].add('');
    }
    if (c < s._values[r].length) s._values[r][c] = value;
  }
}

/// Eén cel van het grafiekdataraster: zelfde chroomloze look als een
/// documenttabelcel, met de toetsen van het rekenblad erop.
class _ChartGridCell extends StatefulWidget {
  const _ChartGridCell({
    super.key,
    required this.focusNode,
    required this.value,
    required this.enabled,
    required this.onChanged,
    required this.onKey,
    this.number = false,
    this.bold = false,
    this.muted = false,
  });

  final FocusNode focusNode;
  final String value;
  final bool enabled;
  final ValueChanged<String> onChanged;
  final KeyEventResult Function(KeyEvent event, TextEditingController ctrl)
  onKey;
  final bool number;
  final bool bold;
  final bool muted;

  @override
  State<_ChartGridCell> createState() => _ChartGridCellState();
}

class _ChartGridCellState extends State<_ChartGridCell> {
  late final TextEditingController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(text: widget.value);
  }

  @override
  void didUpdateWidget(covariant _ChartGridCell oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.value != widget.value && _ctrl.text != widget.value) {
      _ctrl.text = widget.value;
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListenableBuilder(
      listenable: widget.focusNode,
      builder: (context, _) {
        final focused = widget.focusNode.hasFocus;
        return ColoredBox(
          color: focused
              ? theme.colorScheme.primary.withValues(alpha: 0.12)
              : (widget.muted ? AppTheme.slate100 : Colors.transparent),
          child: Focus(
            onKeyEvent: (_, event) => widget.onKey(event, _ctrl),
            child: TextField(
              controller: _ctrl,
              focusNode: widget.focusNode,
              enabled: widget.enabled,
              onChanged: widget.onChanged,
              keyboardType: widget.number
                  ? const TextInputType.numberWithOptions(
                      decimal: true,
                      signed: true,
                    )
                  : TextInputType.text,
              inputFormatters: widget.number
                  ? [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,\-]'))]
                  : null,
              style: TextStyle(
                fontSize: 12,
                fontWeight: widget.bold ? FontWeight.w600 : FontWeight.normal,
                color: widget.muted ? AppTheme.slate500 : null,
              ),
              decoration: const InputDecoration(
                isDense: true,
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                filled: false,
                contentPadding: EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 8,
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
