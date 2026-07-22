// Importeren vanaf een URL: ophalen, uitpakken naar een projectmap, en het
// resultaat openen. Afgesplitst van `tabs_provider.dart` toen dat bestand tegen
// het plafond van 1000 regels liep — niet willekeurig geknipt: dit is één weg,
// van een geplakte link tot een geopend tabblad.
//
// Let op: dit is een extensie, dus `state` is hier niet bereikbaar. Lezen gaat
// via `currentState`, en een tabbladlijst verversen via `refreshTabs()`.
part of 'tabs_provider.dart';

extension TabsImport on TabsNotifier {
  Future<void> _discardImportArtifacts(String mdPath) async {
    try {
      final dir = Directory(p.dirname(mdPath));
      if (await dir.exists()) await dir.delete(recursive: true);
    } catch (e) {
      logWarning('TabsNotifier._discardImportArtifacts: cleanup failed', e);
    }
  }

  /// Map waarin geïmporteerde pakketten worden uitgepakt.
  Future<String> _importDestDir(String? homeDir) async {
    if (homeDir != null && homeDir.trim().isNotEmpty) return homeDir;
    return (await getApplicationDocumentsDirectory()).path;
  }

  /// Importeer een `.ocideck`-pakket (zip) en open het in een tab.
  ///
  /// Retourneert `null` wanneer het pakket is opgehaald én verwerkt — ook als
  /// de veiligheidscontrole de inhoud blokkeert (dan toont de shell het alarm).
  /// Anders de reden waarom het pakket niet kon worden gelezen/uitgepakt.
  Future<ImportFailure?> importPackageFile(
    String zipPath, {
    String? homeDir,
  }) async {
    final dest = await _importDestDir(homeDir);
    final file = File(zipPath);
    if (await file.length() > FileService.maxPackageBytes) {
      return ImportFailure.tooLarge;
    }
    final bytes = await file.readAsBytes();
    final outcome = await _file.importPackageBytesDetailed(
      bytes,
      dest,
      onPassword: packagePasswordResolver,
    );
    final mdPath = outcome.mdPath;
    // Afbreken van de wachtwoordvraag is geen fout: geen melding tonen.
    if (outcome.failure == ImportFailure.encryptedCancelled) return null;
    if (mdPath == null) return outcome.failure;
    final result = await _openImported(mdPath);
    return _importHandled(result) ? null : ImportFailure.unsupported;
  }

  /// Haal een presentatie op via een URL (pakket of platte markdown) en open
  /// het in een tab. Zie [importPackageFile] voor de betekenis van de retour.
  Future<ImportFailure?> importFromUrl(String url, {String? homeDir}) async {
    final dest = await _importDestDir(homeDir);
    final outcome = await _file.importFromUrlDetailed(
      url,
      dest,
      onPassword: packagePasswordResolver,
    );
    final mdPath = outcome.mdPath;
    if (outcome.failure == ImportFailure.encryptedCancelled) return null;
    if (mdPath == null) return outcome.failure;
    final result = await _openImported(mdPath);
    if (result == OpenResult.opened && mounted) {
      // Herkomst voor de wolk-badge in recente presentaties.
      await _settings.setRecentFileOrigin(mdPath, url);
    }
    return _importHandled(result) ? null : ImportFailure.unsupported;
  }

  /// Web-variant van [importFromUrl]: haalt de presentatie in de browser op
  /// (CORS en de pagina-CSP bewaken het verkeer) en opent haar volledig in
  /// het geheugen — een `.ocideck`/zip-pakket wordt daarbij in het geheugen
  /// uitgepakt, met dezelfde omvangslimiet als de desktop-import.
  Future<OpenResult> importFromUrlWeb(String url) async {
    final bytes = await _file.fetchUrlBytes(
      url,
      maxBytes: FileService.maxPackageBytes,
      onConfirmProxy: proxyFallbackConfirm,
    );
    if (bytes == null || !mounted) return OpenResult.unreadable;
    // Zelfde kern als de web-picker en drag-drop: [openDeckFromBytes]. De URL
    // reist mee als [remoteOrigin] zodat de statusbalk de privacy-badge toont:
    // deze presentatie is van buiten het apparaat opgehaald.
    return openDeckFromBytes(bytes, url, remoteOrigin: url);
  }

  /// Gedeelde staart van elke import-flow (pakket/URL/WebDAV): open het
  /// geïmporteerde bestand en ruim de import-artefacten op wanneer dat niet
  /// lukte.
  Future<OpenResult> _openImported(String mdPath) async {
    final result = await openFileByPath(mdPath);
    if (result != OpenResult.opened) await _discardImportArtifacts(mdPath);
    return result;
  }

  /// "Verwerkt" betekent voor de bool-imports: geopend, óf geblokkeerd door de
  /// security-gate (de shell toont dan het alarm) — niet-leesbaar is `false`.
  static bool _importHandled(OpenResult result) =>
      result == OpenResult.opened || result == OpenResult.blocked;

  /// Download [entry] van de WebDAV-bron, haal het door de bestaande
  /// security-gate en open het in een tab. Het tabblad onthoudt zijn herkomst
  /// zodat "Opslaan naar Nextcloud" terug kan schrijven. Een netwerk-/auth-fout
  /// wordt als [WebdavException] doorgegeven aan de aanroeper.
  Future<OpenResult> openFromWebdav(
    WebdavService service,
    WebdavEntry entry, {
    String connectionId = '',
    String? homeDir,
  }) async {
    final dest = await _importDestDir(homeDir);
    final maxBytes = entry.isMarkdown
        ? FileService.maxDeckMarkdownBytes
        : FileService.maxPackageBytes;
    final downloaded = await service.download(
      entry.relativePath,
      maxBytes: maxBytes,
    );
    final bytes = downloaded.bytes;
    if (!mounted) return OpenResult.unreadable;
    final String? mdPath;
    if (entry.isMarkdown) {
      mdPath = await _file.importMarkdownBytes(bytes, dest, entry.name);
    } else {
      final outcome = await _file.importPackageBytesDetailed(
        bytes,
        dest,
        onPassword: packagePasswordResolver,
      );
      if (outcome.failure == ImportFailure.encryptedCancelled) {
        return OpenResult.passwordCancelled;
      }
      mdPath = outcome.mdPath;
    }
    if (mdPath == null) return OpenResult.unreadable;
    final result = await _openImported(mdPath);
    if (result != OpenResult.opened) return result;
    // De zojuist geopende deck zit in het huidige tabblad (zie openFileByPath).
    currentState.current?.webdavOrigin = WebdavOrigin(
      connectionId: connectionId,
      baseUrl: service.server.baseUrl,
      username: service.server.username,
      remotePath: entry.relativePath,
      // De versie die we nét ophaalden; hierop toetst een latere opslag.
      etag: downloaded.etag,
    );
    // Herkomst voor de wolk-badge in recente presentaties.
    await _settings.setRecentFileOrigin(
      mdPath,
      '${service.server.baseUrl} · ${entry.relativePath}',
    );
    refreshTabs();
    return OpenResult.opened;
  }

  /// Schrijf het deck van [tab] terug naar de WebDAV-bron op [targetPath]
  /// (relatief aan de wortelmap). Bij [DeckSaveFormat.ocideck] gaat er één
  /// pakketbestand omhoog; bij [DeckSaveFormat.flat] worden de pakket-leden
  /// (`.md` + assetmappen) los geüpload in dezelfde map. Werkt de herkomst van
  /// het tabblad bij. Gooit [WebdavException] bij een netwerk-/auth-fout.
  Future<void> saveToWebdav(
    TabInfo tab,
    WebdavService service, {
    required DeckSaveFormat format,
    required String targetPath,
    String connectionId = '',
    bool overwrite = false,
  }) async {
    final deck = tab.deckNotifier.currentState.deck;
    if (deck == null) return;
    // Alleen terugschrijven naar precies het bestand dat we ophaalden valt te
    // bewaken; voor elk ander doelpad hebben we geen versie om tegen te
    // toetsen, en koos de gebruiker het pad zelf.
    final origin = tab.webdavOrigin;
    final guard =
        (!overwrite &&
            origin != null &&
            origin.matchesServer(service.server) &&
            origin.remotePath == targetPath)
        ? origin.etag
        : null;
    String? savedEtag;
    if (format == DeckSaveFormat.ocideck) {
      final bytes = await _file.buildPackageBytes(deck);
      savedEtag = await service.upload(targetPath, bytes, ifMatch: guard);
    } else {
      final members = await _file.buildPackageMembers(deck);
      final dir = p.posix.dirname(targetPath);
      final mdBase = p.posix.basename(targetPath);
      // Het markdownbestand eerst; zie [saveToS3] voor waarom die volgorde telt.
      final ordered = [
        ...members.entries.where(_isRootMd),
        ...members.entries.where((e) => !_isRootMd(e)),
      ];
      for (final entry in ordered) {
        // Het pakket-markdownbestand heet naar de deck-titel; geef het op de
        // server de naam die de gebruiker koos. Assets behouden hun submap.
        final isRootMd = _isRootMd(entry);
        final remote = isRootMd
            ? p.posix.join(dir, mdBase)
            : p.posix.join(dir, entry.key);
        // Alleen het markdownbestand ís het deck; de assets ernaast hebben we
        // nooit opgehaald, dus daar valt niets te toetsen.
        final etag = await service.upload(
          remote,
          entry.value,
          ifMatch: isRootMd ? guard : null,
        );
        if (isRootMd) savedEtag = etag;
      }
    }
    tab.webdavOrigin = WebdavOrigin(
      // Een leeg id bij opslaan zou de herkomst van een geopend deck wissen;
      // val dan terug op wat er al stond.
      connectionId: connectionId.isEmpty
          ? (tab.webdavOrigin?.connectionId ?? '')
          : connectionId,
      baseUrl: service.server.baseUrl,
      username: service.server.username,
      remotePath: targetPath,
      // Vanaf nu is dít de versie waarop we verder werken. Gaf de server er
      // geen, dan blijft het `null` en is de volgende opslag onbewaakt — dat
      // is zichtbaar zo, en niet een gok die stil de guard uitzet.
      etag: savedEtag,
    );
    refreshTabs();
  }
}
