part of 'tabs_provider.dart';

/// Het open- en opslaanpad van de S3-opslag. Apart bestand omdat
/// `tabs_provider` tegen de regelratchet aan zit; de extensie zit in dezelfde
/// library, dus de gedeelde security-poort blijft bereikbaar.
///
/// Spiegelt bewust `openFromWebdav`/`saveToWebdav`: een bucket is voor een deck
/// niet iets anders dan een map op een server, en waar het gedrag hetzelfde
/// hoort te zijn, is de code dat ook.
extension TabsNotifierS3 on TabsNotifier {
  /// Download het gekozen object, haal het door de security-gate en open het in
  /// een tab.
  ///
  /// Net als bij WebDAV en git gaat de inhoud door dezelfde importroute: een
  /// bucket is niet vertrouwder dan een willekeurige server, en ophalen is een
  /// import, geen zegen.
  Future<OpenResult> openFromS3(
    S3Service service,
    S3Entry entry, {
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
    // Het zojuist geopende deck zit in het huidige tabblad (zie openFileByPath).
    currentState.current?.s3Origin = S3Origin(
      connectionId: connectionId,
      endpoint: service.bucket.endpoint,
      bucket: service.bucket.bucket,
      remotePath: entry.relativePath,
      // De versie die we nét ophaalden; hierop toetst een latere opslag.
      etag: downloaded.etag,
    );
    // Herkomst voor de wolk-badge in recente presentaties.
    await _settings.setRecentFileOrigin(
      mdPath,
      '${service.bucket.bucket} · ${entry.relativePath}',
    );
    refreshTabs();
    return OpenResult.opened;
  }

  /// Schrijf het deck van [tab] terug naar de bucket op [targetPath] (relatief
  /// aan de wortelprefix). Bij [DeckSaveFormat.ocideck] gaat er één pakket
  /// omhoog; bij [DeckSaveFormat.flat] worden de pakket-leden (`.md` plus
  /// assetmappen) los geüpload onder dezelfde prefix.
  ///
  /// Gooit [S3Exception] bij een netwerk-/auth-fout en [S3ConflictException]
  /// wanneer het object sinds ons ophalen is veranderd.
  Future<void> saveToS3(
    TabInfo tab,
    S3Service service, {
    required DeckSaveFormat format,
    required String targetPath,
    String connectionId = '',
    bool overwrite = false,
  }) async {
    final deck = tab.deckNotifier.currentState.deck;
    if (deck == null) return;
    // Alleen terugschrijven naar precies het object dat we ophaalden valt te
    // bewaken; voor elk ander doelpad hebben we geen versie om tegen te
    // toetsen, en koos de gebruiker het pad zelf.
    final origin = tab.s3Origin;
    final guard =
        (!overwrite &&
            origin != null &&
            origin.matchesBucket(service.bucket) &&
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
      for (final entry in members.entries) {
        // Het pakket-markdownbestand heet naar de deck-titel; geef het in de
        // bucket de naam die de gebruiker koos. Assets houden hun submap.
        final isRootMd =
            entry.key.toLowerCase().endsWith('.md') && !entry.key.contains('/');
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
    tab.s3Origin = S3Origin(
      // Een leeg id bij opslaan zou de herkomst van een geopend deck wissen;
      // val dan terug op wat er al stond.
      connectionId: connectionId.isEmpty
          ? (tab.s3Origin?.connectionId ?? '')
          : connectionId,
      endpoint: service.bucket.endpoint,
      bucket: service.bucket.bucket,
      remotePath: targetPath,
      // Vanaf nu is dít de versie waarop we verder werken. Gaf het endpoint er
      // geen, dan blijft het `null` en is de volgende opslag onbewaakt — dat is
      // zichtbaar zo, en niet een gok die stil de guard uitzet.
      etag: savedEtag,
    );
    refreshTabs();
  }
}
