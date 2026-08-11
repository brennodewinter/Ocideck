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
  bool get _stylePreviewShowsPresentation =>
      owner._stylePreviewShowsPresentation;
  set _stylePreviewShowsPresentation(bool value) =>
      owner._stylePreviewShowsPresentation = value;
  set _profileTouched(bool value) => owner._profileTouched = value;
  String? get _highlightedSection => owner._highlightedSection;
  TextEditingController get _footerText => owner._footerText;
  bool get mounted => owner.mounted;

  void _rebuild(VoidCallback fn) => owner._rebuild(fn);
  void _selectProfile(String name) => owner._selectProfile(name);
  Future<void> _createProfile() => owner._createProfile();
  Future<String?> _pickHexColor(String value) => owner._pickHexColor(value);
  Widget _sectionTitle(String title) => owner._sectionTitle(title);
  BoxDecoration _boxDecoration() => owner._boxDecoration();
  Widget _fontSection() => owner._fontSection();
  Widget _presentationStyleDivider(String title) =>
      owner._presentationStyleDivider(title);
  List<Widget> _colorsSectionChildren() => owner._colorsSectionChildren();
  List<Widget> _animationSettings() => owner._animationSettings();
  List<Widget> _logoSectionChildren() => owner._logoSectionChildren();

  bool _showsPresentation(AppLocalizations l10n) =>
      _stylePreviewShowsPresentation ||
      (_highlightedSection != null &&
          _highlightedSection!.isNotEmpty &&
          _highlightedSection != l10n.t('styleProfile'));

  Widget _surfaceSelector(AppLocalizations l10n) => SegmentedButton<bool>(
    segments: [
      ButtonSegment(
        value: false,
        label: Text(
          l10n.d('Document'),
          key: const Key('style-surface-document'),
        ),
        icon: const Icon(Icons.description_outlined, size: 17),
      ),
      ButtonSegment(
        value: true,
        label: Text(
          l10n.d('Presentatie'),
          key: const Key('style-surface-presentation'),
        ),
        icon: const Icon(Icons.slideshow_outlined, size: 17),
      ),
    ],
    selected: {_showsPresentation(l10n)},
    showSelectedIcon: false,
    onSelectionChanged: (value) =>
        _rebuild(() => _stylePreviewShowsPresentation = value.first),
  );
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

  Widget _documentStyleSettings(AppLocalizations l10n) {
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
            l10n.d('Achtergrond'),
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
          _profileContrastSummary(),
        ],
      ),
    );
  }

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
          _sectionTitle(l10n.d('Lettertype')),
          const SizedBox(height: 8),
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
  );

  Widget _profileContrastSummary() {
    final issues = owner._themeContrastByField().values;
    if (issues.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
      child: owner._contrastWarning(issues.first),
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
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 12,
            runSpacing: 8,
            children: [
              Text(
                l10n.d('Voorvertoning'),
                style: TextStyle(
                  color: AppTheme.slate700,
                  fontWeight: FontWeight.w700,
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

  Widget _presentationStylePreview(AppLocalizations l10n) {
    final profile = owner._editedProfile();
    final slide = Slide.create(SlideType.bullets).copyWith(
      title: l10n.d('Voorvertoning'),
      bullets: [
        l10n.d('De snelle bruine vos springt over de luie hond.'),
        l10n.d('Besluit gevraagd'),
        l10n.d('Voorbeeldtekst'),
      ],
    );
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
          Text(
            l10n.d('Voorvertoning'),
            style: TextStyle(
              color: AppTheme.slate700,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 12),
          Container(
            key: const Key('presentation-style-preview'),
            decoration: const BoxDecoration(
              boxShadow: [
                BoxShadow(
                  color: AppTheme.shadow20,
                  blurRadius: 12,
                  offset: Offset(0, 4),
                ),
              ],
            ),
            child: SlidePreviewWidget(
              slide: slide,
              themeProfile: profile,
              slideNumber: 2,
              slideCount: 8,
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
          child: SingleChildScrollView(
            primary: false,
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
    return Theme(
      data: Theme.of(context).copyWith(
        colorScheme: Theme.of(
          context,
        ).colorScheme.copyWith(onSurfaceVariant: ink),
      ),
      child: ThemeProfileLogo(profile: _themeProfile, width: 76, height: 30),
    );
  }
}
