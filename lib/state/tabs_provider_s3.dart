part of 'tabs_provider.dart';

/// Het open- en opslaanpad van de S3-opslag. Apart bestand omdat
/// `tabs_provider` tegen de regelratchet aan zit; de extensie zit in dezelfde
/// library, dus de gedeelde security-poort blijft bereikbaar.
///
/// Spiegelt bewust `openFromWebdav`/`saveToWebdav`: een bucket is voor een deck
/// niet iets anders dan een map op een server, en waar het gedrag hetzelfde
/// hoort te zijn, is de code dat ook.
/// Het markdownbestand ín de wortel van het pakket — het deck zelf, en het enige
/// lid dat de conflictbewaking draagt.
bool _isRootMd(MapEntry<String, List<int>> entry) =>
    entry.key.toLowerCase().endsWith('.md') && !entry.key.contains('/');

/// Het pad van één pakket-lid naast een doelpad in de map [dir].
///
/// `p.posix.dirname` geeft `.` voor een doelpad zonder map, en `join('.', x)`
/// maakt daar `./x` van. Dat is geen pad dat iemand intikt: op S3 is de sleutel
/// waarnaar we uploaden dan anders gespeld dan de herkomst die we bewaren, en
/// op WebDAV probeert `_ensureParents` er een map `.` van te maken. Beide
/// kanten normaliseren het weg, dus er ging niets mis — maar wat over de lijn
/// gaat hoort te staan zoals de gebruiker het koos.
String _remoteMemberPath(String dir, String member) =>
    dir == '.' || dir.isEmpty ? member : p.posix.join(dir, member);

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
      // De reden vasthouden zodat de schil de specifieke melding toont i.p.v.
      // het generieke "Kon dit bestand niet openen." — zelfde mapping als de
      // lokale pakket-open.
      return _packageOpenResult(_ref, mounted, outcome.failure);
    }
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
      // Het markdownbestand eerst, en pas daarna de assets.
      //
      // Alleen de `.md` draagt de conflictbewaking; de assets gingen er
      // ongewapend overheen. In de oorspronkelijke volgorde stonden ze bovendien
      // vóóraan, dus bij een botsing waren andermans afbeeldingen al vervangen
      // tegen de tijd dat de `.md` met 412 werd geweigerd — en de melding
      // ("opslaan onder een andere naam?") wekte de indruk dat er niets was
      // aangeraakt. Andersom botst het vóórdat er iets aan de assets is gedaan.
      final ordered = [
        ...members.entries.where(_isRootMd),
        ...members.entries.where((e) => !_isRootMd(e)),
      ];
      for (final entry in ordered) {
        // Het pakket-markdownbestand heet naar de deck-titel; geef het in de
        // bucket de naam die de gebruiker koos. Assets houden hun submap.
        final isRootMd = _isRootMd(entry);
        final remote = _remoteMemberPath(dir, isRootMd ? mdBase : entry.key);
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
