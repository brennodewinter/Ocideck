// Part of the settings_dialog library — see ../settings_dialog.dart.
// De compacte stijlbouwer met afzonderlijke document- en presentatievlakken.
part of '../settings_dialog.dart';

List<ThemeProfile> _availableStyleProfiles(List<ThemeProfile> stored) {
  final seen = <String>{};
  return [
    for (final profile in stored)
      if (seen.add(profile.name)) profile,
    // Toon nieuwe presets ook aan bestaande installaties, zonder de provider
    // te muteren voordat de gebruiker Opslaan kiest.
    for (final profile in ThemeProfile.builtIns)
      if (seen.add(profile.name)) profile,
  ];
}

double _settingsDialogWidth({
  required double scale,
  required double screenWidth,
  required double availableWidth,
  required bool styleBuilder,
}) => math
    .min(
      math.max(
        640.0,
        math.min((styleBuilder ? 1240.0 : 920.0) * scale, screenWidth * 0.92),
      ),
      availableWidth,
    )
    .toDouble();

/// De sectiekoppen per vlak, in de taal waarin ze op het scherm staan.
///
/// Bestaat voor de sprong vanuit het zoekveld en vanuit het kwaliteitspaneel:
/// die wijzen een sectie of een kleurveld aan, en dat anker hangt in de boom
/// van één vlak. Landde de sprong op het verkeerde vlak, dan stond de
/// instelling er niet en gebeurde er zichtbaar niets.
///
/// Top-level, net als de twee lijsten hieronder: het zijn afleidingen uit de
/// taal en uit vaste veldnamen, niet uit de staat van het dialoog. Ze hoeven de
/// klasse dus niet te belasten — die zit tegen haar plafond.
Map<_StyleSurface, List<String>> _surfaceSections(AppLocalizations l10n) => {
  _StyleSurface.general: [
    l10n.d('Lettertype'),
    l10n.d('Kleuren'),
    l10n.d('Checklist'),
    l10n.d('Tabel'),
    l10n.d('Broncode'),
    l10n.d('Severity (bevindingen)'),
  ],
  _StyleSurface.document: [l10n.d('Tekst'), l10n.d('Logo'), l10n.d('Koptekst')],
  _StyleSurface.presentation: [
    l10n.d('Footer'),
    l10n.d('Laatste slide'),
    l10n.d('Animatie'),
  ],
};

/// De kleurvelden die alléén op een dia bestaan. Alle andere ankers zitten in
/// het algemene vlak; een lijst van de uitzonderingen blijft klein en is dus de
/// kant die je bijhoudt.
const _slideOnlyThemeFields = {
  'titleBackgroundColor',
  'titleTextColor',
  'sectionBackgroundColor',
  'logoPath',
};

/// Dezelfde uitzonderingslijst, maar voor het documentvlak: de kopkleur van een
/// document, en de tekst- en achtergrondkleur van de kop- en voetband. Zonder
/// deze lijst landde een contrastsprong op het algemene vlak, waar het veld
/// niet staat — en dan lijkt de melding nergens heen te wijzen.
const _documentOnlyThemeFields = {
  'documentHeadingColor',
  'documentBandTextColor',
  'documentBandBackgroundColor',
};

/// Zelfstandige bouwer: houdt de omvang van de instellingen-State begrensd.
class _DocumentStyleBuilder {
  const _DocumentStyleBuilder(this.owner);

  final _SettingsDialogState owner;

  BuildContext get context => owner.context;
  String get _originalName => owner._originalName;
  ThemeProfile get _themeProfile => owner._themeProfile;
  set _themeProfile(ThemeProfile value) => owner._themeProfile = value;
  bool get _stylePreviewShowsContent => owner._stylePreviewShowsContent;
  set _stylePreviewShowsContent(bool value) =>
      owner._stylePreviewShowsContent = value;
  _StyleSurface get _styleSurface => owner._styleSurface;
  set _styleSurface(_StyleSurface value) => owner._styleSurface = value;
  String? get _highlightedThemeField => owner._highlightedThemeField;
  set _profileTouched(bool value) => owner._profileTouched = value;
  String? get _highlightedSection => owner._highlightedSection;
  bool get mounted => owner.mounted;

  void _rebuild(VoidCallback fn) => owner._rebuild(fn);
  void _selectProfile(String name) => owner._selectProfile(name);
  Future<void> _createProfile() => owner._createProfile();
  Future<String?> _pickHexColor(String value) => owner._pickHexColor(value);
  Widget _sectionTitle(String title) => owner._sectionTitle(title);
  Widget _fontSection() => owner._fontSection();
  Widget _presentationStyleDivider(String title) =>
      owner._presentationStyleDivider(title);
  List<Widget> _generalColorChildren() => owner._generalColorChildren();
  List<Widget> _slideColorChildren() => owner._slideColorChildren();
  Widget _themeColorAnchor(String field, Widget child) =>
      owner._themeColorAnchor(field, child);
  Map<String, SlideQualityIssue> _themeContrastByField() =>
      owner._themeContrastByField();
  Widget _colorWithContrastWarning(
    Widget colorSetting,
    String field,
    Map<String, SlideQualityIssue> contrast,
  ) => owner._colorWithContrastWarning(colorSetting, field, contrast);
  List<Widget> _animationSettings() => owner._animationSettings();
  List<Widget> _slideLogoChildren() => owner._slideLogoChildren();
  List<Widget> _footerSettings() => owner._footerSettings();
  List<Widget> _closingSlideSettings() => owner._closingSlideSettings();

  /// Het vlak dat nu getekend wordt: de keuze van de gebruiker, tenzij een
  /// sprong een anker aanwijst dat op een ander vlak hangt.
  _StyleSurface _activeSurface(AppLocalizations l10n) {
    final field = _highlightedThemeField;
    if (field != null) {
      if (_slideOnlyThemeFields.contains(field)) {
        return _StyleSurface.presentation;
      }
      return _documentOnlyThemeFields.contains(field)
          ? _StyleSurface.document
          : _StyleSurface.general;
    }
    final section = _highlightedSection;
    if (section != null && section.isNotEmpty) {
      for (final entry in _surfaceSections(l10n).entries) {
        if (entry.value.contains(section)) return entry.key;
      }
    }
    return _styleSurface;
  }

  Widget _surfaceSelector(AppLocalizations l10n, _StyleSurface surface) =>
      LayoutBuilder(
        builder: (context, constraints) {
          // Op smal web (telefoonbreedte) past de SegmentedButton met icoon +
          // label net niet; de iconen vallen dan weg zodat de labels alleen
          // passen (#1885).
          final showIcons = constraints.maxWidth > 260;
          return SegmentedButton<_StyleSurface>(
            segments: [
              for (final value in _StyleSurface.values)
                ButtonSegment(
                  value: value,
                  label: Text(
                    value.label(l10n),
                    key: Key('style-surface-${value.name}'),
                  ),
                  icon: showIcons ? Icon(value.icon, size: 17) : null,
                ),
            ],
            selected: {surface},
            showSelectedIcon: false,
            onSelectionChanged: (value) =>
                _rebuild(() => _styleSurface = value.first),
          );
        },
      );

  Widget _surfaceHint(AppLocalizations l10n, _StyleSurface surface) => Row(
    children: [
      Icon(Icons.info_outline, size: 15, color: AppTheme.slate500),
      const SizedBox(width: 7),
      Flexible(
        child: Text(
          surface.hint(l10n),
          key: const Key('style-surface-hint'),
          style: TextStyle(fontSize: 12, color: AppTheme.slate600),
        ),
      ),
    ],
  );

  Widget _surfaceEditor(AppLocalizations l10n, _StyleSurface surface) =>
      switch (surface) {
        _StyleSurface.general => _generalStyleSettings(l10n),
        _StyleSurface.document => _documentStyleSettings(l10n),
        _StyleSurface.presentation => _presentationStyleSettings(l10n),
      };

  Widget _surfacePreview(AppLocalizations l10n, _StyleSurface surface) =>
      switch (surface) {
        _StyleSurface.general => _generalStylePreview(l10n),
        _StyleSurface.document => _documentStylePreview(l10n),
        _StyleSurface.presentation => _presentationStylePreview(l10n),
      };
  Widget _styleProfileCards(List<ThemeProfile> profiles) {
    final l10n = context.l10n;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionTitle(l10n.t('styleProfile')),
        const SizedBox(height: 10),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            for (final profile in profiles) _styleProfileCard(profile),
            Tooltip(
              message: l10n.d('Nieuw profiel'),
              child: InkWell(
                key: const Key('style-profile-create-card'),
                onTap: _createProfile,
                borderRadius: BorderRadius.circular(10),
                child: Container(
                  width: 216,
                  height: 66,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: AppTheme.slate300),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.add, color: AppTheme.slate500, size: 19),
                      const SizedBox(width: 7),
                      Flexible(
                        child: Text(
                          l10n.d('Nieuw profiel'),
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(color: AppTheme.slate600),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _styleProfileCard(ThemeProfile profile) {
    final selected = profile.name == _originalName;
    final accent = AppTheme.parseHexColor(profile.accentColor);
    final shownProfile = selected ? owner._editedProfile() : profile;
    final logoPath = shownProfile.logoPath?.trim() ?? '';
    return Semantics(
      button: true,
      selected: selected,
      child: InkWell(
        key: Key('style-profile-${profile.name}'),
        onTap: () => _selectProfile(profile.name),
        borderRadius: BorderRadius.circular(10),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          width: 216,
          height: 66,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: selected ? accent.withValues(alpha: 0.08) : AppTheme.paper,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: selected ? accent : AppTheme.slate300,
              width: selected ? 2 : 1,
            ),
          ),
          child: Row(
            children: [
              if (logoPath.isNotEmpty)
                Container(
                  width: 36,
                  height: 36,
                  padding: const EdgeInsets.all(3),
                  decoration: BoxDecoration(
                    color: AppTheme.paper,
                    borderRadius: BorderRadius.circular(7),
                    border: Border.all(color: accent),
                  ),
                  child: ThemeProfileLogo(
                    profile: shownProfile,
                    width: 30,
                    height: 30,
                  ),
                )
              else
                Container(
                  width: 30,
                  height: 30,
                  decoration: BoxDecoration(
                    color: accent.withValues(alpha: 0.13),
                    shape: BoxShape.circle,
                    border: Border.all(color: accent, width: 2),
                  ),
                  child: Icon(
                    Icons.description_outlined,
                    color: accent,
                    size: 17,
                  ),
                ),
              const SizedBox(width: 9),
              Expanded(
                child: Text(
                  profile.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: AppTheme.slate800,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
                  ),
                ),
              ),
              if (selected) Icon(Icons.check_circle, color: accent, size: 17),
            ],
          ),
        ),
      ),
    );
  }

  /// Het algemene vlak: alles wat een document én een presentatie draagt.
  Widget _generalStyleSettings(AppLocalizations l10n) => Material(
    key: const Key('general-style-editor'),
    color: AppTheme.paper,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(6),
      side: BorderSide(color: AppTheme.slate300),
    ),
    clipBehavior: Clip.antiAlias,
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _sectionTitle(l10n.d('Lettertype')),
          const SizedBox(height: 8),
          _fontSection(),
          _presentationStyleDivider(l10n.d('Kleuren')),
          ..._generalColorChildren(),
        ],
      ),
    ),
  );

  /// Het documentvlak: wat alleen op een blad bestaat — een eigen logo, een
  /// kop- en voetregel en de paginanummering.
  ///
  /// De contrastmeldingen komen uit één analyse voor het hele vlak. Zowel de
  /// kopkleur als de bandtekst vraagt ernaar, en dit vlak tekent ze allebei;
  /// zou elk veld zijn eigen analyse starten, dan draaide die bij élke
  /// kleurbewerking dubbel.
  Widget _documentStyleSettings(AppLocalizations l10n) {
    final contrast = _themeContrastByField();
    return Material(
      key: const Key('document-style-editor'),
      color: AppTheme.paper,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(6),
        side: BorderSide(color: AppTheme.slate300),
      ),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Niet "Lettertype": dat is de sectie van het algemene vlak, waar het
            // lettertype zelf staat. Twee secties met dezelfde kop zouden ook
            // hetzelfde zoekanker dragen, en dan landt een treffer op het
            // verkeerde vlak.
            _sectionTitle(l10n.d('Tekst')),
            const SizedBox(height: 8),
            ..._documentFontSizeSettings(l10n),
            _themeColorAnchor(
              'documentHeadingColor',
              _colorWithContrastWarning(
                _styleColorField(
                  l10n.d('Kop'),
                  _themeProfile.effectiveDocumentHeadingColor,
                  (value) => _themeProfile = _themeProfile.copyWith(
                    documentHeadingColor: value,
                  ),
                  key: const Key('document-heading-color'),
                ),
                'documentHeadingColor',
                contrast,
              ),
            ),
            _presentationStyleDivider(l10n.d('Logo')),
            ..._documentLogoSettings(l10n),
            _presentationStyleDivider(l10n.d('Koptekst')),
            ..._documentChromeSettings(l10n, contrast),
          ],
        ),
      ),
    );
  }

  /// De basislettergrootte van een document.
  ///
  /// Alleen hier, want alleen een blad heeft een vaste lettermaat: een dia
  /// schaalt haar tekst naar het 16:9-kader. De koppen, de noten en de
  /// tijdlijnkaartjes verhouden zich tot deze maat, dus één schuif verzet de
  /// hele typografie van het document — in de weergave, in het schrijfvlak, in
  /// de paginaverdeling en in de export.
  List<Widget> _documentFontSizeSettings(AppLocalizations l10n) {
    final size = clampDocumentBodyFontSize(_themeProfile.documentBodyFontSize);
    return [
      Text(
        // Placeholder, geen interpolatie in de bronsleutel: een string mét
        // ingebakken waarde is per definitie onvertaalbaar, en dezelfde vorm
        // draagt de celopvulling hierboven al.
        l10n
            .d('Basislettergrootte: {pt} pt')
            .replaceAll('{pt}', size.toStringAsFixed(1)),
        style: const TextStyle(fontSize: 13),
      ),
      Slider(
        key: const Key('document-body-font-size'),
        value: size,
        min: kDocumentMinBodyFontSize,
        max: kDocumentMaxBodyFontSize,
        divisions: ((kDocumentMaxBodyFontSize - kDocumentMinBodyFontSize) * 2)
            .round(),
        label: size.toStringAsFixed(1),
        onChanged: (value) => _rebuild(() {
          _themeProfile = _themeProfile.copyWith(
            documentBodyFontSize: clampDocumentBodyFontSize(value),
          );
          _profileTouched = true;
        }),
      ),
      const SizedBox(height: 4),
      Text(
        l10n.d(
          'Koppen, voetnoten en tijdlijnkaarten schalen mee met deze maat.',
        ),
        style: TextStyle(fontSize: 11, color: AppTheme.slate400),
      ),
    ];
  }

  List<Widget> _documentLogoSettings(AppLocalizations l10n) {
    final shared = _themeProfile.documentLogoPath == null;
    return [
      SwitchListTile(
        key: const Key('document-logo-shared'),
        value: shared,
        onChanged: (value) => _rebuild(() {
          _themeProfile = value
              ? _themeProfile.copyWith(clearDocumentLogoOverride: true)
              : _themeProfile.copyWith(
                  documentLogoPath: _themeProfile.logoPath ?? '',
                );
          _profileTouched = true;
        }),
        title: Text(
          '${l10n.d('Logo')}: ${l10n.d('Presentatie')} + ${l10n.d('Document')}',
          style: const TextStyle(fontSize: 13),
        ),
        contentPadding: EdgeInsets.zero,
        dense: true,
      ),
      if (!shared && supportsLocalProjectFolders) ...[
        Row(
          children: [
            Container(
              key: const Key('document-logo-preview'),
              width: 64,
              height: 52,
              padding: const EdgeInsets.all(5),
              decoration: BoxDecoration(
                color: AppTheme.slate100,
                borderRadius: BorderRadius.circular(7),
                border: Border.all(color: AppTheme.slate300),
              ),
              child: ThemeProfileLogo(
                profile: _themeProfile,
                logoPath: _themeProfile.documentLogoPath,
                width: 54,
                height: 42,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: owner._pathBox(
                _themeProfile.documentLogoPath?.isNotEmpty == true
                    ? _themeProfile.documentLogoPath!
                    : l10n.d('Geen logo ingesteld'),
                muted: _themeProfile.documentLogoPath?.isNotEmpty != true,
              ),
            ),
            const SizedBox(width: 8),
            ElevatedButton.icon(
              onPressed: _pickDocumentLogo,
              icon: const Icon(Icons.image_outlined, size: 16),
              label: Text(l10n.d('Kiezen')),
            ),
            if (_themeProfile.documentLogoPath?.isNotEmpty == true)
              IconButton(
                onPressed: () => _rebuild(() {
                  _themeProfile = _themeProfile.copyWith(documentLogoPath: '');
                  _profileTouched = true;
                }),
                icon: const Icon(Icons.clear, size: 18),
                tooltip: l10n.d('Verwijder logo'),
              ),
          ],
        ),
        const SizedBox(height: 14),
      ],
      DropdownButtonFormField<String>(
        key: const Key('document-logo-position'),
        isExpanded: true,
        initialValue: _themeProfile.documentLogoPosition,
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
        onChanged: (value) {
          if (value == null) return;
          _rebuild(() {
            _themeProfile = _themeProfile.copyWith(documentLogoPosition: value);
            _profileTouched = true;
          });
        },
      ),
      const SizedBox(height: 12),
      TextFormField(
        key: Key('document-logo-size-${_themeProfile.name}'),
        initialValue: _themeProfile.effectiveDocumentLogoSize.toString(),
        decoration: InputDecoration(
          labelText: l10n.d('Logo px'),
          isDense: true,
        ),
        keyboardType: TextInputType.number,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        onChanged: (raw) {
          final size = int.tryParse(raw);
          if (size == null) return;
          _rebuild(() {
            _themeProfile = _themeProfile.copyWith(
              documentLogoSize: size.clamp(32, 480),
            );
            _profileTouched = true;
          });
        },
      ),
    ];
  }

  List<Widget> _documentChromeSettings(
    AppLocalizations l10n,
    Map<String, SlideQualityIssue> contrast,
  ) => [
    TextFormField(
      key: Key('document-header-${_themeProfile.name}'),
      initialValue: _themeProfile.documentHeaderText,
      minLines: 2,
      maxLines: 4,
      decoration: InputDecoration(
        labelText: '${l10n.d('Koptekst')} · ${l10n.t('markdownMode')}',
        helperText: l10n.d('Gebruik {naam} in de kop- of voettekst.'),
        isDense: true,
      ),
      onChanged: (value) => _rebuild(() {
        _themeProfile = _themeProfile.copyWith(documentHeaderText: value);
        _profileTouched = true;
      }),
    ),
    const SizedBox(height: 12),
    TextFormField(
      key: Key('document-footer-${_themeProfile.name}'),
      initialValue: _themeProfile.documentFooterText,
      minLines: 2,
      maxLines: 4,
      decoration: InputDecoration(
        labelText: '${l10n.d('Footertekst')} · ${l10n.t('markdownMode')}',
        helperText: l10n.d('Gebruik {naam} in de kop- of voettekst.'),
        isDense: true,
      ),
      onChanged: (value) => _rebuild(() {
        _themeProfile = _themeProfile.copyWith(documentFooterText: value);
        _profileTouched = true;
      }),
    ),
    _themeColorAnchor(
      'documentBandTextColor',
      _colorWithContrastWarning(
        _styleColorField(
          l10n.d('Tekst'),
          _themeProfile.effectiveDocumentBandTextColor,
          (value) => _themeProfile = _themeProfile.copyWith(
            documentBandTextColor: value,
          ),
          key: const Key('document-band-text-color'),
        ),
        'documentBandTextColor',
        contrast,
      ),
    ),
    _themeColorAnchor(
      'documentBandBackgroundColor',
      _colorWithContrastWarning(
        _styleColorField(
          l10n.d('Achtergrond'),
          _themeProfile.effectiveDocumentBandBackgroundColor,
          (value) => _themeProfile = _themeProfile.copyWith(
            documentBandBackgroundColor: value,
          ),
          key: const Key('document-band-background-color'),
        ),
        'documentBandBackgroundColor',
        contrast,
      ),
    ),
    CheckboxListTile(
      key: const Key('document-page-numbers'),
      value: _themeProfile.documentShowPageNumbers,
      onChanged: (value) => _rebuild(() {
        _themeProfile = _themeProfile.copyWith(
          documentShowPageNumbers: value ?? false,
        );
        _profileTouched = true;
      }),
      title: Text(
        l10n.d('Paginanummers tonen (rechtsonder)'),
        style: const TextStyle(fontSize: 13),
      ),
      contentPadding: EdgeInsets.zero,
      dense: true,
      controlAffinity: ListTileControlAffinity.leading,
    ),
  ];

  Future<void> _pickDocumentLogo() async {
    if (!supportsLocalProjectFolders) return;
    final file = await FilePicker.pickFile(
      dialogTitle: context.l10n.d('Logo kiezen'),
      type: FileType.image,
    );
    if (!mounted) return;
    final path = file?.path;
    if (path == null) return;
    _rebuild(() {
      _themeProfile = _themeProfile.copyWith(documentLogoPath: path);
      _profileTouched = true;
    });
  }

  /// Het presentatievlak: wat alleen een dia heeft — de titel- en sectiebalk,
  /// het dialogo, de footer, de slotdia en de animatieduur.
  Widget _presentationStyleSettings(AppLocalizations l10n) => Material(
    key: const Key('presentation-style-editor'),
    color: AppTheme.paper,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(6),
      side: BorderSide(color: AppTheme.slate300),
    ),
    clipBehavior: Clip.antiAlias,
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _sectionTitle(l10n.d('Kleuren')),
          const SizedBox(height: 8),
          ..._slideColorChildren(),
          _presentationStyleDivider(l10n.d('Logo')),
          ..._slideLogoChildren(),
          _presentationStyleDivider(l10n.d('Footer')),
          ..._footerSettings(),
          _presentationStyleDivider(l10n.d('Laatste slide')),
          ..._closingSlideSettings(),
          _presentationStyleDivider(l10n.d('Animatie')),
          ..._animationSettings(),
        ],
      ),
    ),
  );

  Widget _styleColorField(
    String label,
    String value,
    ValueChanged<String> onChanged, {
    Key? key,
  }) {
    final color = AppTheme.parseHexColor(value);
    return InkWell(
      key: key,
      onTap: () async {
        final picked = await _pickHexColor(value);
        if (picked == null || !mounted) return;
        _rebuild(() {
          onChanged(picked);
          _profileTouched = true;
        });
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        child: Row(
          children: [
            Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                color: color,
                shape: BoxShape.circle,
                border: Border.all(color: AppTheme.slate300),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(child: Text(label, style: const TextStyle(fontSize: 13))),
            Text(
              value.toUpperCase(),
              style: TextStyle(
                fontSize: 12,
                color: AppTheme.slate600,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
            const SizedBox(width: 6),
            Icon(Icons.edit_outlined, color: AppTheme.slate500, size: 16),
          ],
        ),
      ),
    );
  }
}
