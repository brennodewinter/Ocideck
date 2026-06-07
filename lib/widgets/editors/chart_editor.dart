import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import '../../l10n/app_localizations.dart';
import '../../models/chart.dart';
import '../../models/slide.dart';
import '_editor_field.dart';

/// Editor for a chart slide: type, title, and an editable data grid. Data can
/// be entered directly in the interface, imported from a CSV (inline), or
/// linked to a CSV file kept in the deck's data/ directory (the living source).
class ChartEditor extends StatefulWidget {
  final Slide slide;
  final ValueChanged<Slide> onUpdate;
  final String? projectPath;

  const ChartEditor({
    super.key,
    required this.slide,
    required this.onUpdate,
    this.projectPath,
  });

  @override
  State<ChartEditor> createState() => _ChartEditorState();
}

class _ChartEditorState extends State<ChartEditor> {
  late final TextEditingController _title;
  late ChartType _type;
  String? _source;

  // Editable grid model (strings while editing).
  List<String> _xLabels = [];
  List<String> _seriesNames = [];
  List<List<String>> _values = []; // [row][col]

  // Bumped on structural changes so cell fields rebuild with fresh values.
  int _rev = 0;

  static const _labelW = 130.0;
  static const _cellW = 96.0;

  @override
  void initState() {
    super.initState();
    final spec = ChartSpec.parse(widget.slide.customMarkdown);
    _type = spec.type;
    _source = spec.source;
    _title = TextEditingController(text: spec.title);
    _title.addListener(_emit);
    _loadFromSpec(spec);
  }

  void _loadFromSpec(ChartSpec spec) {
    if (spec.hasInlineData) {
      _seriesNames = [for (final s in spec.series) s.name];
      _xLabels = List<String>.from(spec.x);
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
      _xLabels = ['', '', ''];
      _values = List.generate(3, (_) => ['']);
    }
  }

  static String _fmt(double v) =>
      v == v.roundToDouble() ? v.toInt().toString() : v.toString();

  @override
  void dispose() {
    _title.dispose();
    super.dispose();
  }

  void _emit() {
    final series = <ChartSeries>[
      for (var c = 0; c < _seriesNames.length; c++)
        ChartSeries(
          name: _seriesNames[c],
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
    final spec = ChartSpec(
      type: _type,
      title: _title.text,
      source: _source,
      x: List<String>.from(_xLabels),
      series: series,
    );
    widget.onUpdate(widget.slide.copyWith(customMarkdown: spec.toBlock()));
  }

  void _bump() => setState(() => _rev++);

  void _addColumn() {
    _seriesNames.add('Reeks ${_seriesNames.length + 1}');
    for (final row in _values) {
      row.add('');
    }
    _bump();
    _emit();
  }

  void _removeColumn(int c) {
    if (_seriesNames.length <= 1) return;
    _seriesNames.removeAt(c);
    for (final row in _values) {
      if (c < row.length) row.removeAt(c);
    }
    _bump();
    _emit();
  }

  void _addRow() {
    _xLabels.add('');
    _values.add(List<String>.filled(_seriesNames.length, '', growable: true));
    _bump();
    _emit();
  }

  void _removeRow(int r) {
    if (_xLabels.length <= 1) return;
    _xLabels.removeAt(r);
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
    if (result == null || result.files.isEmpty) return;
    final file = result.files.first;
    final text = file.bytes != null
        ? utf8.decode(file.bytes!)
        : (file.path != null ? await File(file.path!).readAsString() : null);
    if (text == null) return;

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

    final parsed = parseCsv(text);
    setState(() {
      _source = source;
      _xLabels = parsed.$1.isEmpty ? [''] : parsed.$1;
      _seriesNames = parsed.$2.isEmpty
          ? ['Reeks 1']
          : [for (final s in parsed.$2) s.name];
      _values = [
        for (var r = 0; r < _xLabels.length; r++)
          [for (final s in parsed.$2) r < s.data.length ? _fmt(s.data[r]) : ''],
      ];
      _rev++;
    });
    _emit();
  }

  void _unlink() {
    setState(() => _source = null);
    _emit();
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
          Row(
            children: [
              Text(
                l10n.d('Type grafiek'),
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF64748B),
                ),
              ),
              const SizedBox(width: 12),
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
                    value: ChartType.line,
                    child: Text(l10n.d('Lijn')),
                  ),
                  DropdownMenuItem(
                    value: ChartType.pie,
                    child: Text(l10n.d('Cirkel')),
                  ),
                ],
                onChanged: (v) {
                  if (v == null) return;
                  setState(() => _type = v);
                  _emit();
                },
              ),
              const Spacer(),
              TextButton.icon(
                onPressed: _importCsv,
                icon: const Icon(Icons.upload_file, size: 16),
                label: Text(l10n.d('CSV importeren')),
              ),
            ],
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
          Expanded(
            child: SingleChildScrollView(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: _grid(enabled: !linked),
              ),
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

  Widget _grid({required bool enabled}) {
    final cols = _seriesNames.length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Header row: empty label cell + series name fields.
        Row(
          children: [
            SizedBox(
              width: _labelW,
              child: _headerHint(context.l10n.d('Label')),
            ),
            for (var c = 0; c < cols; c++)
              SizedBox(
                width: _cellW,
                child: Row(
                  children: [
                    Expanded(
                      child: _cell(
                        key: ValueKey('s-$_rev-$c'),
                        value: _seriesNames[c],
                        enabled: enabled,
                        onChanged: (v) => _seriesNames[c] = v,
                        bold: true,
                      ),
                    ),
                    if (enabled && cols > 1)
                      _iconBtn(Icons.close, () => _removeColumn(c)),
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
                  width: _labelW,
                  child: _cell(
                    key: ValueKey('x-$_rev-$r'),
                    value: _xLabels[r],
                    enabled: enabled,
                    onChanged: (v) => _xLabels[r] = v,
                  ),
                ),
                for (var c = 0; c < cols; c++)
                  SizedBox(
                    width: _cellW,
                    child: _cell(
                      key: ValueKey('v-$_rev-$r-$c'),
                      value: c < _values[r].length ? _values[r][c] : '',
                      enabled: enabled,
                      number: true,
                      onChanged: (v) {
                        while (_values[r].length <= c) {
                          _values[r].add('');
                        }
                        _values[r][c] = v;
                      },
                    ),
                  ),
                if (enabled && _xLabels.length > 1)
                  _iconBtn(Icons.close, () => _removeRow(r)),
              ],
            ),
          ),
      ],
    );
  }

  Widget _headerHint(String text) => Padding(
    padding: const EdgeInsets.only(left: 4, bottom: 4),
    child: Text(
      text,
      style: const TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w600,
        color: Color(0xFF94A3B8),
      ),
    ),
  );

  Widget _cell({
    required Key key,
    required String value,
    required bool enabled,
    required ValueChanged<String> onChanged,
    bool number = false,
    bool bold = false,
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
        ),
        decoration: const InputDecoration(
          isDense: true,
          contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          border: OutlineInputBorder(),
        ),
      ),
    );
  }

  Widget _iconBtn(IconData icon, VoidCallback onTap) => IconButton(
    onPressed: onTap,
    icon: Icon(icon, size: 14),
    color: const Color(0xFF94A3B8),
    visualDensity: VisualDensity.compact,
    padding: EdgeInsets.zero,
    constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
  );
}
