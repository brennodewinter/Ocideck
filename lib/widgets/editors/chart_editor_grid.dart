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
    required String value,
    required bool enabled,
    required ValueChanged<String> onChanged,
    bool number = false,
    bool bold = false,
    bool muted = false,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: TextFormField(
        key: key,
        initialValue: value,
        enabled: enabled,
        onChanged: (v) {
          onChanged(v);
          _emit();
        },
        keyboardType: number
            ? const TextInputType.numberWithOptions(decimal: true, signed: true)
            : TextInputType.text,
        inputFormatters: number
            ? [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,\-]'))]
            : null,
        style: TextStyle(
          fontSize: 12,
          fontWeight: bold ? FontWeight.w600 : FontWeight.normal,
          color: muted ? AppTheme.slate500 : null,
        ),
        decoration: InputDecoration(
          isDense: true,
          filled: muted,
          fillColor: muted ? AppTheme.slate100 : null,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 8,
            vertical: 8,
          ),
          border: const OutlineInputBorder(),
        ),
      ),
    );
  }

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
