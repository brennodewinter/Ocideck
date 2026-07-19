// Part of the settings_dialog library — see ../settings_dialog.dart.
//
// Opslag als één lijst. Hiervóór stonden hier twee lijsten met een verschillend
// idioom: "Bibliotheken" (meerdere, benoemd, toevoegbaar) en daaronder
// "Opslagwijzen" (precies drie regels, waarvan er twee elk één configuratie
// konden dragen). Wie voor twee opdrachtgevers werkte kon lokaal wél twee
// mappen aanhouden, maar niet twee Nextclouds — en moest de vraag "waar staat
// het werk van deze klant?" op twee plekken beantwoorden.
//
// Nu is er één lijst bestandsverbindingen. Lokale mappen, WebDAV-servers,
// S3-buckets en git-repositories staan er door elkaar, in de volgorde die de
// gebruiker zelf sleept. Die volgorde is geen cosmetica: de bovenste bruikbare verbinding van
// een soort is de standaard voor die soort (`AppSettings.primaryOf`), dus
// slepen is hoe je zegt welke server "de" server is.
//
// Nog een soort opslag erbij is een waarde in [StorageConnectionKind] plus een
// tak in [_connectionPanel] — geen tweede lijst, geen tabblad.
part of '../settings_dialog.dart';

/// Presentatie-eigenschappen per soort verbinding: het pictogram in de rij en
/// de teksten in het "toevoegen"-menu. De configuratie zelf zit in het model
/// ([StorageConnection]); dit is puur wat het scherm ervan laat zien.
extension StorageConnectionKindUi on StorageConnectionKind {
  IconData get icon => switch (this) {
    StorageConnectionKind.local => Icons.folder_outlined,
    StorageConnectionKind.webdav => Icons.cloud_outlined,
    StorageConnectionKind.s3 => Icons.inventory_2_outlined,
    StorageConnectionKind.git => Icons.account_tree_outlined,
  };

  String label(AppLocalizations l10n) => switch (this) {
    StorageConnectionKind.local => l10n.d('Map op deze computer'),
    StorageConnectionKind.webdav => l10n.d('WebDAV-server'),
    StorageConnectionKind.s3 => l10n.d('S3-bucket'),
    StorageConnectionKind.git => l10n.d('Git-repository'),
  };

  String summary(AppLocalizations l10n) => switch (this) {
    StorageConnectionKind.local => l10n.d(
      'Een map op de schijf van deze computer.',
    ),
    StorageConnectionKind.webdav => l10n.d(
      'Een map op een WebDAV-server, bijvoorbeeld Nextcloud.',
    ),
    StorageConnectionKind.s3 => l10n.d(
      'Een S3-bucket, bijvoorbeeld AWS S3 of een eigen MinIO-server.',
    ),
    StorageConnectionKind.git => l10n.d(
      'Een git-repository; elke opgeslagen versie blijft bewaard.',
    ),
  };

  /// De Nederlandse bronstring van de sectiekop in het uitklappaneel — het
  /// anker waar een zoektreffer naartoe springt. `null` als de soort geen eigen
  /// paneel heeft. Bewust de bronstring en niet de vertaalde tekst, zodat het
  /// koppelen in elke taal hetzelfde werkt.
  String? get sectionSource => switch (this) {
    StorageConnectionKind.local => null,
    StorageConnectionKind.webdav => 'WebDAV-bron',
    StorageConnectionKind.s3 => 'S3-bucket',
    StorageConnectionKind.git => 'Git-repository',
  };
}

extension _SettingsStorageTab on _SettingsDialogState {
  Widget _storageTab() {
    final l10n = context.l10n;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ..._connectionsSection(l10n),
        // De exportmap stuurt het bestandssysteem aan. Op web bestaat dat niet
        // (export = browser-download), dus dan is de mapkeuze zinloos.
        if (supportsLocalProjectFolders) ...[
          const SizedBox(height: 20),
          ..._exportFolderSection(l10n),
        ],
      ],
    );
  }

  /// De verbindingenlijst. Op web valt de lokale schijf weg en zijn er ook geen
  /// netwerkbronnen; dan heeft de hele sectie geen inhoud.
  List<Widget> _connectionsSection(AppLocalizations l10n) {
    if (!supportsLocalProjectFolders && !supportsNetworkDeckSources) {
      return const [];
    }
    return [
      _sectionTitle(l10n.d('Bestandsverbindingen')),
      Text(
        l10n.d(
          'De plekken waar je presentaties bewaart en doorzoekt — mappen op deze computer, WebDAV-servers en git-repositories door elkaar. Sleep ze in de volgorde die jij wilt: de bovenste van een soort geldt als standaard.',
        ),
        style: TextStyle(fontSize: 11, color: AppTheme.slate400),
      ),
      const SizedBox(height: 10),
      if (_connections.isEmpty)
        _pathBox(
          l10n.d('Nog geen verbinding — voeg er hieronder een toe.'),
          muted: true,
        )
      else
        _connectionList(l10n),
      const SizedBox(height: 10),
      _addConnectionButton(l10n),
    ];
  }

  /// De sleepbare lijst zelf.
  ///
  /// `shrinkWrap` met een uitgeschakelde eigen scroll: het tabblad scrollt al,
  /// en een lijst die zelf óók scrolt levert twee scrollgebieden in elkaar op —
  /// met een muiswiel dat op de verkeerde reageert.
  Widget _connectionList(AppLocalizations l10n) => ReorderableListView.builder(
    shrinkWrap: true,
    physics: const NeverScrollableScrollPhysics(),
    buildDefaultDragHandles: false,
    itemCount: _connections.length,
    // onReorderItem en niet het oudere onReorder: die tweede geeft een newIndex
    // die het gesleepte item nog op zijn oude plek meetelt, en die correctie
    // hier herhalen is precies de fout die je één keer te vaak maakt.
    onReorderItem: (oldIndex, newIndex) => _rebuild(
      () => _connections.insert(newIndex, _connections.removeAt(oldIndex)),
    ),
    itemBuilder: (context, index) =>
        _connectionRow(_connections[index], index, l10n),
  );

  /// Eén regel: sleepgreep, pictogram, naam, de stand van zaken in één zin, een
  /// knop om te verwijderen, en een uitklappaneel eronder.
  Widget _connectionRow(
    StorageConnection connection,
    int index,
    AppLocalizations l10n,
  ) {
    final expanded = _expandedConnectionId == connection.id;
    final panel = _connectionPanel(connection);

    return Padding(
      key: ValueKey(connection.id),
      padding: const EdgeInsets.only(bottom: 8),
      // Material en niet Container: het paneel bevat SwitchListTiles, en die
      // schilderen hun inkt op de dichtstbijzijnde Material-voorouder. Zit daar
      // een gekleurde box tussen, dan verdwijnt de inkt erachter — Flutter
      // struikelt er terecht over.
      child: Material(
        color: Colors.white,
        shape: RoundedRectangleBorder(
          side: BorderSide(
            color: expanded ? AppTheme.blue400 : AppTheme.iceBlue,
          ),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(6, 6, 8, 6),
              child: Row(
                children: [
                  ReorderableDragStartListener(
                    index: index,
                    child: Tooltip(
                      message: l10n.d('Sleep om de volgorde te wijzigen'),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        child: Icon(
                          Icons.drag_indicator,
                          size: 18,
                          color: AppTheme.slate400,
                        ),
                      ),
                    ),
                  ),
                  Icon(
                    connection.kind.icon,
                    size: 19,
                    color: AppTheme.slate500,
                  ),
                  const SizedBox(width: 10),
                  Expanded(child: _connectionNameField(connection, l10n)),
                  const SizedBox(width: 8),
                  _connectionStatusLine(connection, l10n),
                  IconButton(
                    onPressed: () => _removeConnection(connection.id),
                    icon: const Icon(Icons.delete_outline, size: 18),
                    tooltip: l10n.d('Verbinding verwijderen'),
                  ),
                  // Zonder paneel valt er niets uit te klappen; dan blijft de
                  // regel een mededeling in plaats van een knop.
                  if (panel != null)
                    IconButton(
                      onPressed: () => _rebuild(
                        () => _expandedConnectionId = expanded
                            ? null
                            : connection.id,
                      ),
                      icon: Icon(
                        expanded ? Icons.expand_less : Icons.expand_more,
                        size: 20,
                      ),
                      tooltip: expanded
                          ? l10n.d('Instellingen verbergen')
                          : l10n.d('Instellingen tonen'),
                    ),
                ],
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

  /// De naam is direct in de rij te wijzigen: het is het enige veld dat elke
  /// soort verbinding deelt, en het is precies wat je aanpast als je twee
  /// klanten uit elkaar wilt houden.
  Widget _connectionNameField(
    StorageConnection connection,
    AppLocalizations l10n,
  ) => TextFormField(
    key: ValueKey('name-${connection.id}'),
    initialValue: connection.name,
    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
    decoration: InputDecoration(
      isDense: true,
      border: InputBorder.none,
      hintText: connection.fallbackLabel.isEmpty
          ? l10n.d('Naam van deze verbinding')
          : connection.fallbackLabel,
      hintStyle: TextStyle(fontSize: 13, color: AppTheme.slate400),
    ),
    onChanged: (value) => _renameConnection(connection, value),
  );

  /// De instellingen van één verbinding. `null` betekent: niets in te stellen —
  /// een lokale map is met het kiezen van de map al klaar.
  Widget? _connectionPanel(StorageConnection connection) =>
      switch (connection) {
        LocalConnection() => null,
        WebdavConnection() => switch (_webdavForms[connection.id]) {
          final WebdavForm form => _webdavPanel(form),
          _ => null,
        },
        S3Connection() => switch (_s3Forms[connection.id]) {
          final S3Form form => _s3Panel(form),
          _ => null,
        },
        GitConnection() => switch (_gitForms[connection.id]) {
          final GitForm form => _gitPanel(form),
          _ => null,
        },
      };

  /// De statusregel achter de naam, die met het typen meebeweegt.
  ///
  /// De tekst wordt uit de invoervelden afgeleid, en die velden veranderen
  /// zonder dat er iets herbouwt: een TextEditingController laat het venster met
  /// rust. Zonder deze koppeling zou de regel "Niet ingesteld" blijven melden
  /// terwijl je de server er net onder intypt — en juist die regel is de reden
  /// dat de lijst dichtgeklapt bruikbaar is. Alleen de velden die de status
  /// bepalen luisteren mee, en alleen dit regeltje herbouwt: het venster draagt
  /// twaalf tabbladen, die wil je niet per aanslag opnieuw opbouwen.
  Widget _connectionStatusLine(
    StorageConnection connection,
    AppLocalizations l10n,
  ) {
    Widget line(BuildContext _, Widget? _) {
      final status = _connectionStatus(connection, l10n);
      final text = Text(
        status.text,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: 11,
          color: status.configured ? AppTheme.teal : AppTheme.slate400,
        ),
      );
      return ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 220),
        // Een lokale map toont haar mapnaam; het volledige pad zou de rij
        // opeten terwijl juist het einde ervan onderscheidend is. De tooltip
        // houdt het pad bereikbaar.
        child: status.detail == null
            ? text
            : Tooltip(message: status.detail!, child: text),
      );
    }

    final sources = switch (connection) {
      LocalConnection() => const <Listenable>[],
      WebdavConnection() => switch (_webdavForms[connection.id]) {
        final WebdavForm f => [f.url, f.user],
        _ => const <Listenable>[],
      },
      S3Connection() => switch (_s3Forms[connection.id]) {
        final S3Form f => [f.endpoint, f.bucket],
        _ => const <Listenable>[],
      },
      GitConnection() => switch (_gitForms[connection.id]) {
        final GitForm f => [f.url, f.owner, f.repo],
        _ => const <Listenable>[],
      },
    };
    if (sources.isEmpty) return line(context, null);
    return ListenableBuilder(
      listenable: Listenable.merge(sources),
      builder: line,
    );
  }

  /// De stand van zaken in één zin, plus of de verbinding bruikbaar is — dat
  /// tweede bepaalt of de regel groen leest of grijs.
  ({String text, bool configured, String? detail}) _connectionStatus(
    StorageConnection connection,
    AppLocalizations l10n,
  ) {
    switch (connection) {
      case LocalConnection(:final path):
        if (path.trim().isEmpty) {
          return (
            text: l10n.d('Geen map gekozen'),
            configured: false,
            detail: null,
          );
        }
        return (text: p.basename(path), configured: true, detail: path);
      case WebdavConnection():
        final form = _webdavForms[connection.id];
        final host = _hostOf(form?.url.text ?? '');
        if (host == null || (form?.user.text.trim().isEmpty ?? true)) {
          return (
            text: l10n.d('Niet ingesteld'),
            configured: false,
            detail: null,
          );
        }
        return (text: host, configured: true, detail: null);
      case S3Connection():
        final form = _s3Forms[connection.id];
        final bucketName = form?.bucket.text.trim() ?? '';
        if (_hostOf(form?.endpoint.text ?? '') == null || bucketName.isEmpty) {
          return (
            text: l10n.d('Niet ingesteld'),
            configured: false,
            detail: null,
          );
        }
        // De bucketnaam is wat de gebruiker herkent; het endpoint staat in de
        // tooltip omdat twee buckets met dezelfde naam op verschillende
        // diensten kunnen bestaan.
        return (
          text: bucketName,
          configured: true,
          detail: form?.endpoint.text.trim(),
        );
      case GitConnection():
        final form = _gitForms[connection.id];
        final owner = form?.owner.text.trim() ?? '';
        final repo = form?.repo.text.trim() ?? '';
        if (_hostOf(form?.url.text ?? '') == null ||
            owner.isEmpty ||
            repo.isEmpty) {
          return (
            text: l10n.d('Niet ingesteld'),
            configured: false,
            detail: null,
          );
        }
        return (text: '$owner/$repo', configured: true, detail: null);
    }
  }

  /// De knop die een verbinding toevoegt. Eén knop met een menu in plaats van
  /// drie knoppen: welke soorten er zijn is een detail dat pas telt op het
  /// moment dat je er een kiest.
  Widget _addConnectionButton(AppLocalizations l10n) {
    final kinds = [
      if (supportsLocalProjectFolders) StorageConnectionKind.local,
      if (supportsNetworkDeckSources) ...[
        StorageConnectionKind.webdav,
        StorageConnectionKind.s3,
        StorageConnectionKind.git,
      ],
    ];
    if (kinds.isEmpty) return const SizedBox.shrink();

    return Align(
      alignment: Alignment.centerLeft,
      child: MenuAnchor(
        builder: (context, controller, _) => ElevatedButton.icon(
          onPressed: () =>
              controller.isOpen ? controller.close() : controller.open(),
          icon: const Icon(Icons.add, size: 16),
          label: Text(l10n.d('Verbinding toevoegen')),
        ),
        menuChildren: [
          for (final kind in kinds)
            MenuItemButton(
              onPressed: () => kind == StorageConnectionKind.local
                  ? _addLocalConnection()
                  : _addNetworkConnection(kind),
              leadingIcon: Icon(kind.icon, size: 19),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(kind.label(l10n)),
                    Text(
                      kind.summary(l10n),
                      style: TextStyle(fontSize: 11, color: AppTheme.slate400),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

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
