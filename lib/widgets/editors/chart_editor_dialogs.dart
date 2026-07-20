// Part of the chart_editor library — see chart_editor.dart.
// Split out for navigability (variant & colour picker dialogs); all imports
// live in the main library file. Top-level widgets relocate verbatim.
part of 'chart_editor.dart';

class _ChartVariantsDialog extends StatefulWidget {
  final ChartType currentType;

  const _ChartVariantsDialog({required this.currentType});

  @override
  State<_ChartVariantsDialog> createState() => _ChartVariantsDialogState();
}

class _ChartVariantsDialogState extends State<_ChartVariantsDialog> {
  late final List<ChartType> _types = [
    for (final type in ChartType.values)
      if (type != widget.currentType) type,
  ];

  String _label(BuildContext context, ChartType type) {
    final l10n = context.l10n;
    return switch (type) {
      ChartType.bar => l10n.d('Staaf'),
      ChartType.stackedBar => l10n.d('Gestapelde staaf'),
      ChartType.line => l10n.d('Lijn'),
      ChartType.area => l10n.d('Vlak'),
      ChartType.pie => l10n.d('Cirkel'),
      ChartType.donut => l10n.d('Donut'),
      ChartType.radar => l10n.d('Spider'),
      ChartType.scatter => l10n.d('Spreiding'),
      ChartType.horizontalBar => l10n.d('Horizontale staaf'),
      ChartType.combo => l10n.d('Combo'),
      ChartType.waterfall => l10n.d('Waterval'),
      ChartType.heatmap => l10n.d('Heatmap'),
      ChartType.horizontalStackedBar => l10n.d('Horizontale gestapelde staaf'),
      ChartType.bullet => l10n.d('Norm en prestatie'),
    };
  }

  void _move(int index, int delta) {
    final target = index + delta;
    if (target < 0 || target >= _types.length) return;
    setState(() {
      final type = _types.removeAt(index);
      _types.insert(target, type);
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return AlertDialog(
      title: Text(l10n.d('Grafiekvarianten maken')),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l10n.d(
                'Deze slides gebruiken dezelfde data, kleuren en titel. Kies met de pijlen de volgorde na de huidige slide.',
              ),
              style: TextStyle(fontSize: 12, color: AppTheme.slate500),
            ),
            const SizedBox(height: 12),
            // The list can hold every other chart type; cap its height and let
            // it scroll so the dialog never overflows.
            Flexible(
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (var i = 0; i < _types.length; i++)
                      ListTile(
                        key: ValueKey('chart-variant-${_types[i].name}'),
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        // A horizontal stacked bar IS a stacked bar turned a
                        // quarter turn, so its icon is the stacked-bar glyph
                        // rotated to match.
                        leading: RotatedBox(
                          quarterTurns:
                              _types[i] == ChartType.horizontalStackedBar
                              ? 1
                              : 0,
                          child: Icon(switch (_types[i]) {
                            ChartType.bar => Icons.bar_chart,
                            ChartType.stackedBar => Icons.stacked_bar_chart,
                            ChartType.line => Icons.show_chart,
                            ChartType.area => Icons.area_chart,
                            ChartType.pie => Icons.pie_chart_outline,
                            ChartType.donut => Icons.donut_large,
                            ChartType.radar => Icons.radar,
                            ChartType.scatter => Icons.scatter_plot,
                            ChartType.bullet => Icons.speed_outlined,
                            ChartType.horizontalBar =>
                              Icons.align_horizontal_left,
                            ChartType.combo => Icons.insights,
                            ChartType.waterfall => Icons.waterfall_chart,
                            ChartType.heatmap => Icons.grid_on,
                            ChartType.horizontalStackedBar =>
                              Icons.stacked_bar_chart,
                          }),
                        ),
                        title: Text(_label(context, _types[i])),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              key: ValueKey('chart-variant-up-$i'),
                              onPressed: i == 0 ? null : () => _move(i, -1),
                              icon: const Icon(Icons.arrow_upward, size: 18),
                              tooltip: l10n.d('Omhoog'),
                            ),
                            IconButton(
                              key: ValueKey('chart-variant-down-$i'),
                              onPressed: i == _types.length - 1
                                  ? null
                                  : () => _move(i, 1),
                              icon: const Icon(Icons.arrow_downward, size: 18),
                              tooltip: l10n.d('Omlaag'),
                            ),
                            IconButton(
                              onPressed: () =>
                                  setState(() => _types.removeAt(i)),
                              icon: const Icon(Icons.close, size: 18),
                              tooltip: l10n.d('Niet toevoegen'),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(l10n.d('Annuleren')),
        ),
        FilledButton(
          onPressed: _types.isEmpty
              ? null
              : () => Navigator.pop(context, List<ChartType>.from(_types)),
          child: Text(l10n.d('Slides toevoegen')),
        ),
      ],
    );
  }
}

class _ChartColorDialog extends StatefulWidget {
  final String initial;
  final String title;

  const _ChartColorDialog({required this.initial, required this.title});

  @override
  State<_ChartColorDialog> createState() => _ChartColorDialogState();
}

class _ChartColorDialogState extends State<_ChartColorDialog> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initial);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final normalized = normalizeChartColor(_controller.text);
    return AlertDialog(
      title: Text(widget.title),
      content: SizedBox(
        width: 320,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                for (final hex in chartColorPalette)
                  _colorChoice(
                    hex,
                    selected: normalized == hex,
                    onTap: () {
                      _controller.text = hex;
                      setState(() {});
                    },
                  ),
              ],
            ),
            const SizedBox(height: 18),
            TextField(
              controller: _controller,
              decoration: InputDecoration(
                labelText: context.l10n.d('Hexkleur'),
                hintText: '#2563EB',
                border: const OutlineInputBorder(),
                isDense: true,
              ),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[#0-9a-fA-F]')),
                LengthLimitingTextInputFormatter(7),
              ],
              onChanged: (_) => setState(() {}),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(context.l10n.d('Annuleren')),
        ),
        FilledButton(
          onPressed: normalized == null
              ? null
              : () => Navigator.pop(context, normalized),
          child: Text(context.l10n.d('Toepassen')),
        ),
      ],
    );
  }

  Widget _colorChoice(
    String hex, {
    required bool selected,
    required VoidCallback onTap,
  }) {
    final color = Color(int.parse(hex.substring(1), radix: 16) | 0xFF000000);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: Container(
        width: 34,
        height: 34,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          border: Border.all(
            color: selected ? Colors.black : AppTheme.slate200,
            width: selected ? 3 : 1,
          ),
        ),
        child: selected
            ? const Icon(Icons.check, size: 16, color: Colors.white)
            : null,
      ),
    );
  }
}

extension _ChartEditorUnlink on _ChartEditorState {
  /// Vraag bevestiging voor het verbreken van de CSV-koppeling: één klik zou
  /// anders ongemerkt de live-link opgeven en de data vast in de slide zetten.
  Future<void> _unlink() async {
    final l10n = context.l10n;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.d('CSV-koppeling verbreken?')),
        content: Text(
          l10n.d(
            'De data blijft in de slide staan, maar wijzigingen in het CSV-bestand komen niet meer mee.',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(l10n.t('cancel')),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(l10n.d('Ontkoppelen')),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    _rebuild(() => _source = null);
    _emit();
  }
}

/// One number as it would read under a convention, for the preview in
/// [askDecimalConvention]. Kept local and blunt: this is a sample, not output.
String _previewNumber(double? value) {
  if (value == null) return '?';
  return value == value.roundToDouble()
      ? value.toInt().toString()
      : value.toString();
}

/// Ask how the commas in an imported CSV are meant.
///
/// Only reached when the file itself does not settle it — see
/// [scanDecimalConvention]. Rather than describe the two conventions in the
/// abstract, both options show what *these* values become, because "1,234 or
/// 1234?" is a question anyone can answer about their own data while "decimal
/// separator" is not.
///
/// Returns null when the user backs out, which cancels the import rather than
/// falling back to a reading nobody chose.
Future<DecimalConvention?> askDecimalConvention(
  BuildContext context,
  List<String> values,
) {
  final l10n = context.l10n;
  final samples = values.toSet().take(3).toList();
  String previewOf(DecimalConvention convention) => [
    for (final v in samples) _previewNumber(parseNumberUnder(v, convention)),
  ].join(' · ');

  return showDialog<DecimalConvention>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(l10n.d('Getalnotatie herkennen')),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l10n.d(
              'In dit bestand staan getallen waarvan de komma op twee manieren te lezen is:',
            ),
          ),
          const SizedBox(height: 8),
          Text(
            samples.join(' · '),
            style: const TextStyle(
              fontFeatures: [FontFeature.tabularFigures()],
            ),
          ),
          const SizedBox(height: 16),
          ListTile(
            key: const ValueKey('csv-convention-thousands'),
            title: Text(l10n.d('Duizendtalscheiding')),
            subtitle: Text(previewOf(DecimalConvention.dot)),
            onTap: () => Navigator.pop(ctx, DecimalConvention.dot),
          ),
          ListTile(
            key: const ValueKey('csv-convention-decimal'),
            title: Text(l10n.d('Decimaalteken')),
            subtitle: Text(previewOf(DecimalConvention.comma)),
            onTap: () => Navigator.pop(ctx, DecimalConvention.comma),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: Text(l10n.t('cancel')),
        ),
      ],
    ),
  );
}
