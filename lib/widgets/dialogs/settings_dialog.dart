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
import '../../models/reference_standard.dart';
import '../../services/reference_standards.dart';
import '../../services/ai_client_service.dart';
import '../../services/ai_security_gate.dart';
import '../../services/file_service.dart';
import '../../services/recovery_service.dart';
import '../../services/classification_enforcement_policy.dart';
import '../../services/webdav_service.dart';
import '../../models/local_cve_status.dart';
import '../../services/cve/local_cve_database.dart';
import '../../services/info_safety/info_safety_reference_inventory.dart';
import '../../state/local_cve_provider.dart';
import '../../services/slide_quality_analyzer.dart';
import '../../state/deck_provider.dart';
import '../../state/git_provider.dart';
import '../../state/settings_provider.dart';
import '../../state/tabs_provider.dart';
import '../../state/consent_provider.dart';
import '../../state/info_safety_provider.dart';
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

part 'parts/settings_dialog_sections.dart';
part 'parts/settings_dialog_secret.dart';
part 'parts/settings_dialog_webdav_form.dart';
part 'parts/settings_dialog_git_form.dart';
part 'parts/settings_dialog_ai_form.dart';
part 'parts/settings_dialog_chrome.dart';
part 'parts/settings_dialog_general.dart';
part 'parts/settings_dialog_storage.dart';
part 'parts/settings_dialog_presentation.dart';
part 'parts/settings_dialog_appearance.dart';
part 'parts/settings_dialog_colors.dart';
part 'parts/settings_dialog_profile.dart';
part 'parts/settings_dialog_webdav.dart';
part 'parts/settings_dialog_git.dart';
part 'parts/settings_dialog_privacy.dart';
part 'parts/settings_dialog_security.dart';
part 'parts/settings_dialog_ai.dart';
part 'parts/settings_dialog_docs.dart';
part 'parts/settings_dialog_modules.dart';
part 'parts/settings_dialog_checklists.dart';
part 'parts/settings_dialog_about.dart';
part 'parts/settings_dialog_standards.dart';
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
  /// Het tabblad dat bij openen actief is.
  final SettingsSection initialSection;

  /// Theme profile field to scroll to and briefly highlight on the Colours tab
  /// (e.g. `textColor`, `accentColor`). See [SlideQualityIssue.field].
  final String? highlightThemeField;

  const SettingsDialog({
    super.key,
    this.initialSection = SettingsSection.general,
    this.highlightThemeField,
  });

  static Future<void> show(
    BuildContext context, {
    SettingsSection initialSection = SettingsSection.general,
    String? highlightThemeField,
  }) {
    return showDialog(
      context: context,
      builder: (_) => SettingsDialog(
        initialSection: initialSection,
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

  /// De git-bron: velden, forgekeuze en token bij elkaar.
  final GitForm _git = GitForm();

  /// De Nextcloud-bron: velden, testuitslag en wachtwoord bij elkaar in één
  /// object in plaats van dertien losse velden op deze klasse.
  final WebdavForm _webdav = WebdavForm();

  /// De AI-backend (optioneel, standaard uit): velden, modus en API-sleutel.
  final AiForm _ai = AiForm();

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
      InfoSafetyReferenceInventory.load();

  /// Het tabblad dat de zijbalk op dit moment toont.
  late SettingsSection _selectedTab;

  /// De opslagwijze die op het tabblad Opslag is uitgeklapt, of `null` als ze
  /// alle drie dicht staan. Er staat er hooguit één open: de panelen zijn lang
  /// genoeg dat twee tegelijk de lijst onleesbaar maken.
  StorageModality? _expandedModality;

  /// De taal zoals die bij het openen actief was, plus of er is opgeslagen. De
  /// taalkeuze wisselt de interface meteen (dat is de bedoeling: je wilt zien
  /// wat je kiest), maar schrijft daarmee buiten Opslaan om in de instellingen.
  /// Zonder deze twee zou Annuleren de taal laten staan terwijl het de rest van
  /// je wijzigingen verwerpt.
  late final String _initialLanguageCode;
  bool _saved = false;

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
    final git = settings.gitRepo;
    _git.adoptFrom(git);
    if (git != null && git.isConfigured) {
      // Zelfde reden als bij het WebDAV-wachtwoord: het token staat in de
      // keychain, laad het in zodat de gebruiker ziet dát het er is.
      ref
          .read(settingsProvider.notifier)
          .readGitToken(git.baseUrl, git.owner)
          .then((token) {
            if (!mounted || token == null) return;
            setState(() => _git.token.adopt(token));
          });
    }
    final webdav = settings.webdavServer;
    _webdav.adoptFrom(webdav);
    if (webdav != null && webdav.isConfigured) {
      // Het wachtwoord staat in de keychain; laad het in zodat de gebruiker
      // ziet dat het er is en het niet opnieuw hoeft te typen.
      ref
          .read(settingsProvider.notifier)
          .readWebdavPassword(webdav.baseUrl, webdav.username)
          .then((pw) {
            if (mounted && pw != null) {
              setState(() => _webdav.password.adopt(pw));
            }
          });
    }
    _initAiFields(settings.aiSettings);
    _highlightedThemeField = widget.highlightThemeField;
    _selectedTab = widget.initialSection;
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
    _git.dispose();
    _webdav.dispose();
    _ai.dispose();
    super.dispose();
  }

  /// Trigger a rebuild from the extension methods in the `parts/` files. They
  /// cannot call the `@protected` [setState] directly (it is only callable from
  /// instance members of a State subclass), so they route through this wrapper.
  void _rebuild(VoidCallback fn) => setState(fn);

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

    _git.save(notifier);
    _webdav.save(notifier);

    _ai.save(notifier);

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

    // Eén ingang per tabblad, in de volgorde van de enum, zodat de IndexedStack
    // hieronder nooit uit de pas kan lopen met de zijbalk.
    final bodies = [
      for (final section in SettingsSection.values)
        _tabBody(switch (section) {
          SettingsSection.general => _generalTab(),
          SettingsSection.storage => _storageTab(),
          SettingsSection.appearance => _appearanceTab(),
          SettingsSection.presentation => _presentationStyleTab(profiles),
          SettingsSection.cockpit => _cockpitTab(),
          SettingsSection.privacy => _privacyTab(),
          SettingsSection.security => _securityTab(),
          SettingsSection.ai => _aiTab(),
          SettingsSection.checklists => _checklistsTab(),
          SettingsSection.modules => _modulesTab(),
          SettingsSection.documentation => _documentationTab(),
          SettingsSection.about => _aboutTab(),
        }),
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
              _sidebar(l10n),
              Expanded(
                // Material (not ColoredBox) so ListTiles inside the tab bodies
                // paint their ink/selected state onto this surface instead of a
                // hidden ancestor behind an opaque box.
                child: Material(
                  color: AppTheme.slate50,
                  child: Column(
                    children: [
                      _contentHeader(_selectedTab.label(l10n)),
                      Expanded(
                        // De zoekresultaten leggen zich óver de actieve tab; de
                        // IndexedStack blijft eronder staan zodat zijn GlobalKeys
                        // (de sectie-ankers) in de boom blijven en een treffer er
                        // meteen naartoe kan scrollen.
                        child: Stack(
                          children: [
                            IndexedStack(
                              index: _selectedTab.index,
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
