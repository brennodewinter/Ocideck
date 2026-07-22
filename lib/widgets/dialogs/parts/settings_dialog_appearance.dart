// Part of the settings_dialog library — see ../settings_dialog.dart.
// Split out for navigability (appearance tab + helpers); all imports live in the main
// library file. Instance methods relocate verbatim into an extension on
// _SettingsDialogState — same library, same members, no behaviour change.
part of '../settings_dialog.dart';

extension _SettingsAppearanceTab on _SettingsDialogState {
  Widget _appearanceTab() {
    final l10n = context.l10n;
    final profiles = ref.watch(settingsProvider).appAppearanceProfiles;
    final selectedName =
        profiles.any((profile) => profile.name == _originalAppearanceName)
        ? _originalAppearanceName
        : profiles.first.name;
    final editable = !_appearanceProfile.isBuiltIn;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionTitle(l10n.d('Look-and-feel')),
        _appearanceProfileSelector(profiles, selectedName, editable),
        const SizedBox(height: 12),
        TextField(
          controller: _appearanceName,
          enabled: editable,
          decoration: InputDecoration(
            labelText: l10n.d('Themanaam'),
            isDense: true,
            prefixIcon: const Icon(Icons.badge_outlined, size: 18),
          ),
          onChanged: (value) {
            if (value.trim().isNotEmpty) {
              _appearanceProfile = _appearanceProfile.copyWith(
                name: value.trim(),
              );
            }
          },
        ),
        if (!editable)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              l10n.d(
                'Dit is een ingebouwd thema. Maak een kopie om kleuren aan te passen.',
              ),
              style: TextStyle(
                fontSize: 11,
                color: Theme.of(context).extension<AppPalette>()?.mutedText,
              ),
            ),
          ),
        const SizedBox(height: 12),
        SwitchListTile(
          value: _appearanceProfile.isDark,
          onChanged: editable
              ? (value) => _rebuild(() {
                  _appearanceProfile = _appearanceProfile.copyWith(
                    isDark: value,
                  );
                })
              : null,
          title: Text(
            l10n.d('Donkere interface'),
            style: const TextStyle(fontSize: 13),
          ),
          subtitle: Text(
            l10n.d('Past contrast, invoervelden en systeemcomponenten aan.'),
            style: const TextStyle(fontSize: 11),
          ),
          contentPadding: EdgeInsets.zero,
          dense: true,
        ),
        const SizedBox(height: 8),
        _appearanceFontField(editable),
        const SizedBox(height: 8),
        _appearanceColorSetting(
          l10n.d('Hoofdkleur en bovenbalk'),
          _appearanceProfile.primaryColor,
          editable,
          (value) => _appearanceProfile = _appearanceProfile.copyWith(
            primaryColor: value,
          ),
        ),
        _appearanceColorSetting(
          l10n.d('Knoppen en accenten'),
          _appearanceProfile.accentColor,
          editable,
          (value) => _appearanceProfile = _appearanceProfile.copyWith(
            accentColor: value,
          ),
        ),
        _appearanceColorSetting(
          l10n.d('Schermachtergrond'),
          _appearanceProfile.backgroundColor,
          editable,
          (value) => _appearanceProfile = _appearanceProfile.copyWith(
            backgroundColor: value,
          ),
        ),
        _appearanceColorSetting(
          l10n.d('Kaarten en dialogen'),
          _appearanceProfile.surfaceColor,
          editable,
          (value) => _appearanceProfile = _appearanceProfile.copyWith(
            surfaceColor: value,
          ),
        ),
        _appearanceColorSetting(
          l10n.d('Tekst'),
          _appearanceProfile.textColor,
          editable,
          (value) => _appearanceProfile = _appearanceProfile.copyWith(
            textColor: value,
          ),
        ),
        _appearanceColorSetting(
          l10n.d('Gedempte tekst'),
          _appearanceProfile.mutedTextColor,
          editable,
          (value) => _appearanceProfile = _appearanceProfile.copyWith(
            mutedTextColor: value,
          ),
        ),
        _appearanceColorSetting(
          l10n.d('Zijpanelen'),
          _appearanceProfile.panelColor,
          editable,
          (value) => _appearanceProfile = _appearanceProfile.copyWith(
            panelColor: value,
          ),
        ),
        _appearanceColorSetting(
          l10n.d('Tekst op zijpanelen'),
          _appearanceProfile.panelTextColor,
          editable,
          (value) => _appearanceProfile = _appearanceProfile.copyWith(
            panelTextColor: value,
          ),
        ),
        const SizedBox(height: 8),
        _appearancePreview(),
      ],
    );
  }

  Widget _appearanceProfileSelector(
    List<AppAppearanceProfile> profiles,
    String selectedName,
    bool editable,
  ) {
    final l10n = context.l10n;
    return Row(
      children: [
        Expanded(
          child: DropdownButtonFormField<String>(
            initialValue: selectedName,
            // isExpanded laat het item een begrensde breedte krijgen zodat de
            // Flexible-naam kan ellipsen — en voorkomt de onbegrensde
            // intrinsieke meting die anders op de Flexible zou crashen.
            isExpanded: true,
            decoration: InputDecoration(
              labelText: l10n.d('App-thema'),
              isDense: true,
            ),
            items: [
              for (final profile in profiles)
                DropdownMenuItem(
                  value: profile.name,
                  child: Row(
                    children: [
                      _appearanceDot(profile.primaryColor),
                      const SizedBox(width: 8),
                      Flexible(
                        child: Text(
                          profile.name,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
            onChanged: (name) {
              if (name == null) return;
              final profile = profiles.firstWhere((item) => item.name == name);
              _rebuild(() {
                _appearanceProfile = profile;
                _originalAppearanceName = profile.name;
                _appearanceName.text = profile.name;
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
                .createAppAppearanceProfile(base: _appearanceProfile);
            if (!mounted) return;
            _rebuild(() {
              _appearanceProfile = created;
              _originalAppearanceName = created.name;
              _appearanceName.text = created.name;
            });
          },
          icon: const Icon(Icons.add, size: 18),
        ),
        IconButton(
          tooltip: l10n.d('Thema verwijderen'),
          onPressed: editable
              ? () async {
                  await ref
                      .read(settingsProvider.notifier)
                      .deleteAppAppearanceProfile(_appearanceProfile.name);
                  if (!mounted) return;
                  const profile = AppAppearanceProfile.basic;
                  _rebuild(() {
                    _appearanceProfile = profile;
                    _originalAppearanceName = profile.name;
                    _appearanceName.text = profile.name;
                  });
                }
              : null,
          icon: const Icon(Icons.delete_outline, size: 18),
        ),
      ],
    );
  }

  Widget _appearanceFontField(bool editable) {
    final l10n = context.l10n;
    return InputDecorator(
      decoration: InputDecoration(
        labelText: l10n.d('Lettertype interface'),
        isDense: true,
        prefixIcon: const Icon(Icons.font_download_outlined, size: 18),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value:
              AppAppearanceProfile.uiFonts.contains(
                _appearanceProfile.fontFamily,
              )
              ? _appearanceProfile.fontFamily
              : 'Roboto',
          isExpanded: true,
          isDense: true,
          items: [
            for (final family in AppAppearanceProfile.uiFonts)
              DropdownMenuItem(
                value: family,
                child: Text(family, style: TextStyle(fontFamily: family)),
              ),
          ],
          onChanged: editable
              ? (value) {
                  if (value == null) return;
                  _rebuild(() {
                    _appearanceProfile = _appearanceProfile.copyWith(
                      fontFamily: value,
                    );
                  });
                }
              : null,
        ),
      ),
    );
  }

  Widget _appearanceColorSetting(
    String label,
    String value,
    bool enabled,
    ValueChanged<String> onChanged,
  ) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          _appearanceDot(value, size: 30),
          const SizedBox(width: 10),
          Expanded(
            child: TextFormField(
              key: ValueKey('$label-$value-$enabled'),
              initialValue: value,
              enabled: enabled,
              decoration: InputDecoration(labelText: label, isDense: true),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[0-9a-fA-F#]')),
                LengthLimitingTextInputFormatter(7),
              ],
              onChanged: (input) {
                final normalized = input.startsWith('#')
                    ? input.toUpperCase()
                    : '#${input.toUpperCase()}';
                if (RegExp(r'^#[0-9A-F]{6}$').hasMatch(normalized)) {
                  _rebuild(() => onChanged(normalized));
                }
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _appearanceDot(String value, {double size = 18}) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: AppTheme.parseHexColor(value),
        shape: BoxShape.circle,
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
      ),
    );
  }

  Widget _appearancePreview() {
    final profile = _appearanceProfile;
    final foreground = AppTheme.parseHexColor(profile.textColor);
    return Container(
      height: 112,
      decoration: BoxDecoration(
        color: AppTheme.parseHexColor(profile.backgroundColor),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppTheme.parseHexColor(profile.panelColor)),
      ),
      child: Column(
        children: [
          Container(
            height: 30,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            color: AppTheme.parseHexColor(profile.primaryColor),
            child: Row(
              children: [
                Text(
                  context.l10n.d('OciDeck'),
                  style: TextStyle(
                    color: _contrastColor(
                      AppTheme.parseHexColor(profile.primaryColor),
                    ),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(10),
              child: Row(
                children: [
                  Container(
                    width: 52,
                    color: AppTheme.parseHexColor(profile.panelColor),
                    alignment: Alignment.center,
                    child: Icon(
                      Icons.slideshow_outlined,
                      color: AppTheme.parseHexColor(profile.panelTextColor),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.all(8),
                      color: AppTheme.parseHexColor(profile.surfaceColor),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              context.l10n.d('Voorbeeldtekst'),
                              style: TextStyle(color: foreground),
                            ),
                          ),
                          FilledButton(
                            style: FilledButton.styleFrom(
                              backgroundColor: AppTheme.parseHexColor(
                                profile.accentColor,
                              ),
                              foregroundColor: _contrastColor(
                                AppTheme.parseHexColor(profile.accentColor),
                              ),
                            ),
                            onPressed: () {},
                            child: Text(context.l10n.d('Knop')),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Color _contrastColor(Color color) {
    return color.computeLuminance() > 0.55 ? Colors.black : Colors.white;
  }

  /// Lettertype-keuze — hoort bij de stijl (themeProfile), niet bij de app.
  Widget _fontSection() {
    return Container(
      decoration: _boxDecoration(),
      child: Column(
        children: AppSettings.availableFonts.map((font) {
          final selected = font == _themeProfile.fontFamily;
          return InkWell(
            onTap: () => _rebuild(() {
              _themeProfile = _themeProfile.copyWith(fontFamily: font);
              _profileTouched = true;
            }),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: selected
                    ? AppTheme.accent.withValues(alpha: 0.08)
                    : Colors.transparent,
                border: Border(
                  bottom: BorderSide(
                    color: AppTheme.slate200,
                    width: font == AppSettings.availableFonts.last ? 0 : 1,
                  ),
                ),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      font,
                      style: _fontStyle(
                        font,
                        TextStyle(
                          fontSize: 15,
                          color: selected
                              ? AppTheme.accentFg
                              : AppTheme.slate700,
                          fontWeight: selected
                              ? FontWeight.w600
                              : FontWeight.normal,
                        ),
                      ),
                    ),
                  ),
                  if (selected)
                    Icon(Icons.check, size: 16, color: AppTheme.accentFg),
                ],
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  /// A banner shown on tabs that edit the active style profile, so it is clear
  /// these settings belong to the loaded profile (and which one).
  Widget _profileScopeBanner() {
    final name = _themeProfile.name;
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppTheme.accent.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border(left: BorderSide(color: AppTheme.accent, width: 3)),
      ),
      child: Row(
        children: [
          Icon(Icons.style_outlined, size: 16, color: AppTheme.accentFg),
          const SizedBox(width: 8),
          Expanded(
            child: Text.rich(
              TextSpan(
                children: [
                  TextSpan(text: context.l10n.d('Presentatiestijl: ')),
                  TextSpan(
                    text: '“$name”',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ],
              ),
              style: TextStyle(fontSize: 12, color: AppTheme.slate700),
            ),
          ),
        ],
      ),
    );
  }
}
