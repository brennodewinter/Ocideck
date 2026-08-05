// Part of the app_shell library — see app_shell.dart.
// The "more" (…) popup-menu builder, split out of app_shell_main_layout.dart to
// keep that file under the size ratchet. An extension on _MainLayoutState in the
// same library: it reaches `ref`, `_menuItem` and the providers verbatim.
//
// Volgorde is bewust: het menu loopt van "waar haal ik een deck vandaan" via
// "waar zet ik het neer" naar "wat doe ik erin", en sluit af met afronden en
// instellingen. Elk blok staat tussen scheidingslijnen zodat de gebruiker niet
// hoeft te zoeken welk item bij welke handeling hoort.
part of 'app_shell.dart';

extension _MainLayoutMenu on _MainLayoutState {
  /// Of er iets te openen of op te slaan valt buiten de lokale schijf. Zonder
  /// verbinding zouden beide items altijd op dezelfde "stel eerst iets in"-
  /// melding uitkomen, en dat is geen menu-item maar ruis.
  bool get _hasRemoteConnections => _remoteConnections(ref).isNotEmpty;

  /// De git-blokken van het menu.
  ///
  /// Eigen methode omdat dit één samenhangend verhaal is: wat er te zien is
  /// hangt van twee dingen tegelijk af — of er überhaupt een repository is
  /// ingesteld, en of het geopende deck uit git komt. Die twee door de rest van
  /// het menu heen vlechten leest slechter dan ze bij elkaar te zetten.
  ///
  /// De git-blokken hebben pas betekenis als er een repository is ingesteld.
  /// Zonder verbinding kan geen van deze handelingen slagen, dus tonen we ze
  /// niet: een item dat altijd op dezelfde snackbar uitkomt is geen menu-item
  /// maar ruis (zelfde lijn als de informatieveiligheidsmodule: weglaten, niet
  /// grijs maken).
  ///
  /// Bewust buiten de supportsNetworkDeckSources-poort: die staat op web uit
  /// omdat de WebDAV-client dart:io-pinning nodig heeft. Git praat https+JSON
  /// dat de browser-sandbox al inperkt, dus dit werkt daar wél (§4.4).
  List<PopupMenuEntry<String>> _gitMenuItems(AppLocalizations l10n) {
    final hasGitRepo = ref.read(gitConnectionsProvider).isNotEmpty;
    if (!hasGitRepo) return const [];
    final gitOrigin = ref.read(tabsProvider).current?.gitOrigin;
    // Echte historie bestaat alleen op het native plane (§8.1): alleen als er
    // van dít deck een lokale clone is.
    final hasLocalClone =
        gitOrigin != null &&
        ref
                .read(nativeGitMirrorProvider(gitOrigin.connectionId))
                .asData
                ?.value !=
            null;

    return [
      const PopupMenuDivider(),
      // Openen en opslaan staan hier niet meer: die lopen via de gedeelde
      // "Openen uit…" en "Opslaan naar…" hierboven, samen met WebDAV en S3.
      // Wat hier overblijft is wat git écht toevoegt en geen andere opslag kan.
      _menuItem('sync_git', Icons.sync, l10n.d('Nu synchroniseren')),
      _menuItem(
        'search_git',
        Icons.manage_search,
        l10n.d('Zoeken in alle decks…'),
      ),
      _menuItem(
        'assets_git',
        Icons.photo_library_outlined,
        l10n.d('Afbeeldingen in de repository…'),
      ),
      if (ref.watch(assetRightsModuleEnabledProvider))
        _menuItem(
          'rights_git',
          Icons.copyright_outlined,
          l10n.d('Afbeeldingsrechten controleren…'),
        ),
      if (hasLocalClone)
        _menuItem('history_git', Icons.history, l10n.d('Git-geschiedenis…')),
      // Versies (release-tags) werken op elk plane, ook op web: het is een
      // forge-listing. Verschijnt zodra dit deck uit git is geopend.
      if (gitOrigin != null)
        _menuItem('versions_git', Icons.label_outline, l10n.d('Versies…')),
      // Uitbrengen ter review + concept mergen kunnen pas als er een
      // concept-ronde loopt: het tabblad staat dan op een werkbranch, niet op
      // de standaardbranch (D3). De standaardbranch van de repo waar dít deck
      // vandaan komt, niet die van de bovenste verbinding — met twee repo's
      // zijn dat verschillende.
      if (gitOrigin != null &&
          gitOrigin.branch != gitOrigin.config.defaultBranch) ...[
        _menuItem(
          'review_git',
          Icons.rate_review_outlined,
          l10n.d('Uitbrengen ter review…'),
        ),
        _menuItem('merge_git', Icons.merge_outlined, l10n.d('Concept mergen…')),
      ],
      // Een versie vastleggen (release-tag op main) kan voor elk uit-git-
      // geopend deck; bedoeld ná het mergen.
      if (gitOrigin != null)
        _menuItem(
          'tag_git',
          Icons.bookmark_add_outlined,
          l10n.d('Versie vastleggen…'),
        ),
    ];
  }

  List<PopupMenuEntry<String>> _moreMenuItems(AppLocalizations l10n) {
    return [
      _menuItem(
        'command_palette',
        Icons.keyboard_command_key,
        labelWithShortcut(l10n, 'Commandopalet', 'K'),
      ),
      const PopupMenuDivider(),
      // ── Openen ────────────────────────────────────────────────────
      // "Nieuwe presentatie" staat hier bewust niet: de tabbalk-"+" en het
      // welkomscherm regelen dat al, en het commandopalet houdt de variant met
      // dialoog-in-nieuw-tabblad bereikbaar. Drie keer hetzelfde in beeld maakt
      // het menu alleen langer.
      _menuItem('open', Icons.folder_open_outlined, l10n.t('openEllipsis')),
      // Eén ingang per richting, ongeacht de soort opslag. De vraag is "waar
      // staat mijn presentatie", niet "welk protocol draait daar" — en met
      // precies één verbinding stelt de kiezer de vraag helemaal niet.
      // Opslaan zonder meer volgt de herkomst; dit is het pad om iets bewust
      // ergens ánders neer te zetten.
      if (_hasRemoteConnections) ...[
        _menuItem(
          'open_remote',
          Icons.cloud_download_outlined,
          l10n.d('Openen uit…'),
        ),
        _menuItem(
          'save_remote',
          Icons.cloud_upload_outlined,
          l10n.d('Opslaan naar…'),
        ),
      ],
      const PopupMenuDivider(),
      // ── Pakket en import ──────────────────────────────────────────
      // Pakketten en URL-import werken overal: op web volledig in het
      // geheugen (pakket als download, import via de browser met dezelfde
      // security-gate). Alleen Nextcloud is op web bewust uit (zie
      // platform_features.dart).
      _menuItem(
        'export_package',
        Icons.inventory_2_outlined,
        l10n.t('exportPackage'),
      ),
      _menuItem(
        'import_package',
        Icons.unarchive_outlined,
        l10n.t('importPackage'),
      ),
      _menuItem('import_url', Icons.link, l10n.t('importUrl')),
      // OpenKAT: map-import én live server. Op web weglaten (geen mapkiezer /
      // sleutelbos). Reveal = aan óf inhoud (map of installatie).
      if (supportsLocalProjectFolders &&
          ref.watch(openKatIntegrationRevealProvider)) ...[
        _menuItem(
          'import_openkat',
          Icons.radar_outlined,
          openKatLabel(l10n, updating: hasActiveOpenKatReport(ref)),
        ),
        _menuItem(
          'openkat_add_server',
          Icons.add_link,
          l10n.d('OpenKAT-server toevoegen…'),
        ),
        _menuItem(
          'openkat_server_report',
          Icons.cloud_download_outlined,
          l10n.d('Rapportage van OpenKAT-server…'),
        ),
      ],
      // Presentatie-import (PowerPoint/Keynote/Impress): werkt op bytes, dus ook op web.
      if (ref.watch(importModuleRevealProvider))
        _menuItem(
          'import_presentation',
          Icons.slideshow_outlined,
          presentationImportLabel(l10n),
        ),
      ..._gitMenuItems(l10n),
      const PopupMenuDivider(),
      // ── Bewerken in dit deck ──────────────────────────────────────
      _menuItem('find', Icons.find_replace, l10n.t('findReplace')),
      _menuItem(
        'clear_checklists',
        Icons.check_box_outline_blank,
        l10n.d('Alle checkboxen legen'),
      ),
      _menuItem(
        'full_preview',
        Icons.preview_outlined,
        l10n.t('fullDeckPreview'),
      ),
      // Hoort bij "invoegen in dit deck", niet bij git: het stond daar alleen
      // omdat het er ooit tussen is geschoven. De bijlage is MIAUW-vastlegging
      // (EIS 4.8.2), dus alleen met de informatieveiligheidsmodule aan — zonder
      // die module is er ook nooit een ingevulde hulpmiddelenlijst en liep dit
      // item altijd op de "niets in te voegen"-melding vast.
      if (ref.read(infoSafetyRevealProvider))
        _menuItem(
          'tools_appendix',
          Icons.handyman_outlined,
          l10n.d('Bijlage hulpmiddelen invoegen…'),
        ),
      const PopupMenuDivider(),
      // Documentintegriteit (§8 A1): afronden is bewust eenrichtingsverkeer, dus
      // het item verdwijnt zodra het deck verzegeld is. Verzegelen is een
      // informatieveiligheidsfunctie — het hoort achter dezelfde module-gate als
      // het RFC3161-tijdstempel dat er in het commandopalet op volgt, anders is
      // het halve verzegelspoor bereikbaar met de module uit.
      if (ref.read(infoSafetyRevealProvider) &&
          ref.read(deckProvider).deck?.finalized != true)
        _menuItem(
          'finalize',
          Icons.verified_user_outlined,
          l10n.d('Afronden & verzegelen'),
        ),
      // Style profiles are chosen via the "STIJL" pulldown in the
      // editor toolbar; no need to duplicate them here.
      _menuItem('settings', Icons.settings_outlined, l10n.t('settings')),
    ];
  }
}
