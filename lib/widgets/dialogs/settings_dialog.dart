import 'dart:math' as math;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/deck.dart';
import '../../models/markdown_validation.dart';
import '../../models/settings.dart';
import '../../models/slide.dart';
import '../../models/slide_quality.dart';
import '../../platform/platform_features.dart';
import '../../services/ai_client_service.dart';
import '../../services/ai_security_gate.dart';
import '../../services/file_service.dart';
import '../../services/recovery_service.dart';
import '../../services/classification_enforcement_policy.dart';
import '../../services/webdav_service.dart';
import '../../models/local_cve_status.dart';
import '../../services/cve/local_cve_database.dart';
import '../../services/secmodule/sec_module_provisioner.dart';
import '../../services/secmodule/sec_reference_inventory.dart';
import '../../state/local_cve_provider.dart';
import '../../services/slide_quality_analyzer.dart';
import '../../state/deck_provider.dart';
import '../../state/settings_provider.dart';
import '../../state/tabs_provider.dart';
import '../../state/consent_provider.dart';
import '../../state/sec_module_provider.dart';
import '../../theme/app_theme.dart';
import '../../utils/error_snackbar.dart';
import '../../utils/log.dart';
import '../../utils/url_launcher_util.dart';
import '../../l10n/app_localizations.dart';
import '../../l10n/slide_quality_localization.dart';
import '../../models/privacy_disposition.dart';
import '../editors/advanced_section.dart';
import '../language_flag.dart';
import '../privacy_badge.dart';
import '../privacy_statement_content.dart';
import '../reader/documentation_search_tab.dart';

part 'parts/settings_dialog_general.dart';
part 'parts/settings_dialog_presentation.dart';
part 'parts/settings_dialog_appearance.dart';
part 'parts/settings_dialog_colors.dart';
part 'parts/settings_dialog_profile.dart';
part 'parts/settings_dialog_webdav.dart';
part 'parts/settings_dialog_privacy.dart';
part 'parts/settings_dialog_security.dart';
part 'parts/settings_dialog_ai.dart';
part 'parts/settings_dialog_docs.dart';
part 'parts/settings_dialog_modules.dart';
part 'parts/settings_dialog_checklists.dart';
part 'parts/settings_dialog_about.dart';
part 'parts/settings_dialog_hex_color.dart';
part 'parts/settings_dialog_search.dart';
part 'parts/settings_dialog_search_index.dart';
part 'parts/settings_dialog_cve_local.dart';

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
  /// Bewerkbare kopie van de bibliotheken; toegepast bij Opslaan (zoals de
  /// export­map en het stijlprofiel), zodat Annuleren de wijzigingen verwerpt.
  late List<LibraryFolder> _libraries;
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

  // AI-assistentie (optioneel, standaard uit).
  late bool _aiEnabled;
  late AiBackendMode _aiMode;
  late bool _aiTrusted;
  late bool _aiCloudConfirmed;
  late TextEditingController _aiBaseUrl;
  late TextEditingController _aiModel;
  late TextEditingController _aiApiKey;

  /// De API-sleutel zoals uit de keychain geladen, om bij opslaan te bepalen of
  /// hij écht gewijzigd is (zelfde patroon als het WebDAV-wachtwoord).
  String _loadedAiApiKey = '';

  /// Basis-URL bij het openen, om te detecteren dat de keychain-sleutel wijzigt
  /// en de API-sleutel onder de nieuwe sleutel moet.
  String _initialAiBaseUrl = '';
  bool? _aiTestOk;
  String? _aiTestMessage;
  bool _aiTesting = false;

  /// Whether the user changed the active profile in this session. Used to
  /// decide whether to apply the profile to the currently open presentation.
  bool _profileTouched = false;

  String? _highlightedThemeField;
  final _themeFieldKeys = <String, GlobalKey>{};

  /// Anchors for the settings search: every `_sectionTitle` registers a key
  /// under its own (translated) text, so a search hit can scroll its section
  /// into view and flash it. See parts/settings_dialog_search.dart.
  final _sectionKeys = <String, GlobalKey>{};
  String? _highlightedSection;
  final _searchController = TextEditingController();
  String _searchQuery = '';

  /// De telling van de referentiecatalogi (Uitbreidingen). Eén keer starten en
  /// vasthouden: de volledige CWE-lijst komt uit een asset, en een FutureBuilder
  /// die elke build opnieuw begint zou hem elke build opnieuw willen laden.
  late final Future<List<ReferenceCatalog>> _referenceInventory =
      SecReferenceInventory.load();

  /// Index of the section shown in the sidebar navigation (0..4).
  late int _selectedTab;

  /// De taal zoals die bij het openen actief was, plus of er is opgeslagen. De
  /// taalkeuze wisselt de interface meteen (dat is de bedoeling: je wilt zien
  /// wat je kiest), maar schrijft daarmee buiten Opslaan om in de instellingen.
  /// Zonder deze twee zou Annuleren de taal laten staan terwijl het de rest van
  /// je wijzigingen verwerpt.
  late final String _initialLanguageCode;
  bool _saved = false;

  static const _navIcons = [
    Icons.tune,
    Icons.format_paint_outlined,
    Icons.slideshow_outlined,
    Icons.speed_outlined,
    Icons.privacy_tip_outlined,
    Icons.shield_outlined,
    Icons.smart_toy_outlined,
    Icons.cloud_outlined,
    Icons.checklist_outlined,
    Icons.extension_outlined,
    Icons.menu_book_outlined,
    Icons.info_outline,
  ];

  /// Index of the "Over OciDeck" pane. It is the last entry in the tab lists
  /// but is opened from the branded footer at the bottom of the sidebar rather
  /// than from a regular nav item, so the nav list stops one short of it.
  static const _aboutTabIndex = 11;

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
    _initialLanguageCode = settings.languageCode;
    _libraries = List.of(settings.libraries);
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
    _initAiFields(settings.aiSettings);
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
    _searchController.dispose();
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
    _aiBaseUrl.dispose();
    _aiModel.dispose();
    _aiApiKey.dispose();
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

  /// Kies een map en voeg 'm als nieuwe bibliotheek toe. De naam start op de
  /// mapnaam en is daarna in de rij te wijzigen. Een al toegevoegd pad wordt
  /// overgeslagen.
  Future<void> _addLibrary() async {
    final result = await FilePicker.getDirectoryPath(
      dialogTitle: context.l10n.d('Map kiezen'),
      initialDirectory: _libraries.isEmpty ? null : _libraries.last.path,
    );
    if (!mounted || result == null) return;
    if (_libraries.any((l) => l.path == result)) return;
    setState(
      () =>
          _libraries.add(LibraryFolder(name: p.basename(result), path: result)),
    );
  }

  /// De bibliotheken zoals ze worden opgeslagen: namen getrimd, en een leeg
  /// gemaakte naam valt terug op de mapnaam zodat elke rij een label houdt.
  List<LibraryFolder> _normalizedLibraries() => [
    for (final lib in _libraries)
      lib.copyWith(
        name: lib.name.trim().isEmpty ? p.basename(lib.path) : lib.name.trim(),
      ),
  ];

  Future<void> _pickExportDirectory() async {
    final result = await FilePicker.getDirectoryPath(
      dialogTitle: context.l10n.d('Map voor exports'),
      initialDirectory:
          _exportDirectory ??
          (_libraries.isEmpty ? null : _libraries.first.path),
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
    _adoptProfile(_profiles.firstWhere((p) => p.name == name));
  }

  /// Neem [profile] over als het profiel in bewerking. Eén plek voor de
  /// veldsynchronisatie die kiezen, aanmaken, importeren en verwijderen delen,
  /// en het setState-aanspreekpunt voor de profiel-extensie (zie
  /// parts/settings_dialog_profile.dart).
  void _adoptProfile(ThemeProfile profile) {
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

  /// Het profiel zoals het nú in de editor staat: [_themeProfile] plus de
  /// velden die nog in hun controller leven. Opslaan én exporteren gaan hier
  /// doorheen, zodat je exporteert wat je ziet.
  ThemeProfile _editedProfile() {
    final name = _profileName.text.trim();
    final size = int.tryParse(_logoSize.text)?.clamp(32, 240);
    return _themeProfile.copyWith(
      name: name.isEmpty ? 'Stijlprofiel' : name,
      logoSize: size,
      footerText: _footerText.text,
      closingSlideMarkdown: _closingSlideMarkdown.text,
    );
  }

  void _save() {
    _saved = true;
    final notifier = ref.read(settingsProvider.notifier);
    final profile = _editedProfile();
    notifier.setLibraries(_normalizedLibraries());
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

    _saveAiSettings(notifier);

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

    final labels = _tabLabels(l10n);

    final bodies = <Widget>[
      _tabBody(_generalTab()),
      _tabBody(_appearanceTab()),
      _tabBody(_presentationStyleTab(profiles)),
      _tabBody(_cockpitTab()),
      _tabBody(_privacyTab()),
      _tabBody(_securityTab()),
      _tabBody(_aiTab()),
      _tabBody(_webdavTab()),
      _tabBody(_checklistsTab()),
      _tabBody(_modulesTab()),
      _tabBody(_documentationTab()),
      _tabBody(_aboutTab()),
    ];

    return PopScope(
      // Vangt élke manier van sluiten zonder opslaan: de knop, het kruisje,
      // Escape en een klik naast het venster.
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) _restoreLanguageIfDiscarded();
      },
      child: Dialog(
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
                        // De zoekresultaten leggen zich óver de actieve tab; de
                        // IndexedStack blijft eronder staan zodat zijn GlobalKeys
                        // (de sectie-ankers) in de boom blijven en een treffer er
                        // meteen naartoe kan scrollen.
                        child: Stack(
                          children: [
                            IndexedStack(
                              index: _selectedTab,
                              sizing: StackFit.expand,
                              children: bodies,
                            ),
                            if (_searchQuery.isNotEmpty)
                              Positioned.fill(
                                child: _settingsSearchResults(l10n),
                              ),
                          ],
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
      ),
    );
  }

  /// Zet de taal terug zoals ze bij het openen was wanneer het venster zonder
  /// opslaan sluit. Alleen schrijven als er écht iets veranderde, zodat een
  /// gewone Annuleren geen instellingen aanraakt.
  void _restoreLanguageIfDiscarded() {
    if (_saved) return;
    if (ref.read(settingsProvider).languageCode == _initialLanguageCode) return;
    ref.read(settingsProvider.notifier).setLanguageCode(_initialLanguageCode);
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
          // reached from the branded footer below, so stop one short. The nav
          // list scrolls so extra tabs (AI, Modules, …) never overflow the
          // sidebar; the footer stays pinned at the bottom.
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (var i = 0; i < labels.length - 1; i++)
                    _navItem(i, _navIcons[i], labels[i]),
                ],
              ),
            ),
          ),
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
          _settingsSearchField(),
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
