import 'dart:convert';
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
import '../../models/storage_connection.dart';
import '../../models/slide_quality.dart';
import '../../platform/platform_features.dart';
import '../../models/reference_standard.dart';
import '../../services/privacy/privacy_regions.dart';
import '../../services/reference_standards.dart';
import '../../services/ai_client_service.dart';
import '../../services/ai_security_gate.dart';
import '../../services/disk_traces.dart';
import '../../services/file_service.dart';
import '../../services/git/outbox.dart';
import '../../services/recovery_service.dart';
import '../../services/classification_enforcement_policy.dart';
import '../../services/git/git_forge.dart';
import '../../utils/net_guard.dart';
import 'certificate_trust_dialog.dart';
import '../../services/s3/s3_service.dart';
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
import '../slides/image_zoom_dialog.dart';

part 'parts/settings_dialog_sections.dart';
part 'parts/settings_dialog_secret.dart';
part 'parts/settings_dialog_webdav_form.dart';
part 'parts/settings_dialog_git_form.dart';
part 'parts/settings_dialog_s3_form.dart';
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
part 'parts/settings_dialog_s3.dart';
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
  /// Bewerkbare kopie van de bestandsverbindingen, in de volgorde die de
  /// gebruiker sleept; toegepast bij Opslaan (zoals de exportmap en het
  /// stijlprofiel), zodat Annuleren de wijzigingen verwerpt.
  ///
  /// Voor lokale mappen staat hier alles wat de verbinding is. Voor WebDAV en
  /// git staat hier alleen de identiteit (id, naam) — de invulvelden leven in
  /// [_webdavForms] en [_gitForms], omdat een TextEditingController niet in een
  /// onveranderlijk model past.
  late List<StorageConnection> _connections;

  /// Eén invulformulier per WebDAV-verbinding, op verbindings-id. Lui
  /// aangemaakt en pas bij [dispose] opgeruimd: een formulier weggooien zodra
  /// het paneel dichtklapt zou de half ingetypte server kwijtmaken.
  final Map<String, WebdavForm> _webdavForms = {};

  /// Idem voor git-verbindingen.
  final Map<String, GitForm> _gitForms = {};

  /// Idem voor S3-verbindingen.
  final Map<String, S3Form> _s3Forms = {};

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

  /// De verbinding die op het tabblad Opslag is uitgeklapt, of `null` als alles
  /// dicht staat. Er staat er hooguit één open: de panelen zijn lang genoeg dat
  /// twee tegelijk de lijst onleesbaar maken.
  String? _expandedConnectionId;

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
    _connections = List.of(settings.connections);
    for (final connection in _connections) {
      _adoptConnectionForm(connection);
      // De configuratie zoals hij bij het openen was. Wijzigt hij, dan slaat
      // een eerdere geslaagde test nergens meer op en vervalt hij.
      _configAtOpen[connection.id] = jsonEncode(connection.toJson()['config']);
    }
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
    for (final form in _gitForms.values) {
      form.dispose();
    }
    for (final form in _webdavForms.values) {
      form.dispose();
    }
    for (final form in _s3Forms.values) {
      form.dispose();
    }
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

  /// Alle lokale verbindingen, in lijstvolgorde — het startpunt voor de
  /// mapkiezers hieronder.
  List<LocalConnection> get _localConnections => [
    for (final c in _connections)
      if (c is LocalConnection) c,
  ];

  /// Maak (of hergebruik) het invulformulier van een netwerkverbinding en vul
  /// het met de opgeslagen waarden. Het geheim komt asynchroon uit de keychain
  /// na, zodat de gebruiker ziet dát het er is en het niet opnieuw hoeft te
  /// typen.
  void _adoptConnectionForm(StorageConnection connection) {
    final notifier = ref.read(settingsProvider.notifier);
    switch (connection) {
      case LocalConnection():
        break;
      case WebdavConnection(:final server):
        final form = _webdavForms.putIfAbsent(connection.id, WebdavForm.new);
        form.adoptFrom(server);
        if (!server.isConfigured) return;
        notifier.readWebdavPassword(server.baseUrl, server.username).then((pw) {
          if (!mounted || pw == null) return;
          setState(() => form.password.adopt(pw));
        });
      case S3Connection(:final bucket):
        final form = _s3Forms.putIfAbsent(connection.id, S3Form.new);
        form.adoptFrom(bucket);
        if (!bucket.isConfigured) return;
        notifier.readS3SecretKey(bucket.endpoint, bucket.accessKeyId).then((
          key,
        ) {
          if (!mounted || key == null) return;
          setState(() => form.secret.adopt(key));
        });
      case GitConnection(:final repo):
        final form = _gitForms.putIfAbsent(connection.id, GitForm.new);
        form.adoptFrom(repo);
        if (!repo.isConfigured) return;
        notifier.readGitToken(repo.baseUrl, repo.owner).then((token) {
          if (!mounted || token == null) return;
          setState(() => form.token.adopt(token));
        });
    }
  }

  /// De verbindingen zoals ze worden opgeslagen: de netwerkvelden uit hun
  /// formulier gelezen, namen getrimd, en een leeg gelaten naam vervangen door
  /// iets herkenbaars zodat elke rij een label houdt.
  /// Per verbinding de configuratie zoals hij bij het openen was, als JSON.
  /// Alleen om te kúnnen zien dát er iets veranderde — niet om terug te lezen.
  final Map<String, String> _configAtOpen = {};

  List<StorageConnection> _normalizedConnections() => [
    for (final c in _connections) _normalizeConnection(c),
  ];

  StorageConnection _normalizeConnection(StorageConnection c) {
    final verified = _verificationFor(c);
    final withValues = switch (c) {
      LocalConnection() => c,
      WebdavConnection() => c.copyWith(
        server: _webdavForms[c.id]?.server,
        verifiedAt: verified,
        clearVerified: verified == null,
      ),
      S3Connection() => c.copyWith(
        bucket: _s3Forms[c.id]?.config,
        verifiedAt: verified,
        clearVerified: verified == null,
      ),
      GitConnection() => c.copyWith(
        repo: _gitForms[c.id]?.config,
        verifiedAt: verified,
        clearVerified: verified == null,
      ),
    };
    final name = withValues.name.trim();
    if (name.isNotEmpty) return withValues;
    // Zonder naam valt de rij terug op iets wat de gebruiker herkent: de
    // mapnaam, de host of owner/repo.
    final fallback = switch (withValues) {
      LocalConnection(:final path) => path.isEmpty ? '' : p.basename(path),
      final other => other.fallbackLabel,
    };
    return switch (withValues) {
      LocalConnection() => withValues.copyWith(name: fallback),
      WebdavConnection() => withValues.copyWith(name: fallback),
      S3Connection() => withValues.copyWith(name: fallback),
      GitConnection() => withValues.copyWith(name: fallback),
    };
  }

  /// Wanneer deze verbinding voor het laatst antwoord gaf — na deze
  /// bewerkronde.
  ///
  /// Drie gevallen, in deze volgorde:
  ///  1. In dit venster geslaagd getest → nú. Dat is de verste waarneming.
  ///  2. De configuratie is gewijzigd → `null`. Een eerdere test ging over een
  ///     andere server; hem laten staan zou een groen vinkje opleveren voor
  ///     iets dat nooit is geprobeerd.
  ///  3. Verder ongewijzigd → wat er stond.
  ///
  /// Een *mislukte* test wist niets. Hij bewijst dat het nú niet gaat, niet dat
  /// het vorige week niet ging — en die eerdere waarneming is nog steeds het
  /// beste dat we hebben.
  DateTime? _verificationFor(StorageConnection c) {
    final testedOk = switch (c) {
      WebdavConnection() => _webdavForms[c.id]?.testOk,
      S3Connection() => _s3Forms[c.id]?.testOk,
      GitConnection() => _gitForms[c.id]?.testOk,
      LocalConnection() => null,
    };
    if (testedOk == true) return DateTime.now();
    final before = _configAtOpen[c.id];
    final now = jsonEncode(_configOf(c));
    if (before != null && before != now) return null;
    return c.verifiedAt;
  }

  /// De configuratie zoals hij nú in de formulieren staat, voor de
  /// vergelijking in [_verificationFor].
  Object? _configOf(StorageConnection c) => switch (c) {
    WebdavConnection() => _webdavForms[c.id]?.server.toJson(),
    S3Connection() => _s3Forms[c.id]?.config.toJson(),
    GitConnection() => _gitForms[c.id]?.config.toJson(),
    LocalConnection() => c.toJson()['config'],
  };

  /// Kies een map en voeg 'm als nieuwe lokale verbinding toe. De naam start op
  /// de mapnaam en is daarna in de rij te wijzigen. Een al toegevoegd pad wordt
  /// overgeslagen.
  Future<void> _addLocalConnection() async {
    final locals = _localConnections;
    final result = await FilePicker.getDirectoryPath(
      dialogTitle: context.l10n.d('Map kiezen'),
      initialDirectory: locals.isEmpty ? null : locals.last.path,
    );
    if (!mounted || result == null) return;
    if (locals.any((c) => c.path == result)) return;
    setState(() {
      _connections.add(
        LocalConnection(
          id: StorageConnection.newId(),
          name: p.basename(result),
          path: result,
        ),
      );
    });
  }

  /// Voeg een lege netwerkverbinding toe en klap hem meteen open — er valt
  /// niets te zien tot de gebruiker hem invult, dus dichtgeklapt toevoegen zou
  /// als een mislukking lezen.
  void _addNetworkConnection(StorageConnectionKind kind) {
    final id = StorageConnection.newId();
    final connection = switch (kind) {
      StorageConnectionKind.webdav => WebdavConnection(
        id: id,
        name: '',
        server: const WebdavServer(baseUrl: '', username: ''),
      ),
      StorageConnectionKind.s3 => S3Connection(
        id: id,
        name: '',
        bucket: const S3Bucket(endpoint: '', bucket: ''),
      ),
      StorageConnectionKind.git => GitConnection(
        id: id,
        name: '',
        repo: const GitRepoConfig(baseUrl: '', owner: '', repo: ''),
      ),
      StorageConnectionKind.local => throw ArgumentError(
        'lokale verbindingen lopen via _addLocalConnection',
      ),
    };
    _adoptConnectionForm(connection);
    setState(() {
      _connections.add(connection);
      _expandedConnectionId = id;
    });
  }

  /// Verbindingen waarvan de gebruiker heeft bevestigd dat hun wachtende,
  /// nog niet gepushte werk verloren mag gaan. Zie [_removeConnection].
  final Set<String> _discardPendingWorkFor = {};

  /// Verwijder een verbinding uit de bewerkkopie. Het formulier blijft staan:
  /// pas bij Opslaan telt de lijst, en tot dan mag Annuleren alles terugdraaien.
  ///
  /// Bij een git-verbinding wordt bij Opslaan ook de werkkopie op schijf
  /// gewist — de hele repo-inhoud mét historie. Wacht daar nog werk in dat
  /// nergens anders bestaat, dan is dat dataverlies, en dan hoort de gebruiker
  /// éérst te horen wát hij kwijtraakt.
  Future<void> _removeConnection(String id) async {
    final connection = _connections.where((c) => c.id == id).firstOrNull;
    if (connection is GitConnection) {
      final pending = await DiskTraces().pendingCommitsFor(
        connection.repo.storageSlug,
      );
      if (!mounted) return;
      if (pending.isNotEmpty) {
        final go = await _confirmDiscardPendingWork(connection, pending);
        if (!go || !mounted) return;
        _discardPendingWorkFor.add(id);
      }
    }
    setState(() {
      _connections.removeWhere((c) => c.id == id);
      if (_expandedConnectionId == id) _expandedConnectionId = null;
    });
  }

  /// Vraagt of het wachtende werk van [connection] weg mag, en noemt het bij
  /// naam: welk deck, op welke tak, met welke boodschap. Een aantal alleen zegt
  /// niets — de gebruiker moet kunnen herkennen of dít het werk is waar hij
  /// gisteren een uur aan zat.
  Future<bool> _confirmDiscardPendingWork(
    GitConnection connection,
    List<PendingCommit> pending,
  ) async {
    final l10n = context.l10n;
    final answer = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.d('Er wacht nog werk dat niet verstuurd is')),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l10n.d(
                'Deze git-verbinding heeft wijzigingen die nog niet naar de server zijn gestuurd. Verwijder je de verbinding, dan gaat ook de werkkopie op dit apparaat weg — en bestaat dit werk nergens meer.',
              ),
              style: const TextStyle(fontSize: 13),
            ),
            const SizedBox(height: 10),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 200),
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (final commit in pending)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 3),
                        child: Text(
                          '•  ${commit.deckDir}  ·  ${commit.branch}  ·  ${commit.message}',
                          style: TextStyle(
                            fontSize: 12.5,
                            color: AppTheme.slate600,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(l10n.d('Verbinding behouden')),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(l10n.d('Toch verwijderen')),
          ),
        ],
      ),
    );
    return answer ?? false;
  }

  /// Hernoem een verbinding in de bewerkkopie.
  ///
  /// Bewust zonder setState: dit hangt aan de `onChanged` van het naamveld, en
  /// een rebuild tijdens het typen zet de cursor terug naar het begin. Er is
  /// ook niets te herbouwen — het veld toont zijn eigen invoer al.
  void _renameConnection(StorageConnection connection, String name) {
    _connections = [
      for (final c in _connections)
        if (c.id != connection.id)
          c
        else
          switch (c) {
            LocalConnection() => c.copyWith(name: name),
            WebdavConnection() => c.copyWith(name: name),
            S3Connection() => c.copyWith(name: name),
            GitConnection() => c.copyWith(name: name),
          },
    ];
  }

  Future<void> _pickExportDirectory() async {
    final locals = _localConnections;
    final result = await FilePicker.getDirectoryPath(
      dialogTitle: context.l10n.d('Map voor exports'),
      initialDirectory:
          _exportDirectory ?? (locals.isEmpty ? null : locals.first.path),
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
    notifier.setConnections(
      _normalizedConnections(),
      discardPendingWorkFor: _discardPendingWorkFor,
    );
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

    // De configuraties zijn hierboven als één lijst weggeschreven; hier blijven
    // alleen de geheimen over, die per verbinding hun eigen keychain-entry
    // hebben.
    for (final form in _gitForms.values) {
      form.saveSecret(notifier);
    }
    for (final form in _webdavForms.values) {
      form.saveSecret(notifier);
    }
    for (final form in _s3Forms.values) {
      form.saveSecret(notifier);
    }

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
}
