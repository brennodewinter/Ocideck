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

/// Sla [deckNotifier] op. Voor een nieuw deck (nog geen bestandspad) toont dit
/// eerst een bestemmingsdialoog — kies een bibliotheek en zie waar de
/// presentatie, afbeeldingen en media landen — en opent daarna het
/// systeem-opslaanvenster in de gekozen map. Bestaande decks slaan direct op.
/// Op web (geen schrijfbaar bestandssysteem) is opslaan een download; dan geen
/// dialoog. Geeft terug of er daadwerkelijk is opgeslagen.
Future<bool> saveDeckWithDestination(
  BuildContext context,
  WidgetRef ref,
  DeckNotifier deckNotifier,
) async {
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
  final isNewDeck = deckNotifier.currentState.filePath == null;
  if (!isNewDeck || !supportsLocalProjectFolders) {
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
      await _saveToGit(context, ref);
      return true;
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
