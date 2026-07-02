// Part of the settings_dialog library — see ../settings_dialog.dart.
// Split out for navigability (colour + logo sections); all imports live in the main
// library file. Instance methods relocate verbatim into an extension on
// _SettingsDialogState — same library, same members, no behaviour change.
part of '../settings_dialog.dart';

extension _SettingsColors on _SettingsDialogState {
  List<Widget> _colorsSectionChildren() {
    final l10n = context.l10n;
    return [
      _themeColorAnchor(
        'slideBackgroundColor',
        _colorSetting(
          l10n.d('Achtergrond slides'),
          _themeProfile.slideBackgroundColor,
          (v) =>
              _themeProfile = _themeProfile.copyWith(slideBackgroundColor: v),
        ),
      ),
      const SizedBox(height: 12),
      _themeColorAnchor(
        'textColor',
        _colorSetting(
          l10n.d('Tekst'),
          _themeProfile.textColor,
          (v) => _themeProfile = _themeProfile.copyWith(textColor: v),
        ),
      ),
      const SizedBox(height: 12),
      _themeColorAnchor(
        'accentColor',
        _colorSetting(
          l10n.d('Accent / bullets'),
          _themeProfile.accentColor,
          (v) => _themeProfile = _themeProfile.copyWith(accentColor: v),
        ),
      ),
      const SizedBox(height: 12),
      Row(
        children: [
          Expanded(
            child: Text(
              l10n.d('Opsommingsteken'),
              style: const TextStyle(fontSize: 13),
            ),
          ),
          SegmentedButton<BulletMarker>(
            segments: [
              ButtonSegment(
                value: BulletMarker.dot,
                icon: const Icon(Icons.fiber_manual_record, size: 12),
                label: Text(l10n.d('Stip')),
              ),
              ButtonSegment(
                value: BulletMarker.paw,
                icon: const Icon(Icons.pets, size: 16),
                label: Text(l10n.d('Pootje')),
              ),
            ],
            selected: {_themeProfile.bulletMarker},
            showSelectedIcon: false,
            style: const ButtonStyle(visualDensity: VisualDensity.compact),
            onSelectionChanged: (selection) => _rebuild(() {
              _themeProfile = _themeProfile.copyWith(
                bulletMarker: selection.first,
              );
              _profileTouched = true;
            }),
          ),
        ],
      ),
      ..._checklistTableColorSettings(),
      ..._codeColorSettings(),
    ];
  }

  /// Deck-wide default activation duration for animated slide types (timeline,
  /// cockpit). A slide inherits this unless it sets its own duration.
  List<Widget> _animationSettings() {
    final l10n = context.l10n;
    final ms = clampThemeAnimationDuration(_themeProfile.animationDurationMs);
    final seconds = ms / 1000;
    return [
      const SizedBox(height: 12),
      Row(
        children: [
          const Icon(Icons.timer_outlined, size: 18, color: AppTheme.slate500),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              l10n.d('Activatieduur'),
              style: const TextStyle(fontSize: 13),
            ),
          ),
          SizedBox(
            width: 44,
            child: Text(
              '${seconds.toStringAsFixed(1)}s',
              textAlign: TextAlign.right,
              style: const TextStyle(
                fontSize: 12,
                color: AppTheme.slate500,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
      Slider(
        min: kThemeMinAnimationDurationMs.toDouble(),
        max: kThemeMaxAnimationDurationMs.toDouble(),
        divisions:
            (kThemeMaxAnimationDurationMs - kThemeMinAnimationDurationMs) ~/
            200,
        label: '${seconds.toStringAsFixed(1)}s',
        value: ms.toDouble(),
        onChanged: (value) => _rebuild(() {
          _themeProfile = _themeProfile.copyWith(
            animationDurationMs: clampThemeAnimationDuration(
              (value / 100).round() * 100,
            ),
          );
          _profileTouched = true;
        }),
      ),
    ];
  }

  List<Widget> _checklistTableColorSettings() {
    final l10n = context.l10n;
    return [
      const SizedBox(height: 24),
      _sectionTitle(l10n.d('Checklist')),
      _themeColorAnchor(
        'checklistCheckedColor',
        _colorSetting(
          l10n.d('Afgevinkt'),
          _themeProfile.checklistCheckedColor,
          (v) =>
              _themeProfile = _themeProfile.copyWith(checklistCheckedColor: v),
        ),
      ),
      const SizedBox(height: 12),
      _themeColorAnchor(
        'checklistUncheckedColor',
        _colorSetting(
          l10n.d('Niet afgevinkt'),
          _themeProfile.checklistUncheckedColor,
          (v) => _themeProfile = _themeProfile.copyWith(
            checklistUncheckedColor: v,
          ),
        ),
      ),
      const SizedBox(height: 6),
      SwitchListTile(
        value: _themeProfile.checklistStrikeThrough,
        onChanged: (value) => _rebuild(() {
          _themeProfile = _themeProfile.copyWith(checklistStrikeThrough: value);
          _profileTouched = true;
        }),
        title: Text(
          l10n.d('Afgevinkte tekst doorhalen'),
          style: const TextStyle(fontSize: 13),
        ),
        subtitle: Text(
          l10n.d('Toont een streep door voltooide checklistitems.'),
          style: const TextStyle(fontSize: 11, color: AppTheme.slate400),
        ),
        controlAffinity: ListTileControlAffinity.leading,
        contentPadding: EdgeInsets.zero,
        dense: true,
      ),
      const SizedBox(height: 12),
      _themeColorAnchor(
        'tableTextColor',
        _colorSetting(
          l10n.d('Tabeltekst'),
          _themeProfile.tableTextColor,
          (v) => _themeProfile = _themeProfile.copyWith(tableTextColor: v),
        ),
      ),
      const SizedBox(height: 12),
      _themeColorAnchor(
        'tableHeaderTextColor',
        _colorSetting(
          l10n.d('Tabel koptekst'),
          _themeProfile.tableHeaderTextColor,
          (v) =>
              _themeProfile = _themeProfile.copyWith(tableHeaderTextColor: v),
        ),
      ),
      const SizedBox(height: 12),
      _themeColorAnchor(
        'tableHeaderBackgroundColor',
        _colorSetting(
          l10n.d('Tabel kopachtergrond'),
          _themeProfile.tableHeaderBackgroundColor,
          (v) => _themeProfile = _themeProfile.copyWith(
            tableHeaderBackgroundColor: v,
          ),
        ),
      ),
      const SizedBox(height: 12),
      _themeColorAnchor(
        'titleBackgroundColor',
        _colorSetting(
          l10n.d('Titelachtergrond'),
          _themeProfile.titleBackgroundColor,
          (v) =>
              _themeProfile = _themeProfile.copyWith(titleBackgroundColor: v),
        ),
      ),
      const SizedBox(height: 12),
      _themeColorAnchor(
        'titleTextColor',
        _colorSetting(
          l10n.d('Titeltekst'),
          _themeProfile.titleTextColor,
          (v) => _themeProfile = _themeProfile.copyWith(titleTextColor: v),
        ),
      ),
      const SizedBox(height: 12),
      _themeColorAnchor(
        'sectionBackgroundColor',
        _colorSetting(
          l10n.d('Sectieachtergrond'),
          _themeProfile.sectionBackgroundColor,
          (v) =>
              _themeProfile = _themeProfile.copyWith(sectionBackgroundColor: v),
        ),
      ),
    ];
  }

  List<Widget> _codeColorSettings() {
    final l10n = context.l10n;
    return [
      const SizedBox(height: 24),
      _sectionTitle(l10n.d('Broncode')),
      _themeColorAnchor(
        'codeBackgroundColor',
        _colorSetting(
          l10n.d('Broncode achtergrond'),
          _themeProfile.codeBackgroundColor,
          (v) => _themeProfile = _themeProfile.copyWith(codeBackgroundColor: v),
        ),
      ),
      const SizedBox(height: 12),
      _themeColorAnchor(
        'codeTextColor',
        _colorSetting(
          l10n.d('Broncode tekst'),
          _themeProfile.codeTextColor,
          (v) => _themeProfile = _themeProfile.copyWith(codeTextColor: v),
        ),
      ),
      const SizedBox(height: 6),
      SwitchListTile(
        value: _themeProfile.codeHighlightSyntax,
        onChanged: (v) => _rebuild(() {
          _themeProfile = _themeProfile.copyWith(codeHighlightSyntax: v);
          _profileTouched = true;
        }),
        title: Text(
          l10n.d('Syntaxkleuring'),
          style: const TextStyle(fontSize: 13),
        ),
        subtitle: Text(
          l10n.d(
            'Uit = alles in één kleur (bijv. groen op zwart voor een CRT-scherm).',
          ),
          style: const TextStyle(fontSize: 11, color: AppTheme.slate400),
        ),
        controlAffinity: ListTileControlAffinity.leading,
        contentPadding: EdgeInsets.zero,
        dense: true,
      ),
      const SizedBox(height: 10),
      DropdownButtonFormField<String>(
        initialValue:
            AppSettings.codeFonts.contains(_themeProfile.codeFontFamily)
            ? _themeProfile.codeFontFamily
            : 'monospace',
        decoration: InputDecoration(
          labelText: l10n.d('Broncode lettertype'),
          isDense: true,
        ),
        items: [
          for (final f in AppSettings.codeFonts)
            DropdownMenuItem(
              value: f,
              child: Text(
                f == 'monospace' ? l10n.d('Systeem (monospace)') : f,
                style: TextStyle(fontFamily: f),
              ),
            ),
        ],
        onChanged: (v) {
          if (v == null) return;
          _rebuild(() {
            _themeProfile = _themeProfile.copyWith(codeFontFamily: v);
            _profileTouched = true;
          });
        },
      ),
    ];
  }

  List<Widget> _logoSectionChildren() {
    final l10n = context.l10n;
    return [
      Row(
        children: [
          Expanded(
            child: _pathBox(
              _themeProfile.logoPath ?? l10n.d('Geen logo ingesteld'),
              muted: _themeProfile.logoPath == null,
            ),
          ),
          const SizedBox(width: 8),
          ElevatedButton.icon(
            onPressed: _pickLogo,
            icon: const Icon(Icons.image_outlined, size: 16),
            label: Text(l10n.d('Kiezen')),
          ),
          if (_themeProfile.logoPath != null)
            IconButton(
              onPressed: () => _rebuild(() {
                _themeProfile = _themeProfile.copyWith(clearLogo: true);
                _profileTouched = true;
              }),
              icon: const Icon(Icons.clear, size: 18),
              tooltip: l10n.d('Verwijder logo'),
            ),
        ],
      ),
      const SizedBox(height: 18),
      DropdownButtonFormField<String>(
        initialValue: _themeProfile.logoPosition,
        decoration: InputDecoration(
          labelText: l10n.d('Logo positie'),
          isDense: true,
        ),
        items: [
          DropdownMenuItem(
            value: 'top-left',
            child: Text(l10n.d('Linksboven')),
          ),
          DropdownMenuItem(
            value: 'top-right',
            child: Text(l10n.d('Rechtsboven')),
          ),
          DropdownMenuItem(
            value: 'bottom-left',
            child: Text(l10n.d('Linksonder')),
          ),
          DropdownMenuItem(
            value: 'bottom-right',
            child: Text(l10n.d('Rechtsonder')),
          ),
        ],
        onChanged: (v) {
          if (v != null) {
            _rebuild(() {
              _themeProfile = _themeProfile.copyWith(logoPosition: v);
              _profileTouched = true;
            });
          }
        },
      ),
      const SizedBox(height: 14),
      SizedBox(
        width: 160,
        child: TextField(
          controller: _logoSize,
          decoration: InputDecoration(
            labelText: context.l10n.d('Logo px'),
            isDense: true,
          ),
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          onChanged: (_) => _profileTouched = true,
        ),
      ),
      ..._footerSettings(),
      ..._closingSlideSettings(),
    ];
  }

  List<Widget> _footerSettings() {
    final l10n = context.l10n;
    return [
      const SizedBox(height: 24),
      _sectionTitle('Footer'),
      TextField(
        controller: _footerText,
        decoration: InputDecoration(
          labelText: l10n.d('Footertekst'),
          hintText: l10n.d('bijv. Vertrouwelijk · {title} · {date}'),
          isDense: true,
        ),
        onChanged: (_) => _profileTouched = true,
      ),
      const SizedBox(height: 6),
      Text(
        l10n.d(
          'Tokens: {page}, {total}, {date}, {title}. Footer verschijnt op alle slides behalve titel- en sectieslides, tenzij je hem per slide uitzet.',
        ),
        style: const TextStyle(fontSize: 11, color: AppTheme.slate400),
      ),
      const SizedBox(height: 14),
      DropdownButtonFormField<String>(
        initialValue: _themeProfile.footerPosition,
        decoration: InputDecoration(
          labelText: l10n.d('Footerpositie'),
          isDense: true,
        ),
        items: [
          DropdownMenuItem(value: 'left', child: Text(l10n.d('Links'))),
          DropdownMenuItem(value: 'center', child: Text(l10n.d('Midden'))),
          DropdownMenuItem(value: 'right', child: Text(l10n.d('Rechts'))),
        ],
        onChanged: (v) {
          if (v != null) {
            _rebuild(() {
              _themeProfile = _themeProfile.copyWith(footerPosition: v);
              _profileTouched = true;
            });
          }
        },
      ),
      const SizedBox(height: 6),
      CheckboxListTile(
        value: _themeProfile.footerShowPageNumbers,
        onChanged: (v) => _rebuild(() {
          _themeProfile = _themeProfile.copyWith(
            footerShowPageNumbers: v ?? false,
          );
          _profileTouched = true;
        }),
        title: Text(
          l10n.d('Paginanummers tonen (rechtsonder)'),
          style: const TextStyle(fontSize: 13),
        ),
        controlAffinity: ListTileControlAffinity.leading,
        contentPadding: EdgeInsets.zero,
        dense: true,
      ),
    ];
  }

  List<Widget> _closingSlideSettings() {
    final l10n = context.l10n;
    return [
      const SizedBox(height: 24),
      _sectionTitle(l10n.d('Laatste slide')),
      SwitchListTile(
        value: _themeProfile.closingSlideEnabled,
        onChanged: (v) => _rebuild(() {
          _themeProfile = _themeProfile.copyWith(
            closingSlideEnabled: v,
            closingSlideMarkdown: _closingSlideMarkdown.text,
          );
          _profileTouched = true;
        }),
        title: Text(
          l10n.d('Standaard laatste slide gebruiken'),
          style: const TextStyle(fontSize: 13),
        ),
        subtitle: Text(
          l10n.d('Wordt automatisch toegevoegd bij presenteren en exporteren.'),
          style: const TextStyle(fontSize: 11, color: AppTheme.slate500),
        ),
        contentPadding: EdgeInsets.zero,
        dense: true,
      ),
      const SizedBox(height: 8),
      TextField(
        controller: _closingSlideMarkdown,
        enabled: _themeProfile.closingSlideEnabled,
        minLines: 4,
        maxLines: 8,
        decoration: InputDecoration(
          labelText: l10n.d('Markdown voor laatste slide'),
          hintText: '# Bedankt\n\nVragen?',
          alignLabelWithHint: true,
          isDense: true,
        ),
        onChanged: (value) {
          _themeProfile = _themeProfile.copyWith(closingSlideMarkdown: value);
          _profileTouched = true;
        },
      ),
    ];
  }

  Widget _colorSetting(
    String label,
    String value,
    ValueChanged<String> onChanged,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '$label  $value',
          style: const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: AppTheme.slate700,
          ),
        ),
        const SizedBox(height: 6),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final color in _SettingsDialogState._colorPresets)
              _colorSwatch(
                color,
                selected: value.toUpperCase() == color,
                onTap: () => _rebuild(() {
                  onChanged(color);
                  _profileTouched = true;
                }),
              ),
            // Show the current value as a selected swatch when it isn't one of
            // the presets (e.g. a hand-entered CRT green).
            if (!_SettingsDialogState._colorPresets.contains(
              value.toUpperCase(),
            ))
              _colorSwatch(
                value,
                selected: true,
                onTap: () => _editCustomColor(value, onChanged),
              ),
            _customColorButton(value, onChanged),
          ],
        ),
      ],
    );
  }

  Widget _customColorButton(String value, ValueChanged<String> onChanged) {
    return Tooltip(
      message: context.l10n.d('Eigen kleur (hex)'),
      child: InkWell(
        onTap: () => _editCustomColor(value, onChanged),
        borderRadius: BorderRadius.circular(8),
        child: Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: AppTheme.slate300),
          ),
          child: const Icon(Icons.tune, size: 18, color: AppTheme.slate500),
        ),
      ),
    );
  }

  Future<void> _editCustomColor(
    String initial,
    ValueChanged<String> onChanged,
  ) async {
    final picked = await _pickHexColor(initial);
    if (picked == null || !mounted) return;
    _rebuild(() {
      onChanged(picked);
      _profileTouched = true;
    });
  }

  Future<String?> _pickHexColor(String initial) {
    return showDialog<String>(
      context: context,
      builder: (context) => _HexColorDialog(initial: initial),
    );
  }

  Widget _colorSwatch(
    String color, {
    required bool selected,
    required VoidCallback onTap,
  }) {
    final parsed = _parseColor(color);
    final checkColor = parsed.computeLuminance() > 0.55
        ? const Color(0xFF0F172A)
        : Colors.white;
    return Tooltip(
      message: selected ? '${context.l10n.d('Geselecteerd')}: $color' : color,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          width: 34,
          height: 34,
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            color: selected
                ? AppTheme.accent.withValues(alpha: 0.12)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: selected ? AppTheme.accent : AppTheme.slate300,
              width: selected ? 2 : 1,
            ),
          ),
          child: Stack(
            alignment: Alignment.center,
            children: [
              Container(
                decoration: BoxDecoration(
                  color: parsed,
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 2),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x330F172A),
                      blurRadius: 2,
                      offset: Offset(0, 1),
                    ),
                  ],
                ),
              ),
              if (selected)
                Icon(
                  Icons.check,
                  size: 16,
                  color: checkColor,
                  shadows: [
                    Shadow(
                      color: checkColor == Colors.white
                          ? Colors.black54
                          : Colors.white70,
                      blurRadius: 2,
                    ),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _stylePreview() {
    final l10n = context.l10n;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: _parseColor(_themeProfile.titleBackgroundColor),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l10n.d('Voorvertoning'),
            style: _fontStyle(
              _themeProfile.fontFamily,
              TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: _parseColor(_themeProfile.titleTextColor),
              ),
            ),
          ),
          const SizedBox(height: 2),
          Text(
            l10n.d('De snelle bruine vos springt over de luie hond.'),
            style: _fontStyle(
              _themeProfile.fontFamily,
              TextStyle(
                fontSize: 12,
                color: _parseColor(
                  _themeProfile.titleTextColor,
                ).withValues(alpha: 0.72),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
