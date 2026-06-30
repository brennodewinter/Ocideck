import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import '../../l10n/app_localizations.dart';
import '../../models/chart.dart';
import '../../models/slide.dart';
import '_editor_field.dart';

part 'chart_editor_dialogs.dart';

/// Editor for a chart slide: type, title, and an editable data grid. Data can
/// be entered directly in the interface, imported from a CSV (inline), or
/// linked to a CSV file kept in the deck's data/ directory (the living source).
class ChartEditor extends StatefulWidget {
  final Slide slide;
  final ValueChanged<Slide> onUpdate;
  final ValueChanged<List<Slide>>? onAddVariants;
  final String? projectPath;
  final bool nestedInScrollView;

  const ChartEditor({
    super.key,
    required this.slide,
    required this.onUpdate,
    this.onAddVariants,
    this.projectPath,
    this.nestedInScrollView = false,
  });

  @override
  State<ChartEditor> createState() => _ChartEditorState();
}

class _ChartEditorState extends State<ChartEditor> {
  late final TextEditingController _title;
  late final TextEditingController _minBound;
  late final TextEditingController _maxBound;
  late ChartType _type;
  String? _source;

  // Editable grid model (strings while editing).
  List<String> _xLabels = [];
  List<String?> _rowColors = [];
  List<String> _seriesNames = [];
  List<String?> _seriesColors = [];
  List<List<String>> _values = []; // [row][col]

  // Bumped on structural changes so cell fields rebuild with fresh values.
  int _rev = 0;

  static const _minLabelW = 238.0;
  static const _minCellW = 150.0;

  @override
  void initState() {
    super.initState();
    final spec = ChartSpec.parse(widget.slide.customMarkdown);
    _type = spec.type;
    _source = spec.source;
    _title = TextEditingController(text: spec.title);
    _title.addListener(_emit);
    _minBound = TextEditingController(text: _fmtBound(spec.minBound));
    _maxBound = TextEditingController(text: _fmtBound(spec.maxBound));
    _minBound.addListener(_emit);
    _maxBound.addListener(_emit);
    _loadFromSpec(spec);
  }

  bool get _supportsBounds => _type != ChartType.pie;

  static String _fmtBound(double? v) => v == null ? '' : _fmt(v);

  static double? _parseBound(String raw) {
    final text = raw.trim().replaceAll(',', '.');
    return text.isEmpty ? null : double.tryParse(text);
  }

  void _loadFromSpec(ChartSpec spec) {
    if (spec.hasInlineData) {
      _seriesNames = [for (final s in spec.series) s.name];
      _seriesColors = [for (final s in spec.series) s.color];
      _xLabels = List<String>.from(spec.x);
      _rowColors = [
        for (var i = 0; i < spec.x.length; i++)
          i < spec.rowColors.length ? spec.rowColors[i] : null,
      ];
      _values = [
        for (var r = 0; r < spec.x.length; r++)
          [
            for (final s in spec.series)
              r < s.data.length ? _fmt(s.data[r]) : '',
          ],
      ];
    } else {
      // Sensible empty starting grid.
      _seriesNames = ['Reeks 1'];
      _seriesColors = [null];
      _xLabels = ['', '', ''];
      _rowColors = [null, null, null];
      _values = List.generate(3, (_) => ['']);
    }
  }

  static String _fmt(double v) =>
      v == v.roundToDouble() ? v.toInt().toString() : v.toString();

  @override
  void dispose() {
    _title.dispose();
    _minBound.dispose();
    _maxBound.dispose();
    super.dispose();
  }

  ChartSpec _currentSpec() {
    final series = <ChartSeries>[
      for (var c = 0; c < _seriesNames.length; c++)
        ChartSeries(
          name: _seriesNames[c],
          color: _seriesColors[c],
          data: [
            for (var r = 0; r < _values.length; r++)
              double.tryParse(
                    (c < _values[r].length ? _values[r][c] : '')
                        .trim()
                        .replaceAll(',', '.'),
                  ) ??
                  0,
          ],
        ),
    ];
    return ChartSpec(
      type: _type,
      title: _title.text,
      source: _source,
      x: List<String>.from(_xLabels),
      rowColors: List<String?>.from(_rowColors),
      series: series,
      minBound: _supportsBounds ? _parseBound(_minBound.text) : null,
      maxBound: _supportsBounds ? _parseBound(_maxBound.text) : null,
    );
  }

  void _emit() {
    widget.onUpdate(
      widget.slide.copyWith(customMarkdown: _currentSpec().toBlock()),
    );
  }

  Future<void> _createVariants() async {
    final selected = await showDialog<List<ChartType>>(
      context: context,
      builder: (context) => _ChartVariantsDialog(currentType: _type),
    );
    if (selected == null || selected.isEmpty) return;
    final base = _currentSpec();
    widget.onAddVariants?.call([
      for (final type in selected)
        widget.slide.copyWith(
          customMarkdown: base
              .copyWith(
                type: type,
                clearMinBound: type == ChartType.pie,
                clearMaxBound: type == ChartType.pie,
              )
              .toBlock(),
        ),
    ]);
  }

  void _bump() => setState(() => _rev++);

  void _addColumn() {
    _seriesNames.add('Reeks ${_seriesNames.length + 1}');
    _seriesColors.add(null);
    for (final row in _values) {
      row.add('');
    }
    _bump();
    _emit();
  }

  void _removeColumn(int c) {
    if (_seriesNames.length <= 1) return;
    _seriesNames.removeAt(c);
    _seriesColors.removeAt(c);
    for (final row in _values) {
      if (c < row.length) row.removeAt(c);
    }
    _bump();
    _emit();
  }

  void _addRow() {
    _xLabels.add('');
    _rowColors.add(null);
    _values.add(List<String>.filled(_seriesNames.length, '', growable: true));
    _bump();
    _emit();
  }

  void _removeRow(int r) {
    if (_xLabels.length <= 1) return;
    _xLabels.removeAt(r);
    _rowColors.removeAt(r);
    _values.removeAt(r);
    _bump();
    _emit();
  }

  Future<void> _importCsv() async {
    final result = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['csv'],
      withData: true,
    );
    if (!mounted) return;
    if (result == null || result.files.isEmpty) return;
    final file = result.files.first;
    final text = file.bytes != null
        ? utf8.decode(file.bytes!)
        : (file.path != null ? await File(file.path!).readAsString() : null);
    if (text == null) return;
    if (!mounted) return;

    var asFile = false;
    if (widget.projectPath != null && mounted) {
      asFile =
          await showDialog<bool>(
            context: context,
            builder: (ctx) => AlertDialog(
              title: Text(ctx.l10n.d('CSV importeren')),
              content: Text(
                ctx.l10n.d(
                  'Data in de slide opslaan, of als los CSV-bestand naast de presentatie bewaren?',
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: Text(ctx.l10n.d('In de slide')),
                ),
                TextButton(
                  onPressed: () => Navigator.pop(ctx, true),
                  child: Text(ctx.l10n.d('Als CSV-bestand')),
                ),
              ],
            ),
          ) ??
          false;
    }

    String? source;
    if (asFile && widget.projectPath != null) {
      final name = p.basename(file.name);
      final dir = Directory(p.join(widget.projectPath!, chartDataDirName));
      await dir.create(recursive: true);
      await File(p.join(dir.path, name)).writeAsString(text, flush: true);
      source = '$chartDataDirName/$name';
    }

    if (!mounted) return;
    final parsed = parseCsv(text);
    setState(() {
      _source = source;
      _xLabels = parsed.$1.isEmpty ? [''] : parsed.$1;
      _rowColors = [
        for (var i = 0; i < _xLabels.length; i++)
          i < _rowColors.length ? _rowColors[i] : null,
      ];
      _seriesNames = parsed.$2.isEmpty
          ? ['Reeks 1']
          : [for (final s in parsed.$2) s.name];
      _seriesColors = [
        for (var i = 0; i < _seriesNames.length; i++)
          i < _seriesColors.length ? _seriesColors[i] : null,
      ];
      _values = [
        for (var r = 0; r < _xLabels.length; r++)
          if (parsed.$2.isEmpty)
            ['']
          else
            [
              for (final s in parsed.$2)
                r < s.data.length ? _fmt(s.data[r]) : '',
            ],
      ];
      _rev++;
    });
    _emit();
  }

  void _unlink() {
    setState(() => _source = null);
    _emit();
  }

  void _moveRow(int from, int to) {
    if (to < 0 || to >= _xLabels.length || from == to) return;
    setState(() {
      final label = _xLabels.removeAt(from);
      final color = _rowColors.removeAt(from);
      final values = _values.removeAt(from);
      _xLabels.insert(to, label);
      _rowColors.insert(to, color);
      _values.insert(to, values);
      _rev++;
    });
    _emit();
  }

  void _sortRows({int? column, required bool ascending}) {
    final indices = List<int>.generate(_xLabels.length, (i) => i);
    indices.sort((a, b) {
      int result;
      if (column == null) {
        result = _xLabels[a].toLowerCase().compareTo(_xLabels[b].toLowerCase());
      } else {
        final av =
            double.tryParse(_values[a][column].replaceAll(',', '.')) ?? 0;
        final bv =
            double.tryParse(_values[b][column].replaceAll(',', '.')) ?? 0;
        result = av.compareTo(bv);
      }
      return ascending ? result : -result;
    });
    setState(() {
      final labels = [for (final i in indices) _xLabels[i]];
      final colors = [for (final i in indices) _rowColors[i]];
      final values = [for (final i in indices) _values[i]];
      _xLabels = labels;
      _rowColors = colors;
      _values = values;
      _rev++;
    });
    _emit();
  }

  Future<void> _pickSeriesColor(int index) async {
    final selected = await _pickColor(
      initial:
          _seriesColors[index] ??
          chartSeriesColor(ChartSeries(name: '', data: const []), index),
      title: context.l10n.d('Kleur van reeks'),
    );
    if (selected == null || !mounted) return;
    setState(() => _seriesColors[index] = selected);
    _emit();
  }

  Future<void> _pickRowColor(int index) async {
    final selected = await _pickColor(
      initial:
          _rowColors[index] ??
          chartColorPalette[index % chartColorPalette.length],
      title: context.l10n.d('Kleur van rij'),
    );
    if (selected == null || !mounted) return;
    setState(() => _rowColors[index] = selected);
    _emit();
  }

  Future<String?> _pickColor({
    required String initial,
    required String title,
  }) async {
    return showDialog<String>(
      context: context,
      builder: (_) => _ChartColorDialog(initial: initial, title: title),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final linked = _source != null;
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          EditorField(label: 'Titel (optioneel)', controller: _title),
          const SizedBox(height: 16),
          Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 12,
            runSpacing: 8,
            children: [
              Text(
                l10n.d('Type grafiek'),
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF64748B),
                ),
              ),
              DropdownButton<ChartType>(
                value: _type,
                isDense: true,
                borderRadius: BorderRadius.circular(6),
                style: const TextStyle(fontSize: 12, color: Color(0xFF0F172A)),
                items: [
                  DropdownMenuItem(
                    value: ChartType.bar,
                    child: Text(l10n.d('Staaf')),
                  ),
                  DropdownMenuItem(
                    value: ChartType.stackedBar,
                    child: Text(l10n.d('Gestapelde staaf')),
                  ),
                  DropdownMenuItem(
                    value: ChartType.line,
                    child: Text(l10n.d('Lijn')),
                  ),
                  DropdownMenuItem(
                    value: ChartType.pie,
                    child: Text(l10n.d('Cirkel')),
                  ),
                  DropdownMenuItem(
                    value: ChartType.radar,
                    child: Text(l10n.d('Spider')),
                  ),
                  DropdownMenuItem(
                    value: ChartType.scatter,
                    child: Text(l10n.d('Spreiding')),
                  ),
                ],
                onChanged: (v) {
                  if (v == null) return;
                  setState(() => _type = v);
                  _emit();
                },
              ),
              if (widget.onAddVariants != null)
                TextButton.icon(
                  key: const ValueKey('chart-create-variants'),
                  onPressed: _createVariants,
                  icon: const Icon(Icons.auto_awesome_motion, size: 16),
                  label: Text(l10n.d('Varianten')),
                ),
              TextButton.icon(
                onPressed: _importCsv,
                icon: const Icon(Icons.upload_file, size: 16),
                label: Text(l10n.d('CSV importeren')),
              ),
            ],
          ),
          if (_type == ChartType.pie)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                l10n.d(
                  'Bij een cirkel worden maximaal de eerste twee reeksen getoond; de labels vormen de segmenten.',
                ),
                style: const TextStyle(fontSize: 11, color: Color(0xFF64748B)),
              ),
            ),
          if (_type == ChartType.radar)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                l10n.d(
                  'Een spider-diagram heeft minstens drie labels (assen) nodig; elke reeks vormt een vlak.',
                ),
                style: const TextStyle(fontSize: 11, color: Color(0xFF64748B)),
              ),
            ),
          if (_supportsBounds)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: _boundField(
                      key: const ValueKey('chart-min-bound'),
                      controller: _minBound,
                      label: _type == ChartType.radar
                          ? l10n.d('Schaalminimum (optioneel)')
                          : l10n.d('Minimumlijn (optioneel)'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _boundField(
                      key: const ValueKey('chart-max-bound'),
                      controller: _maxBound,
                      label: _type == ChartType.radar
                          ? l10n.d('Schaalmaximum (optioneel)')
                          : l10n.d('Maximumlijn (optioneel)'),
                    ),
                  ),
                ],
              ),
            ),
          if (linked)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Row(
                children: [
                  const Icon(Icons.link, size: 14, color: Color(0xFF0369A1)),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      '${l10n.d('Gekoppeld aan')} $_source',
                      style: const TextStyle(
                        fontSize: 11,
                        color: Color(0xFF0369A1),
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  TextButton(
                    onPressed: _unlink,
                    child: Text(l10n.d('Ontkoppelen')),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 12),
          if (widget.nestedInScrollView)
            SizedBox(
              height: 280,
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final availableWidth = constraints.maxWidth;
                  return SingleChildScrollView(
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: _grid(
                        enabled: !linked,
                        availableWidth: availableWidth,
                      ),
                    ),
                  );
                },
              ),
            )
          else
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final availableWidth = constraints.maxWidth;
                  return SingleChildScrollView(
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: _grid(
                        enabled: !linked,
                        availableWidth: availableWidth,
                      ),
                    ),
                  );
                },
              ),
            ),
          if (!linked) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                OutlinedButton.icon(
                  onPressed: _addRow,
                  icon: const Icon(Icons.add, size: 16),
                  label: Text(l10n.d('Rij')),
                ),
                const SizedBox(width: 8),
                OutlinedButton.icon(
                  onPressed: _addColumn,
                  icon: const Icon(Icons.add, size: 16),
                  label: Text(l10n.d('Reeks')),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _grid({required bool enabled, required double availableWidth}) {
    final cols = _seriesNames.length;
    const trailingWidth = 40.0;
    final labelWidth = math.max(_minLabelW, availableWidth * 0.28);
    final remaining = availableWidth - labelWidth - trailingWidth;
    final cellWidth = math.max(_minCellW, remaining / cols);
    final gridWidth = math.max(
      availableWidth,
      labelWidth + cellWidth * cols + trailingWidth,
    );
    return SizedBox(
      key: const ValueKey('chart-grid'),
      width: gridWidth,
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
                  color: _type == ChartType.pie && c >= 2
                      ? const Color(0xFFE2E8F0)
                      : null,
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
                              _type == ChartType.pie && c >= 2
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
                            border: Border.all(color: Colors.white, width: 1.5),
                            boxShadow: const [
                              BoxShadow(
                                color: Color(0x330F172A),
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
                          muted: _type == ChartType.pie && c >= 2,
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
            Padding(
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
                            r == _xLabels.length - 1
                                ? null
                                : () => _moveRow(r, r + 1),
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
                      color: _type == ChartType.pie && c >= 2
                          ? const Color(0xFFE2E8F0)
                          : null,
                      child: _cell(
                        key: ValueKey('v-$_rev-$r-$c'),
                        value: c < _values[r].length ? _values[r][c] : '',
                        enabled: enabled,
                        number: true,
                        muted: _type == ChartType.pie && c >= 2,
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
      labelStyle: const TextStyle(fontSize: 12, color: Color(0xFF64748B)),
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
      style: const TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w600,
        color: Color(0xFF64748B),
      ),
    ),
  );

  Widget _sortButton({required int? column, required bool enabled}) {
    return PopupMenuButton<bool>(
      key: ValueKey('chart-sort-${column ?? 'label'}'),
      enabled: enabled,
      tooltip: context.l10n.d('Sorteren'),
      icon: const Icon(Icons.sort, size: 15, color: Color(0xFF64748B)),
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
      boxShadow: const [BoxShadow(color: Color(0x330F172A), blurRadius: 2)],
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
          color: muted ? const Color(0xFF64748B) : null,
        ),
        decoration: InputDecoration(
          isDense: true,
          filled: muted,
          fillColor: muted ? const Color(0xFFF1F5F9) : null,
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
    color: const Color(0xFF64748B),
    visualDensity: VisualDensity.compact,
    padding: EdgeInsets.zero,
    constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
  );
}
