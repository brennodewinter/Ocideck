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
  List<PopupMenuEntry<String>> _moreMenuItems(AppLocalizations l10n) {
    // De git-blokken hebben pas betekenis als er een repository is ingesteld.
    // Zonder config kan geen van deze handelingen slagen, dus tonen we ze niet:
    // een item dat altijd op dezelfde snackbar uitkomt is geen menu-item maar
    // ruis (zelfde lijn als de secmodule: weglaten, niet grijs maken).
    final hasGitRepo = ref.read(settingsProvider).gitRepo != null;
    final gitOrigin = ref.read(tabsProvider).current?.gitOrigin;

    return [
      _menuItem(
        'command_palette',
        Icons.keyboard_command_key,
        '${l10n.d('Commandopalet')}  (Ctrl/Cmd+K)',
      ),
      const PopupMenuDivider(),
      // ── Openen ────────────────────────────────────────────────────
      // "Nieuwe presentatie" staat hier bewust niet: de tabbalk-"+" en het
      // welkomscherm regelen dat al, en het commandopalet houdt de variant met
      // dialoog-in-nieuw-tabblad bereikbaar. Drie keer hetzelfde in beeld maakt
      // het menu alleen langer.
      _menuItem('open', Icons.folder_open_outlined, l10n.t('openEllipsis')),
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
      // ── Git ───────────────────────────────────────────────────────
      // Bewust buiten de supportsNetworkDeckSources-poort: die staat op web uit
      // omdat de WebDAV-client dart:io-pinning nodig heeft. Git praat https+JSON
      // dat de browser-sandbox al inperkt, dus dit werkt daar wél (§4.4).
      if (hasGitRepo) ...[
        const PopupMenuDivider(),
        _menuItem('open_git', Icons.hub_outlined, l10n.d('Openen uit git…')),
        _menuItem(
          'save_git',
          Icons.cloud_upload_outlined,
          l10n.d('Opslaan naar git…'),
        ),
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
        // Echte historie bestaat alleen op het native plane (§8.1): het item
        // verschijnt zodra dit deck uit git is geopend én er een lokale clone is.
        if (gitOrigin != null &&
            ref.read(nativeGitMirrorProvider).asData?.value != null)
          _menuItem('history_git', Icons.history, l10n.d('Git-geschiedenis…')),
        // Versies (release-tags) werken op elk plane, ook op web: het is een
        // forge-listing. Verschijnt zodra dit deck uit git is geopend.
        if (gitOrigin != null)
          _menuItem('versions_git', Icons.label_outline, l10n.d('Versies…')),
        // Uitbrengen ter review + concept mergen kunnen pas als er een
        // concept-ronde loopt: het tabblad staat dan op een werkbranch, niet op
        // de standaardbranch (D3).
        if (gitOrigin != null &&
            gitOrigin.branch !=
                (ref.read(settingsProvider).gitRepo?.defaultBranch ??
                    'main')) ...[
          _menuItem(
            'review_git',
            Icons.rate_review_outlined,
            l10n.d('Uitbrengen ter review…'),
          ),
          _menuItem(
            'merge_git',
            Icons.merge_outlined,
            l10n.d('Concept mergen…'),
          ),
        ],
        // Een versie vastleggen (release-tag op main) kan voor elk uit-git-
        // geopend deck; bedoeld ná het mergen.
        if (gitOrigin != null)
          _menuItem(
            'tag_git',
            Icons.bookmark_add_outlined,
            l10n.d('Versie vastleggen…'),
          ),
      ],
      // ── Nextcloud ─────────────────────────────────────────────────
      if (supportsNetworkDeckSources) ...[
        const PopupMenuDivider(),
        _menuItem(
          'open_nextcloud',
          Icons.cloud_download_outlined,
          l10n.d('Openen vanaf Nextcloud'),
        ),
        _menuItem(
          'save_nextcloud',
          Icons.cloud_upload_outlined,
          l10n.d('Opslaan naar Nextcloud'),
        ),
      ],
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
      // omdat het er ooit tussen is geschoven.
      _menuItem(
        'tools_appendix',
        Icons.handyman_outlined,
        l10n.d('Bijlage hulpmiddelen invoegen…'),
      ),
      const PopupMenuDivider(),
      // Documentintegriteit (§8 A1): afronden is bewust eenrichtingsverkeer, dus
      // het item verdwijnt zodra het deck verzegeld is.
      if (ref.read(deckProvider).deck?.finalized != true)
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
