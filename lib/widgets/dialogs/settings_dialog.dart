import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/settings.dart';
import '../../state/settings_provider.dart';
import '../../state/tabs_provider.dart';
import '../../theme/app_theme.dart';
import '../../l10n/app_localizations.dart';

TextStyle _fontStyle(String font, TextStyle base) {
  return base.copyWith(fontFamily: font);
}

class SettingsDialog extends ConsumerStatefulWidget {
  const SettingsDialog({super.key});

  static Future<void> show(BuildContext context) {
    return showDialog(context: context, builder: (_) => const SettingsDialog());
  }

  @override
  ConsumerState<SettingsDialog> createState() => _SettingsDialogState();
}

class _SettingsDialogState extends ConsumerState<SettingsDialog> {
  late String? _homeDirectory;
  late String? _exportDirectory;
  late ThemeProfile _themeProfile;
  late AppAppearanceProfile _appearanceProfile;
  late String _originalAppearanceName;
  late TextEditingController _appearanceName;

  /// The saved name of the profile currently being edited. Used as a stable
  /// identity so renaming updates the existing profile instead of creating a
  /// duplicate.
  late String _originalName;
  late TextEditingController _profileName;
  late TextEditingController _logoSize;
  late TextEditingController _footerText;
  late TextEditingController _closingSlideMarkdown;

  /// Whether the user changed the active profile in this session. Used to
  /// decide whether to apply the profile to the currently open presentation.
  bool _profileTouched = false;

  static const _colorPresets = [
    '#FFFFFF',
    '#F8FAFC',
    '#111827',
    '#003399',
    '#FFCC00',
    '#1C2B47',
    '#2E7D64',
    '#2563EB',
    '#7C3AED',
    '#DC2626',
    '#F59E0B',
  ];

  @override
  void initState() {
    super.initState();
    final settings = ref.read(settingsProvider);
    _homeDirectory = settings.homeDirectory;
    _exportDirectory = settings.exportDirectory;
    // Reflect the profile the open presentation actually uses, falling back to
    // the globally selected profile when no deck is open.
    final deckProfile = ref
        .read(tabsProvider)
        .current
        ?.deckNotifier
        .currentState
        .deck
        ?.themeProfile;
    _themeProfile = deckProfile ?? settings.themeProfile;
    _appearanceProfile = settings.appAppearanceProfile;
    _originalAppearanceName = _appearanceProfile.name;
    _appearanceName = TextEditingController(text: _appearanceProfile.name);
    _originalName = _themeProfile.name;
    _profileName = TextEditingController(text: _themeProfile.name);
    _logoSize = TextEditingController(text: _themeProfile.logoSize.toString());
    _footerText = TextEditingController(text: _themeProfile.footerText);
    _closingSlideMarkdown = TextEditingController(
      text: _themeProfile.closingSlideMarkdown,
    );
  }

  @override
  void dispose() {
    _profileName.dispose();
    _logoSize.dispose();
    _footerText.dispose();
    _closingSlideMarkdown.dispose();
    _appearanceName.dispose();
    super.dispose();
  }

  List<ThemeProfile> get _profiles {
    final seen = <String>{};
    return [
      for (final profile in ref.watch(settingsProvider).themeProfiles)
        if (seen.add(profile.name)) profile,
    ];
  }

  Future<void> _pickHomeDirectory() async {
    final result = await FilePicker.getDirectoryPath(
      dialogTitle: context.l10n.d('Standaard map voor presentaties'),
      initialDirectory: _homeDirectory,
    );
    if (result != null) setState(() => _homeDirectory = result);
  }

  Future<void> _pickExportDirectory() async {
    final result = await FilePicker.getDirectoryPath(
      dialogTitle: context.l10n.d('Map voor exports'),
      initialDirectory: _exportDirectory ?? _homeDirectory,
    );
    if (result != null) setState(() => _exportDirectory = result);
  }

  Future<void> _pickLogo() async {
    final result = await FilePicker.pickFiles(
      dialogTitle: context.l10n.d('Logo kiezen'),
      type: FileType.image,
    );
    final path = result?.files.single.path;
    if (path != null) {
      setState(() {
        _themeProfile = _themeProfile.copyWith(logoPath: path);
        _profileTouched = true;
      });
    }
  }

  void _selectProfile(String name) {
    final profile = _profiles.firstWhere((p) => p.name == name);
    setState(() {
      _themeProfile = profile;
      _originalName = profile.name;
      _profileName.text = profile.name;
      _logoSize.text = profile.logoSize.toString();
      _footerText.text = profile.footerText;
      _closingSlideMarkdown.text = profile.closingSlideMarkdown;
      _profileTouched = true;
    });
  }

  void _save() {
    final notifier = ref.read(settingsProvider.notifier);
    final name = _profileName.text.trim();
    final size = int.tryParse(_logoSize.text)?.clamp(32, 240);
    final profile = _themeProfile.copyWith(
      name: name.isEmpty ? 'Stijlprofiel' : name,
      logoSize: size,
      footerText: _footerText.text,
      closingSlideMarkdown: _closingSlideMarkdown.text,
    );
    notifier.setHomeDirectory(_homeDirectory);
    notifier.setExportDirectory(_exportDirectory);
    notifier.saveThemeProfile(profile, previousName: _originalName);
    if (_appearanceProfile.isBuiltIn) {
      notifier.selectAppAppearanceProfile(_appearanceProfile.name);
    } else {
      final appearanceName = _appearanceName.text.trim();
      notifier.saveAppAppearanceProfile(
        _appearanceProfile.copyWith(
          name: appearanceName.isEmpty ? 'Eigen thema' : appearanceName,
        ),
        previousName: _originalAppearanceName,
      );
    }

    // Apply the chosen/edited profile to the presentation that is currently
    // open, so the change is visible immediately. Only when the user actually
    // touched the profile in this session (otherwise we would clobber a
    // per-deck profile the user set elsewhere).
    if (_profileTouched) {
      ref.read(tabsProvider).current?.deckNotifier.updateThemeProfile(profile);
    }
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final profiles = _profiles;
    final dropdownValue = profiles.any((p) => p.name == _originalName)
        ? _originalName
        : profiles.first.name;

    return DefaultTabController(
      length: 5,
      child: AlertDialog(
        title: Text(l10n.t('settings')),
        content: SizedBox(
          width: 520,
          height: 600,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TabBar(
                isScrollable: true,
                tabs: [
                  Tab(
                    icon: const Icon(Icons.tune),
                    text: l10n.t('settingsGeneral'),
                  ),
                  Tab(
                    icon: const Icon(Icons.format_paint_outlined),
                    text: l10n.d('App-thema'),
                  ),
                  Tab(
                    icon: const Icon(Icons.style_outlined),
                    text: l10n.t('styleProfile'),
                  ),
                  Tab(
                    icon: const Icon(Icons.palette_outlined),
                    text: l10n.t('settingsColors'),
                  ),
                  Tab(
                    icon: const Icon(Icons.image_outlined),
                    text: l10n.t('settingsLogo'),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Expanded(
                child: TabBarView(
                  children: [
                    _tabBody(_generalTab()),
                    _tabBody(_appearanceTab()),
                    _tabBody(_styleTab(profiles, dropdownValue)),
                    _tabBody(_colorsTab()),
                    _tabBody(_logoTab()),
                  ],
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(l10n.t('cancel')),
          ),
          ElevatedButton(onPressed: _save, child: Text(l10n.t('saveSettings'))),
        ],
      ),
    );
  }

  Widget _profileNameField() {
    final l10n = context.l10n;
    return TextField(
      controller: _profileName,
      textInputAction: TextInputAction.done,
      decoration: InputDecoration(
        labelText: l10n.d('Profielnaam'),
        hintText: l10n.d('Naam van het stijlprofiel'),
        isDense: true,
        prefixIcon: const Icon(Icons.badge_outlined, size: 18),
      ),
      onChanged: (value) {
        final name = value.trim();
        _themeProfile = _themeProfile.copyWith(
          name: name.isEmpty ? _themeProfile.name : name,
        );
        _profileTouched = true;
      },
    );
  }

  Widget _profileSelector(List<ThemeProfile> profiles, String dropdownValue) {
    final l10n = context.l10n;
    return Row(
      children: [
        Expanded(
          child: InputDecorator(
            decoration: InputDecoration(
              labelText: l10n.d('Stijlprofiel'),
              isDense: true,
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: dropdownValue,
                isExpanded: true,
                isDense: true,
                items: [
                  for (final profile in profiles)
                    DropdownMenuItem(
                      value: profile.name,
                      child: Text(profile.name),
                    ),
                ],
                onChanged: (name) {
                  if (name != null) _selectProfile(name);
                },
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        IconButton(
          tooltip: l10n.d('Nieuw profiel'),
          onPressed: _createProfile,
          icon: const Icon(Icons.add, size: 18),
        ),
        IconButton(
          tooltip: l10n.d('Standaardprofiel laden'),
          onPressed: _loadDefaultProfile,
          icon: const Icon(Icons.restart_alt, size: 18),
        ),
        IconButton(
          tooltip: l10n.d('Profiel verwijderen'),
          onPressed: profiles.length <= 1
              ? null
              : () {
                  ref
                      .read(settingsProvider.notifier)
                      .deleteThemeProfile(_themeProfile.name);
                  final profile = ref.read(settingsProvider).themeProfile;
                  setState(() {
                    _themeProfile = profile;
                    _originalName = profile.name;
                    _profileName.text = profile.name;
                    _logoSize.text = profile.logoSize.toString();
                    _footerText.text = profile.footerText;
                    _closingSlideMarkdown.text = profile.closingSlideMarkdown;
                    _profileTouched = true;
                  });
                },
          icon: const Icon(Icons.delete_outline, size: 18),
        ),
      ],
    );
  }

  void _loadDefaultProfile() {
    final profile = ref.read(settingsProvider).themeProfile;
    setState(() {
      _themeProfile = profile;
      _originalName = profile.name;
      _profileName.text = profile.name;
      _logoSize.text = profile.logoSize.toString();
      _footerText.text = profile.footerText;
      _closingSlideMarkdown.text = profile.closingSlideMarkdown;
      _profileTouched = true;
    });
  }

  Future<void> _createProfile() async {
    final created = await ref
        .read(settingsProvider.notifier)
        .createThemeProfile(base: _themeProfile);
    if (!mounted) return;
    setState(() {
      _themeProfile = created;
      _originalName = created.name;
      _profileName.text = created.name;
      _logoSize.text = created.logoSize.toString();
      _footerText.text = created.footerText;
      _closingSlideMarkdown.text = created.closingSlideMarkdown;
      _profileTouched = true;
    });
  }

  Widget _tabBody(Widget child) {
    return SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.only(right: 4, bottom: 8),
        child: child,
      ),
    );
  }

  Widget _styleTab(List<ThemeProfile> profiles, String dropdownValue) {
    final l10n = context.l10n;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionTitle(l10n.t('styleProfile')),
        _profileSelector(profiles, dropdownValue),
        const SizedBox(height: 12),
        _profileNameField(),
        const SizedBox(height: 20),
        _sectionTitle(l10n.d('Lettertype')),
        _fontSection(),
        const SizedBox(height: 18),
        _stylePreview(),
      ],
    );
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
                onPressed: () => setState(() => _homeDirectory = null),
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
                onPressed: () => setState(() => _exportDirectory = null),
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
        Row(
          children: [
            Expanded(
              child: DropdownButtonFormField<String>(
                initialValue: selectedName,
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
                          Text(profile.name),
                        ],
                      ),
                    ),
                ],
                onChanged: (name) {
                  if (name == null) return;
                  final profile = profiles.firstWhere(
                    (item) => item.name == name,
                  );
                  setState(() {
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
                setState(() {
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
                      setState(() {
                        _appearanceProfile = profile;
                        _originalAppearanceName = profile.name;
                        _appearanceName.text = profile.name;
                      });
                    }
                  : null,
              icon: const Icon(Icons.delete_outline, size: 18),
            ),
          ],
        ),
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
              ? (value) => setState(() {
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
                  setState(() => onChanged(normalized));
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
        color: _parseColor(value),
        shape: BoxShape.circle,
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
      ),
    );
  }

  Widget _appearancePreview() {
    final profile = _appearanceProfile;
    final foreground = _parseColor(profile.textColor);
    return Container(
      height: 112,
      decoration: BoxDecoration(
        color: _parseColor(profile.backgroundColor),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: _parseColor(profile.panelColor)),
      ),
      child: Column(
        children: [
          Container(
            height: 30,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            color: _parseColor(profile.primaryColor),
            child: Row(
              children: [
                Text(
                  'OciDeck',
                  style: TextStyle(
                    color: _contrastColor(_parseColor(profile.primaryColor)),
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
                    color: _parseColor(profile.panelColor),
                    alignment: Alignment.center,
                    child: Icon(
                      Icons.slideshow_outlined,
                      color: _parseColor(profile.panelTextColor),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.all(8),
                      color: _parseColor(profile.surfaceColor),
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
                              backgroundColor: _parseColor(profile.accentColor),
                              foregroundColor: _contrastColor(
                                _parseColor(profile.accentColor),
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
            onTap: () => setState(() {
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
                    color: const Color(0xFFE2E8F0),
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
                              ? AppTheme.accent
                              : const Color(0xFF334155),
                          fontWeight: selected
                              ? FontWeight.w600
                              : FontWeight.normal,
                        ),
                      ),
                    ),
                  ),
                  if (selected)
                    const Icon(Icons.check, size: 16, color: AppTheme.accent),
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
          Icon(Icons.style_outlined, size: 16, color: AppTheme.accent),
          const SizedBox(width: 8),
          Expanded(
            child: Text.rich(
              TextSpan(
                children: [
                  TextSpan(text: context.l10n.d('Onderdeel van stijlprofiel ')),
                  TextSpan(
                    text: '“$name”',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ],
              ),
              style: const TextStyle(fontSize: 12, color: Color(0xFF334155)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _colorsTab() {
    final l10n = context.l10n;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _profileScopeBanner(),
        _sectionTitle(l10n.d('Kleuren')),
        _colorSetting(
          l10n.d('Achtergrond slides'),
          _themeProfile.slideBackgroundColor,
          (v) =>
              _themeProfile = _themeProfile.copyWith(slideBackgroundColor: v),
        ),
        const SizedBox(height: 12),
        _colorSetting(
          l10n.d('Tekst'),
          _themeProfile.textColor,
          (v) => _themeProfile = _themeProfile.copyWith(textColor: v),
        ),
        const SizedBox(height: 12),
        _colorSetting(
          l10n.d('Accent / bullets'),
          _themeProfile.accentColor,
          (v) => _themeProfile = _themeProfile.copyWith(accentColor: v),
        ),
        const SizedBox(height: 24),
        _sectionTitle(l10n.d('Checklist')),
        _colorSetting(
          l10n.d('Afgevinkt'),
          _themeProfile.checklistCheckedColor,
          (v) =>
              _themeProfile = _themeProfile.copyWith(checklistCheckedColor: v),
        ),
        const SizedBox(height: 12),
        _colorSetting(
          l10n.d('Niet afgevinkt'),
          _themeProfile.checklistUncheckedColor,
          (v) => _themeProfile = _themeProfile.copyWith(
            checklistUncheckedColor: v,
          ),
        ),
        const SizedBox(height: 6),
        SwitchListTile(
          value: _themeProfile.checklistStrikeThrough,
          onChanged: (value) => setState(() {
            _themeProfile = _themeProfile.copyWith(
              checklistStrikeThrough: value,
            );
            _profileTouched = true;
          }),
          title: Text(
            l10n.d('Afgevinkte tekst doorhalen'),
            style: const TextStyle(fontSize: 13),
          ),
          subtitle: Text(
            l10n.d('Toont een streep door voltooide checklistitems.'),
            style: const TextStyle(fontSize: 11, color: Color(0xFF94A3B8)),
          ),
          controlAffinity: ListTileControlAffinity.leading,
          contentPadding: EdgeInsets.zero,
          dense: true,
        ),
        const SizedBox(height: 12),
        _colorSetting(
          l10n.d('Tabeltekst'),
          _themeProfile.tableTextColor,
          (v) => _themeProfile = _themeProfile.copyWith(tableTextColor: v),
        ),
        const SizedBox(height: 12),
        _colorSetting(
          l10n.d('Tabel koptekst'),
          _themeProfile.tableHeaderTextColor,
          (v) =>
              _themeProfile = _themeProfile.copyWith(tableHeaderTextColor: v),
        ),
        const SizedBox(height: 12),
        _colorSetting(
          l10n.d('Titelachtergrond'),
          _themeProfile.titleBackgroundColor,
          (v) =>
              _themeProfile = _themeProfile.copyWith(titleBackgroundColor: v),
        ),
        const SizedBox(height: 12),
        _colorSetting(
          l10n.d('Titeltekst'),
          _themeProfile.titleTextColor,
          (v) => _themeProfile = _themeProfile.copyWith(titleTextColor: v),
        ),
        const SizedBox(height: 12),
        _colorSetting(
          l10n.d('Sectieachtergrond'),
          _themeProfile.sectionBackgroundColor,
          (v) =>
              _themeProfile = _themeProfile.copyWith(sectionBackgroundColor: v),
        ),
        const SizedBox(height: 24),
        _sectionTitle(l10n.d('Broncode')),
        _colorSetting(
          l10n.d('Broncode achtergrond'),
          _themeProfile.codeBackgroundColor,
          (v) => _themeProfile = _themeProfile.copyWith(codeBackgroundColor: v),
        ),
        const SizedBox(height: 12),
        _colorSetting(
          l10n.d('Broncode tekst'),
          _themeProfile.codeTextColor,
          (v) => _themeProfile = _themeProfile.copyWith(codeTextColor: v),
        ),
        const SizedBox(height: 6),
        SwitchListTile(
          value: _themeProfile.codeHighlightSyntax,
          onChanged: (v) => setState(() {
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
            style: const TextStyle(fontSize: 11, color: Color(0xFF94A3B8)),
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
            setState(() {
              _themeProfile = _themeProfile.copyWith(codeFontFamily: v);
              _profileTouched = true;
            });
          },
        ),
        const SizedBox(height: 18),
        _stylePreview(),
      ],
    );
  }

  Widget _logoTab() {
    final l10n = context.l10n;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _profileScopeBanner(),
        _sectionTitle(l10n.d('Logo')),
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
                onPressed: () => setState(() {
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
              setState(() {
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
          style: const TextStyle(fontSize: 11, color: Color(0xFF94A3B8)),
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
              setState(() {
                _themeProfile = _themeProfile.copyWith(footerPosition: v);
                _profileTouched = true;
              });
            }
          },
        ),
        const SizedBox(height: 6),
        CheckboxListTile(
          value: _themeProfile.footerShowPageNumbers,
          onChanged: (v) => setState(() {
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
        const SizedBox(height: 24),
        _sectionTitle(l10n.d('Laatste slide')),
        SwitchListTile(
          value: _themeProfile.closingSlideEnabled,
          onChanged: (v) => setState(() {
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
            l10n.d(
              'Wordt automatisch toegevoegd bij presenteren en exporteren.',
            ),
            style: const TextStyle(fontSize: 11, color: Color(0xFF64748B)),
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
      ],
    );
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
            color: Color(0xFF334155),
          ),
        ),
        const SizedBox(height: 6),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final color in _colorPresets)
              _colorSwatch(
                color,
                selected: value.toUpperCase() == color,
                onTap: () => setState(() {
                  onChanged(color);
                  _profileTouched = true;
                }),
              ),
            // Show the current value as a selected swatch when it isn't one of
            // the presets (e.g. a hand-entered CRT green).
            if (!_colorPresets.contains(value.toUpperCase()))
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
            border: Border.all(color: const Color(0xFFCBD5E1)),
          ),
          child: const Icon(Icons.tune, size: 18, color: Color(0xFF64748B)),
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
    setState(() {
      onChanged(picked);
      _profileTouched = true;
    });
  }

  Future<String?> _pickHexColor(String initial) {
    final controller = TextEditingController(text: initial);
    String? normalize(String raw) {
      final up = raw.trim().toUpperCase();
      final hex = up.startsWith('#') ? up : '#$up';
      return RegExp(r'^#[0-9A-F]{6}$').hasMatch(hex) ? hex : null;
    }

    final l10n = context.l10n;
    return showDialog<String>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          final normalized = normalize(controller.text);
          return AlertDialog(
            title: Text(l10n.d('Eigen kleur (hex)')),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: _parseColor(normalized ?? '#FFFFFF'),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: const Color(0xFFCBD5E1)),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextField(
                        controller: controller,
                        autofocus: true,
                        decoration: InputDecoration(
                          labelText: l10n.d('Hexkleur'),
                          hintText: '#33FF33',
                          isDense: true,
                          border: const OutlineInputBorder(),
                        ),
                        inputFormatters: [
                          FilteringTextInputFormatter.allow(
                            RegExp(r'[#0-9a-fA-F]'),
                          ),
                          LengthLimitingTextInputFormatter(7),
                        ],
                        onChanged: (_) => setDialogState(() {}),
                        onSubmitted: (_) {
                          final ok = normalize(controller.text);
                          if (ok != null) Navigator.pop(context, ok);
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  l10n.d('Bijvoorbeeld #33FF33 voor een CRT-groen scherm.'),
                  style: const TextStyle(
                    fontSize: 11,
                    color: Color(0xFF94A3B8),
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text(l10n.d('Annuleren')),
              ),
              FilledButton(
                onPressed: normalized == null
                    ? null
                    : () => Navigator.pop(context, normalized),
                child: Text(l10n.d('Toepassen')),
              ),
            ],
          );
        },
      ),
    ).whenComplete(controller.dispose);
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
              color: selected ? AppTheme.accent : const Color(0xFFCBD5E1),
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

  Widget _sectionTitle(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        text.toUpperCase(),
        style: const TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          color: Color(0xFF64748B),
          letterSpacing: 1.2,
        ),
      ),
    );
  }

  Widget _pathBox(String text, {bool muted = false}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: _boxDecoration(),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 12,
          color: muted ? const Color(0xFF94A3B8) : const Color(0xFF334155),
        ),
        overflow: TextOverflow.ellipsis,
      ),
    );
  }

  BoxDecoration _boxDecoration() {
    return BoxDecoration(
      border: Border.all(color: const Color(0xFFCBD5E1)),
      borderRadius: BorderRadius.circular(6),
      color: Colors.white,
    );
  }

  Color _parseColor(String hex) {
    final cleaned = hex.replaceFirst('#', '');
    final value = int.tryParse(
      cleaned.length == 6 ? 'FF$cleaned' : cleaned,
      radix: 16,
    );
    return Color(value ?? 0xFFFFFFFF);
  }
}
