import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../l10n/app_localizations.dart';
import '../../models/chart.dart';
import '../../models/settings.dart';
import '../../models/slide.dart';
import 'advanced_section.dart';
import 'animation_duration_control.dart';
import '_editor_field.dart';
import '../../theme/app_theme.dart';

part 'chart_editor_dialogs.dart';
part 'chart_editor_grid.dart';

/// Editor for a chart slide: type, title, and an editable data grid. Data can
/// be entered directly in the interface, imported from a CSV, or linked to a
/// data file in the deck's data/ directory.
///
/// The grid stays editable in every one of those cases — a linked chart writes
/// its file back on save. It used to be read-only while linked, because there
/// was no way back to the file and an edit would quietly disappear at the next
/// save; that is no longer true.
class ChartEditor extends StatefulWidget {
  final Slide slide;
  final ValueChanged<Slide> onUpdate;
  final ValueChanged<List<Slide>>? onAddVariants;
  final String? projectPath;

  /// Theme's shared activation duration (ms), used as the inherited value when
  /// the chart sets no own duration.
  final int themeAnimationDurationMs;
  final bool nestedInScrollView;

  const ChartEditor({
    super.key,
    required this.slide,
    required this.onUpdate,
    this.onAddVariants,
    this.projectPath,
    required this.themeAnimationDurationMs,
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
  late bool _animateOnEnter;

  /// Per-slide duration override; null = inherit the theme's duration.
  int? _animationOverrideMs;

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
    _animateOnEnter = spec.animateOnEnter;
    _animationOverrideMs = spec.animationDurationMs;
    _title = TextEditingController(text: spec.title);
    _title.addListener(_emit);
    _minBound = TextEditingController(text: _fmtBound(spec.minBound));
    _maxBound = TextEditingController(text: _fmtBound(spec.maxBound));
    _minBound.addListener(_emit);
    _maxBound.addListener(_emit);
    _loadFromSpec(spec);
  }

  /// Pie and donut share the "one circle per series, labels are the segments"
  /// data mapping, so the grid dims columns past the first two for both.
  bool get _isPieLike => _type == ChartType.pie || _type == ChartType.donut;

  bool get _supportsBounds =>
      _type != ChartType.pie &&
      _type != ChartType.donut &&
      _type != ChartType.horizontalBar &&
      _type != ChartType.horizontalStackedBar &&
      _type != ChartType.heatmap;

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
      animateOnEnter: _animateOnEnter,
      animationDurationMs: _animationOverrideMs,
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
                clearMinBound: !base.copyWith(type: type).supportsBounds,
                clearMaxBound: !base.copyWith(type: type).supportsBounds,
              )
              .toBlock(),
        ),
    ]);
  }

  void _bump() => setState(() => _rev++);

  /// setState is protected; extensions in part-bestanden (zoals de
  /// ontkoppel-dialoog) lopen via deze wrapper.
  void _rebuild(VoidCallback fn) => setState(fn);

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

    // De import vult alleen het grid. Waar de data belandt is geen keuze meer
    // die de gebruiker hier hoeft te maken: bij het opslaan verhuist ze sowieso
    // naar een bestand naast de presentatie. Hier stond een dialoog "in de
    // slide of als CSV-bestand?"; die vroeg om een beslissing waarvan het ene
    // antwoord inmiddels niet meer waar te maken is.
    final parsed = parseCsv(text);
    setState(() {
      // Een import vervangt de cijfers, niet de bestemming: een grafiek die al
      // aan een bestand hangt blijft daaraan hangen en krijgt de nieuwe data
      // daar geschreven.
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
          _typeControls(l10n),
          if (_typeHint(l10n) case final hint?)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                hint,
                style: TextStyle(fontSize: 11, color: AppTheme.slate500),
              ),
            ),
          if (linked) _linkedSourceRow(l10n),
          // Grenzen en animatie zijn verfijning; ingeklapt tenzij er al iets
          // is ingesteld (dan mag het niet uit beeld verdwijnen).
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: AdvancedSection(
              title: l10n.d('Geavanceerd'),
              initiallyExpanded:
                  _animateOnEnter ||
                  _minBound.text.isNotEmpty ||
                  _maxBound.text.isNotEmpty,
              children: [
                if (_supportsBounds) _boundControls(l10n),
                _animationControls(l10n),
              ],
            ),
          ),
          const SizedBox(height: 12),
          if (widget.nestedInScrollView)
            SizedBox(height: 280, child: _scrollableGrid())
          else
            Expanded(child: _scrollableGrid()),
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
      ),
    );
  }

  /// Min/max-grenzen (of schaalgrenzen bij radar) naast elkaar.
  Widget _boundControls(AppLocalizations l10n) {
    return Padding(
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
    );
  }

  /// Indicator + ontkoppelknop wanneer de data aan een CSV is gekoppeld.
  Widget _linkedSourceRow(AppLocalizations l10n) {
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Row(
        children: [
          const Icon(Icons.link, size: 14, color: AppTheme.infoAccent),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              '${l10n.d('Gekoppeld aan')} $_source',
              style: const TextStyle(fontSize: 11, color: AppTheme.infoAccent),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          TextButton(onPressed: _unlink, child: Text(l10n.d('Ontkoppelen'))),
        ],
      ),
    );
  }

  /// Animatie-schakelaar plus (indien aan) de duur-regelaar.
  Widget _animationControls(AppLocalizations l10n) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 12),
          child: Row(
            children: [
              Icon(Icons.auto_awesome, size: 18, color: AppTheme.slate500),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  l10n.d('Animatie bij openen'),
                  style: const TextStyle(fontSize: 13),
                ),
              ),
              Switch(
                value: _animateOnEnter,
                onChanged: (v) {
                  setState(() => _animateOnEnter = v);
                  _emit();
                },
              ),
            ],
          ),
        ),
        if (_animateOnEnter)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: AnimationDurationControl(
              overrideMs: _animationOverrideMs,
              themeMs: widget.themeAnimationDurationMs,
              minMs: kThemeMinAnimationDurationMs,
              maxMs: kThemeMaxAnimationDurationMs,
              onChanged: (value) {
                setState(() => _animationOverrideMs = value);
                _emit();
              },
            ),
          ),
      ],
    );
  }

  /// Het datagrid in een tweerichtings-scroller.
  ///
  /// Ook bewerkbaar wanneer de data aan een los bestand is gekoppeld: bij
  /// opslaan wordt dat bestand bijgewerkt. Het grid stond hier vroeger uit,
  /// omdat er toen geen weg terug naar het bestand was en een bewerking dus
  /// stilzwijgend verloren ging.
  Widget _scrollableGrid() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final availableWidth = constraints.maxWidth;
        return SingleChildScrollView(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: _grid(enabled: true, availableWidth: availableWidth),
          ),
        );
      },
    );
  }

  /// Short explanation of the non-obvious data mapping for the current type,
  /// or null for the self-explanatory ones (bar, line, …).
  String? _typeHint(AppLocalizations l10n) {
    if (_isPieLike) {
      return l10n.d(
        'Bij een cirkel worden maximaal de eerste twee reeksen getoond; de labels vormen de segmenten.',
      );
    }
    return switch (_type) {
      ChartType.radar => l10n.d(
        'Een spider-diagram heeft minstens drie labels (assen) nodig; elke reeks vormt een vlak.',
      ),
      ChartType.combo => l10n.d(
        'Laatste reeks als lijn op een tweede as; de rest als staven.',
      ),
      ChartType.waterfall => l10n.d(
        'Eerste reeks: elke waarde is een op- of neerwaartse stap op het vorige totaal.',
      ),
      ChartType.heatmap => l10n.d(
        'Reeks = rij, kolom = label, celkleur volgt de waarde. Label de assen kans en impact voor een risicomatrix.',
      ),
      _ => null,
    };
  }

  Widget _typeControls(AppLocalizations l10n) {
    return Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 12,
      runSpacing: 8,
      children: [
        Text(
          l10n.d('Type grafiek'),
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: AppTheme.slate500,
          ),
        ),
        DropdownButton<ChartType>(
          value: _type,
          isDense: true,
          borderRadius: BorderRadius.circular(6),
          style: TextStyle(fontSize: 12, color: AppTheme.ink),
          items: [
            DropdownMenuItem(
              value: ChartType.bar,
              child: Text(l10n.d('Staaf')),
            ),
            DropdownMenuItem(
              value: ChartType.horizontalBar,
              child: Text(l10n.d('Horizontale staaf')),
            ),
            DropdownMenuItem(
              value: ChartType.stackedBar,
              child: Text(l10n.d('Gestapelde staaf')),
            ),
            DropdownMenuItem(
              value: ChartType.horizontalStackedBar,
              child: Text(l10n.d('Horizontale gestapelde staaf')),
            ),
            DropdownMenuItem(
              value: ChartType.combo,
              child: Text(l10n.d('Combo')),
            ),
            DropdownMenuItem(
              value: ChartType.line,
              child: Text(l10n.d('Lijn')),
            ),
            DropdownMenuItem(
              value: ChartType.area,
              child: Text(l10n.d('Vlak')),
            ),
            DropdownMenuItem(
              value: ChartType.pie,
              child: Text(l10n.d('Cirkel')),
            ),
            DropdownMenuItem(
              value: ChartType.donut,
              child: Text(l10n.d('Donut')),
            ),
            DropdownMenuItem(
              value: ChartType.radar,
              child: Text(l10n.d('Spider')),
            ),
            DropdownMenuItem(
              value: ChartType.scatter,
              child: Text(l10n.d('Spreiding')),
            ),
            DropdownMenuItem(
              value: ChartType.waterfall,
              child: Text(l10n.d('Waterval')),
            ),
            DropdownMenuItem(
              value: ChartType.heatmap,
              child: Text(l10n.d('Heatmap')),
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
    );
  }
}
