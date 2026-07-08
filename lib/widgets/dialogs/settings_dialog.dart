import 'dart:math' as math;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/deck.dart';
import '../../models/settings.dart';
import '../../services/recovery_service.dart';
import '../../services/classification_enforcement_policy.dart';
import '../../services/webdav_service.dart';
import '../../state/settings_provider.dart';
import '../../state/tabs_provider.dart';
import '../../state/consent_provider.dart';
import '../../theme/app_theme.dart';
import '../../utils/log.dart';
import '../../utils/url_launcher_util.dart';
import '../../l10n/app_localizations.dart';
import '../editors/advanced_section.dart';
import '../language_flag.dart';
import '../privacy_statement_content.dart';
import '../reader/documentation_search_tab.dart';

part 'parts/settings_dialog_general.dart';
part 'parts/settings_dialog_appearance.dart';
part 'parts/settings_dialog_colors.dart';
part 'parts/settings_dialog_webdav.dart';
part 'parts/settings_dialog_privacy.dart';
part 'parts/settings_dialog_security.dart';
part 'parts/settings_dialog_docs.dart';
part 'parts/settings_dialog_about.dart';
part 'parts/settings_dialog_hex_color.dart';

TextStyle _fontStyle(String font, TextStyle base) {
  return base.copyWith(fontFamily: font);
}

Color _parseHexColor(String hex) {
  final cleaned = hex.replaceFirst('#', '');
  final value = int.tryParse(
    cleaned.length == 6 ? 'FF$cleaned' : cleaned,
    radix: 16,
  );
  return Color(value ?? 0xFFFFFFFF);
}

class SettingsDialog extends ConsumerStatefulWidget {
  final int initialTab;

  /// Theme profile field to scroll to and briefly highlight on the Colours tab
  /// (e.g. `textColor`, `accentColor`). See [SlideQualityIssue.field].
  final String? highlightThemeField;

  const SettingsDialog({
    super.key,
    this.initialTab = 0,
    this.highlightThemeField,
  });

  static Future<void> show(
    BuildContext context, {
    int initialTab = 0,
    String? highlightThemeField,
  }) {
    return showDialog(
      context: context,
      builder: (_) => SettingsDialog(
        initialTab: initialTab,
        highlightThemeField: highlightThemeField,
      ),
    );
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

  /// The cockpit colour scheme currently being edited, plus its saved name as a
  /// stable identity for rename/save.
  late CockpitColorScheme _cockpitScheme;
  late String _originalCockpitName;
  late TextEditingController _cockpitName;

  /// The saved name of the profile currently being edited. Used as a stable
  /// identity so renaming updates the existing profile instead of creating a
  /// duplicate.
  late String _originalName;
  late TextEditingController _profileName;
  late TextEditingController _logoSize;
  late TextEditingController _footerText;
  late TextEditingController _closingSlideMarkdown;

  // WebDAV/Nextcloud-bron.
  late TextEditingController _webdavUrl;
  late TextEditingController _webdavUser;
  late TextEditingController _webdavRoot;
  late TextEditingController _webdavPassword;

  /// Het wachtwoord zoals uit de keychain geladen, om bij opslaan te bepalen of
  /// het écht gewijzigd is. Voorkomt dat een snelle Opslaan vóórdat de
  /// asynchrone keychain-load klaar is het wachtwoord met leeg overschrijft.
  String _loadedWebdavPassword = '';

  /// Server-identiteit (URL|gebruiker) bij het openen, om te detecteren dat de
  /// keychain-sleutel wijzigt en het wachtwoord onder de nieuwe sleutel moet.
  String _initialWebdavIdentity = '';
  bool _webdavTrusted = false;

  /// Status van de verbindingstest: null = nog niet getest, true = ok,
  /// false = mislukt (met [_webdavTestMessage]).
  bool? _webdavTestOk;
  String? _webdavTestMessage;
  bool _webdavTesting = false;

  /// Whether the user changed the active profile in this session. Used to
  /// decide whether to apply the profile to the currently open presentation.
  bool _profileTouched = false;

  String? _highlightedThemeField;
  final _themeFieldKeys = <String, GlobalKey>{};

  /// Index of the section shown in the sidebar navigation (0..4).
  late int _selectedTab;

  static const _navIcons = [
    Icons.tune,
    Icons.format_paint_outlined,
    Icons.slideshow_outlined,
    Icons.speed_outlined,
    Icons.privacy_tip_outlined,
    Icons.shield_outlined,
    Icons.cloud_outlined,
    Icons.menu_book_outlined,
    Icons.info_outline,
  ];

  /// Index of the "Over OciDeck" pane. It is the last entry in the tab lists
  /// but is opened from the branded footer at the bottom of the sidebar rather
  /// than from a regular nav item, so the nav list stops one short of it.
  static const _aboutTabIndex = 8;

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
    _cockpitScheme = settings.cockpitColorScheme;
    _originalCockpitName = _cockpitScheme.name;
    _cockpitName = TextEditingController(text: _cockpitScheme.name);
    _originalName = _themeProfile.name;
    _profileName = TextEditingController(text: _themeProfile.name);
    _logoSize = TextEditingController(text: _themeProfile.logoSize.toString());
    _footerText = TextEditingController(text: _themeProfile.footerText);
    _closingSlideMarkdown = TextEditingController(
      text: _themeProfile.closingSlideMarkdown,
    );
    final webdav = settings.webdavServer;
    _webdavUrl = TextEditingController(text: webdav?.baseUrl ?? '');
    _webdavUser = TextEditingController(text: webdav?.username ?? '');
    _webdavRoot = TextEditingController(text: webdav?.rootPath ?? '');
    _webdavPassword = TextEditingController();
    _webdavTrusted = webdav?.trustedInternal ?? false;
    _initialWebdavIdentity =
        '${webdav?.baseUrl ?? ''}|${webdav?.username ?? ''}';
    if (webdav != null && webdav.isConfigured) {
      // Het wachtwoord staat in de keychain; laad het in zodat de gebruiker
      // ziet dat het er is en het niet opnieuw hoeft te typen.
      ref
          .read(settingsProvider.notifier)
          .readWebdavPassword(webdav.baseUrl, webdav.username)
          .then((pw) {
            if (mounted && pw != null) {
              setState(() {
                _webdavPassword.text = pw;
                _loadedWebdavPassword = pw;
              });
            }
          });
    }
    _highlightedThemeField = widget.highlightThemeField;
    _selectedTab = widget.initialTab.clamp(0, _aboutTabIndex);
    if (widget.highlightThemeField != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _scrollToThemeField(widget.highlightThemeField!);
      });
    }
  }

  @override
  void dispose() {
    _profileName.dispose();
    _logoSize.dispose();
    _footerText.dispose();
    _closingSlideMarkdown.dispose();
    _appearanceName.dispose();
    _cockpitName.dispose();
    _webdavUrl.dispose();
    _webdavUser.dispose();
    _webdavRoot.dispose();
    _webdavPassword.dispose();
    super.dispose();
  }

  /// Trigger a rebuild from the extension methods in the `parts/` files. They
  /// cannot call the `@protected` [setState] directly (it is only callable from
  /// instance members of a State subclass), so they route through this wrapper.
  void _rebuild(VoidCallback fn) => setState(fn);

  /// Bouw een [WebdavServer] uit de huidige veldwaarden (zonder wachtwoord).
  WebdavServer _webdavServerFromFields() {
    var url = _webdavUrl.text.trim();
    // "cloud.example.com" zonder schema is de meest gemaakte invoerfout;
    // vul https:// aan i.p.v. later op een ongeldige URL te stranden.
    if (url.isNotEmpty && !url.contains('://')) url = 'https://$url';
    return WebdavServer(
      baseUrl: url,
      username: _webdavUser.text.trim(),
      rootPath: WebdavServer.normalizeRoot(_webdavRoot.text),
      trustedInternal: _webdavTrusted,
    );
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
    if (!mounted) return;
    if (result != null) setState(() => _homeDirectory = result);
  }

  Future<void> _pickExportDirectory() async {
    final result = await FilePicker.getDirectoryPath(
      dialogTitle: context.l10n.d('Map voor exports'),
      initialDirectory: _exportDirectory ?? _homeDirectory,
    );
    if (!mounted) return;
    if (result != null) setState(() => _exportDirectory = result);
  }

  Future<void> _pickLogo() async {
    final result = await FilePicker.pickFiles(
      dialogTitle: context.l10n.d('Logo kiezen'),
      type: FileType.image,
    );
    if (!mounted) return;
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
    if (_cockpitScheme.isBuiltIn) {
      notifier.selectCockpitColorScheme(_cockpitScheme.name);
    } else {
      final cockpitName = _cockpitName.text.trim();
      notifier.saveCockpitColorScheme(
        _cockpitScheme.copyWith(
          name: cockpitName.isEmpty ? 'Eigen schema' : cockpitName,
        ),
        previousName: _originalCockpitName,
      );
    }

    // Apply the chosen/edited profile to the presentation that is currently
    // open, so the change is visible immediately. Only when the user actually
    // touched the profile in this session (otherwise we would clobber a
    // per-deck profile the user set elsewhere).
    if (_profileTouched) {
      ref.read(tabsProvider).current?.deckNotifier.updateThemeProfile(profile);
    }

    // WebDAV/Nextcloud-bron: serverconfig in prefs, wachtwoord in de keychain.
    final server = _webdavServerFromFields();
    if (server.isConfigured) {
      notifier.setWebdavServer(server);
      // Schrijf het wachtwoord als het is gewijzigd, of wanneer de server-
      // identiteit (en dus de keychain-sleutel) wijzigde. Zo leegt een Opslaan
      // vóór de asynchrone keychain-load het wachtwoord niet, maar verhuist het
      // wél mee bij een nieuwe gebruikersnaam/URL.
      final identityChanged =
          '${server.baseUrl}|${server.username}' != _initialWebdavIdentity;
      if (_webdavPassword.text != _loadedWebdavPassword || identityChanged) {
        notifier.setWebdavPassword(
          server.baseUrl,
          server.username,
          _webdavPassword.text,
        );
      }
    } else {
      notifier.setWebdavServer(null);
    }

    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final profiles = _profiles;
    final screen = MediaQuery.sizeOf(context);
    final dialogWidth = math
        .min(920.0, screen.width * 0.88)
        .clamp(640.0, 920.0);
    final dialogHeight = math
        .min(760.0, screen.height * 0.86)
        .clamp(560.0, 760.0);

    final labels = <String>[
      l10n.t('settingsGeneral'),
      l10n.d('App-thema'),
      l10n.d('Presentatiestijl'),
      l10n.d('Cockpit'),
      l10n.d('Licentie en Privacy'),
      l10n.d('Beveiliging'),
      l10n.d('Nextcloud'),
      l10n.d('Documentatie'),
      l10n.d('Over OciDeck'),
    ];

    final bodies = <Widget>[
      _tabBody(_generalTab()),
      _tabBody(_appearanceTab()),
      _tabBody(_presentationStyleTab(profiles)),
      _tabBody(_cockpitTab()),
      _tabBody(_privacyTab()),
      _tabBody(_securityTab()),
      _tabBody(_webdavTab()),
      _tabBody(_documentationTab()),
      _tabBody(_aboutTab()),
    ];

    return Dialog(
      clipBehavior: Clip.antiAlias,
      backgroundColor: Colors.white,
      insetPadding: const EdgeInsets.symmetric(horizontal: 40, vertical: 28),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: SizedBox(
        width: dialogWidth,
        height: dialogHeight,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _sidebar(l10n, labels),
            Expanded(
              // Material (not ColoredBox) so ListTiles inside the tab bodies
              // paint their ink/selected state onto this surface instead of a
              // hidden ancestor behind an opaque box.
              child: Material(
                color: AppTheme.slate50,
                child: Column(
                  children: [
                    _contentHeader(labels[_selectedTab]),
                    Expanded(
                      child: IndexedStack(
                        index: _selectedTab,
                        sizing: StackFit.expand,
                        children: bodies,
                      ),
                    ),
                    _footerBar(l10n),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _sidebar(AppLocalizations l10n, List<String> labels) {
    return Container(
      width: 234,
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [AppTheme.navySoft, AppTheme.navy],
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 26, 20, 22),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [AppTheme.blue500, AppTheme.accent],
                    ),
                    borderRadius: BorderRadius.circular(11),
                    boxShadow: [
                      BoxShadow(
                        color: AppTheme.accent.withValues(alpha: 0.45),
                        blurRadius: 12,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: const Icon(
                    Icons.settings_suggest_outlined,
                    color: Colors.white,
                    size: 23,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    l10n.t('settings'),
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.2,
                    ),
                  ),
                ),
              ],
            ),
          ),
          // The last label ("Over OciDeck") is not a regular nav item; it is
          // reached from the branded footer below, so stop one short.
          for (var i = 0; i < labels.length - 1; i++)
            _navItem(i, _navIcons[i], labels[i]),
          const Spacer(),
          _aboutFooter(labels.last),
        ],
      ),
    );
  }

  /// The branded footer at the bottom of the sidebar. Doubles as the entry
  /// point to the "Over OciDeck" pane: tapping it selects that tab and the
  /// footer lights up like a selected nav item.
  Widget _aboutFooter(String aboutLabel) {
    final selected = _selectedTab == _aboutTabIndex;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 14),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(11),
          onTap: () => setState(() => _selectedTab = _aboutTabIndex),
          child: Tooltip(
            message: aboutLabel,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              padding: const EdgeInsets.fromLTRB(10, 10, 12, 10),
              decoration: BoxDecoration(
                color: selected
                    ? Colors.white.withValues(alpha: 0.13)
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(11),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // EU-yellow recolour of the logo, so it reads on the dark
                  // sidebar without a backing plate.
                  Semantics(
                    label: 'OciDeck',
                    image: true,
                    child: Image.asset(
                      'assets/images/ocideck-logo-eu.png',
                      width: 30,
                      height: 30,
                      fit: BoxFit.contain,
                      filterQuality: FilterQuality.high,
                    ),
                  ),
                  const SizedBox(width: 10),
                  const Expanded(
                    child: Text(
                      'OciDeck',
                      style: TextStyle(
                        // EU-vlaggeel: leesbaar op de donkere/EU-blauwe
                        // zijbalk, passend bij het geel-hertinte logo ernaast.
                        color: AppTheme.amberVivid,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 2.5,
                      ),
                    ),
                  ),
                  Icon(
                    Icons.info_outline,
                    size: 16,
                    color: selected
                        ? Colors.white
                        : Colors.white.withValues(alpha: 0.5),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _navItem(int index, IconData icon, String label) {
    final selected = _selectedTab == index;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(11),
          onTap: () => setState(() => _selectedTab = index),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            padding: const EdgeInsets.fromLTRB(12, 11, 14, 11),
            decoration: BoxDecoration(
              color: selected
                  ? Colors.white.withValues(alpha: 0.13)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(11),
            ),
            child: Row(
              children: [
                AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  width: 3,
                  height: 18,
                  margin: const EdgeInsets.only(right: 11),
                  decoration: BoxDecoration(
                    color: selected ? AppTheme.blue400 : Colors.transparent,
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
                Icon(
                  icon,
                  size: 19,
                  color: selected
                      ? Colors.white
                      : Colors.white.withValues(alpha: 0.62),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    label,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: selected
                          ? Colors.white
                          : Colors.white.withValues(alpha: 0.72),
                      fontSize: 13.5,
                      fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _contentHeader(String title) {
    return Container(
      padding: const EdgeInsets.fromLTRB(28, 18, 14, 16),
      decoration: BoxDecoration(
        color: AppTheme.paper,
        border: const Border(bottom: BorderSide(color: AppTheme.iceBlue)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              title,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: AppTheme.slate800,
                letterSpacing: 0.1,
              ),
            ),
          ),
          IconButton(
            tooltip: context.l10n.t('cancel'),
            onPressed: () => Navigator.pop(context),
            icon: const Icon(Icons.close, size: 20),
            color: AppTheme.slate400,
            splashRadius: 20,
          ),
        ],
      ),
    );
  }

  Widget _footerBar(AppLocalizations l10n) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 13),
      decoration: BoxDecoration(
        color: AppTheme.paper,
        border: const Border(top: BorderSide(color: AppTheme.iceBlue)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(l10n.t('cancel')),
          ),
          const SizedBox(width: 10),
          ElevatedButton.icon(
            onPressed: _save,
            icon: const Icon(Icons.check_rounded, size: 18),
            label: Text(l10n.t('saveSettings')),
          ),
        ],
      ),
    );
  }

  Widget _profileSelector(List<ThemeProfile> profiles) {
    final l10n = context.l10n;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: TextField(
            controller: _profileName,
            textInputAction: TextInputAction.done,
            decoration: InputDecoration(
              labelText: l10n.d('Stijlprofiel'),
              hintText: l10n.d('Naam van het stijlprofiel'),
              isDense: true,
              prefixIcon: const Icon(Icons.style_outlined, size: 18),
              suffixIcon: PopupMenuButton<String>(
                tooltip: l10n.d('Ander profiel kiezen'),
                icon: const Icon(Icons.arrow_drop_down),
                onSelected: _selectProfile,
                itemBuilder: (context) => [
                  for (final profile in profiles)
                    PopupMenuItem(
                      value: profile.name,
                      child: Row(
                        children: [
                          if (profile.name == _originalName)
                            const Padding(
                              padding: EdgeInsets.only(right: 8),
                              child: Icon(Icons.check, size: 16),
                            ),
                          Expanded(child: Text(profile.name)),
                        ],
                      ),
                    ),
                ],
              ),
            ),
            onChanged: (value) {
              final name = value.trim();
              _themeProfile = _themeProfile.copyWith(
                name: name.isEmpty ? _themeProfile.name : name,
              );
              _profileTouched = true;
            },
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
      padding: const EdgeInsets.fromLTRB(28, 22, 24, 22),
      child: child,
    );
  }

  GlobalKey _themeFieldKey(String field) =>
      _themeFieldKeys.putIfAbsent(field, GlobalKey.new);

  void _scrollToThemeField(String field) {
    if (!mounted) return;
    setState(() => _highlightedThemeField = field);
    final ctx = _themeFieldKeys[field]?.currentContext;
    if (ctx != null) {
      Scrollable.ensureVisible(
        ctx,
        alignment: 0.25,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    }
    Future<void>.delayed(const Duration(seconds: 3), () {
      if (mounted && _highlightedThemeField == field) {
        setState(() => _highlightedThemeField = null);
      }
    });
  }

  Widget _themeColorAnchor(String field, Widget child) {
    final highlighted = _highlightedThemeField == field;
    return KeyedSubtree(
      key: _themeFieldKey(field),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        margin: const EdgeInsets.only(bottom: 2),
        padding: highlighted ? const EdgeInsets.all(8) : EdgeInsets.zero,
        decoration: highlighted
            ? BoxDecoration(
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppTheme.accent, width: 2),
                color: AppTheme.accent.withValues(alpha: 0.06),
              )
            : null,
        child: child,
      ),
    );
  }

  Widget _presentationStyleTab(List<ThemeProfile> profiles) {
    final l10n = context.l10n;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _profileScopeBanner(),
        _sectionTitle(l10n.t('styleProfile')),
        _profileSelector(profiles),
        const SizedBox(height: 20),
        _sectionTitle(l10n.d('Lettertype')),
        _fontSection(),
        _presentationStyleDivider(l10n.t('settingsColors')),
        ..._colorsSectionChildren(),
        _presentationStyleDivider(l10n.d('Animatie')),
        ..._animationSettings(),
        _presentationStyleDivider(l10n.d('Logo en footer')),
        ..._logoSectionChildren(),
        const SizedBox(height: 18),
        _stylePreview(),
      ],
    );
  }

  Widget _presentationStyleDivider(String title) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 24),
        const Divider(height: 1),
        const SizedBox(height: 16),
        _sectionTitle(title),
      ],
    );
  }

  Widget _sectionTitle(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        text.toUpperCase(),
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          color: AppTheme.slate500,
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
          color: muted ? AppTheme.slate400 : AppTheme.slate700,
        ),
        overflow: TextOverflow.ellipsis,
      ),
    );
  }

  BoxDecoration _boxDecoration() {
    return BoxDecoration(
      border: Border.all(color: AppTheme.slate300),
      borderRadius: BorderRadius.circular(6),
      color: AppTheme.paper,
    );
  }

  Color _parseColor(String hex) {
    return _parseHexColor(hex);
  }
}
