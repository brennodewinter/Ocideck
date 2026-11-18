// Part of the settings_dialog library — zie ../settings_dialog.dart.
// Uitgesplitst voor de vindbaarheid: het logo van het stijlprofiel, gedeeld
// tussen document en presentatie. Alle imports leven in het bibliotheek-
// bestand zelf; de methoden verhuizen verbatim naar een extensie op
// _SettingsDialogState — zelfde bibliotheek, zelfde leden, geen gedrags-
// wijziging.
part of '../settings_dialog.dart';

ThemeProfile _withoutLogoAndBrandStrip(ThemeProfile profile) =>
    profile.copyWith(clearLogo: true, clearBrandStrip: true);

extension _SettingsLogo on _SettingsDialogState {
  /// Het logo van het profiel: gedeeld tussen dia en blad (#3003). Een
  /// document kan er bewust van afwijken — dat afwijkende logo staat in het
  /// documentvlak van de stijlbouwer. Alleen de positie is dia-specifiek;
  /// die staat apart in [_slideLogoPositionChildren].
  List<Widget> _sharedLogoChildren() {
    final l10n = context.l10n;
    return [
      // Op web komen de bytes in het sessiegeheugen (mem:). Een losse
      // markdown-download bewaart die niet; een pakket wel. De knoppen staan
      // daarom op elk platform.
      _themeColorAnchor(
        'logoPath',
        // Twee regels: pad + preview boven, acties rechts eronder. De knoppen
        // in dezelfde rij liepen op telefoonbreedte over (#3003).
        Column(
          children: [
            Row(
              children: [
                Container(
                  key: const Key('style-logo-preview'),
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
                    width: 54,
                    height: 42,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _pathBox(
                    _themeProfile.logoPath == null
                        ? l10n.d('Geen logo ingesteld')
                        : _profileImageLabel(_themeProfile.logoPath!),
                    muted: _themeProfile.logoPath == null,
                  ),
                ),
              ],
            ),
            OverflowBar(
              alignment: MainAxisAlignment.end,
              spacing: 4,
              children: [
                ElevatedButton.icon(
                  onPressed: () => _pickPresentationLogo(this),
                  icon: const Icon(Icons.image_outlined, size: 16),
                  label: Text(l10n.d('Kiezen')),
                ),
                Tooltip(
                  message: l10n.d('Plak logo van klembord'),
                  child: OutlinedButton.icon(
                    key: const Key('style-logo-paste'),
                    onPressed: () => _pastePresentationLogo(this),
                    icon: const Icon(Icons.content_paste, size: 16),
                    label: Text(l10n.d('Plakken')),
                  ),
                ),
                if (_themeProfile.logoPath != null)
                  IconButton(
                    onPressed: () => _rebuild(() {
                      _themeProfile = _withoutLogoAndBrandStrip(_themeProfile);
                      _profileTouched = true;
                    }),
                    icon: const Icon(Icons.clear, size: 18),
                    tooltip: l10n.d('Verwijder logo'),
                  ),
              ],
            ),
          ],
        ),
      ),
      const SizedBox(height: 14),
      // Donkere logo-variant: alleen zinnig met een lichte logo ingesteld.
      // Gebundelde merken kiezen automatisch; dit veld is voor een eigen logo.
      if (_themeProfile.logoPath != null) ..._darkLogoChildren(l10n),
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
          onChanged: (_) => _rebuild(() => _profileTouched = true),
        ),
      ),
      if (!supportsLocalProjectFolders && _themeProfile.logoPath != null)
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Text(
            l10n.d(
              'Dit logo leeft in deze browsersessie en verdwijnt na herladen. Exporteer als pakket om het mee te nemen.',
            ),
            style: TextStyle(fontSize: 11, color: AppTheme.slate400),
          ),
        ),
    ];
  }

  /// Het donkere-logo-blok uit [_sharedLogoChildren] — los omdat die anders
  /// over de methodelengte-grens heen ging.
  List<Widget> _darkLogoChildren(AppLocalizations l10n) => [
    _themeColorAnchor(
      'logoDarkPath',
      Column(
        children: [
          Row(
            children: [
              Container(
                key: const Key('style-logo-dark-preview'),
                width: 64,
                height: 52,
                padding: const EdgeInsets.all(5),
                decoration: BoxDecoration(
                  color: AppTheme.chartTooltipBg,
                  borderRadius: BorderRadius.circular(7),
                  border: Border.all(color: AppTheme.slate700),
                ),
                child: ThemeProfileLogo(
                  profile: _themeProfile,
                  logoPath: _themeProfile.logoDarkPath,
                  width: 54,
                  height: 42,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _pathBox(
                  _themeProfile.logoDarkPath == null
                      ? l10n.d('Geen donker logo ingesteld')
                      : _profileImageLabel(_themeProfile.logoDarkPath!),
                  muted: _themeProfile.logoDarkPath == null,
                ),
              ),
            ],
          ),
          OverflowBar(
            alignment: MainAxisAlignment.end,
            spacing: 4,
            children: [
              ElevatedButton.icon(
                onPressed: () => _pickDarkPresentationLogo(this),
                icon: const Icon(Icons.nights_stay_outlined, size: 16),
                label: Text(l10n.d('Kiezen')),
              ),
              Tooltip(
                message: l10n.d('Plak donker logo van klembord'),
                child: OutlinedButton.icon(
                  key: const Key('style-logo-dark-paste'),
                  onPressed: () => _pasteDarkPresentationLogo(this),
                  icon: const Icon(Icons.content_paste, size: 16),
                  label: Text(l10n.d('Plakken')),
                ),
              ),
              if (_themeProfile.logoDarkPath != null)
                IconButton(
                  onPressed: () => _rebuild(() {
                    _themeProfile = _themeProfile.copyWith(clearLogoDark: true);
                    _profileTouched = true;
                  }),
                  icon: const Icon(Icons.clear, size: 18),
                  tooltip: l10n.d('Verwijder donker logo'),
                ),
            ],
          ),
        ],
      ),
    ),
    const SizedBox(height: 14),
  ];

  /// De positie van het logo op de dia — het enige stuk logo dat alléén een
  /// dia heeft: een document kent zijn eigen `documentLogoPosition`. Daarom
  /// staat dit veld op het presentatievlak, terwijl het logo zelf op het
  /// algemene vlak staat (#3003).
  List<Widget> _slideLogoPositionChildren() {
    final l10n = context.l10n;
    return [
      DropdownButtonFormField<String>(
        key: const Key('style-logo-position'),
        isExpanded: true,
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
    ];
  }
}
