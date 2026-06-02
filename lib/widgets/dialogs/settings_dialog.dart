import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../models/settings.dart';
import '../../state/settings_provider.dart';
import '../../state/tabs_provider.dart';
import '../../theme/app_theme.dart';

TextStyle _fontStyle(String font, TextStyle base) {
  if (font == 'EB Garamond') return GoogleFonts.ebGaramond(textStyle: base);
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
  late ThemeProfile _themeProfile;

  /// The saved name of the profile currently being edited. Used as a stable
  /// identity so renaming updates the existing profile instead of creating a
  /// duplicate.
  late String _originalName;
  late TextEditingController _profileName;
  late TextEditingController _logoSize;
  late TextEditingController _footerText;

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
    _originalName = _themeProfile.name;
    _profileName = TextEditingController(text: _themeProfile.name);
    _logoSize = TextEditingController(text: _themeProfile.logoSize.toString());
    _footerText = TextEditingController(text: _themeProfile.footerText);
  }

  @override
  void dispose() {
    _profileName.dispose();
    _logoSize.dispose();
    _footerText.dispose();
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
      dialogTitle: 'Standaard map voor presentaties',
      initialDirectory: _homeDirectory,
    );
    if (result != null) setState(() => _homeDirectory = result);
  }

  Future<void> _pickLogo() async {
    final result = await FilePicker.pickFiles(
      dialogTitle: 'Logo kiezen',
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
    );
    notifier.setHomeDirectory(_homeDirectory);
    notifier.saveThemeProfile(profile, previousName: _originalName);

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
    final profiles = _profiles;
    final dropdownValue = profiles.any((p) => p.name == _originalName)
        ? _originalName
        : profiles.first.name;

    return DefaultTabController(
      length: 3,
      child: AlertDialog(
        title: const Text('Instellingen'),
        content: SizedBox(
          width: 520,
          height: 560,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _profileSelector(profiles, dropdownValue),
              const SizedBox(height: 12),
              _profileNameField(),
              const SizedBox(height: 12),
              const TabBar(
                tabs: [
                  Tab(icon: Icon(Icons.tune), text: 'Algemeen'),
                  Tab(icon: Icon(Icons.palette_outlined), text: 'Kleuren'),
                  Tab(icon: Icon(Icons.image_outlined), text: 'Logo'),
                ],
              ),
              const SizedBox(height: 12),
              Expanded(
                child: TabBarView(
                  children: [
                    _tabBody(_generalTab()),
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
            child: const Text('Annuleren'),
          ),
          ElevatedButton(onPressed: _save, child: const Text('Opslaan')),
        ],
      ),
    );
  }

  Widget _profileNameField() {
    return TextField(
      controller: _profileName,
      textInputAction: TextInputAction.done,
      decoration: const InputDecoration(
        labelText: 'Profielnaam',
        hintText: 'Naam van het stijlprofiel',
        isDense: true,
        prefixIcon: Icon(Icons.badge_outlined, size: 18),
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
    return Row(
      children: [
        Expanded(
          child: InputDecorator(
            decoration: const InputDecoration(
              labelText: 'Stijlprofiel',
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
          tooltip: 'Nieuw profiel',
          onPressed: _createProfile,
          icon: const Icon(Icons.add, size: 18),
        ),
        IconButton(
          tooltip: 'Standaardprofiel laden',
          onPressed: _loadDefaultProfile,
          icon: const Icon(Icons.restart_alt, size: 18),
        ),
        IconButton(
          tooltip: 'Profiel verwijderen',
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

  Widget _generalTab() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionTitle('Presentatiemap'),
        Row(
          children: [
            Expanded(
              child: _pathBox(
                _homeDirectory ?? 'Niet ingesteld',
                muted: _homeDirectory == null,
              ),
            ),
            const SizedBox(width: 8),
            ElevatedButton.icon(
              onPressed: _pickHomeDirectory,
              icon: const Icon(Icons.folder_open, size: 16),
              label: const Text('Kiezen'),
            ),
            if (_homeDirectory != null)
              IconButton(
                onPressed: () => setState(() => _homeDirectory = null),
                icon: const Icon(Icons.clear, size: 18),
                tooltip: 'Verwijder standaard map',
              ),
          ],
        ),
      ],
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

  Widget _colorsTab() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionTitle('Lettertype'),
        _fontSection(),
        const SizedBox(height: 20),
        _sectionTitle('Kleuren'),
        _colorSetting(
          'Achtergrond slides',
          _themeProfile.slideBackgroundColor,
          (v) =>
              _themeProfile = _themeProfile.copyWith(slideBackgroundColor: v),
        ),
        const SizedBox(height: 12),
        _colorSetting(
          'Tekst',
          _themeProfile.textColor,
          (v) => _themeProfile = _themeProfile.copyWith(textColor: v),
        ),
        const SizedBox(height: 12),
        _colorSetting(
          'Accent / bullets',
          _themeProfile.accentColor,
          (v) => _themeProfile = _themeProfile.copyWith(accentColor: v),
        ),
        const SizedBox(height: 12),
        _colorSetting(
          'Tabeltekst',
          _themeProfile.tableTextColor,
          (v) => _themeProfile = _themeProfile.copyWith(tableTextColor: v),
        ),
        const SizedBox(height: 12),
        _colorSetting(
          'Tabel koptekst',
          _themeProfile.tableHeaderTextColor,
          (v) =>
              _themeProfile = _themeProfile.copyWith(tableHeaderTextColor: v),
        ),
        const SizedBox(height: 12),
        _colorSetting(
          'Titelachtergrond',
          _themeProfile.titleBackgroundColor,
          (v) =>
              _themeProfile = _themeProfile.copyWith(titleBackgroundColor: v),
        ),
        const SizedBox(height: 12),
        _colorSetting(
          'Titeltekst',
          _themeProfile.titleTextColor,
          (v) => _themeProfile = _themeProfile.copyWith(titleTextColor: v),
        ),
        const SizedBox(height: 12),
        _colorSetting(
          'Sectieachtergrond',
          _themeProfile.sectionBackgroundColor,
          (v) =>
              _themeProfile = _themeProfile.copyWith(sectionBackgroundColor: v),
        ),
        const SizedBox(height: 18),
        _stylePreview(),
      ],
    );
  }

  Widget _logoTab() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionTitle('Logo'),
        Row(
          children: [
            Expanded(
              child: _pathBox(
                _themeProfile.logoPath ?? 'Geen logo ingesteld',
                muted: _themeProfile.logoPath == null,
              ),
            ),
            const SizedBox(width: 8),
            ElevatedButton.icon(
              onPressed: _pickLogo,
              icon: const Icon(Icons.image_outlined, size: 16),
              label: const Text('Kiezen'),
            ),
            if (_themeProfile.logoPath != null)
              IconButton(
                onPressed: () => setState(() {
                  _themeProfile = _themeProfile.copyWith(clearLogo: true);
                  _profileTouched = true;
                }),
                icon: const Icon(Icons.clear, size: 18),
                tooltip: 'Verwijder logo',
              ),
          ],
        ),
        const SizedBox(height: 18),
        DropdownButtonFormField<String>(
          initialValue: _themeProfile.logoPosition,
          decoration: const InputDecoration(
            labelText: 'Logo positie',
            isDense: true,
          ),
          items: const [
            DropdownMenuItem(value: 'top-left', child: Text('Linksboven')),
            DropdownMenuItem(value: 'top-right', child: Text('Rechtsboven')),
            DropdownMenuItem(value: 'bottom-left', child: Text('Linksonder')),
            DropdownMenuItem(value: 'bottom-right', child: Text('Rechtsonder')),
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
            decoration: const InputDecoration(
              labelText: 'Logo px',
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
          decoration: const InputDecoration(
            labelText: 'Footertekst',
            hintText: 'bijv. Vertrouwelijk · {title} · {date}',
            isDense: true,
          ),
          onChanged: (_) => _profileTouched = true,
        ),
        const SizedBox(height: 6),
        const Text(
          'Tokens: {page}, {total}, {date}, {title}. Footer verschijnt op alle '
          'slides behalve titel- en sectieslides, tenzij je hem per slide uitzet.',
          style: TextStyle(fontSize: 11, color: Color(0xFF94A3B8)),
        ),
        const SizedBox(height: 14),
        DropdownButtonFormField<String>(
          initialValue: _themeProfile.footerPosition,
          decoration: const InputDecoration(
            labelText: 'Footerpositie',
            isDense: true,
          ),
          items: const [
            DropdownMenuItem(value: 'left', child: Text('Links')),
            DropdownMenuItem(value: 'center', child: Text('Midden')),
            DropdownMenuItem(value: 'right', child: Text('Rechts')),
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
          title: const Text(
            'Paginanummers tonen (rechtsonder)',
            style: TextStyle(fontSize: 13),
          ),
          controlAffinity: ListTileControlAffinity.leading,
          contentPadding: EdgeInsets.zero,
          dense: true,
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
          label,
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
              Tooltip(
                message: color,
                child: InkWell(
                  onTap: () => setState(() {
                    onChanged(color);
                    _profileTouched = true;
                  }),
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    width: 24,
                    height: 24,
                    decoration: BoxDecoration(
                      color: _parseColor(color),
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: value == color
                            ? AppTheme.accent
                            : const Color(0xFFCBD5E1),
                        width: value == color ? 2 : 1,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }

  Widget _stylePreview() {
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
            'Voorvertoning',
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
            'De snelle bruine vos springt over de luie hond.',
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
