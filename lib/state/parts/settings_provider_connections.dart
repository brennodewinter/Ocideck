// Part of the settings_provider library — see ../settings_provider.dart.
// Split out for navigability (de bestandsverbindingen); alle imports leven in
// het hoofdbestand.
part of '../settings_provider.dart';

/// De prefs-sleutel waaronder de hele verbindingenlijst staat. Eén sleutel voor
/// alle soorten, want de volgorde loopt dwars door de soorten heen en die zou
/// je met aparte sleutels niet kunnen bewaren.
const _connectionsKey = 'storageConnections';

/// De naam die een gemigreerde bron krijgt wanneer er niets beters is. Kort
/// gehouden: de gebruiker ziet hem meteen in de lijst staan en hernoemt hem.
const _migratedWebdavName = 'WebDAV';
const _migratedGitName = 'Git';

/// De naam die de nóg oudere enkele `homeDirectory` bij migratie krijgt.
const _migratedLibraryName = 'Mijn presentaties';

/// Beheer van de bestandsverbindingen: toevoegen, bijwerken, verwijderen en —
/// het punt van de hele exercitie — herordenen.
///
/// Volgorde is hier geen cosmetica. De bovenste bruikbare verbinding van een
/// soort is de standaard voor die soort (`AppSettings.primaryOf`), dus slepen
/// is hoe de gebruiker zegt welke server "de" server is. Dat maakt het mogelijk
/// om voor klant A en klant B allebei een Nextcloud te bewaren en per klus de
/// juiste bovenaan te zetten, zonder configuratie weg te gooien.
extension SettingsNotifierConnections on SettingsNotifier {
  /// Schrijf de volledige lijst weg. Alle andere mutaties lopen hierlangs, zodat
  /// er precies één plek is die persisteert, één plek die de legacy-sleutels
  /// opruimt en één plek die de sporen op schijf achter een verdwenen
  /// verbinding aan opruimt.
  ///
  /// [discardPendingWorkFor] bevat de id's van verbindingen waarvoor de
  /// gebruiker uitdrukkelijk heeft bevestigd dat wachtend, nog niet gepusht werk
  /// weg mag. Staat een verbinding daar niet in en wacht er nog werk, dan blijft
  /// haar werkkopie staan — liever een spoor dat de gebruiker zelf kan wissen
  /// dan werk dat stil verdwijnt.
  Future<void> setConnections(
    List<StorageConnection> connections, {
    Set<String> discardPendingWorkFor = const {},
  }) async {
    final gone = [
      for (final c in currentState.connections)
        if (!connections.any((n) => n.id == c.id)) c,
    ];
    currentState = currentState.copyWith(connections: connections);
    await _persist('setConnections', (prefs) async {
      await prefs.setString(
        _connectionsKey,
        StorageConnection.encodeList(connections),
      );
      // De oude sleutels zijn nu overbodig. Ze weghalen voorkomt dat de
      // migratie opnieuw aanslaat nadat de gebruiker alles heeft verwijderd —
      // anders zou een leeggemaakte lijst bij de volgende start weer vol staan.
      await prefs.remove('libraries');
      await prefs.remove('homeDirectory');
      await prefs.remove('webdavServer');
      await prefs.remove('gitRepo');
    });
    for (final connection in gone) {
      await _diskTraces.removeTracesOf(
        connection,
        discardPendingWork: discardPendingWorkFor.contains(connection.id),
      );
    }
  }

  /// Voeg een verbinding achteraan toe.
  Future<void> addConnection(StorageConnection connection) =>
      setConnections([...currentState.connections, connection]);

  /// Vervang de verbinding met dezelfde id. Onbekende id: no-op — de verbinding
  /// is dan tussentijds verwijderd, en hem stilletjes terugzetten zou die
  /// verwijdering ongedaan maken.
  Future<void> updateConnection(StorageConnection connection) async {
    if (!currentState.connections.any((c) => c.id == connection.id)) return;
    await setConnections([
      for (final c in currentState.connections)
        if (c.id == connection.id) connection else c,
    ]);
  }

  /// Verwijder de verbinding met [id]. Het bijbehorende geheim blijft in de
  /// keychain staan: dat hoort bij het account, niet bij deze verbinding, en
  /// een tweede verbinding naar dezelfde server kan het nog nodig hebben.
  ///
  /// De werkkopie op schijf gaat wél mee — zie [setConnections]. Zet
  /// [discardPendingWork] alleen wanneer de gebruiker heeft bevestigd dat
  /// wachtend werk verloren mag gaan.
  Future<void> removeConnection(String id, {bool discardPendingWork = false}) =>
      setConnections([
        for (final c in currentState.connections)
          if (c.id != id) c,
      ], discardPendingWorkFor: discardPendingWork ? {id} : const {});

  /// Verplaats de verbinding van [oldIndex] naar [newIndex] — de sleepactie uit
  /// de instellingen. Buiten bereik of geen verplaatsing: no-op.
  ///
  /// Beide indexen tellen in de eindlijst, zoals `onReorderItem` ze geeft. De
  /// oudere `onReorder` telt het gesleepte item nog op zijn oude plek mee; die
  /// correctie hoort bij de widget, niet hier.
  Future<void> reorderConnections(int oldIndex, int newIndex) async {
    final list = [...currentState.connections];
    if (oldIndex < 0 || oldIndex >= list.length) return;
    if (newIndex < 0 || newIndex >= list.length) return;
    if (newIndex == oldIndex) return;
    list.insert(newIndex, list.removeAt(oldIndex));
    await setConnections(list);
  }
}

/// Lees de verbindingen uit prefs, en migreer eenmalig wanneer ze er nog niet
/// staan.
///
/// De migratie zet de oude drie-in-één-vorm om: eerst de bibliotheken (in hun
/// bestaande volgorde, want die was al betekenisvol — `libraries.first` was de
/// thuismap), daarna de WebDAV-bron en dan de git-repo. Die vololgorde maakt van
/// de vorige standaard vanzelf de nieuwe standaard, zodat er voor de gebruiker
/// niets verschuift.
///
/// De uitkomst wordt hier bewust nog niet weggeschreven: dat gebeurt bij de
/// eerste mutatie. Zolang de gebruiker niets aanraakt blijven de oude sleutels
/// staan, en dat is precies wat je wilt als hij terugvalt op een oudere versie.
List<StorageConnection> _loadConnections(SharedPreferences prefs) {
  final stored = StorageConnection.decodeList(prefs.getString(_connectionsKey));
  if (stored.isNotEmpty) return stored;
  if (prefs.getString(_connectionsKey) != null) {
    // Sleutel bestaat maar is leeg: de gebruiker heeft alles verwijderd. Niet
    // migreren, anders komt zijn opruiming elke start terug.
    return const [];
  }
  return _migrateLegacyConnections(prefs);
}

List<StorageConnection> _migrateLegacyConnections(SharedPreferences prefs) {
  final connections = <StorageConnection>[];

  for (final folder in _legacyLibraries(prefs)) {
    connections.add(
      LocalConnection(
        id: StorageConnection.newId(),
        name: folder.name,
        path: folder.path,
      ),
    );
  }

  final webdavJson = prefs.getString('webdavServer');
  if (webdavJson != null) {
    try {
      final server = WebdavServer.fromJson(
        Map<String, Object?>.from(jsonDecode(webdavJson) as Map),
      );
      connections.add(
        WebdavConnection(
          id: StorageConnection.newId(),
          name: _migratedWebdavName,
          server: server,
        ),
      );
    } catch (e) {
      logWarning('SettingsNotifier: ongeldige webdavServer-prefs', e);
    }
  }

  final gitJson = prefs.getString('gitRepo');
  if (gitJson != null) {
    try {
      final repo = GitRepoConfig.fromJson(
        Map<String, Object?>.from(jsonDecode(gitJson) as Map),
      );
      connections.add(
        GitConnection(
          id: StorageConnection.newId(),
          name: _migratedGitName,
          repo: repo,
        ),
      );
    } catch (e) {
      logWarning('SettingsNotifier: ongeldige gitRepo-prefs', e);
    }
  }

  return connections;
}

/// De bibliotheken zoals ze vóór de verbindingenlijst waren opgeslagen,
/// inclusief de nóg oudere enkele `homeDirectory`.
List<LibraryFolder> _legacyLibraries(SharedPreferences prefs) {
  final stored = LibraryFolder.decodeList(prefs.getString('libraries'));
  if (stored.isNotEmpty) return stored;
  final legacy = prefs.getString('homeDirectory');
  if (legacy != null && legacy.trim().isNotEmpty) {
    return [LibraryFolder(name: _migratedLibraryName, path: legacy)];
  }
  return const [];
}
