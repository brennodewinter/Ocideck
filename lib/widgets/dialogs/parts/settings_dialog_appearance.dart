// Part of the settings_dialog library — see ../settings_dialog.dart.
// Split out for navigability (appearance tab + helpers); all imports live in the main
// library file. Instance methods relocate verbatim into an extension on
// _SettingsDialogState — same library, same members, no behaviour change.
part of '../settings_dialog.dart';

extension _SettingsAppearanceTab on _SettingsDialogState {
  Widget _appearanceTab() {
    final l10n = context.l10n;
    // De wérkkopie, niet de provider (#760): aanmaken en verwijderen landen
    // pas bij Opslaan, dus tot dan is dit de lijst die de kiezer toont.
    final profiles = _appearanceProfiles;
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
        AppearancePreview(profile: _appearanceProfile),
        const SizedBox(height: 12),
        AppearanceLegibility(profile: _appearanceProfile),
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
              _rebuild(() {
                _syncAppearanceEdits();
                _selectAppearanceLocal(
                  _appearanceProfiles.firstWhere((item) => item.name == name),
                );
              });
            },
          ),
        ),
        const SizedBox(width: 8),
        // Beide knoppen bewerken de wérkkopie en raken de provider niet aan
        // (#760): één rij, één soort gedrag, en Annuleren draait álles terug.
        IconButton(
          tooltip: l10n.d('Kopie maken en aanpassen'),
          onPressed: () {
            _rebuild(() {
              _syncAppearanceEdits();
              final created = _appearanceProfile.copyWith(
                name: _uniqueLocalAppearanceName('Eigen thema'),
                isBuiltIn: false,
              );
              _appearanceProfiles = [..._appearanceProfiles, created];
              _selectAppearanceLocal(created);
            });
          },
          icon: const Icon(Icons.add, size: 18),
        ),
        IconButton(
          tooltip: l10n.d('Thema verwijderen'),
          onPressed: editable
              ? () {
                  _rebuild(() {
                    _appearanceProfiles = [
                      for (final item in _appearanceProfiles)
                        if (item.name != _originalAppearanceName) item,
                    ];
                    // Terug naar het thema van vóór de kopie; is dát het
                    // verwijderde, dan het eerste uit de lijst — maar nooit
                    // een naam die niet in de kiezer staat.
                    _selectAppearanceLocal(
                      _appearanceProfiles.firstWhere(
                        (item) => item.name == _appearanceOpenName,
                        orElse: () => _appearanceProfiles.first,
                      ),
                    );
                  });
                }
              : null,
          icon: const Icon(Icons.delete_outline, size: 18),
        ),
      ],
    );
  }

  /// Zet de kiezer, het naamveld en de bewerkstatus op [profile] — de drie
  /// horen altijd samen te bewegen.
  void _selectAppearanceLocal(AppAppearanceProfile profile) {
    _appearanceProfile = profile;
    _originalAppearanceName = profile.name;
    _appearanceName.text = profile.name;
  }

  /// Vouw de lopende bewerking (kleuren én naam) terug in de werkkopie, zodat
  /// wisselen, kopiëren of opslaan geen wijzigingen laat vallen.
  void _syncAppearanceEdits() {
    if (_appearanceProfile.isBuiltIn) return;
    final raw = _appearanceName.text.trim();
    final name = _uniqueLocalAppearanceName(
      raw.isEmpty ? 'Eigen thema' : raw,
      exceptName: _originalAppearanceName,
    );
    final updated = _appearanceProfile.copyWith(name: name, isBuiltIn: false);
    _appearanceProfiles = [
      for (final item in _appearanceProfiles)
        if (item.name == _originalAppearanceName) updated else item,
    ];
    _selectAppearanceLocal(updated);
  }

  /// Een naam die nog niet in de wérkkopie voorkomt — dezelfde regel die de
  /// provider bij het landen nog eens afdwingt, maar dan tegen wat de
  /// gebruiker nu op het scherm heeft.
  String _uniqueLocalAppearanceName(String base, {String? exceptName}) {
    final used = _appearanceProfiles
        .map((item) => item.name)
        .where((name) => name != exceptName)
        .toSet();
    if (!used.contains(base)) return base;
    var index = 2;
    while (used.contains('$base $index')) {
      index++;
    }
    return '$base $index';
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
}

/// De lettertypekeuze toont elk lettertype in zijn eigen letter. Top-level en
/// hier, bij de enige aanroeper — in de bibliotheekkop stond hij ver van het
/// scherm dat hem gebruikt.
TextStyle _fontStyle(String font, TextStyle base) =>
    base.copyWith(fontFamily: font);
