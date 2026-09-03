// Part of the settings_dialog library — see ../settings_dialog.dart.
// Split out for navigability (general + cockpit tabs); all imports live in the main
// library file. Instance methods relocate verbatim into an extension on
// _SettingsDialogState — same library, same members, no behaviour change.
part of '../settings_dialog.dart';

extension _SettingsGeneralTab on _SettingsDialogState {
  /// Zet de taal terug zoals ze bij het openen was wanneer het venster zonder
  /// opslaan sluit. Alleen schrijven als er écht iets veranderde, zodat een
  /// gewone Annuleren geen instellingen aanraakt.
  void _restoreLanguageIfDiscarded() {
    if (_saved) return;
    if (ref.read(settingsProvider).languageCode == _initialLanguageCode) return;
    ref.read(settingsProvider.notifier).setLanguageCode(_initialLanguageCode);
  }

  Widget _generalTab() {
    final l10n = context.l10n;
    final languageCode = ref.watch(
      settingsProvider.select((s) => s.languageCode),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionTitle(l10n.t('language')),
        InputDecorator(
          decoration: InputDecoration(
            labelText: l10n.t('applicationLanguage'),
            isDense: true,
            prefixIcon: const Icon(Icons.language, size: 18),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: languageCode,
              isExpanded: true,
              isDense: true,
              items: [
                for (final entry in AppLocalizations.languageOptions)
                  DropdownMenuItem(
                    value: entry.key,
                    child: languageOptionRow(entry.key, entry.value),
                  ),
              ],
              onChanged: (code) {
                if (code == null) return;
                ref.read(settingsProvider.notifier).setLanguageCode(code);
              },
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Text(
            l10n.t('languageHelp'),
            style: TextStyle(fontSize: 11, color: AppTheme.slate400),
          ),
        ),
        const SizedBox(height: 16),
        ..._accessibilitySettings(),
        const SizedBox(height: 16),
        ..._exportQualitySettings(),
        const SizedBox(height: 16),
        ..._documentStyleSection(ref, l10n),
      ],
    );
  }

  List<Widget> _accessibilitySettings() {
    final l10n = context.l10n;
    return [
      _sectionTitle(l10n.d('Toegankelijkheid')),
      _uiTextScaleField(),
      Padding(
        padding: const EdgeInsets.only(top: 6),
        child: Text(
          l10n.d(
            'Vergroot alle tekst van de bewerkomgeving tot maximaal 200%. De slides zelf veranderen niet mee.',
          ),
          style: TextStyle(fontSize: 11, color: AppTheme.slate400),
        ),
      ),
      const SizedBox(height: 8),
      Builder(
        builder: (context) {
          const presets = <double>[4.5, 4.0, 3.5, 3.0];
          final current = ref.watch(
            settingsProvider.select((s) => s.contrastMinRatio),
          );
          // Keep the current value selectable even if it is not a preset.
          final values = <double>{...presets, current}.toList()
            ..sort((a, b) => b.compareTo(a));
          return ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(
              l10n.d('Minimale contrastverhouding'),
              style: const TextStyle(fontSize: 13),
            ),
            subtitle: Text(
              l10n.d(
                'Tekst onder deze verhouding wordt gemarkeerd. 4.5 = WCAG AA, 3.0 = WCAG AA grote tekst. Hoger is strenger.',
              ),
              style: TextStyle(fontSize: 11, color: AppTheme.slate400),
            ),
            trailing: DropdownButton<double>(
              value: current,
              items: [
                for (final v in values)
                  DropdownMenuItem<double>(
                    value: v,
                    child: Text('${v.toStringAsFixed(1)} : 1'),
                  ),
              ],
              onChanged: (v) {
                if (v != null) {
                  ref.read(settingsProvider.notifier).setContrastMinRatio(v);
                }
              },
            ),
          );
        },
      ),
    ];
  }

  /// Exportkwaliteit: waarschuwen en blokkeren bij slide-kwaliteitsproblemen.
  /// Dit is slide-kwaliteit (te veel bullets, contrast op de dia), niet
  /// toegankelijkheid van de interface — vandaar een eigen kop, niet onder
  /// Toegankelijkheid (#1956).
  List<Widget> _exportQualitySettings() {
    final l10n = context.l10n;
    return [
      _sectionTitle(l10n.d('Exportkwaliteit')),
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        title: Text(
          l10n.d('Waarschuwing bij export'),
          style: const TextStyle(fontSize: 13),
        ),
        subtitle: Text(
          l10n.d(
            'Vraag bevestiging voordat je exporteert wanneer er slide-kwaliteitsproblemen zijn.',
          ),
          style: TextStyle(fontSize: 11, color: AppTheme.slate400),
        ),
        value: ref.watch(
          settingsProvider.select((s) => s.qualityWarningsOnExport),
        ),
        onChanged: (value) => ref
            .read(settingsProvider.notifier)
            .setQualityWarningsOnExport(value),
      ),
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        title: Text(
          l10n.d('Blokkeer export bij ernstige kwaliteitsproblemen'),
          style: const TextStyle(fontSize: 13),
        ),
        subtitle: Text(
          l10n.d(
            'Export is niet mogelijk zolang er fouten in de slide-kwaliteitscontrole staan.',
          ),
          style: TextStyle(fontSize: 11, color: AppTheme.slate400),
        ),
        value: ref.watch(
          settingsProvider.select((s) => s.qualityBlockExportOnErrors),
        ),
        onChanged: (value) => ref
            .read(settingsProvider.notifier)
            .setQualityBlockExportOnErrors(value),
      ),
    ];
  }

  /// Dropdown with interface text-scale steps (WCAG 1.4.4 asks for up to
  /// 200%). The stored value snaps to the nearest offered step.
  Widget _uiTextScaleField() {
    final l10n = context.l10n;
    const steps = [1.0, 1.15, 1.3, 1.5, 1.75, 2.0];
    final current = ref.watch(settingsProvider.select((s) => s.uiTextScale));
    final value = steps.reduce(
      (a, b) => (a - current).abs() <= (b - current).abs() ? a : b,
    );
    return InputDecorator(
      decoration: InputDecoration(
        labelText: l10n.d('Tekstgrootte van de interface'),
        isDense: true,
        prefixIcon: const Icon(Icons.text_increase, size: 18),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<double>(
          value: value,
          isExpanded: true,
          isDense: true,
          items: [
            for (final step in steps)
              DropdownMenuItem(
                value: step,
                child: Text('${(step * 100).round()}%'),
              ),
          ],
          onChanged: (scale) {
            if (scale == null) return;
            ref.read(settingsProvider.notifier).setUiTextScale(scale);
          },
        ),
      ),
    );
  }

  Widget _classificationEnforcementSection(AppLocalizations l10n) {
    final settings = ref.watch(settingsProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _tlpPolicyDropdown(
          label: l10n.d('Vrijgaveplafond'),
          help: l10n.d(
            'Hoogste TLP-niveau dat geëxporteerd mag worden. Leeg = geen plafond.',
          ),
          noneLabel: l10n.d('Geen plafond'),
          currentKey: settings.maxReleaseExportTlpKey,
          includeNoneLevel: true,
          onChanged: (key) =>
              ref.read(settingsProvider.notifier).setMaxReleaseExportTlp(key),
        ),
        const SizedBox(height: 12),
        _tlpPolicyDropdown(
          label: l10n.d('Vereist minimumniveau'),
          help: l10n.d(
            'Laagste classificatie die een deck moet hebben om te exporteren. Leeg = geen minimum.',
          ),
          noneLabel: l10n.d('Geen minimum'),
          currentKey: settings.minRequiredExportTlpKey,
          includeNoneLevel: false,
          onChanged: (key) =>
              ref.read(settingsProvider.notifier).setMinRequiredExportTlp(key),
        ),
        const SizedBox(height: 8),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(
            l10n.d('Classificatie verplicht'),
            style: const TextStyle(fontSize: 13),
          ),
          subtitle: Text(
            l10n.d('Weiger export wanneer het deck geen TLP-niveau heeft.'),
            style: TextStyle(fontSize: 11, color: AppTheme.slate400),
          ),
          value: settings.requireClassificationOnExport,
          onChanged: (value) => ref
              .read(settingsProvider.notifier)
              .setRequireClassificationOnExport(value),
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(
            l10n.d('Classificatie-watermerk'),
            style: const TextStyle(fontSize: 13),
          ),
          subtitle: Text(
            l10n.d(
              'Toon een diagonaal watermerk met TLP en organisatie op elke slide.',
            ),
            style: TextStyle(fontSize: 11, color: AppTheme.slate400),
          ),
          value: settings.classificationWatermarkEnabled,
          onChanged: (value) => ref
              .read(settingsProvider.notifier)
              .setClassificationWatermarkEnabled(value),
        ),
      ],
    );
  }

  Widget _tlpPolicyDropdown({
    required String label,
    required String help,
    required String noneLabel,
    required String? currentKey,
    required ValueChanged<String?> onChanged,
    bool includeNoneLevel = true,
  }) {
    final levels = includeNoneLevel
        ? TlpLevel.values
        : TlpLevel.values.where((level) => level != TlpLevel.none);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InputDecorator(
          decoration: InputDecoration(
            labelText: label,
            isDense: true,
            prefixIcon: const Icon(Icons.shield_outlined, size: 18),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String?>(
              value: currentKey,
              isExpanded: true,
              isDense: true,
              items: [
                DropdownMenuItem(value: null, child: Text(noneLabel)),
                for (final level in levels)
                  DropdownMenuItem(value: level.key, child: Text(level.label)),
              ],
              onChanged: onChanged,
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Text(
            help,
            style: TextStyle(fontSize: 11, color: AppTheme.slate400),
          ),
        ),
      ],
    );
  }

  Widget _cockpitTab() {
    final l10n = context.l10n;
    final schemes = ref.watch(settingsProvider).cockpitColorSchemes;
    final selectedName = schemes.any((s) => s.name == _originalCockpitName)
        ? _originalCockpitName
        : schemes.first.name;
    final editable = !_cockpitScheme.isBuiltIn;
    final mutedText = Theme.of(context).extension<AppPalette>()?.mutedText;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionTitle(l10n.d('Weergave')),
        DropdownButtonFormField<CockpitVisualStyle>(
          isExpanded: true,
          initialValue: _cockpitVisualStyle,
          decoration: InputDecoration(
            labelText: l10n.d('Weergave'),
            isDense: true,
            prefixIcon: const Icon(Icons.speed_outlined, size: 18),
          ),
          items: [
            DropdownMenuItem(
              value: CockpitVisualStyle.authentic,
              child: Text(l10n.d('Authentieke cockpit')),
            ),
            DropdownMenuItem(
              value: CockpitVisualStyle.classic,
              child: Text(l10n.d('Klassiek')),
            ),
          ],
          onChanged: (style) {
            if (style != null) _rebuild(() => _cockpitVisualStyle = style);
          },
        ),
        const SizedBox(height: 20),
        _sectionTitle(l10n.d('Cockpit-kleurschema')),
        Text(
          l10n.d(
            'De statuskleuren van de cockpit-meters. Maak benoemde varianten; het gekozen schema geldt voor alle cockpit-slides.',
          ),
          style: TextStyle(fontSize: 11, color: mutedText),
        ),
        const SizedBox(height: 12),
        _cockpitSchemeSelector(schemes, selectedName, editable),
        const SizedBox(height: 12),
        TextField(
          controller: _cockpitName,
          enabled: editable,
          decoration: InputDecoration(
            labelText: l10n.d('Schemanaam'),
            isDense: true,
            prefixIcon: const Icon(Icons.badge_outlined, size: 18),
          ),
          onChanged: (value) {
            if (value.trim().isNotEmpty) {
              _cockpitScheme = _cockpitScheme.copyWith(name: value.trim());
            }
          },
        ),
        if (!editable)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              l10n.d(
                'Dit is het ingebouwde schema. Maak een kopie om kleuren aan te passen.',
              ),
              style: TextStyle(fontSize: 11, color: mutedText),
            ),
          ),
        const SizedBox(height: 16),
        _appearanceColorSetting(
          l10n.d('Goed'),
          _cockpitScheme.good,
          editable,
          (v) =>
              _rebuild(() => _cockpitScheme = _cockpitScheme.copyWith(good: v)),
        ),
        _appearanceColorSetting(
          l10n.d('Waarschuwing'),
          _cockpitScheme.warning,
          editable,
          (v) => _rebuild(
            () => _cockpitScheme = _cockpitScheme.copyWith(warning: v),
          ),
        ),
        _appearanceColorSetting(
          l10n.d('Kritiek'),
          _cockpitScheme.critical,
          editable,
          (v) => _rebuild(
            () => _cockpitScheme = _cockpitScheme.copyWith(critical: v),
          ),
        ),
        _appearanceColorSetting(
          l10n.d('Te laag (koud)'),
          _cockpitScheme.cold,
          editable,
          (v) =>
              _rebuild(() => _cockpitScheme = _cockpitScheme.copyWith(cold: v)),
        ),
        _appearanceColorSetting(
          l10n.d('Lucht (horizon)'),
          _cockpitScheme.sky,
          editable,
          (v) =>
              _rebuild(() => _cockpitScheme = _cockpitScheme.copyWith(sky: v)),
        ),
        _appearanceColorSetting(
          l10n.d('Grond (horizon)'),
          _cockpitScheme.ground,
          editable,
          (v) => _rebuild(
            () => _cockpitScheme = _cockpitScheme.copyWith(ground: v),
          ),
        ),
      ],
    );
  }

  Widget _cockpitSchemeSelector(
    List<CockpitColorScheme> schemes,
    String selectedName,
    bool editable,
  ) {
    final l10n = context.l10n;
    return Row(
      children: [
        Expanded(
          child: DropdownButtonFormField<String>(
            isExpanded: true,
            initialValue: selectedName,
            decoration: InputDecoration(
              labelText: l10n.d('Cockpit-kleurschema'),
              isDense: true,
            ),
            items: [
              for (final scheme in schemes)
                DropdownMenuItem(
                  value: scheme.name,
                  child: Row(
                    children: [
                      _appearanceDot(scheme.good),
                      const SizedBox(width: 8),
                      Flexible(
                        child: Text(
                          scheme.name,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
            onChanged: (name) {
              if (name == null) return;
              final scheme = schemes.firstWhere((s) => s.name == name);
              _rebuild(() {
                _cockpitScheme = scheme;
                _originalCockpitName = scheme.name;
                _cockpitName.text = scheme.name;
              });
            },
          ),
        ),
        const SizedBox(width: 8),
        IconButton(
          tooltip: l10n.d('Kopie maken en aanpassen'),
          onPressed: () async {
            final created = await ref
                .read(settingsProvider.notifier)
                .createCockpitColorScheme(base: _cockpitScheme);
            if (!mounted) return;
            _rebuild(() {
              _cockpitScheme = created;
              _originalCockpitName = created.name;
              _cockpitName.text = created.name;
            });
          },
          icon: const Icon(Icons.add, size: 18),
        ),
        IconButton(
          tooltip: l10n.d('Kleurschema verwijderen'),
          onPressed: editable
              ? () async {
                  await ref
                      .read(settingsProvider.notifier)
                      .deleteCockpitColorScheme(_cockpitScheme.name);
                  if (!mounted) return;
                  const scheme = CockpitColorScheme.standard;
                  _rebuild(() {
                    _cockpitScheme = scheme;
                    _originalCockpitName = scheme.name;
                    _cockpitName.text = scheme.name;
                  });
                }
              : null,
          icon: const Icon(Icons.delete_outline, size: 18),
        ),
      ],
    );
  }
}

/// Documentmodus-stijl: de standaardstijl voor documenten zonder eigen
/// `theme:`, en of die als huisstijl wordt afgedwongen. Puur weergave en
/// export — deze keuze raakt geen enkel `.md`-bestand (alleen een per-document
/// keuze in de editor doet dat, byte-chirurgisch). Top-level zodat de sectie
/// niet meetelt voor het regelplafond van [_SettingsDialogState].
List<Widget> _documentStyleSection(WidgetRef ref, AppLocalizations l10n) {
  final settings = ref.watch(settingsProvider);
  final profileNames = [for (final p in settings.themeProfiles) p.name];
  final defaultStyle = settings.documentDefaultStyle;
  // Een sinds verwijderd profiel mag de kiezer niet laten crashen.
  final value = profileNames.contains(defaultStyle) ? defaultStyle : null;
  return [
    SettingsSectionTitle(l10n.d('Uiterlijk van documenten')),
    Text(
      l10n.d(
        'De standaardstijl voor documenten die zelf geen stijl kiezen. Puur weergave en export — het schrijft niets in een bestand.',
      ),
      style: TextStyle(fontSize: 11, color: AppTheme.slate400),
    ),
    const SizedBox(height: 8),
    InputDecorator(
      decoration: InputDecoration(
        labelText: l10n.d('Standaard documentstijl'),
        isDense: true,
        prefixIcon: const Icon(Icons.style_outlined, size: 18),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: value,
          isExpanded: true,
          isDense: true,
          items: [
            DropdownMenuItem(child: Text(l10n.d('Geen (platte tekst)'))),
            for (final name in profileNames)
              DropdownMenuItem(value: name, child: Text(name)),
          ],
          onChanged: (name) =>
              ref.read(settingsProvider.notifier).setDocumentDefaultStyle(name),
        ),
      ),
    ),
    const SizedBox(height: 8),
    SwitchListTile(
      contentPadding: EdgeInsets.zero,
      dense: true,
      value: settings.documentStyleEnforced,
      onChanged: defaultStyle == null
          ? null
          : (v) =>
                ref.read(settingsProvider.notifier).setDocumentStyleEnforced(v),
      title: Text(
        l10n.d('Deze stijl afdwingen'),
        style: const TextStyle(fontSize: 13),
      ),
      subtitle: Text(
        l10n.d(
          'Negeer de eigen stijl van een document en gebruik overal de standaardstijl (huisstijl).',
        ),
        style: const TextStyle(fontSize: 11),
      ),
    ),
    SwitchListTile(
      contentPadding: EdgeInsets.zero,
      dense: true,
      value: settings.documentChapterPageBreak,
      onChanged: (v) =>
          ref.read(settingsProvider.notifier).setDocumentChapterPageBreak(v),
      title: Text(
        l10n.d('Nieuw hoofdstuk op een nieuwe pagina'),
        style: const TextStyle(fontSize: 13),
      ),
      subtitle: Text(
        l10n.d(
          'Laat elk hoofdstuk (een H1-kop) bij het exporteren en afdrukken op een nieuwe pagina beginnen.',
        ),
        style: const TextStyle(fontSize: 11),
      ),
    ),
    const SizedBox(height: 12),
    // Feature 2: instelbare schrijfbreedte van de visuele editor. Dit is de
    // maat van de stand "Leeskolom"; welke stand geldt, kiest de gebruiker in
    // de werkbalk van de documenteditor.
    Text(
      l10n.d('Schrijfbreedte editor'),
      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
    ),
    const SizedBox(height: 4),
    Text(
      l10n.d(
        'Hoe breed de leeskolom in de visuele modus is. Smal leest rustig, breed gebruikt meer van het scherm. Of je op die kolom, op paginabreedte of op het hele venster schrijft, kies je in de werkbalk.',
      ),
      style: const TextStyle(fontSize: 11),
    ),
    const SizedBox(height: 8),
    DropdownButtonFormField<double?>(
      initialValue: settings.documentEditorMaxWidth,
      // Zonder isExpanded meet de dropdown zich op zijn breedste label en
      // duwt dat een smalle kolom uit beeld.
      isExpanded: true,
      decoration: const InputDecoration(
        border: OutlineInputBorder(),
        contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      ),
      items: [
        DropdownMenuItem(value: 860, child: Text(l10n.d('Smal (860 px)'))),
        DropdownMenuItem(
          value: 1100,
          child: Text(l10n.d('Standaard (1100 px)')),
        ),
        DropdownMenuItem(value: 1400, child: Text(l10n.d('Breed (1400 px)'))),
      ],
      onChanged: (v) =>
          ref.read(settingsProvider.notifier).setDocumentEditorMaxWidth(v),
    ),
    const SizedBox(height: 16),
    // Feature 3: paginamaat en marges voor export.
    Text(
      l10n.d('Pagina-instellingen export'),
      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
    ),
    const SizedBox(height: 4),
    Text(
      l10n.d(
        'Paginamaat (ISO-216) en marges voor HTML-print, LaTeX en PDF-export.',
      ),
      style: const TextStyle(fontSize: 11),
    ),
    const SizedBox(height: 8),
    _pageSizeControls(l10n, ref, settings),
    const SizedBox(height: 8),
    _pageMarginsControls(l10n, ref, settings),
    const SizedBox(height: 8),
    _printBleedControls(l10n, ref, settings),
  ];
}

/// De paginamaat-keuze: reeks, nummer en oriëntatie apart.
///
/// Een vaste lijst met veelgebruikte maten dekte A3/A4/A5 en een handvol B en
/// C, maar wie op B1 of C6 drukt kwam er niet. ISO 216 is een raster van drie
/// reeksen maal elf nummers; die keuze uit elkaar trekken geeft alle 66 maten
/// (met oriëntatie) zonder een dropdown van 66 regels.
Widget _pageSizeControls(
  AppLocalizations l10n,
  WidgetRef ref,
  AppSettings settings,
) {
  final spec = settings.documentPageSize;
  final notifier = ref.read(settingsProvider.notifier);
  void set(PageSizeSpec next) => notifier.setDocumentPageSize(next);

  return LayoutBuilder(
    builder: (context, constraints) {
      final children = <Widget>[
        Expanded(
          child: DropdownButtonFormField<PaperSeries>(
            initialValue: spec.series,
            isExpanded: true,
            decoration: _pageSizeDecoration(l10n.d('Reeks')),
            items: [
              for (final series in PaperSeries.values)
                DropdownMenuItem(
                  value: series,
                  child: Text(_seriesLabel(l10n, series)),
                ),
            ],
            onChanged: (v) => v == null
                ? null
                : set(
                    PageSizeSpec(
                      series: v,
                      number: spec.number,
                      landscape: spec.landscape,
                    ),
                  ),
          ),
        ),
        Expanded(
          child: DropdownButtonFormField<int>(
            initialValue: spec.number,
            isExpanded: true,
            decoration: _pageSizeDecoration(l10n.d('Maat')),
            items: [
              for (var n = 0; n <= 10; n++)
                DropdownMenuItem(
                  value: n,
                  child: Text(
                    // De maatnaam plus zijn afmeting, want "B7" zegt niemand
                    // iets en "88 × 125 mm" wel.
                    _sizeItemLabel(
                      PageSizeSpec(series: spec.series, number: n),
                    ),
                  ),
                ),
            ],
            onChanged: (v) => v == null
                ? null
                : set(
                    PageSizeSpec(
                      series: spec.series,
                      number: v,
                      landscape: spec.landscape,
                    ),
                  ),
          ),
        ),
        Expanded(
          child: DropdownButtonFormField<bool>(
            initialValue: spec.landscape,
            isExpanded: true,
            decoration: _pageSizeDecoration(l10n.d('Richting')),
            items: [
              DropdownMenuItem(value: false, child: Text(l10n.d('Staand'))),
              DropdownMenuItem(value: true, child: Text(l10n.d('Liggend'))),
            ],
            onChanged: (v) => v == null
                ? null
                : set(
                    PageSizeSpec(
                      series: spec.series,
                      number: spec.number,
                      landscape: v,
                    ),
                  ),
          ),
        ),
      ];
      // Naast elkaar op een ruime kolom, onder elkaar op een smalle — dezelfde
      // afweging als bij de margevelden.
      if (constraints.maxWidth >= 420) {
        return Row(
          children: [
            for (var i = 0; i < children.length; i++) ...[
              if (i > 0) const SizedBox(width: 8),
              children[i],
            ],
          ],
        );
      }
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < children.length; i++) ...[
            if (i > 0) const SizedBox(height: 8),
            Row(children: [children[i]]),
          ],
        ],
      );
    },
  );
}

InputDecoration _pageSizeDecoration(String label) => InputDecoration(
  labelText: label,
  border: const OutlineInputBorder(),
  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
);

/// De reeks met waar ze voor bedoeld is — de letter alleen is een raadsel.
String _seriesLabel(AppLocalizations l10n, PaperSeries series) =>
    switch (series) {
      PaperSeries.a => 'A — ${l10n.d('documenten')}',
      PaperSeries.b => 'B — ${l10n.d('posters en boeken')}',
      PaperSeries.c => 'C — ${l10n.d('enveloppen')}',
    };

/// Bijv. `"A4 — 210 × 297 mm"`. De maten komen uit het model, zodat de
/// interface en de export het niet oneens kunnen zijn.
String _sizeItemLabel(PageSizeSpec spec) {
  final (w, h) = spec.dimensions;
  return '${spec.sizeName} — ${w.toStringAsFixed(0)} × '
      '${h.toStringAsFixed(0)} mm';
}

/// De marge-controls: vier tekstvelden (top/onder/links/rechts in mm).
Widget _pageMarginsControls(
  AppLocalizations l10n,
  WidgetRef ref,
  AppSettings settings,
) {
  final m = settings.documentPageMargins;
  final notifier = ref.read(settingsProvider.notifier);
  final fields = [
    _marginField(
      l10n.d('Boven (mm)'),
      m.topMm,
      (v) => notifier.setDocumentPageMargins(m.copyWith(topMm: v)),
    ),
    _marginField(
      l10n.d('Onder (mm)'),
      m.bottomMm,
      (v) => notifier.setDocumentPageMargins(m.copyWith(bottomMm: v)),
    ),
    _marginField(
      l10n.d('Links (mm)'),
      m.leftMm,
      (v) => notifier.setDocumentPageMargins(m.copyWith(leftMm: v)),
    ),
    _marginField(
      l10n.d('Rechts (mm)'),
      m.rightMm,
      (v) => notifier.setDocumentPageMargins(m.copyWith(rightMm: v)),
    ),
  ];
  // Vier velden naast elkaar passen alleen op een ruime kolom. Bij een smal
  // tabblad of grote tekst gaan ze twee-bij-twee — de overflow-stresspoort
  // vond hier 302 px die buiten beeld vielen bij 200% tekst.
  return LayoutBuilder(
    builder: (context, constraints) {
      final perRow = constraints.maxWidth >= 420 ? 4 : 2;
      final rows = <Widget>[];
      for (var i = 0; i < fields.length; i += perRow) {
        if (rows.isNotEmpty) rows.add(const SizedBox(height: 8));
        rows.add(
          Row(
            children: [
              for (var c = 0; c < perRow; c++) ...[
                if (c > 0) const SizedBox(width: 8),
                Expanded(child: fields[i + c]),
              ],
            ],
          ),
        );
      }
      return Column(mainAxisSize: MainAxisSize.min, children: rows);
    },
  );
}

/// De drukkersafloop: hoeveel millimeter het vel groter wordt dan het
/// snijformaat.
///
/// Standaard 0 — wie op kantoorpapier afdrukt heeft hier niets aan, en een
/// stille afloop van 3 mm zou zijn A4 tot een raar formaat maken. Drie
/// millimeter is wél wat een drukker doorgaans vraagt.
///
/// Bewust zonder snijtekens erbij: zie [PageMargins]. De uitleg noemt daarom
/// alleen wat de afloop echt doet.
Widget _printBleedControls(
  AppLocalizations l10n,
  WidgetRef ref,
  AppSettings settings,
) {
  final m = settings.documentPageMargins;
  final notifier = ref.read(settingsProvider.notifier);
  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    mainAxisSize: MainAxisSize.min,
    children: [
      _marginField(
        l10n.d('Afloop voor de drukker (mm)'),
        m.bleedMm,
        (v) => notifier.setDocumentPageMargins(m.copyWith(bleedMm: v)),
      ),
      const SizedBox(height: 4),
      Text(
        l10n.d(
          'Met afloop wordt de pagina rondom groter dan het gekozen formaat, zodat inkt die tot de rand loopt dóór de snijlijn heen gaat. De afloop geldt voor élke export tot je hem weer op 0 zet. Laat dit op 0 voor gewoon afdrukken.',
        ),
        style: const TextStyle(fontSize: 11),
      ),
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        value: m.hasBleed && settings.documentCropMarks,
        // Zonder afloop wijzen snijtekens nergens naar.
        onChanged: m.hasBleed
            ? (v) => ref.read(settingsProvider.notifier).setDocumentCropMarks(v)
            : null,
        title: Text(l10n.d('Snijtekens'), style: const TextStyle(fontSize: 12)),
        subtitle: Text(
          // Eerlijk over het bereik: het LaTeX-pad zet ze echt, de
          // browser-afdruk van de HTML-export niet — die kent `marks` uit CSS
          // Paged Media niet. Dat verschil hoort hier te staan en niet alleen
          // in de code.
          l10n.d(
            'Alleen in de LaTeX/PDF-export, en alleen met afloop. Vereist het crop-pakket in je TeX-installatie; een browser-afdruk van de HTML-export zet ze niet.',
          ),
          style: const TextStyle(fontSize: 11),
        ),
      ),
    ],
  );
}

Widget _marginField(
  String label,
  double value,
  ValueChanged<double> onChanged,
) => TextFormField(
  initialValue: value.toStringAsFixed(0),
  decoration: InputDecoration(
    labelText: label,
    border: const OutlineInputBorder(),
    contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
  ),
  keyboardType: const TextInputType.numberWithOptions(decimal: true),
  onChanged: (text) {
    final v = double.tryParse(text);
    if (v != null && v >= 0 && v <= 100) onChanged(v);
  },
);
