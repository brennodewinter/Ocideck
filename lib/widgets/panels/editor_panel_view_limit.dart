// Part of the editor_panel library — see editor_panel.dart.
//
// De view-limit-editor (#672): de sectie "Weergave beperken" in de
// dia-instellingen. Een eigen part omdat editor_panel_slide_settings zijn
// regelplafond raakte; zelfde library, zelfde private leden.
part of 'editor_panel.dart';

// ── View limit editor ────────────────────────────────────────────────────────

bool _supportsViewLimit(SlideType type) =>
    type == SlideType.bullets ||
    type == SlideType.twoBullets ||
    type == SlideType.bulletsImage ||
    type == SlideType.timeline ||
    type == SlideType.table ||
    type == SlideType.scorecard ||
    type == SlideType.assets ||
    type == SlideType.discoveries ||
    type == SlideType.checklist ||
    type == SlideType.scopeMatrix ||
    type == SlideType.findingsSummary ||
    type == SlideType.chart;

String _displayWindowModeLabel(AppLocalizations l10n, DisplayWindowMode mode) {
  switch (mode) {
    case DisplayWindowMode.first:
      return l10n.d('Eerste');
    case DisplayWindowMode.last:
      return l10n.d('Laatste');
    case DisplayWindowMode.top:
      return l10n.d('Hoogste');
    case DisplayWindowMode.bottom:
      return l10n.d('Laagste');
  }
}

String _displayWindowRemainderLabel(
  AppLocalizations l10n,
  DisplayWindowRemainder remainder,
) {
  switch (remainder) {
    case DisplayWindowRemainder.hide:
      return l10n.d('Verbergen, wel bewaren');
    case DisplayWindowRemainder.other:
      return l10n.d('Samenvoegen tot Overig');
  }
}

class _ViewLimitSetting extends StatefulWidget {
  final Slide slide;
  final ValueChanged<Slide> onUpdate;

  const _ViewLimitSetting({required this.slide, required this.onUpdate});

  @override
  State<_ViewLimitSetting> createState() => _ViewLimitSettingState();
}

class _ViewLimitSettingState extends State<_ViewLimitSetting> {
  late final TextEditingController _limitController;
  late final TextEditingController _keyController;
  final _limitFocus = FocusNode();
  final _keyFocus = FocusNode();
  String? _limitError;

  @override
  void initState() {
    super.initState();
    final spec = widget.slide.viewLimit;
    _limitController = TextEditingController(
      text: spec?.limit?.toString() ?? '',
    );
    _keyController = TextEditingController(text: spec?.key ?? '');
  }

  @override
  void dispose() {
    _limitController.dispose();
    _keyController.dispose();
    _limitFocus.dispose();
    _keyFocus.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant _ViewLimitSetting oldWidget) {
    super.didUpdateWidget(oldWidget);
    final spec = widget.slide.viewLimit;
    if (!_limitFocus.hasFocus &&
        spec?.limit?.toString() != _limitController.text) {
      _limitController.text = spec?.limit?.toString() ?? '';
    }
    if (!_keyFocus.hasFocus && spec?.key != _keyController.text) {
      _keyController.text = spec?.key ?? '';
    }
  }

  void _updateLimit() {
    final raw = _limitController.text.trim();
    final n = raw.isEmpty ? null : int.tryParse(raw);
    if (raw.isNotEmpty && n == null) {
      setState(() => _limitError = 'Geef een heel getal op');
      return;
    }
    if (n != null && n <= 0) {
      setState(() => _limitError = 'Limiet moet groter dan 0 zijn');
      return;
    }
    setState(() => _limitError = null);
    final spec = widget.slide.viewLimit ?? const DisplayWindowSpec();
    widget.onUpdate(
      widget.slide.copyWith(
        viewLimit: spec.copyWith(limit: n, clearLimit: n == null),
      ),
    );
  }

  void _updateKey() {
    final spec = widget.slide.viewLimit ?? const DisplayWindowSpec();
    widget.onUpdate(
      widget.slide.copyWith(
        viewLimit: spec.copyWith(key: _keyController.text.trim()),
      ),
    );
  }

  void _updateMode(DisplayWindowMode? mode) {
    if (mode == null) return;
    final spec = widget.slide.viewLimit ?? const DisplayWindowSpec();
    widget.onUpdate(
      widget.slide.copyWith(viewLimit: spec.copyWith(mode: mode)),
    );
  }

  void _updateRemainder(DisplayWindowRemainder? remainder) {
    if (remainder == null) return;
    final spec = widget.slide.viewLimit ?? const DisplayWindowSpec();
    widget.onUpdate(
      widget.slide.copyWith(viewLimit: spec.copyWith(remainder: remainder)),
    );
  }

  void _updateShowCount(bool value) {
    final spec = widget.slide.viewLimit ?? const DisplayWindowSpec();
    widget.onUpdate(
      widget.slide.copyWith(viewLimit: spec.copyWith(showCount: value)),
    );
  }

  void _toggle(bool enabled) {
    widget.onUpdate(
      widget.slide.copyWith(
        viewLimit: enabled ? const DisplayWindowSpec(limit: 5) : null,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final spec = widget.slide.viewLimit;
    final active = spec?.isActive == true;

    return _SettingsGroup(
      label: l10n.d('Weergave beperken'),
      children: [
        _SettingRow(
          icon: Icons.filter_list_outlined,
          label: l10n.d('Beperk het aantal getoonde items'),
          help: l10n.d(
            'Toon alleen een deel van de bullets, tabel of grafiek. De oorspronkelijke data blijft in het bestand bewaard.',
          ),
          control: _SettingSwitch(
            value: active,
            semanticLabel: l10n.d('Beperk het aantal getoonde items'),
            onChanged: _toggle,
          ),
          detail: active
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _SettingRow(
                      icon: Icons.format_list_numbered,
                      label: l10n.d('Maximaal aantal items'),
                      control: SizedBox(
                        width: 80,
                        child: TextField(
                          controller: _limitController,
                          focusNode: _limitFocus,
                          keyboardType: TextInputType.number,
                          textAlign: TextAlign.end,
                          style: const TextStyle(fontSize: 12),
                          decoration: InputDecoration(
                            isDense: true,
                            contentPadding: const EdgeInsets.symmetric(
                              vertical: 6,
                              horizontal: 6,
                            ),
                            errorText: _limitError,
                          ),
                          onChanged: (_) => _updateLimit(),
                        ),
                      ),
                    ),
                    _SettingRow(
                      icon: Icons.sort,
                      label: l10n.d('Welke items'),
                      control: _SettingDropdown<DisplayWindowMode>(
                        value: spec!.mode,
                        items: [
                          for (final mode in DisplayWindowMode.values)
                            DropdownMenuItem(
                              value: mode,
                              child: Text(
                                _displayWindowModeLabel(l10n, mode),
                                style: const TextStyle(fontSize: 12),
                              ),
                            ),
                        ],
                        onChanged: _updateMode,
                      ),
                    ),
                    _SettingRow(
                      icon: Icons.key,
                      label: l10n.d('Sorteerkolom of reeks'),
                      help: l10n.d(
                        'Voor tabellen: kolomindex of naam om op te sorteren. Voor grafieken: naam van de reeks.',
                      ),
                      control: SizedBox(
                        width: 80,
                        child: TextField(
                          controller: _keyController,
                          focusNode: _keyFocus,
                          style: const TextStyle(fontSize: 12),
                          decoration: const InputDecoration(
                            isDense: true,
                            contentPadding: EdgeInsets.symmetric(
                              vertical: 6,
                              horizontal: 6,
                            ),
                          ),
                          onChanged: (_) => _updateKey(),
                        ),
                      ),
                    ),
                    _SettingRow(
                      icon: Icons.more_horiz,
                      label: l10n.d('Niet-getoonde items'),
                      control: _SettingDropdown<DisplayWindowRemainder>(
                        value: spec.remainder,
                        items: [
                          for (final r in DisplayWindowRemainder.values)
                            DropdownMenuItem(
                              value: r,
                              child: Text(
                                _displayWindowRemainderLabel(l10n, r),
                                style: const TextStyle(fontSize: 12),
                              ),
                            ),
                        ],
                        onChanged: _updateRemainder,
                      ),
                    ),
                    _SettingRow(
                      icon: Icons.countertops,
                      label: l10n.d('Toon hoeveel items verborgen zijn'),
                      control: _SettingSwitch(
                        value: spec.showCount,
                        semanticLabel: l10n.d(
                          'Toon hoeveel items verborgen zijn',
                        ),
                        onChanged: _updateShowCount,
                      ),
                    ),
                    // De hele dataset blijft zichtbaar bewerkbaar; hier staat
                    // hoevéél er is en hoeveel de dia toont, zodat de limiet
                    // nooit als verlies leest (#672).
                    Padding(
                      padding: const EdgeInsets.only(left: 26, top: 4),
                      child: Text(
                        '${l10n.d('In de data')}: $_totalItems · '
                        '${l10n.d('getoond')}: $_shownItems',
                        style: TextStyle(
                          fontSize: 11,
                          color: AppTheme.slate500,
                        ),
                      ),
                    ),
                    if (_needsNumericWarning(spec))
                      Padding(
                        padding: const EdgeInsets.only(left: 26, top: 4),
                        child: Text(
                          l10n.d(
                            'De sorteerkolom bevat geen getallen; hoogste/laagste en samenvoegen werken dan niet zinvol.',
                          ),
                          style: TextStyle(
                            fontSize: 11,
                            color: AppTheme.amber700,
                          ),
                        ),
                      ),
                  ],
                )
              : null,
        ),
      ],
    );
  }

  /// Hoeveel items de data van deze dia draagt, per soort.
  int get _totalItems {
    final slide = widget.slide;
    if (slide.type == SlideType.chart) {
      return ChartSpec.parse(slide.customMarkdown).x.length;
    }
    if (slide.tableRows.isNotEmpty) {
      return slide.tableRows.length - 1; // minus de kopregel
    }
    return slide.bullets.length;
  }

  int get _shownItems {
    final limit = widget.slide.viewLimit?.limit;
    final total = _totalItems;
    if (limit == null || limit <= 0) return total;
    return limit < total ? limit : total;
  }

  /// Waarschuw wanneer top/laagste of samenvoegen op een tabelkolom staat die
  /// geen getallen draagt — dan is de rangschikking betekenisloos (#672).
  bool _needsNumericWarning(DisplayWindowSpec spec) {
    final slide = widget.slide;
    final sortsOnValue =
        spec.mode == DisplayWindowMode.top ||
        spec.mode == DisplayWindowMode.bottom ||
        spec.remainder == DisplayWindowRemainder.other;
    if (!sortsOnValue) return false;
    if (slide.type == SlideType.chart || slide.tableRows.length < 2) {
      return false;
    }
    final data = slide.tableRows.skip(1).toList();
    final keyIndex = int.tryParse(spec.key.trim());
    if (keyIndex == null) return spec.key.trim().isNotEmpty;
    return !const DisplayWindowService().isNumericColumn(data, keyIndex);
  }
}
