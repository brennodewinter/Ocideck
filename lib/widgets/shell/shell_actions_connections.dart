// Part of the app_shell library — see ../app_shell.dart.
//
// Welke bestandsverbinding voert een handeling uit?
//
// Apart gezet omdat het één vraag is die overal terugkomt, en omdat het antwoord
// een regel bevat die je op elke aanroepplek opnieuw fout zou kunnen doen: bij
// precies één bruikbare verbinding wordt er níets gevraagd. Wie één server heeft
// — de meeste mensen — houdt daardoor exact de flow van vroeger, en de vraag
// verschijnt pas wanneer het een echte vraag is.
//
// Deck-gebonden handelingen komen hier niet langs. Die volgen de herkomst van
// het geopende deck (`AppSettings.gitConnectionFor`, `WebdavOrigin.connectionId`),
// want die weet al bij welke opdrachtgever het werk hoort — en een keuzedialoog
// zou de gebruiker de kans geven daar per ongeluk van af te wijken.
part of '../app_shell.dart';

/// Laat de gebruiker een git-verbinding kiezen. Bij één verbinding gebeurt dat
/// zonder dialoog; bij geen enkele volgt de melding dat er niets staat
/// ingesteld.
Future<GitConnection?> _pickGitConnection(
  BuildContext context,
  WidgetRef ref,
) async {
  final connections = ref.read(gitConnectionsProvider);
  if (connections.isEmpty) {
    _gitNotConfigured(context);
    return null;
  }
  return StorageConnectionPicker.show(context, connections);
}

void _gitNotConfigured(BuildContext context) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(
        context.l10n.d(
          'Stel eerst een git-repository in bij Instellingen → Opslag.',
        ),
      ),
    ),
  );
}

/// Laat de gebruiker een WebDAV-verbinding kiezen. Bij één verbinding gebeurt
/// dat zonder dialoog; bij geen enkele volgt de melding dat er niets staat
/// ingesteld.
Future<WebdavConnection?> _pickWebdavConnection(
  BuildContext context,
  WidgetRef ref,
) async {
  final connections = ref.read(webdavConnectionsProvider);
  if (connections.isEmpty) {
    _webdavNotConfigured(context);
    return null;
  }
  return StorageConnectionPicker.show(context, connections);
}

void _webdavNotConfigured(BuildContext context) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(
        context.l10n.d(
          'Stel eerst een WebDAV-server in bij Instellingen → Opslag.',
        ),
      ),
    ),
  );
}

/// Sla het tabblad [tab] op via het juiste pad: een documenttabblad byte-getrouw
/// (of "Opslaan als…"), een presentatie via de deck-route. Gedeeld door de
/// app-brede Ctrl/Cmd+S en de opslaan-bij-afsluiten-lus, zodat een vuil
/// documenttabblad het afsluiten niet eeuwig blokkeert. Geeft terug of er
/// daadwerkelijk is opgeslagen.
Future<bool> saveTabWithDestination(
  BuildContext context,
  WidgetRef ref,
  TabInfo tab,
) {
  final document = tab.documentNotifier;
  return document != null
      ? saveDocumentWithDestination(context, ref, document)
      : saveDeckWithDestination(context, ref, tab.deckNotifier);
}

/// Sla [deckNotifier] op. Voor een nieuw deck (nog geen bestandspad) toont dit
/// eerst een bestemmingsdialoog — kies een bibliotheek en zie waar de
/// presentatie, afbeeldingen en media landen — en opent daarna het
/// systeem-opslaanvenster in de gekozen map. Bestaande decks slaan direct op.
/// Op web (geen schrijfbaar bestandssysteem) is opslaan een download; dan geen
/// dialoog. Geeft terug of er daadwerkelijk is opgeslagen.
///
/// Wanneer die dialoog wél verschijnt staat in [shouldAskDestination]; zonder
/// ingerichte bibliotheek heeft hij niets te kiezen en wordt hij overgeslagen.
Future<bool> saveDeckWithDestination(
  BuildContext context,
  WidgetRef ref,
  DeckNotifier deckNotifier,
) async {
  // In een gedeelde samenwerksessie bewaart alleen de eigenaar het deck naar de
  // bron (COLLABORATION.md §5.3). Een gast — ook als die tijdelijk de autoriteit
  // is — houdt zijn wijzigingen in de sessie; ze worden pas bewaard als de
  // eigenaar opslaat. Deze poort staat op de enige plek waar élke opslaanroute
  // langskomt, zodat geen enkele knop of sneltoets eromheen kan.
  if (!ref.read(collabSessionProvider).canPersist) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          context.l10n.d(
            'Alleen de eigenaar bewaart het deck in een gedeelde sessie; jouw wijzigingen blijven in de sessie tot de eigenaar opslaat.',
          ),
        ),
      ),
    );
    return false;
  }

  // Waar het vandaan komt, gaat het naartoe terug. Een deck dat van WebDAV, S3
  // of git is geopend, hoort met de gewone opslaanknop niet ineens als lokaal
  // bestand te landen: dan staat de bewerkte versie op de laptop en blijft de
  // server met de oude zitten, terwijl de gebruiker denkt dat hij heeft
  // opgeslagen. Naar een ándere plek schrijven is een aparte handeling
  // ("Opslaan naar…"), geen bijwerking van opslaan.
  final origin = ref.read(tabsProvider).current?.origin;
  if (origin != null) return _saveToOrigin(context, ref, origin);

  // Web: opslaan is een kale .md-download. Afbeeldingen, video en audio die de
  // gebruiker in dit tabblad koos, leven alleen in het geheugen (mem:-paden) en
  // reizen niet mee in een los .md — bij heropenen zijn ze weg. Op schijf
  // (desktop) kopieert de opslag ze naar een images/-map, dus daar speelt dit
  // niet. Waarschuw, maar blokkeer niet: de gebruiker mag bewust een tekstueel
  // .md willen, en het pakket (.ocideck) is de weg om het beeld mee te nemen.
  if (!supportsLocalProjectFolders) {
    final deck = deckNotifier.currentState.deck;
    if (deck != null && deckCarriesMemoryAssets(deck)) {
      final proceed = await _confirmWebAssetLoss(context);
      if (proceed != true || !context.mounted) return false;
    }
  }

  final settings = ref.read(settingsProvider);
  if (!shouldAskDestination(
    isNewDeck: deckNotifier.currentState.filePath == null,
    supportsFolders: supportsLocalProjectFolders,
    hasLibraries: settings.libraries.isNotEmpty,
  )) {
    return withSaveProgress(
      ref,
      SaveTarget.local,
      () => deckNotifier.save(initialDirectory: settings.homeDirectory),
    );
  }
  final choice = await SaveDestinationDialog.show(
    context,
    libraries: settings.libraries,
    deckTitle: deckNotifier.currentState.deck?.title ?? '',
  );
  if (choice == null || !context.mounted) return false;
  return withSaveProgress(
    ref,
    SaveTarget.local,
    () => deckNotifier.save(initialDirectory: choice.directory),
  );
}

/// Waarschuwt dat een kale .md-download de geheugenmedia niet bewaart, en vraagt
/// of de gebruiker toch wil doorgaan. Geen blokkade — het pakket is de uitweg,
/// maar de keuze blijft aan de gebruiker.
Future<bool?> _confirmWebAssetLoss(BuildContext context) {
  return showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(
        ctx.l10n.d('Media blijft niet bewaard in een los .md-bestand'),
      ),
      content: Text(
        // Eén stringliteral: de l10n-extractie leest naast-elkaar-geplaatste
        // literals als losse sleutels, en dan matcht de vertaling niet.
        // ignore: lines_longer_than_80_chars
        ctx.l10n.d(
          'Afbeeldingen, video en audio die je in dit tabblad koos, leven alleen in het geheugen. Een los .md-bestand bewaart ze niet — bij heropenen zijn ze weg. Exporteer als .ocideck-pakket om het beeld mee te nemen.',
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: Text(ctx.l10n.d('Annuleren')),
        ),
        ElevatedButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: Text(ctx.l10n.d('Doorgaan')),
        ),
      ],
    ),
  );
}

/// Slaat op naar de opslag waar het deck vandaan kwam. Geeft terug of dat
/// gelukt is.
///
/// WebDAV en S3 gaan stil terug naar hetzelfde pad; git vraagt wél, omdat een
/// commit een boodschap nodig heeft en op een werkbranch landt. Verdwijnt de
/// verbinding (verwijderd of niet meer geconfigureerd), dan valt het
/// betreffende pad zelf terug op de keuzedialoog — daar hoort die vraag, niet
/// hier.
Future<bool> _saveToOrigin(
  BuildContext context,
  WidgetRef ref,
  StorageOrigin origin,
) async {
  switch (origin) {
    case WebdavOrigin():
      return _saveToNextcloud(context, ref, silent: true);
    case S3Origin():
      return _saveToS3(context, ref, silent: true);
    case GitOrigin():
      // #1948: git-opslaan kan annuleren of falen — geef dat door aan de
      // afsluitlus, anders wist die de herstelkopie en sluit hij de app
      // terwijl het werk nergens staat.
      return _saveToGit(context, ref);
  }
  // StorageOrigin is geen sealed type (de implementaties wonen bij hun eigen
  // instellingen), dus een onbekende soort valt terug op "niet afgehandeld" en
  // de lokale weg neemt het over.
  // ignore: dead_code
  return false;
}

/// De verbindingen waaruit "Openen uit…" en "Opslaan naar…" laten kiezen:
/// alles wat is ingesteld, behalve de lokale mappen — die hebben hun eigen
/// "Openen…" via het systeemvenster.
///
/// WebDAV en S3 vallen weg waar het platform ze niet draagt (op web leunt de
/// WebDAV-client op dart:io-pinning); git blijft, want dat is https+JSON dat de
/// browser-sandbox al inperkt (§4.4).
List<StorageConnection> _remoteConnections(WidgetRef ref) {
  return ref
      .read(settingsProvider)
      .connections
      .where(
        (c) =>
            c.isConfigured &&
            switch (c) {
              LocalConnection() => false,
              GitConnection() => true,
              WebdavConnection() ||
              S3Connection() => supportsNetworkDeckSources,
            },
      )
      .toList();
}

/// Openen uit een verbinding, welke soort dan ook.
///
/// Eén ingang in plaats van drie. De vraag die de gebruiker heeft is "waar
/// staat mijn presentatie", niet "welk protocol gebruikt de plek waar mijn
/// presentatie staat" — en met één verbinding stelt de kiezer de vraag
/// helemaal niet, dus wie één server heeft merkt er niets van.
Future<void> _openFromConnection(BuildContext context, WidgetRef ref) async {
  final connections = _remoteConnections(ref);
  if (connections.isEmpty) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          context.l10n.d(
            'Stel eerst een verbinding in bij Instellingen → Opslag.',
          ),
        ),
      ),
    );
    return;
  }
  final chosen = await StorageConnectionPicker.show(context, connections);
  if (chosen == null || !context.mounted) return;
  switch (chosen) {
    case WebdavConnection():
      await _openFromNextcloud(context, ref, connection: chosen);
    case S3Connection():
      await _openFromS3(context, ref, connection: chosen);
    case GitConnection():
      await _openFromGit(context, ref, connection: chosen);
    case LocalConnection():
      break; // Gefilterd in [_remoteConnections].
  }
}

/// Opslaan naar een verbinding naar keuze — het deck ergens ánders neerzetten
/// dan waar het vandaan kwam.
///
/// Dit is de uitzondering, niet de regel: de gewone opslaanknop volgt de
/// herkomst (zie [saveDeckWithDestination]). Deze ingang bestaat voor het geval
/// dat je het bewust wilt verplaatsen of kopiëren.
Future<void> _saveToConnection(BuildContext context, WidgetRef ref) async {
  final connections = _remoteConnections(ref);
  if (connections.isEmpty) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          context.l10n.d(
            'Stel eerst een verbinding in bij Instellingen → Opslag.',
          ),
        ),
      ),
    );
    return;
  }
  final chosen = await StorageConnectionPicker.show(context, connections);
  if (chosen == null || !context.mounted) return;
  switch (chosen) {
    case WebdavConnection():
      await _saveToNextcloud(context, ref, connectionOverride: chosen);
    case S3Connection():
      await _saveToS3(context, ref, connectionOverride: chosen);
    case GitConnection():
      await _saveToGit(context, ref, connectionOverride: chosen);
    case LocalConnection():
      break; // Gefilterd in [_remoteConnections].
  }
}

/// Of de bestemmingsdialoog iets toe te voegen heeft vóór het systeemvenster.
///
/// Drie voorwaarden, en de derde is de reparatie uit #646. De dialoog laat je
/// een bibliotheek kiezen en toont vooraf waar de presentatie, afbeeldingen en
/// media terechtkomen — nuttig, zolang er iets te kiezen valt. Is er nog geen
/// bibliotheek ingericht, dan toont hij een lege lijst met twee knoppen die
/// allebei verderleiden ("Andere map…" en "Kies bestandsnaam…"), en dat is
/// precies de "drie dialogen diep om een bestand op te slaan" uit de melding.
///
/// Dat trof iedereen, want bij een eerste start ís er geen bibliotheek. De
/// dialoog is daarom niet weggehaald maar overgeslagen op het pad waar hij
/// niets te bieden heeft.
bool shouldAskDestination({
  required bool isNewDeck,
  required bool supportsFolders,
  required bool hasLibraries,
}) =>
    // Een bestaand deck heeft al een plek; opslaan schrijft daarheen terug.
    isNewDeck &&
    // Op het web is opslaan een download: er valt geen map te kiezen.
    supportsFolders &&
    hasLibraries;

/// Blader door de Nextcloud/WebDAV-bron, download het gekozen deck, haal het
/// door de security-gate en open het in een tab. Toont waar nodig een melding.
Future<void> _openFromNextcloud(
  BuildContext context,
  WidgetRef ref, {
  WebdavConnection? connection,
}) async {
  final chosen = connection ?? await _pickWebdavConnection(context, ref);
  if (chosen == null || !context.mounted) return;
  final service = await ref.read(webdavServiceProvider(chosen.id).future);
  if (!context.mounted) return;
  if (service == null) {
    _webdavNotConfigured(context);
    return;
  }
  final entry = await WebdavBrowserDialog.show(
    context,
    connectionId: chosen.id,
  );
  if (entry == null || !context.mounted) return;
  final messenger = ScaffoldMessenger.of(context);
  final l10n = context.l10n;
  try {
    final result = await ref
        .read(tabsProvider.notifier)
        .openFromWebdav(
          service,
          entry,
          connectionId: chosen.id,
          homeDir: ref.read(settingsProvider).homeDirectory,
        );
    _reportOpenFailure(
      messenger,
      l10n,
      result,
      reason: ref.read(openFailureProvider),
    );
    // OpenResult.blocked toont al het veiligheidsalarm via de shell.
  } on WebdavException catch (e) {
    logWarning('shell: WebDAV-download mislukt', e);
    showErrorSnackBar(
      messenger,
      l10n,
      '${l10n.d('Downloaden mislukt:')} ${webdavErrorMessage(l10n, e)}',
    );
  } catch (e, s) {
    // Vangnet: een niet-WebDAV-fout (bv. een schrijffout in de doelmap of een
    // te groot pakket) mag niet stil in runZonedGuarded verdwijnen — dan opent
    // er niets en ziet de gebruiker geen reden.
    logError('shell: WebDAV openen mislukt', e, s);
    showErrorSnackBar(
      messenger,
      l10n,
      '${l10n.d('Downloaden mislukt:')} ${userFacingError(l10n, e)}',
    );
  }
}

/// Schrijf het deck van het huidige tabblad terug naar Nextcloud. Vraagt het
/// formaat (pakket of platte bestanden) en het doelpad, en uploadt dan.
/// Slaat het actieve deck op naar WebDAV. Geeft terug of er daadwerkelijk is
/// opgeslagen.
///
/// Met [silent] slaat dit de naam- en formaatvraag over wanneer het deck van
/// deze server kwam: dan gaat het terug naar exact hetzelfde pad, in hetzelfde
/// formaat. Dat is wat de gewone opslaanknop doet — die hoort niet elke keer
/// opnieuw te vragen waar iets heen moet dat al ergens vandaan komt. Een
/// botsing met een nieuwere versie vraagt nog steeds, want dat is een keuze die
/// alleen de gebruiker kan maken.
Future<bool> _saveToNextcloud(
  BuildContext context,
  WidgetRef ref, {
  bool silent = false,
  WebdavConnection? connectionOverride,
}) async {
  final tab = ref.read(tabsProvider).current;
  final deck = tab?.deckNotifier.currentState.deck;
  if (tab == null || deck == null) return false;
  // Kwam dit deck van een WebDAV-verbinding die nog bestaat, dan gaat het
  // daarnaartoe terug zonder te vragen. Opnieuw laten kiezen zou de gebruiker
  // elke keer de kans geven het bij de verkeerde klant te laten belanden.
  final origin = tab.webdavOrigin;
  final settings = ref.read(settingsProvider);
  final known = settings.connectionById(origin?.connectionId);
  // Een expliciet gekozen doel wint van de herkomst: dat is precies wat
  // "Opslaan naar…" betekent.
  final connection =
      connectionOverride ??
      (known is WebdavConnection && known.isConfigured
          ? known
          : await _pickWebdavConnection(context, ref));
  if (connection == null || !context.mounted) return false;

  final service = await ref.read(webdavServiceProvider(connection.id).future);
  if (!context.mounted) return false;
  if (service == null) {
    _webdavNotConfigured(context);
    return false;
  }
  // Standaardpad: hergebruik de herkomst als die van dezelfde server komt,
  // anders een nette bestandsnaam uit de deck-titel in de wortelmap.
  final reuse = origin != null && origin.matchesServer(service.server);
  final defaultBase = reuse
      ? origin.remotePath.replaceAll(RegExp(r'\.(ocideck|zip|md)$'), '')
      : _safeRemoteName(deck.title);
  var choice = silent && reuse
      ? (format: _formatOfRemotePath(origin.remotePath), base: defaultBase)
      : await _showRemoteSaveDialog(
          context,
          defaultBase: defaultBase,
          title: context.l10n.d('Opslaan naar WebDAV'),
        );
  if (choice == null || !context.mounted) return false;

  final messenger = ScaffoldMessenger.of(context);
  final l10n = context.l10n;
  // Blijft doorlopen zolang de gebruiker na een botsing een andere weg kiest:
  // onder een nieuwe naam opslaan, of alsnog overschrijven.
  var overwrite = false;
  while (true) {
    final ext = choice!.format == DeckSaveFormat.ocideck ? '.ocideck' : '.md';
    final targetPath = '${choice.base}$ext';
    try {
      await withSaveProgress(
        ref,
        SaveTarget.webdav,
        () => ref
            .read(tabsProvider.notifier)
            .saveToWebdav(
              tab,
              service,
              connectionId: connection.id,
              format: choice!.format,
              targetPath: targetPath,
              overwrite: overwrite,
            ),
      );
      // Het opslaan is geslaagd; alleen de melding kan niet meer getoond worden.
      if (!context.mounted) return true;
      messenger.showSnackBar(
        SnackBar(
          content: Text('${l10n.d('Opgeslagen op WebDAV:')} /$targetPath'),
        ),
      );
      return true;
    } on WebdavConflictException catch (e) {
      logWarning('shell: WebDAV-opslaan botste met een nieuwere versie', e);
      if (!context.mounted) return false;
      final resolution = await _showRemoteConflictDialog(context);
      if (resolution == null || !context.mounted) return false;
      switch (resolution) {
        case _RemoteConflict.overwrite:
          overwrite = true;
        case _RemoteConflict.saveAs:
          final next = await _showRemoteSaveDialog(
            context,
            defaultBase: choice.base,
            title: l10n.d('Opslaan naar WebDAV'),
          );
          if (next == null || !context.mounted) return false;
          choice = next;
          // Een ander doelpad wordt niet bewaakt (we haalden het nooit op),
          // maar een ongewijzigd pad moet de guard hóuden.
          overwrite = false;
      }
    } on WebdavException catch (e) {
      logWarning('shell: WebDAV-opslaan mislukt', e);
      showErrorSnackBar(
        messenger,
        l10n,
        '${l10n.d('Opslaan mislukt:')} ${webdavErrorMessage(l10n, e)}',
      );
      return false;
    } catch (e, s) {
      // Vangnet: een te groot pakket (PackageBudgetExceeded) of een leesfout in
      // een lokaal asset is geen WebdavException en zou anders stil verdwijnen —
      // de spinner stopt, maar de gebruiker zou niet weten waaróm er niets
      // opgeslagen is.
      logError('shell: WebDAV-opslaan mislukt', e, s);
      showErrorSnackBar(
        messenger,
        l10n,
        '${l10n.d('Opslaan mislukt:')} ${userFacingError(l10n, e)}',
      );
      return false;
    }
  }
}

/// Het opslagformaat dat bij [remotePath] hoort. Een deck dat als pakket op de
/// server stond, gaat als pakket terug; een platte spiegel blijft plat.
DeckSaveFormat _formatOfRemotePath(String remotePath) =>
    remotePath.toLowerCase().endsWith('.ocideck')
    ? DeckSaveFormat.ocideck
    : DeckSaveFormat.flat;

/// Wat de gebruiker doet als het bestand op de server inmiddels van iemand
/// anders is. Bewust geen samenvoegkeuze zoals bij git: die leunt erop dat de
/// basisversie nog opvraagbaar is, en bij WebDAV en S3 is die weg zodra de
/// ander heeft geüpload.
enum _RemoteConflict { saveAs, overwrite }
