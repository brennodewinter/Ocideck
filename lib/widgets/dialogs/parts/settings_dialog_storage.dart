// Part of the settings_dialog library — see ../settings_dialog.dart.
//
// Opslag op één plek. Hiervóór lag het verspreid: de bibliotheken en de
// exportmap stonden onder "Algemeen", Nextcloud had een eigen tabblad en git
// ook. Wie wilde weten waar zijn presentaties konden staan, moest dat op drie
// plaatsen bij elkaar zoeken — en elke nieuwe opslagwijze zou er een vierde
// tabblad bij hebben gezet.
//
// De ordening hier volgt de vraag die de gebruiker stelt, niet de techniek die
// erachter zit. Eerst *waar* zijn werk staat (bibliotheken, exportmap), daarna
// *langs welke weg* het daar komt (schijf, Nextcloud, git). Die tweede lijst is
// [StorageModality]: één regel per opslagwijze, uitklapbaar naar zijn eigen
// instellingen. Een vierde wijze is een waarde erbij in die enum plus een tak
// in [_modalityPanel] — geen tabblad, geen hernummering.
part of '../settings_dialog.dart';

/// Een manier waarop presentaties bij de gebruiker terechtkomen.
///
/// [disk] heeft geen eigen instellingen: die wordt bestuurd door de
/// bibliotheken bovenaan hetzelfde tabblad. Hij staat er tóch in, omdat een
/// lijst die alleen de netwerkbronnen toont de indruk wekt dat opslag op de
/// eigen schijf iets aparts is in plaats van de standaard.
enum StorageModality {
  disk(Icons.folder_outlined),
  nextcloud(Icons.cloud_outlined, sectionSource: 'Nextcloud-bron (WebDAV)'),
  git(Icons.account_tree_outlined, sectionSource: 'Git-repository');

  const StorageModality(this.icon, {this.sectionSource});

  final IconData icon;

  /// De Nederlandse bronstring van de sectiekop in het uitklappaneel — het
  /// anker waar een zoektreffer naartoe springt. `null` als de wijze geen eigen
  /// paneel heeft. Bewust de bronstring en niet de vertaalde tekst, zodat het
  /// koppelen in elke taal hetzelfde werkt.
  final String? sectionSource;

  String label(AppLocalizations l10n) => switch (this) {
    StorageModality.disk => l10n.d('Deze computer'),
    StorageModality.nextcloud => l10n.d('Nextcloud'),
    StorageModality.git => l10n.d('Git-repository'),
  };

  String summary(AppLocalizations l10n) => switch (this) {
    StorageModality.disk => l10n.d(
      'Presentaties in de mappen hierboven, op de schijf van deze computer.',
    ),
    StorageModality.nextcloud => l10n.d(
      'Open en bewaar presentaties in een map op je Nextcloud.',
    ),
    StorageModality.git => l10n.d(
      'Open presentaties uit een git-repository; elke opgeslagen versie blijft bewaard.',
    ),
  };
}

extension _SettingsStorageTab on _SettingsDialogState {
  Widget _storageTab() {
    final l10n = context.l10n;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Standaard- en exportmap sturen het bestandssysteem aan. Op web
        // bestaat dat niet (decks openen via bytes, export = browser-download),
        // dus dan is de mapkeuze zinloos — verberg beide secties.
        if (supportsLocalProjectFolders) ...[
          ..._librariesSection(l10n),
          const SizedBox(height: 16),
          ..._exportFolderSection(l10n),
          const SizedBox(height: 20),
        ],
        ..._modalitiesSection(l10n),
      ],
    );
  }

  List<Widget> _librariesSection(AppLocalizations l10n) => [
    _sectionTitle(l10n.d('Bibliotheken')),
    Text(
      l10n.d(
        'Mappen waarin je presentaties bewaart en doorzoekt. Geef ze een eigen naam om ze uit elkaar te houden. Alle bibliotheken worden doorzocht bij openen en in de afbeeldingenbibliotheek.',
      ),
      style: TextStyle(fontSize: 11, color: AppTheme.slate400),
    ),
    const SizedBox(height: 10),
    if (_libraries.isEmpty)
      _pathBox(l10n.d('Nog geen bibliotheek — voeg een map toe.'), muted: true)
    else
      for (var i = 0; i < _libraries.length; i++) _libraryRow(i),
    const SizedBox(height: 10),
    Align(
      alignment: Alignment.centerLeft,
      child: ElevatedButton.icon(
        onPressed: _addLibrary,
        icon: const Icon(Icons.create_new_folder_outlined, size: 16),
        label: Text(l10n.d('Map toevoegen')),
      ),
    ),
  ];

  List<Widget> _exportFolderSection(AppLocalizations l10n) => [
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
            onPressed: () => _rebuild(() => _exportDirectory = null),
            icon: const Icon(Icons.clear, size: 18),
            tooltip: l10n.t('removeExportFolder'),
          ),
      ],
    ),
    Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Text(
        l10n.t('exportFolderHelp'),
        style: TextStyle(fontSize: 11, color: AppTheme.slate400),
      ),
    ),
  ];

  /// De opslagwijzen. Op web valt alles behalve de netwerkbronnen weg, en zijn
  /// die er ook niet, dan heeft de hele sectie geen inhoud meer.
  List<Widget> _modalitiesSection(AppLocalizations l10n) {
    final modalities = [
      if (supportsLocalProjectFolders) StorageModality.disk,
      if (supportsNetworkDeckSources) ...[
        StorageModality.nextcloud,
        StorageModality.git,
      ],
    ];
    if (modalities.isEmpty) return const [];

    return [
      _sectionTitle(l10n.d('Opslagwijzen')),
      Text(
        l10n.d(
          'Langs welke wegen je presentaties kunt openen en bewaren. Klik een wijze open om hem in te stellen.',
        ),
        style: TextStyle(fontSize: 11, color: AppTheme.slate400),
      ),
      const SizedBox(height: 10),
      for (final modality in modalities) _modalityRow(modality, l10n),
    ];
  }

  /// Eén regel in de lijst: pictogram, naam, de stand van zaken in één zin, en
  /// — als de wijze iets in te stellen heeft — een uitklappaneel eronder.
  Widget _modalityRow(StorageModality modality, AppLocalizations l10n) {
    final expanded = _expandedModality == modality;
    final panel = _modalityPanel(modality);
    final status = _modalityStatus(modality, l10n);

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Container(
        decoration: BoxDecoration(
          border: Border.all(
            color: expanded ? AppTheme.blue400 : AppTheme.iceBlue,
          ),
          borderRadius: BorderRadius.circular(10),
          color: Colors.white,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Material(
              color: Colors.transparent,
              child: InkWell(
                borderRadius: BorderRadius.circular(10),
                // Zonder paneel valt er niets uit te klappen; de regel blijft
                // dan een mededeling in plaats van een knop.
                onTap: panel == null
                    ? null
                    : () => _rebuild(
                        () => _expandedModality = expanded ? null : modality,
                      ),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 11, 12, 11),
                  child: Row(
                    children: [
                      Icon(modality.icon, size: 19, color: AppTheme.slate500),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              modality.label(l10n),
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              status.text,
                              style: TextStyle(
                                fontSize: 11,
                                color: status.configured
                                    ? AppTheme.teal
                                    : AppTheme.slate400,
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (panel != null)
                        Icon(
                          expanded ? Icons.expand_less : Icons.expand_more,
                          size: 20,
                          color: AppTheme.slate400,
                        ),
                    ],
                  ),
                ),
              ),
            ),
            if (expanded && panel != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
                child: panel,
              ),
          ],
        ),
      ),
    );
  }

  /// De instellingen van één opslagwijze. `null` betekent: niets in te stellen.
  Widget? _modalityPanel(StorageModality modality) => switch (modality) {
    StorageModality.disk => null,
    StorageModality.nextcloud => _webdavPanel(),
    StorageModality.git => _gitPanel(),
  };

  /// De stand van zaken in één zin, plus of de wijze bruikbaar is — dat tweede
  /// bepaalt of de regel groen leest of grijs.
  ({String text, bool configured}) _modalityStatus(
    StorageModality modality,
    AppLocalizations l10n,
  ) {
    switch (modality) {
      case StorageModality.disk:
        final count = _libraries.length;
        if (count == 0) {
          return (
            text: l10n.d('Nog geen bibliotheek ingesteld'),
            configured: false,
          );
        }
        // "Bibliotheken: 2" in plaats van "2 bibliotheken": hergebruikt de kop
        // die er al staat en ontloopt daarmee het meervoud, dat in dertig talen
        // dertig keer anders werkt.
        return (text: '${l10n.d('Bibliotheken')}: $count', configured: true);
      case StorageModality.nextcloud:
        final host = _hostOf(_webdavUrl.text);
        if (host == null || _webdavUser.text.trim().isEmpty) {
          return (text: l10n.d('Niet ingesteld'), configured: false);
        }
        return (text: '${l10n.d('Ingesteld')} · $host', configured: true);
      case StorageModality.git:
        final owner = _gitOwner.text.trim();
        final repo = _gitRepo.text.trim();
        if (_hostOf(_gitUrl.text) == null || owner.isEmpty || repo.isEmpty) {
          return (text: l10n.d('Niet ingesteld'), configured: false);
        }
        return (
          text: '${l10n.d('Ingesteld')} · $owner/$repo',
          configured: true,
        );
    }
  }

  /// De hostnaam uit een ingetypte URL, of `null` als er nog niets bruikbaars
  /// staat. Vult een ontbrekend schema aan, want "cloud.voorbeeld.nl" zonder
  /// `https://` is wat mensen intypen.
  String? _hostOf(String raw) {
    var url = raw.trim();
    if (url.isEmpty) return null;
    if (!url.contains('://')) url = 'https://$url';
    final host = Uri.tryParse(url)?.host;
    return (host == null || host.isEmpty) ? null : host;
  }
}
