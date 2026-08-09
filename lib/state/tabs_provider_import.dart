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

  /// Map waarin geïmporteerde pakketten worden uitgepakt; zie
  /// [_resolveImportDestDir] voor de terugval op de documentenmap wanneer de
  /// ingestelde thuismap op een onbereikbaar volume staat.
  Future<String> _importDestDir(String? homeDir) =>
      _resolveImportDestDir(this, homeDir);

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
  ///
  /// Geeft naast het [OpenResult] de fetch-reden terug (te groot, 404, geen
  /// http(s)-link, geweigerde host…) zodat de schil de juiste melding kiest in
  /// plaats van standaard CORS de schuld te geven. `failure` is null zodra het
  /// ophalen slaagde; wat er dáárna misging staat in [openFailureProvider].
  Future<({OpenResult result, ImportFailure? failure})> importFromUrlWeb(
    String url,
  ) async {
    final fetched = await _file.fetchUrlBytes(
      url,
      maxBytes: FileService.maxPackageBytes,
      onConfirmProxy: proxyFallbackConfirm,
    );
    final bytes = fetched.bytes;
    if (bytes == null || !mounted) {
      return (result: OpenResult.unreadable, failure: fetched.failure);
    }
    // Zelfde kern als de web-picker en drag-drop: [openDeckFromBytes]. De URL
    // reist mee als [remoteOrigin] zodat de statusbalk de privacy-badge toont:
    // deze presentatie is van buiten het apparaat opgehaald.
    final result = await openDeckFromBytes(bytes, url, remoteOrigin: url);
    return (result: result, failure: null);
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
    final ImportOutcome outcome = entry.isMarkdown
        ? await _file.importMarkdownBytesDetailed(bytes, dest, entry.name)
        : await _file.importPackageBytesDetailed(
            bytes,
            dest,
            onPassword: packagePasswordResolver,
          );
    if (outcome.failure == ImportFailure.encryptedCancelled) {
      return OpenResult.passwordCancelled;
    }
    final mdPath = outcome.mdPath;
    if (mdPath == null) {
      // De reden vasthouden (te groot, beschadigd, doel onbereikbaar…) zodat de
      // schil de specifieke melding toont i.p.v. het generieke "Kon dit bestand
      // niet openen." — zelfde mapping als de lokale pakket-open.
      return _packageOpenResult(_ref, mounted, outcome.failure);
    }
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
    final savedEtag = await _uploadDeckToWebdav(
      _file,
      service,
      deck,
      format: format,
      targetPath: targetPath,
      guard: guard,
    );
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

/// Schrijft [deck] naar de WebDAV-bron in het gekozen [format] en geeft de etag
/// terug die de server voor het markdownbestand teruggaf (of null). Pure I/O
/// zonder toegang tot [TabsNotifier]-state, dus top-level — dat houdt de klasse
/// onder haar plafond. Zie [TabsImport.saveToWebdav] voor de herkomst-bijwerking.
Future<String?> _uploadDeckToWebdav(
  FileService file,
  WebdavService service,
  Deck deck, {
  required DeckSaveFormat format,
  required String targetPath,
  required String? guard,
}) async {
  if (format == DeckSaveFormat.ocideck) {
    final bytes = await file.buildPackageBytes(deck);
    return service.upload(targetPath, bytes, ifMatch: guard);
  }
  final members = await file.buildPackageMembers(deck);
  final dir = p.posix.dirname(targetPath);
  final mdBase = p.posix.basename(targetPath);
  // Het markdownbestand eerst; zie [saveToS3] voor waarom die volgorde telt.
  final ordered = [
    ...members.entries.where(_isRootMd),
    ...members.entries.where((e) => !_isRootMd(e)),
  ];
  String? savedEtag;
  for (final entry in ordered) {
    // Het pakket-markdownbestand heet naar de deck-titel; geef het op de server
    // de naam die de gebruiker koos. Assets behouden hun submap.
    final isRootMd = _isRootMd(entry);
    final remote = isRootMd
        ? p.posix.join(dir, mdBase)
        : p.posix.join(dir, entry.key);
    // Alleen het markdownbestand ís het deck; de assets ernaast hebben we nooit
    // opgehaald, dus daar valt niets te toetsen.
    final etag = await service.upload(
      remote,
      entry.value,
      ifMatch: isRootMd ? guard : null,
    );
    if (isRootMd) savedEtag = etag;
  }
  return savedEtag;
}

/// Bepaalt de map waarin een import wordt uitgepakt: de ingestelde thuismap als
/// die te beschrijven is, anders de documentenmap. Is er een thuismap ingesteld
/// maar staat die op een niet-aangekoppeld of onbereikbaar volume, dan valt dit
/// terug op de documentenmap zodat de import tóch slaagt in plaats van diep in de
/// extractie op een niet-gevangen `PathAccessException` te stuiten die stil
/// verdween (#open-ocideck-package). De terugval wordt niet-blokkerend gemeld via
/// [importHomeUnavailableProvider].
///
/// Top-level (met toegang tot de private velden van [notifier], want dit is één
/// library) zodat [TabsNotifier] onder haar klasseplafond blijft.
Future<String> _resolveImportDestDir(
  TabsNotifier notifier,
  String? homeDir,
) async {
  // Zet (of wist) de melding dat de ingestelde thuismap onbereikbaar was. Na
  // dispose is er geen container om in te schrijven, dus dan overslaan.
  void reportUnavailable(String? path) {
    if (!notifier.mounted) return;
    notifier._ref.read(importHomeUnavailableProvider.notifier).state = path;
  }

  final configured = homeDir?.trim();
  if (configured != null && configured.isNotEmpty) {
    try {
      // De thuismap aanmaken ís de toegankelijkheidstoets: op een losgekoppeld
      // volume gooit `create` hier — vroeg en te vangen. Bestaat de map al, dan
      // is dit een no-op.
      await Directory(configured).create(recursive: true);
      reportUnavailable(null);
      return configured;
    } on FileSystemException catch (e) {
      logWarning(
        'TabsNotifier._importDestDir: ingestelde thuismap onbereikbaar, '
        'terugval op documentenmap',
        e,
      );
      reportUnavailable(configured);
    }
  }
  return (await getApplicationDocumentsDirectory()).path;
}

/// Vertaalt de uitkomst van [TabsImport.importPackageFile] — aangeroepen vanuit
/// [TabsNotifier.openFileByPath] voor een `.ocideck`/zip via "Openen" — naar een
/// [OpenResult], en legt waar mogelijk de [OpenFailure] vast zodat de schil
/// dezelfde gerichte melding toont als bij een losse markdown-open. `null`
/// betekent: afgehandeld (geopend, geblokkeerd met alarm, of wachtwoord
/// afgebroken); dan valt er niets te melden.
OpenResult _packageOpenResult(
  Ref ref,
  bool alive,
  ImportFailure? failure,
) => switch (failure) {
  null => OpenResult.opened,
  ImportFailure.needsPassword ||
  ImportFailure.encryptedCancelled => OpenResult.passwordCancelled,
  ImportFailure.tooLarge || ImportFailure.limitExceeded => _openFailureResult(
    ref,
    alive,
    OpenFailure.tooLarge,
  ),
  ImportFailure.corrupt => _openFailureResult(ref, alive, OpenFailure.corrupt),
  ImportFailure.unsupported => _openFailureResult(
    ref,
    alive,
    OpenFailure.notPresentation,
  ),
  // Netwerk-oorzaken: ophalen mislukte (generiek), DNS onbekend, host
  // geweigerd, geen http(s)-schema, certificaat niet vertrouwd, omleiding, of
  // 404. Deze lokale/WebDAV-weg haalt geen URL op, dus ze kunnen hier niet
  // écht ontstaan — maar de switch moet volledig zijn, en geen van hen heeft
  // een fijnere OpenFailure, dus generiek onleesbaar.
  ImportFailure.network ||
  ImportFailure.unknownHost ||
  ImportFailure.blockedHost ||
  ImportFailure.insecureScheme ||
  ImportFailure.tls ||
  ImportFailure.redirect ||
  ImportFailure.notFound => _openFailureResult(
    ref,
    alive,
    OpenFailure.unreadable,
  ),
  ImportFailure.diskFull => _openFailureResult(
    ref,
    alive,
    OpenFailure.unreadable,
  ),
  // Belandt hier alleen als zelfs de documentenmap-terugval van
  // [TabsImport._importDestDir] faalde — een catastrofaal schrijfprobleem,
  // zeldzaam genoeg voor de generieke melding. De drag-drop/Finder-weg toont
  // via [importFailureMessage] wél de specifieke reden.
  ImportFailure.destinationUnavailable => _openFailureResult(
    ref,
    alive,
    OpenFailure.unreadable,
  ),
};
