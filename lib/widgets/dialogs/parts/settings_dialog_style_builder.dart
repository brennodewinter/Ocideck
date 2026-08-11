// Part of the settings_dialog library — see ../settings_dialog.dart.
// De compacte stijlbouwer en zijn live documentpreview. Presentatievelden die
// niet voor iedere gebruiker nodig zijn blijven bereikbaar onder Geavanceerd.
part of '../settings_dialog.dart';

extension _SettingsStyleBuilder on _SettingsDialogState {
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
                  width: 154,
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
    return Semantics(
      button: true,
      selected: selected,
      child: InkWell(
        key: Key('style-profile-${profile.name}'),
        onTap: () => _selectProfile(profile.name),
        borderRadius: BorderRadius.circular(10),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          width: 154,
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

  Widget _styleBasicsAndAdvanced(AppLocalizations l10n) {
    final revealForSearch =
        _selectedTab == SettingsSection.presentation &&
        _highlightedSection != null &&
        _highlightedSection!.isNotEmpty &&
        _highlightedSection != l10n.t('styleProfile');
    if (revealForSearch && !_styleAdvancedExpanded) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && !_styleAdvancedExpanded) {
          _rebuild(() => _styleAdvancedExpanded = true);
        }
      });
    }
    final advancedExpanded = _styleAdvancedExpanded || revealForSearch;
    return Container(
      key: const Key('document-style-editor'),
      decoration: _boxDecoration(),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
            child: Text(
              l10n.d('Basis'),
              style: TextStyle(
                fontWeight: FontWeight.w700,
                color: AppTheme.slate800,
              ),
            ),
          ),
          _styleColorField(
            l10n.d('Achtergrond slides'),
            _themeProfile.slideBackgroundColor,
            (value) => _themeProfile = _themeProfile.copyWith(
              slideBackgroundColor: value,
            ),
          ),
          _styleColorField(
            l10n.d('Tekst'),
            _themeProfile.textColor,
            (value) => _themeProfile = _themeProfile.copyWith(textColor: value),
          ),
          _styleColorField(
            l10n.d('Accent / bullets'),
            _themeProfile.accentColor,
            (value) =>
                _themeProfile = _themeProfile.copyWith(accentColor: value),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 8, 14, 14),
            child: DropdownButtonFormField<String>(
              isExpanded: true,
              initialValue:
                  AppSettings.availableFonts.contains(_themeProfile.fontFamily)
                  ? _themeProfile.fontFamily
                  : AppSettings.availableFonts.first,
              decoration: InputDecoration(
                labelText: l10n.d('Lettertype'),
                isDense: true,
              ),
              items: [
                for (final font in AppSettings.availableFonts)
                  DropdownMenuItem(
                    value: font,
                    child: Text(font, style: TextStyle(fontFamily: font)),
                  ),
              ],
              onChanged: (font) {
                if (font == null) return;
                _rebuild(() {
                  _themeProfile = _themeProfile.copyWith(fontFamily: font);
                  _profileTouched = true;
                });
              },
            ),
          ),
          const Divider(height: 1),
          Material(
            color: AppTheme.paper,
            child: ExpansionTile(
              key: ValueKey(advancedExpanded),
              initiallyExpanded: advancedExpanded,
              onExpansionChanged: (expanded) =>
                  _rebuild(() => _styleAdvancedExpanded = expanded),
              tilePadding: const EdgeInsets.symmetric(horizontal: 14),
              childrenPadding: const EdgeInsets.fromLTRB(14, 0, 14, 18),
              title: Text(
                l10n.d('Geavanceerd'),
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
              children: [
                _sectionTitle(l10n.d('Lettertype')),
                _fontSection(),
                _presentationStyleDivider(l10n.d('Kleuren')),
                ..._colorsSectionChildren(),
                _presentationStyleDivider(l10n.d('Animatie')),
                ..._animationSettings(),
                _presentationStyleDivider(l10n.d('Logo en footer')),
                ..._logoSectionChildren(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _styleColorField(
    String label,
    String value,
    ValueChanged<String> onChanged,
  ) {
    final color = AppTheme.parseHexColor(value);
    return InkWell(
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

  Widget _documentStylePreview(AppLocalizations l10n) {
    final paper = AppTheme.parseHexColor(_themeProfile.slideBackgroundColor);
    final ink = AppTheme.parseHexColor(_themeProfile.textColor);
    final accent = AppTheme.parseHexColor(_themeProfile.accentColor);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.slate200,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppTheme.slate300),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  l10n.d('Voorvertoning'),
                  style: TextStyle(
                    color: AppTheme.slate700,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              SegmentedButton<bool>(
                segments: [
                  ButtonSegment(value: false, label: Text(l10n.d('Titel'))),
                  ButtonSegment(value: true, label: Text(l10n.d('Inhoud'))),
                ],
                selected: {_stylePreviewShowsContent},
                showSelectedIcon: false,
                style: const ButtonStyle(visualDensity: VisualDensity.compact),
                onSelectionChanged: (value) =>
                    _rebuild(() => _stylePreviewShowsContent = value.first),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Center(
            child: AspectRatio(
              aspectRatio: 1 / 1.414,
              child: Container(
                key: const Key('document-style-preview'),
                constraints: const BoxConstraints(maxWidth: 520),
                padding: const EdgeInsets.fromLTRB(34, 28, 34, 24),
                decoration: BoxDecoration(
                  color: paper,
                  boxShadow: const [
                    BoxShadow(
                      color: AppTheme.shadow20,
                      blurRadius: 12,
                      offset: Offset(0, 4),
                    ),
                  ],
                ),
                child: DefaultTextStyle(
                  style: TextStyle(
                    color: ink,
                    fontFamily: _themeProfile.fontFamily,
                  ),
                  child: _stylePreviewShowsContent
                      ? _documentPreviewContent(l10n, paper, ink, accent)
                      : _documentPreviewTitle(l10n, ink, accent),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _documentPreviewTitle(AppLocalizations l10n, Color ink, Color accent) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Container(
                key: const Key('document-style-accent-rule'),
                height: 3,
                color: accent,
              ),
            ),
            const SizedBox(width: 18),
            _documentPreviewLogo(ink),
          ],
        ),
        const Spacer(),
        Text(
          l10n.d('Documentstijl'),
          style: TextStyle(
            color: accent,
            fontSize: 12,
            letterSpacing: 1.1,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 10),
        Text(
          _themeProfile.name,
          style: TextStyle(
            color: ink,
            fontSize: 30,
            height: 1.05,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 12),
        Text(
          l10n.d('De snelle bruine vos springt over de luie hond.'),
          style: TextStyle(color: ink.withValues(alpha: 0.72), height: 1.45),
        ),
        const Spacer(flex: 2),
        Container(height: 1, color: ink.withValues(alpha: 0.25)),
        const SizedBox(height: 10),
        Text(
          _footerText.text,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(color: ink.withValues(alpha: 0.65), fontSize: 10),
        ),
      ],
    );
  }

  Widget _documentPreviewContent(
    AppLocalizations l10n,
    Color paper,
    Color ink,
    Color accent,
  ) {
    final scheme =
        ColorScheme.fromSeed(
          seedColor: accent,
          brightness: paper.computeLuminance() < 0.45
              ? Brightness.dark
              : Brightness.light,
          surface: paper,
        ).copyWith(
          primary: accent,
          onSurface: ink,
          onSurfaceVariant: ink.withValues(alpha: 0.72),
          outlineVariant: ink.withValues(alpha: 0.25),
          surfaceContainerHighest: accent.withValues(alpha: 0.12),
        );
    final markdown =
        '''
# ${l10n.d('Voorvertoning')}

${l10n.d('De snelle bruine vos springt over de luie hond.')}

## ${l10n.d('Besluit gevraagd')}

- ${l10n.d('Voorbeeldtekst')}
- ${l10n.d('Inhoud')}
''';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Container(
                key: const Key('document-style-accent-rule'),
                height: 2,
                color: accent,
              ),
            ),
            const SizedBox(width: 18),
            _documentPreviewLogo(ink),
          ],
        ),
        const SizedBox(height: 22),
        Expanded(
          child: ClipRect(
            child: Theme(
              data: ThemeData(
                colorScheme: scheme,
                fontFamily: _themeProfile.fontFamily,
                textTheme: ThemeData.light().textTheme.apply(
                  fontFamily: _themeProfile.fontFamily,
                  bodyColor: ink,
                  displayColor: ink,
                ),
              ),
              child: DocumentMarkdownView(
                markdown,
                maxTextWidth: null,
                themeProfile: _themeProfile,
                chartTheme: _themeProfile,
              ),
            ),
          ),
        ),
        Container(height: 1, color: ink.withValues(alpha: 0.25)),
        const SizedBox(height: 8),
        Text(
          _footerText.text,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(color: ink.withValues(alpha: 0.65), fontSize: 10),
        ),
      ],
    );
  }

  Widget _documentPreviewLogo(Color ink) {
    final path = _themeProfile.logoPath;
    if (path != null && path.startsWith('asset:')) {
      return SizedBox(
        width: 76,
        height: 30,
        child: Image.asset(
          path.substring('asset:'.length),
          fit: BoxFit.contain,
          errorBuilder: (_, _, _) =>
              Icon(Icons.description_outlined, color: ink, size: 24),
        ),
      );
    }
    return Icon(Icons.description_outlined, color: ink, size: 24);
  }
}
