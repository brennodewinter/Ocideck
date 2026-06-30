// Part of the settings_dialog library — see ../settings_dialog.dart.
// Split out for navigability (general + cockpit tabs); all imports live in the main
// library file. Instance methods relocate verbatim into an extension on
// _SettingsDialogState — same library, same members, no behaviour change.
part of '../settings_dialog.dart';

extension _SettingsGeneralTab on _SettingsDialogState {
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
                for (final entry in AppLocalizations.languageNames.entries)
                  DropdownMenuItem(value: entry.key, child: Text(entry.value)),
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
            style: const TextStyle(fontSize: 11, color: Color(0xFF94A3B8)),
          ),
        ),
        const SizedBox(height: 16),
        ..._accessibilitySettings(),
        const SizedBox(height: 16),
        _sectionTitle(l10n.d('Presenteren')),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(
            l10n.d('Oefenoverzicht tonen na afloop'),
            style: const TextStyle(fontSize: 13),
          ),
          subtitle: Text(
            l10n.d(
              'Toon na een presentatie het overzicht met de bestede tijd per slide. De tijd wordt altijd gemeten; dit bepaalt alleen of het scherm verschijnt.',
            ),
            style: const TextStyle(fontSize: 11, color: Color(0xFF94A3B8)),
          ),
          value: ref.watch(
            settingsProvider.select((s) => s.showRehearsalSummary),
          ),
          onChanged: (value) => ref
              .read(settingsProvider.notifier)
              .setShowRehearsalSummary(value),
        ),
        const SizedBox(height: 16),
        _sectionTitle(l10n.d('Classificatie-handhaving')),
        _classificationEnforcementSection(l10n),
        const SizedBox(height: 16),
        _sectionTitle(l10n.t('presentationFolder')),
        Row(
          children: [
            Expanded(
              child: _pathBox(
                _homeDirectory ?? l10n.t('notSet'),
                muted: _homeDirectory == null,
              ),
            ),
            const SizedBox(width: 8),
            ElevatedButton.icon(
              onPressed: _pickHomeDirectory,
              icon: const Icon(Icons.folder_open, size: 16),
              label: Text(l10n.t('choose')),
            ),
            if (_homeDirectory != null)
              IconButton(
                onPressed: () => _rebuild(() => _homeDirectory = null),
                icon: const Icon(Icons.clear, size: 18),
                tooltip: l10n.t('removeDefaultFolder'),
              ),
          ],
        ),
        const SizedBox(height: 16),
        _sectionTitle(l10n.t('exportFolderSetting')),
        Row(
          children: [
            Expanded(
              child: _pathBox(
                _exportDirectory ?? l10n.t('nextToPresentationFile'),
                muted: _exportDirectory == null,
              ),
            ),
            const SizedBox(width: 8),
            ElevatedButton.icon(
              onPressed: _pickExportDirectory,
              icon: const Icon(Icons.folder_open, size: 16),
              label: Text(l10n.t('choose')),
            ),
            if (_exportDirectory != null)
              IconButton(
                onPressed: () => _rebuild(() => _exportDirectory = null),
                icon: const Icon(Icons.clear, size: 18),
                tooltip: l10n.t('removeExportFolder'),
              ),
          ],
        ),
        Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Text(
            l10n.t('exportFolderHelp'),
            style: const TextStyle(fontSize: 11, color: Color(0xFF94A3B8)),
          ),
        ),
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
          style: const TextStyle(fontSize: 11, color: Color(0xFF94A3B8)),
        ),
      ),
      const SizedBox(height: 8),
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
          style: const TextStyle(fontSize: 11, color: Color(0xFF94A3B8)),
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
          style: const TextStyle(fontSize: 11, color: Color(0xFF94A3B8)),
        ),
        value: ref.watch(
          settingsProvider.select((s) => s.qualityBlockExportOnErrors),
        ),
        onChanged: (value) => ref
            .read(settingsProvider.notifier)
            .setQualityBlockExportOnErrors(value),
      ),
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
              style: const TextStyle(fontSize: 11, color: Color(0xFF94A3B8)),
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
            style: const TextStyle(fontSize: 11, color: Color(0xFF94A3B8)),
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
            style: const TextStyle(fontSize: 11, color: Color(0xFF94A3B8)),
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
            style: const TextStyle(fontSize: 11, color: Color(0xFF94A3B8)),
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
                      Text(scheme.name),
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
