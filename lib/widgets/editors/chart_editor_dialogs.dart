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
      ChartType.pie => l10n.d('Cirkel'),
      ChartType.radar => l10n.d('Spider'),
      ChartType.scatter => l10n.d('Spreiding'),
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
              style: const TextStyle(fontSize: 12, color: AppTheme.slate500),
            ),
            const SizedBox(height: 12),
            for (var i = 0; i < _types.length; i++)
              ListTile(
                key: ValueKey('chart-variant-${_types[i].name}'),
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: Icon(switch (_types[i]) {
                  ChartType.bar => Icons.bar_chart,
                  ChartType.stackedBar => Icons.stacked_bar_chart,
                  ChartType.line => Icons.show_chart,
                  ChartType.pie => Icons.pie_chart_outline,
                  ChartType.radar => Icons.radar,
                  ChartType.scatter => Icons.scatter_plot,
                }),
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
                      onPressed: () => setState(() => _types.removeAt(i)),
                      icon: const Icon(Icons.close, size: 18),
                      tooltip: l10n.d('Niet toevoegen'),
                    ),
                  ],
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
