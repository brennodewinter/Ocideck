import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../l10n/app_localizations.dart';
import '../../models/chart.dart';
import '../../models/improvement_y01.dart';
import '../../services/improvement/improvement_analysis_helpers.dart';
import '../../services/improvement/chart_derivation.dart';
import '../../state/procesverbetering_provider.dart';
import '../../utils/error_snackbar.dart';
import '../../utils/log.dart';
import '../../utils/number_convention.dart';
import '../../utils/table_clipboard.dart';
import '../../models/settings.dart';
import '../../models/slide.dart';
import 'advanced_section.dart';
import 'animation_duration_control.dart';
import '_editor_field.dart';
import '../../theme/app_theme.dart';
import '../dialogs/improvement_msa_dialog.dart';
import 'chart_doe_design_dialog.dart';
import 'chart_histogram_limits.dart';
import 'chart_type_toolbar.dart';

part 'chart_editor_dialogs.dart';
part 'chart_editor_grid.dart';

bool _revealProcesverbetering(BuildContext context) {
  try {
    return ProviderScope.containerOf(
      context,
      listen: false,
    ).read(procesverbeteringRevealProvider);
  } catch (e, s) {
    // Outside a ProviderScope (tests, early boot) the module is off.
    logError('chart_editor._revealProcesverbetering', e, s);
    return false;
  }
}

/// The line shown after a CSV import that contained values which are not
/// numbers: how many there were, and the first few verbatim so the user can
/// recognise them in the source file. Only a handful are named — a snackbar
/// listing forty values is a wall nobody reads, and the count already carries
/// the scale.
///
/// Separate from the widget so the wording can be tested without driving a
/// file picker, which no test here can do.
@visibleForTesting
String csvUnreadableMessage(AppLocalizations l10n, List<String> unreadable) {
  const shown = 5;
  final examples = unreadable.take(shown).join(' · ');
  final ellipsis = unreadable.length > shown ? ' …' : '';
  return '${unreadable.length} '
      '${l10n.d('waarde(n) uit de CSV zijn niet als getal gelezen en staan nu op 0:')} '
      '$examples$ellipsis';
}

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

  /// Deck-level Y-01 metric for histogram limit linking.
  final ImprovementY01Metric deckY01;

  const ChartEditor({
    super.key,
    required this.slide,
    required this.onUpdate,
    this.onAddVariants,
    this.projectPath,
    required this.themeAnimationDurationMs,
    this.nestedInScrollView = false,
    this.deckY01 = ImprovementY01Metric.empty,
  });

  @override
  State<ChartEditor> createState() => _ChartEditorState();
}

class _ChartEditorState extends State<ChartEditor> {
  late final TextEditingController _title;
  late final TextEditingController _targets;
  late final TextEditingController _bands;
  late final TextEditingController _minBound;
  late final TextEditingController _maxBound;
  late final TextEditingController _usl;
  late final TextEditingController _lsl;
  late final TextEditingController _processTarget;
  late final TextEditingController _startAngle;
  late ChartType _type;
  String? _source;
  late bool _animateOnEnter;
  late bool _useDeckY01;
  late bool _showSliceLabels;

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
    _showSliceLabels = spec.showSliceLabels;
    _title = TextEditingController(text: spec.title);
    _title.addListener(_emit);
    _targets = TextEditingController(text: _fmtList(spec.targets));
    _bands = TextEditingController(text: _fmtList(spec.bands));
    _minBound = TextEditingController(text: _fmtBound(spec.minBound));
    _maxBound = TextEditingController(text: _fmtBound(spec.maxBound));
    _usl = TextEditingController(text: _fmtBound(spec.usl));
    _lsl = TextEditingController(text: _fmtBound(spec.lsl));
    _processTarget = TextEditingController(text: _fmtBound(spec.processTarget));
    _useDeckY01 = spec.yRef?.trim().toUpperCase() == 'Y-01';
    _targets.addListener(_emit);
    _bands.addListener(_emit);
    _minBound.addListener(_emit);
    _maxBound.addListener(_emit);
    _usl.addListener(_emit);
    _lsl.addListener(_emit);
    _processTarget.addListener(_emit);
    _startAngle = TextEditingController(
      text: spec.startAngle == 0 ? '' : _fmt(spec.startAngle),
    );
    _startAngle.addListener(_emit);
    _loadFromSpec(spec);
  }

  bool get _isHistogram => _type == ChartType.histogram;

  bool get _isYRefChart =>
      _type == ChartType.histogram || _type == ChartType.controlChart;

  bool get _deckHasY01 =>
      !widget.deckY01.isEmpty || widget.deckY01.hasSpecLimits;

  /// Pie and donut share the "one circle per series, labels are the segments"
  /// data mapping, so the grid dims columns past the first two for both.
  bool get _isPieLike => _type == ChartType.pie || _type == ChartType.donut;

  bool get _supportsBounds =>
      _type != ChartType.pie &&
      _type != ChartType.donut &&
      _type != ChartType.horizontalBar &&
      _type != ChartType.horizontalStackedBar &&
      _type != ChartType.heatmap;

  bool get _isBullet => _type == ChartType.bullet;

  static String _fmtBound(double? v) => v == null ? '' : _fmt(v);

  /// Een lijst getallen als leesbare, met komma's gescheiden tekst.
  static String _fmtList(List<double> values) => values.map(_fmt).join(', ');

  /// Leest een met komma's gescheiden lijst. Wat geen getal is, valt weg in
  /// plaats van de hele lijst te bederven — tikken gaat nu eenmaal teken voor
  /// teken, en halverwege "9" typen mag de vorige rij niet wissen.
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
    _targets.dispose();
    _bands.dispose();
    _minBound.dispose();
    _maxBound.dispose();
    _usl.dispose();
    _lsl.dispose();
    _processTarget.dispose();
    _startAngle.dispose();
    super.dispose();
  }

  ChartSpec _currentSpec() {
    final useY01 = _useDeckY01 && _isYRefChart;
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
      targets: _isBullet ? parseChartNumberList(_targets.text) : const [],
      bands: _isBullet ? parseChartNumberList(_bands.text) : const [],
      minBound: _supportsBounds ? _parseBound(_minBound.text) : null,
      maxBound: _supportsBounds ? _parseBound(_maxBound.text) : null,
      yRef: useY01 ? 'Y-01' : null,
      usl: useY01 ? null : (_isYRefChart ? _parseBound(_usl.text) : null),
      lsl: useY01 ? null : (_isYRefChart ? _parseBound(_lsl.text) : null),
      processTarget: useY01
          ? null
          : (_isYRefChart ? _parseBound(_processTarget.text) : null),
      animateOnEnter: _animateOnEnter,
      animationDurationMs: _animationOverrideMs,
      showSliceLabels: _showSliceLabels,
      startAngle: _isPieLike ? (_parseBound(_startAngle.text) ?? 0) : 0,
    );
  }

  void _applyDefaultYRefForType(ChartType type) {
    if ((type == ChartType.histogram || type == ChartType.controlChart) &&
        widget.deckY01.hasSpecLimits) {
      _useDeckY01 = true;
      _usl.clear();
      _lsl.clear();
      _processTarget.clear();
    }
  }

  void _emit() {
    widget.onUpdate(
      widget.slide.copyWith(customMarkdown: _currentSpec().toBlock()),
    );
  }

  Future<void> _createVariants() async {
    final selected = await showDialog<List<ChartType>>(
      context: context,
      builder: (dialogContext) => _ChartVariantsDialog(
        currentType: _type,
        revealProcesverbetering: _revealProcesverbetering(dialogContext),
      ),
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

  /// Plakt een spreadsheet-tabel in het raster (Phase 2). Enkele cel blijft
  /// bij het platform — alleen herkende tabellen worden hier overgenomen.
  Future<void> _pasteClipboardTable() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text;
    if (text == null || text.isEmpty) return;
    final table = parseClipboardTable(text);
    if (table == null) return;
    final grid = chartGridFromClipboardTable(table);
    if (grid == null) return;
    setState(() {
      _seriesNames = grid.seriesNames;
      _seriesColors = List<String?>.filled(_seriesNames.length, null);
      _xLabels = grid.xLabels;
      _rowColors = List<String?>.filled(_xLabels.length, null);
      _values = grid.values;
      _rev++;
    });
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
    var parsed = parseCsv(text);
    // Values the file itself cannot settle: ask, rather than pick one and hope.
    // Backing out of the question cancels the import — importing anyway would
    // mean charting a reading the user declined to give.
    if (parsed.ambiguous.isNotEmpty) {
      final convention = await askDecimalConvention(context, parsed.ambiguous);
      if (convention == null || !mounted) return;
      parsed = parseCsv(text, convention: convention);
    }
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

    // Say what could not be read. Those cells are drawn as 0, and a 0 is
    // indistinguishable from a real measurement of zero — so staying quiet
    // would hand the user a chart that looks finished and is wrong.
    if (parsed.unreadable.isNotEmpty) {
      showErrorSnackBar(
        ScaffoldMessenger.of(context),
        context.l10n,
        csvUnreadableMessage(context.l10n, parsed.unreadable),
      );
    }
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
          ChartTypeToolbar(
            l10n: l10n,
            type: _type,
            revealProcesverbetering: _revealProcesverbetering(context),
            showVariants: widget.onAddVariants != null,
            onTypeChanged: (v) {
              setState(() {
                _type = v;
                _applyDefaultYRefForType(v);
              });
              _emit();
            },
            onGageRr: _openGageRr,
            onDoeDesign: _openDoeDesign,
            onCreateVariants: widget.onAddVariants != null
                ? _createVariants
                : null,
            onPasteClipboard: _pasteClipboardTable,
            onImportCsv: _importCsv,
          ),
          if (chartTypeHint(l10n, _type) case final hint?)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                hint,
                style: TextStyle(fontSize: 11, color: AppTheme.slate500),
              ),
            ),
          if (_isHistogram && _deckHasY01)
            ChartHistogramY01Controls(
              l10n: l10n,
              useDeckY01: _useDeckY01,
              deckY01: widget.deckY01,
              usl: _usl,
              lsl: _lsl,
              processTarget: _processTarget,
              onUseDeckY01Changed: (v) {
                setState(() {
                  _useDeckY01 = v;
                  if (v) {
                    _usl.clear();
                    _lsl.clear();
                    _processTarget.clear();
                  }
                });
                _emit();
              },
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
                  _maxBound.text.isNotEmpty ||
                  (!_useDeckY01 &&
                      (_usl.text.isNotEmpty ||
                          _lsl.text.isNotEmpty ||
                          _processTarget.text.isNotEmpty)),
              children: [
                if (_isBullet) _bulletControls(l10n),
                if (_supportsBounds) _boundControls(l10n),
                if (_isHistogram && !_useDeckY01)
                  ChartHistogramLocalLimits(
                    l10n: l10n,
                    usl: _usl,
                    lsl: _lsl,
                    processTarget: _processTarget,
                  ),
                if (_isPieLike) ...[
                  _chartToggleRow(
                    icon: Icons.percent,
                    label: l10n.d('Percentages op de taartpunten tonen'),
                    value: _showSliceLabels,
                    onChanged: (v) {
                      setState(() => _showSliceLabels = v);
                      _emit();
                    },
                  ),
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: _boundField(
                      key: const ValueKey('chart-start-angle'),
                      controller: _startAngle,
                      label: l10n.d('Starthoek (graden)'),
                    ),
                  ),
                ],
                _animationControls(
                  l10n: l10n,
                  animateOnEnter: _animateOnEnter,
                  onAnimateChanged: (v) {
                    setState(() => _animateOnEnter = v);
                    _emit();
                  },
                  overrideMs: _animationOverrideMs,
                  themeMs: widget.themeAnimationDurationMs,
                  onDurationChanged: (v) {
                    setState(() => _animationOverrideMs = v);
                    _emit();
                  },
                ),
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
  /// Streefwaarden en bandgrenzen voor het type "norm en prestatie".
  ///
  /// Twee tekstvelden met komma's, geen tweede raster: het zijn hooguit een
  /// handvol getallen, en een raster ernaast zou de editor zwaarder maken dan
  /// de grafiek zelf.
  Widget _bulletControls(AppLocalizations l10n) {
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: _boundField(
              key: const ValueKey('chart-targets'),
              controller: _targets,
              label: l10n.d('Norm per rij (optioneel)'),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: _boundField(
              key: const ValueKey('chart-bands'),
              controller: _bands,
              label: l10n.d('Bandgrenzen (optioneel)'),
            ),
          ),
        ],
      ),
    );
  }

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

  Future<void> _openGageRr() async {
    final nested = gageRrFromChartGrid(
      partLabels: _xLabels,
      operatorNames: _seriesNames,
      cellValues: _values,
    );
    await ImprovementMsaDialog.show(context, initialMeasurements: nested);
  }

  Future<void> _openDoeDesign() async {
    final grid = await showDialog<DoeDesignGrid>(
      context: context,
      builder: (_) => const DoeDesignDialog(),
    );
    if (grid == null || !mounted) return;
    setState(() {
      _xLabels = List<String>.from(grid.xLabels);
      _seriesNames = List<String>.from(grid.seriesNames);
      _values = [for (final row in grid.cellValues) List<String>.from(row)];
      _rowColors = List<String?>.filled(_xLabels.length, null);
      _seriesColors = List<String?>.filled(_seriesNames.length, null);
      _rev++;
    });
    _emit();
  }
}

/// A labelled on/off row for the chart editor's Advanced section: an icon, a
/// caption, and a trailing switch. Top-level so the shared shape lives in one
/// place and _ChartEditorState stays within its size ceiling.
Widget _chartToggleRow({
  required IconData icon,
  required String label,
  required bool value,
  required ValueChanged<bool> onChanged,
}) {
  return Padding(
    padding: const EdgeInsets.only(top: 12),
    child: Row(
      children: [
        Icon(icon, size: 18, color: AppTheme.slate500),
        const SizedBox(width: 8),
        Expanded(child: Text(label, style: const TextStyle(fontSize: 13))),
        Switch(value: value, onChanged: onChanged),
      ],
    ),
  );
}

/// The "animate on enter" toggle plus (when on) the per-slide duration control,
/// for the editor's Advanced section. Top-level so the block stays out of
/// _ChartEditorState's size budget.
Widget _animationControls({
  required AppLocalizations l10n,
  required bool animateOnEnter,
  required ValueChanged<bool> onAnimateChanged,
  required int? overrideMs,
  required int themeMs,
  required ValueChanged<int?> onDurationChanged,
}) {
  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      _chartToggleRow(
        icon: Icons.auto_awesome,
        label: l10n.d('Animatie bij openen'),
        value: animateOnEnter,
        onChanged: onAnimateChanged,
      ),
      if (animateOnEnter)
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: AnimationDurationControl(
            overrideMs: overrideMs,
            themeMs: themeMs,
            minMs: kThemeMinAnimationDurationMs,
            maxMs: kThemeMaxAnimationDurationMs,
            onChanged: onDurationChanged,
          ),
        ),
    ],
  );
}
