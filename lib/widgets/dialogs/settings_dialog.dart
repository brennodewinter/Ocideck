import 'dart:convert';
import 'dart:math' as math;
import 'package:file_picker/file_picker.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/deck.dart';
import '../../models/markdown_validation.dart';
import '../../models/matrix_settings.dart';
import '../../models/page_size.dart';
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
import '../../services/libreplan/libreplan_client.dart';
import '../../services/secret_store.dart';
import '../../services/disk_traces.dart';
import '../../services/export_metadata.dart';
import '../../services/file_service.dart';
import '../../services/git/outbox.dart';
import '../../services/recovery_service.dart';
import '../../services/classification_enforcement_policy.dart';
import '../../utils/net_guard.dart';
import 'certificate_trust_dialog.dart';
import '../../models/local_cve_status.dart';
import '../../services/cve/local_cve_database.dart';
import '../../services/info_safety/info_safety_reference_inventory.dart';
import '../../state/local_cve_provider.dart';
import '../../services/slide_quality_analyzer.dart';
import '../../state/deck_provider.dart';
import '../../state/settings_provider.dart';
import '../../state/tabs_provider.dart';
import '../../state/consent_provider.dart';
import '../../state/info_safety_provider.dart';
import '../../state/module_registry.dart';
import '../../state/collaboration_provider.dart';
import '../../state/online_storage_provider.dart';
import '../../state/integration_registry.dart';
import '../../theme/app_theme.dart';
import '../../theme/brand_logo.dart';
import '../../utils/error_snackbar.dart';
import '../../utils/log.dart';
import '../../utils/user_facing_error.dart';
import '../../utils/url_launcher_util.dart';
import '../../l10n/app_localizations.dart';
import '../../l10n/slide_quality_localization.dart';
import '../../models/privacy_disposition.dart';
import '../editors/advanced_section.dart';
import '../document_page_chrome.dart';
import '../language_flag.dart';
import '../privacy_badge.dart';
import '../privacy_statement_content.dart';
import '../reader/document_reader_screen.dart';
import '../reader/document_markdown_view.dart';
import '../reader/documentation_search_tab.dart';
import '../slides/image_zoom_dialog.dart';
import 'hex_color_dialog.dart';
import 'settings/ai_form.dart';
import 'settings/ai_module_card.dart';
import 'settings/collaboration_module_card.dart';
import 'settings/online_storage_module_card.dart';
import 'settings/integrations_panel.dart';
import 'settings/import_module_card.dart';
import 'settings/procesverbetering_module_card.dart';
import 'settings/asset_rights_module_card.dart';
import 'settings/video_calls_module_card.dart';
import 'settings/managementsysteem_module_card.dart';
import 'settings/libreplan_module_card.dart';
import 'libreplan_import_dialog.dart';
import 'settings/appearance_legibility.dart';
import 'settings/git_form.dart';
import 'settings/git_panel.dart';
import 'settings/matrix_form.dart';
import 'settings/matrix_panel.dart';
import 'settings/s3_form.dart';
import 'settings/s3_panel.dart';
import 'settings/settings_section_title.dart';
import 'settings/settings_text_field.dart';
import 'settings/webdav_form.dart';
import 'settings/webdav_panel.dart';
import 'settings/set_aside_findings.dart';
import 'settings/disabled_privacy_rules.dart';

part 'parts/settings_dialog_sections.dart';
part 'parts/settings_dialog_chrome.dart';
part 'parts/settings_dialog_general.dart';
part 'parts/settings_dialog_storage.dart';
part 'parts/settings_dialog_collaboration.dart';
part 'parts/settings_dialog_presentation.dart';
part 'parts/settings_dialog_style_builder.dart';
part 'parts/settings_dialog_style_preview.dart';
part 'parts/settings_dialog_appearance.dart';
part 'parts/settings_dialog_colors.dart';
part 'parts/settings_dialog_table_style.dart';
part 'parts/settings_dialog_profile.dart';
part 'parts/settings_dialog_privacy.dart';
part 'parts/settings_dialog_security.dart';
part 'parts/settings_dialog_ai.dart';
part 'parts/settings_dialog_libreplan.dart';
part 'parts/settings_dialog_docs.dart';
part 'parts/settings_dialog_modules.dart';
part 'parts/settings_dialog_checklists.dart';
part 'parts/settings_dialog_about.dart';
part 'parts/settings_dialog_standards.dart';
part 'parts/settings_dialog_search.dart';
part 'parts/settings_dialog_search_index.dart';
part 'parts/settings_dialog_cve_local.dart';

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

  /// Het app-globale Matrix-samenwerkaccount. Eén formulier, geen lijst: het
  /// account is app-globaal (§8), niet per verbinding. Zelfde contract als de
  /// andere formulieren — geheim uit de sleutelhanger na, weggeschreven bij
  /// Opslaan.
  final MatrixForm _matrixForm = MatrixForm();

  late String? _exportDirectory;
  late ThemeProfile _themeProfile;
  late AppAppearanceProfile _appearanceProfile;
  late String _originalAppearanceName;

  /// De werkkopie van de app-themalijst (#760). Aanmaken en verwijderen
  /// bewerken déze lijst en landen pas bij Opslaan — hetzelfde contract als de
  /// acht kleurvelden en de opslagverbindingen (`_connections`), zodat
  /// Annuleren het hele venster terugdraait en niet de helft.
  late List<AppAppearanceProfile> _appearanceProfiles;

  /// Het thema dat actief was toen het venster openging: de terugval wanneer
  /// het geselecteerde thema verwijderd wordt. Wie een kopie van Donker
  /// weggooit hoort weer in Donker te staan, niet in een hardgecodeerd licht
  /// thema (#760, bevinding 3).
  late String _appearanceOpenName;
  late TextEditingController _appearanceName;

  /// The cockpit colour scheme currently being edited, plus its saved name as a
  /// stable identity for rename/save.
  late CockpitColorScheme _cockpitScheme;
  late String _originalCockpitName;
  late TextEditingController _cockpitName;
  late CockpitVisualStyle _cockpitVisualStyle;

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

  /// LibrePlan-connector (optioneel, standaard uit): formulierstand.
  bool _libreplanEnabled = false;
  late final TextEditingController _libreplanBaseUrl;
  late final TextEditingController _libreplanUsername;
  final TextEditingController _libreplanPassword = TextEditingController();
  bool _libreplanTrustedInternal = false;
  bool? _libreplanTestOk;
  String? _libreplanTestMessage;
  bool _libreplanTesting = false;

  /// Whether the user changed the active profile in this session. Used to
  /// decide whether to apply the profile to the currently open presentation.
  bool _profileTouched = false;

  bool _stylePreviewShowsContent = true;
  _StyleSurface _styleSurface = _StyleSurface.general;

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
    // Profiel van de open presentatie (deckNotifierOrNull: documenttab = geen).
    final deckProfile = ref
        .read(tabsProvider)
        .current
        ?.deckNotifierOrNull
        ?.currentState
        .deck
        ?.themeProfile;
    _themeProfile = deckProfile ?? settings.themeProfile;
    _appearanceProfile = settings.appAppearanceProfile;
    _originalAppearanceName = _appearanceProfile.name;
    _appearanceName = TextEditingController(text: _appearanceProfile.name);
    _appearanceProfiles = [...settings.appAppearanceProfiles];
    _appearanceOpenName = _appearanceProfile.name;
    _cockpitScheme = settings.cockpitColorScheme;
    _originalCockpitName = _cockpitScheme.name;
    _cockpitName = TextEditingController(text: _cockpitScheme.name);
    _cockpitVisualStyle = settings.cockpitVisualStyle;
    _originalName = _themeProfile.name;
    _profileName = TextEditingController(text: _themeProfile.name);
    _logoSize = TextEditingController(text: _themeProfile.logoSize.toString());
    _footerText = TextEditingController(text: _themeProfile.footerText);
    _closingSlideMarkdown = TextEditingController(
      text: _themeProfile.closingSlideMarkdown,
    );
    _initAiFields(settings.aiSettings);
    _initLibreplanFields(settings.libreplanSettings);
    _adoptMatrixForm(settings.matrixAccount);
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
    _matrixForm.dispose();
    _ai.dispose();
    _libreplanBaseUrl.dispose();
    _libreplanUsername.dispose();
    _libreplanPassword.dispose();
    super.dispose();
  }

  /// Trigger a rebuild from the extension methods in the `parts/` files. They
  /// cannot call the `@protected` [setState] directly (it is only callable from
  /// instance members of a State subclass), so they route through this wrapper.
  void _rebuild(VoidCallback fn) => setState(fn);

  List<ThemeProfile> get _profiles =>
      _availableStyleProfiles(ref.watch(settingsProvider).themeProfiles);

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
    final result = await _pickDirectoryGated(
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
    final result = await _pickDirectoryGated(
      dialogTitle: context.l10n.d('Map voor exports'),
      initialDirectory:
          _exportDirectory ?? (locals.isEmpty ? null : locals.first.path),
    );
    if (!mounted) return;
    if (result != null) setState(() => _exportDirectory = result);
  }

  Future<void> _pickLogo() async {
    // De knop bestaat op web niet (zie _logoSectionChildren), maar de poort
    // staat hier ook: op web levert pickFiles een blob:-URL in `path`, en die
    // zou als logoPath in het themaprofiel belanden en na herladen nergens meer
    // heen wijzen. Een stille, onherstelbare instelling is erger dan een
    // ontbrekende knop.
    if (!supportsLocalProjectFolders) return;
    final file = await FilePicker.pickFile(
      dialogTitle: context.l10n.d('Logo kiezen'),
      type: FileType.image,
    );
    if (!mounted) return;
    final path = file?.path;
    if (path != null) {
      setState(() {
        _themeProfile = _themeProfile.copyWith(logoPath: path);
        _profileTouched = true;
      });
    }
  }

  Future<void> _pickLogoDark() async {
    if (!supportsLocalProjectFolders) return;
    final file = await FilePicker.pickFile(
      dialogTitle: context.l10n.d('Donker logo kiezen'),
      type: FileType.image,
    );
    if (!mounted) return;
    final path = file?.path;
    if (path != null) {
      setState(() {
        _themeProfile = _themeProfile.copyWith(logoDarkPath: path);
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
    final size = int.tryParse(_logoSize.text)?.clamp(32, 480);
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
    // De hele werkkopie in één keer (#760): aangemaakte en verwijderde
    // thema's landen hier, samen met de lopende bewerking en de selectie.
    _syncAppearanceEdits();
    notifier.setAppAppearanceProfiles(
      _appearanceProfiles,
      selectedName: _appearanceProfile.name,
    );
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
    notifier.setCockpitVisualStyle(_cockpitVisualStyle);

    // Apply the chosen/edited profile to the presentation that is currently
    // open, so the change is visible immediately. Only when the user actually
    // touched the profile in this session (otherwise we would clobber a
    // per-deck profile the user set elsewhere).
    if (_profileTouched) {
      final deckN = ref.read(tabsProvider).current?.deckNotifierOrNull;
      deckN?.updateThemeProfile(profile); // documenttab: geen deck, geen no-op
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

    // LibrePlan-connector: bewaar de schakelaar en de volledige configuratie.
    final lp = ref.read(settingsProvider).libreplanSettings;
    notifier.setLibreplanSettings(
      LibreplanSettings(
        enabled: _libreplanEnabled,
        baseUrl: _libreplanBaseUrl.text.trim(),
        username: _libreplanUsername.text.trim(),
        trustedInternal: _libreplanTrustedInternal,
      ),
    );
    // Wachtwoord in de keychain (gekeyd op base URL + username).
    final lpKey =
        '${_libreplanBaseUrl.text.trim()}::${_libreplanUsername.text.trim()}';
    final lpPass = _libreplanPassword.text;
    if (lpPass.isNotEmpty) {
      notifier.setLibreplanPassword(lpKey, lpPass);
    } else if (lp.hasBackend) {
      notifier.deleteLibreplanPassword(lpKey);
    }

    // Het app-globale Matrix-account: de configuratie via de notifier, het token
    // apart in de sleutelhanger. Leeggemaakt terwijl er een account stond →
    // wissen; onaangeroerd zonder account → niets doen.
    final matrix = _matrixForm.config;
    if (matrix.isConfigured) {
      notifier.setMatrixAccount(matrix);
      _matrixForm.saveSecret(notifier);
    } else if (ref.read(settingsProvider).matrixAccount != null) {
      notifier.setMatrixAccount(null);
    }

    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final profiles = _profiles;
    final screen = MediaQuery.sizeOf(context);
    // Het venster groeit mee met de tekstschaal, want kop, voet en zijbalk doen
    // dat ook: op 200% liep de kolom 65 pixels buiten zijn eigen hoogte en
    // verdween de opslaanknop onder de rand. Begrensd op anderhalf keer en
    // altijd binnen het scherm — een dialoog die groter is dan het scherm
    // ruilt het ene probleem voor het andere.
    final scale = MediaQuery.textScalerOf(context).scale(1).clamp(1.0, 1.5);
    // Op een klein venster (web kent geen minimum vensterbreedte; desktop dwingt
    // 1000x650 af) krimpt de buitenmarge, zodat het dialoog het scherm niet uit
    // groeit. De comfort-ondergrens (640x560) geldt alleen zolang het scherm die
    // ook biedt: `math.min(..., beschikbaar)` maakt de beschikbare ruimte de
    // bovengrens. Een dialoog dat groter is dan het scherm ruilt afknijpen voor
    // overlopen — precies wat op smal web misging, waar de 640-vloer de zijbalk
    // en inhoud in een te krappe Row perste.
    final tight = screen.width < 720 || screen.height < 620;
    final dialogInset = tight
        ? const EdgeInsets.symmetric(horizontal: 12, vertical: 12)
        : const EdgeInsets.symmetric(horizontal: 40, vertical: 28);
    final availableWidth = screen.width - dialogInset.horizontal;
    final availableHeight = screen.height - dialogInset.vertical;
    final dialogWidth = _settingsDialogWidth(
      scale: scale,
      screenWidth: screen.width,
      availableWidth: availableWidth,
      styleBuilder: _selectedTab == SettingsSection.presentation,
    );
    final dialogHeight = math
        .min(
          math.max(560.0, math.min(760.0 * scale, screen.height * 0.86)),
          availableHeight,
        )
        .toDouble();
    // De zijbalk heeft een vaste breedte die met de tekstschaal meegroeit (zie
    // `_sidebarWidth`). Zodra het dialoog te smal wordt om die zijbalk én een
    // bruikbare inhoudskolom naast elkaar te dragen, klapt de navigatie naar een
    // keuzebalk bovenaan en krijgt de inhoud de volle breedte — anders knijpt de
    // zijbalk de tabbladen tot een strook waarin elke rij overloopt.
    final sidebarWidth = _sidebarWidth * scale.clamp(1.0, _sidebarMaxGrowth);

    // Eén ingang per tabblad, in de volgorde van de enum, zodat de IndexedStack
    // hieronder nooit uit de pas kan lopen met de zijbalk.
    final bodies = [
      for (final section in SettingsSection.values)
        _tabBody(switch (section) {
          SettingsSection.general => _generalTab(),
          SettingsSection.storage => _storageTab(),
          SettingsSection.collaboration => _collaborationTab(),
          SettingsSection.appearance => _appearanceTab(),
          SettingsSection.presentation => _presentationStyleTab(profiles),
          SettingsSection.cockpit => _cockpitTab(),
          SettingsSection.privacy => _privacyTab(),
          SettingsSection.security => _securityTab(),
          SettingsSection.ai => _aiTab(),
          SettingsSection.libreplan => _libreplanTab(),
          SettingsSection.checklists => _checklistsTab(),
          SettingsSection.modules => _modulesTab(),
          SettingsSection.integrations => const IntegrationsPanel(),
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
      child: SettingsSectionAnchors(
        keys: _sectionKeys,
        highlighted: _highlightedSection,
        child: Dialog(
          clipBehavior: Clip.antiAlias,
          backgroundColor: Colors.white,
          insetPadding: dialogInset,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
          child: SizedBox(
            width: dialogWidth,
            height: dialogHeight,
            // De rail/smal-keuze op de wérkelijke breedte, niet op
            // MediaQuery: een Dialog knijpt zijn kind terug binnen het scherm,
            // dus de gevraagde `dialogWidth` kan boven de echte ruimte liggen
            // (en in widget-tests wijkt MediaQuery sowieso af van de
            // surface-grootte). De LayoutBuilder leest wat er echt beschikbaar
            // is, zodat de zijbalk precies dan inklapt wanneer hij niet past.
            child: LayoutBuilder(
              builder: (context, constraints) => _buildLayout(
                this,
                l10n,
                useRailLayout:
                    constraints.maxWidth >= sidebarWidth + _minContentWidth,
                // Material (not ColoredBox) so ListTiles inside the tab bodies
                // paint their ink/selected state onto this surface instead of a
                // hidden ancestor behind an opaque box.
                content: Material(
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
                      _footerBar(this, l10n),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
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
                border: Border.all(color: AppTheme.accentFg, width: 2),
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

/// Kies een map — of null wanneer dit platform er geen heeft.
///
/// Buiten de klasse, en niet alleen omdat `_SettingsDialogState` tegen zijn
/// plafond aan zit: de poort hoort één keer te staan in plaats van bij elke
/// kiezer opnieuw. `getDirectoryPath` bestaat op web niet en geeft daar stil
/// null terug, en dan doet de knop niets zonder één woord uitleg — dat was #150
/// en daarna #506. De secties eromheen zijn óók gepoort
/// (settings_dialog_storage.dart); dit is de helft die dit bestand zelf kan
/// bewijzen.
Future<String?> _pickDirectoryGated({
  required String dialogTitle,
  String? initialDirectory,
}) async {
  if (!supportsLocalProjectFolders) return null;
  return FilePicker.getDirectoryPath(
    dialogTitle: dialogTitle,
    initialDirectory: initialDirectory,
  );
}
