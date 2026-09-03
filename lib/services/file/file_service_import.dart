// Part of the file_service library — see ../file_service.dart.
// Split out for navigability (URL/pakket/markdown-import); all imports live in
// the main library file. De gedeelde decode-/hergebruik-infrastructuur
// (decodePackageEntries, _importDirCandidates, _dirMatchesEntries, _uniqueDir)
// leeft in het hoofdbestand; hier staat de import-API met weiger-redenen.
part of '../file_service.dart';

/// Waarom een import (URL, pakket, WebDAV) geen deck opleverde — voor een
/// gerichte melding in plaats van een generiek "kon niet importeren".
enum ImportFailure {
  /// Bestand of pakket is groter dan de toegestane limiet.
  tooLarge,

  /// ZIP of tekst is beschadigd/onleesbaar.
  corrupt,

  /// Wel opgehaald, maar geen Marp/OciDeck-presentatie.
  unsupported,

  /// Veiligheidslimiet geraakt (zip-bomb, te veel entries).
  limitExceeded,

  /// Ophalen mislukte op een manier die we niet fijner konden duiden: een
  /// time-out, een geweigerde verbinding, of een andere transportfout. De
  /// generieke terugval — de specifieke netwerk-oorzaken hieronder krijgen hun
  /// eigen reden zodat een beveiligingsweigering en een tikfout niet meer op
  /// dezelfde melding uitkomen.
  network,

  /// De hostnaam in de URL is niet op te zoeken (bestaat niet, of DNS zweeg).
  /// Eigen reden: het advies ("controleer op een typefout") is het
  /// tegenovergestelde van dat bij [blockedHost].
  unknownHost,

  /// De URL wijst naar een privé-, loopback- of LAN-adres en wordt om
  /// SSRF-redenen niet opgehaald — een veiligheidsweigering, geen storing, dus
  /// een eigen reden met een eigen uitleg.
  blockedHost,

  /// De URL gebruikt een ander schema dan http(s) (bv. `ftp:`/`file:`). Eigen
  /// reden zodat de melding "plak een http(s)-link" kan zeggen in plaats van een
  /// vage netwerkfout.
  insecureScheme,

  /// Het TLS-certificaat van de server werd niet vertrouwd — iets anders om op te
  /// lossen dan een onbereikbare server, dus een eigen reden.
  tls,

  /// De server stuurde een 3xx-omleiding. Die volgen we niet (dat zou de
  /// SSRF-hostcontrole omzeilen); een eigen reden vraagt het doeladres direct.
  redirect,

  /// De server antwoordde met 404 — op deze URL staat geen bestand. Eigen reden
  /// zodat een verkeerde link niet als algemene netwerkfout leest.
  notFound,

  /// Pakket is versleuteld maar er kon niet om een wachtwoord worden gevraagd
  /// (geen resolver geregistreerd — vooral in tests/headless).
  needsPassword,

  /// Pakket is versleuteld en de gebruiker brak de wachtwoordvraag af. Geen
  /// echte fout: de aanroeper toont hierbij géén foutmelding.
  encryptedCancelled,

  /// De doelschijf heeft onvoldoende ruimte voor de extractie.
  diskFull,

  /// De doelmap kon niet worden aangemaakt of beschreven — bijvoorbeeld een
  /// ingestelde thuismap op een niet-aangekoppeld of alleen-lezen volume. Zonder
  /// deze reden gooide het uitpakken een niet-gevangen `PathAccessException` die
  /// stil verdween: het bestand opende niet en er kwam geen melding.
  destinationUnavailable,
}

extension FileServiceImport on FileService {
  /// De meervoudige variant van [FileService.pickMarkdownFile]: dezelfde
  /// filterloze kiezer, maar de gebruiker mag een stapel bestanden tegelijk
  /// aanwijzen; elk opent daarna in een eigen tabblad (#1928). Levert een lege
  /// lijst bij annuleren en op web (zie [_pickPathsGated]).
  ///
  /// In deze extensie en niet in de klasse: [FileService] zit tegen zijn
  /// plafond, en kiezen hoort bij dit bestand.
  Future<List<String>> pickMarkdownFiles({String? initialDirectory}) {
    return _pickPathsGated(
      dialogTitle: _d('Presentaties openen'),
      type: FileType.any,
      initialDirectory: initialDirectory,
      allowsMultiple: true,
    );
  }

  /// Probeer een versleuteld pakket met [password] te ontgrendelen zonder het
  /// helemaal uit te pakken: de central directory lezen valideert de MAC nog
  /// niet, dus we decoderen de inhoud van één lid. Een onjuist wachtwoord laat
  /// de WinZip-AES-MAC falen (gooit) of levert onleesbare bytes — beide → false.
  ///
  /// Werkt op een kopie van [bytes]: de AES-ontsleuteling muteert de
  /// invoerbuffer, dus zonder kopie zou een latere echte decode van dezelfde
  /// bytes op beschadigde inhoud stuiten.
  bool canDecodePackage(List<int> bytes, String password) {
    try {
      final copy = Uint8List.fromList(bytes);
      final archive = ZipDecoder().decodeBytes(copy, password: password);
      final file = archive.files.firstWhere(
        (f) => f.isFile,
        orElse: () => throw StateError('leeg archief'),
      );
      // De content-getter ontsleutelt en controleert de MAC van dit lid.
      final _ = file.content;
      return true;
    } catch (e) {
      logWarning('FileService.canDecodePackage: ontgrendelen mislukt', e);
      return false;
    }
  }

  /// Pak een pakket uit in een submap onder [destParentDir]. Geeft het pad
  /// naar het uitgepakte markdown-bestand terug (om in een tab te openen).
  Future<String?> importPackageBytes(
    List<int> zipBytes,
    String destParentDir, {
    int maxBytes = FileService.maxPackageBytes,
    PackagePasswordResolver? onPassword,
  }) async => (await importPackageBytesDetailed(
    zipBytes,
    destParentDir,
    maxBytes: maxBytes,
    onPassword: onPassword,
  )).mdPath;

  /// Als [importPackageBytes], maar met de weiger-reden zodat de UI kan
  /// uitleggen wát er mis was (te groot, kapot, geen deck, limiet) in plaats
  /// van een generiek "kon niet importeren".
  ///
  /// Een eerdere import met exact dezelfde inhoud wordt hergebruikt in plaats
  /// van een nieuwe kopie-map "naam (n)" te maken: wie hetzelfde deck nogmaals
  /// opent (URL/WebDAV/zip) kreeg anders bij elke keer een extra kopie en dus
  /// dubbele vermeldingen in recente presentaties. Wijkt de inhoud af (lokaal
  /// bewerkt, of de bron is veranderd) dan blijft de kopie-map bestaan zodat
  /// er nooit iets wordt overschreven.
  Future<ImportOutcome> importPackageBytesDetailed(
    List<int> zipBytes,
    String destParentDir, {
    int maxBytes = FileService.maxPackageBytes,
    PackagePasswordResolver? onPassword,
  }) async {
    if (zipBytes.length > maxBytes) {
      return const ImportOutcome.failed(ImportFailure.tooLarge);
    }

    // Versleuteld pakket: vraag (met retry) het wachtwoord vóór elke decode.
    // Zonder resolver kan er niet gevraagd worden; de gebruiker kan afbreken.
    String? password;
    if (FileService.isEncryptedPackage(zipBytes)) {
      if (onPassword == null) {
        return const ImportOutcome.failed(ImportFailure.needsPassword);
      }
      // Vragen tot het lukt, maar nooit tweemaal om dezelfde zin.
      //
      // `canDecodePackage` faalt om twee heel verschillende redenen: een fout
      // wachtwoord, of een pakket waarvan de inhoud is aangetast — WinZip-AES
      // controleert een MAC, en die klopt niet meer na één omgeklapte byte.
      // Van buitenaf zien die twee er hetzelfde uit, dus werd een gemanipuleerd
      // pakket eindeloos als "verkeerd wachtwoord" gepresenteerd. Levert de
      // aanroeper dezelfde zin nóg eens, dan kán het niet meer aan het
      // wachtwoord liggen: dan is het pakket stuk, en dat hoort de gebruiker te
      // horen in plaats van een derde wachtwoordvenster.
      //
      // Dit was geen theoretisch geval: een niet-interactieve aanroeper die
      // altijd dezelfde zin teruggeeft — zoals de toets die precies dit gedrag
      // vastlegt — liet de lus voor onbepaalde tijd op één kern draaien.
      final geprobeerd = <String>{};
      var retry = false;
      while (true) {
        final pw = await onPassword(retry: retry);
        if (pw == null) {
          return const ImportOutcome.failed(ImportFailure.encryptedCancelled);
        }
        if (canDecodePackage(zipBytes, pw)) {
          password = pw;
          break;
        }
        if (!geprobeerd.add(pw)) {
          logWarning(
            'FileService.importPackageBytes: dezelfde zin faalde tweemaal — '
            'het pakket is vermoedelijk aangetast, niet het wachtwoord fout',
          );
          return const ImportOutcome.failed(ImportFailure.corrupt);
        }
        retry = true;
      }
    }

    // Alleen voor de weiger-reden: decodeBytes leest de zip-inhoudsopgave
    // (goedkoop, nog geen inflatie) zodat "kapot" en "te veel leden" een
    // eigen melding krijgen vóór de echte begrensde decode hieronder.
    final Archive archive;
    try {
      archive = ZipDecoder().decodeBytes(zipBytes, password: password);
    } catch (e, s) {
      logError('FileService.importPackageBytes: ZIP decode failed', e, s);
      return const ImportOutcome.failed(ImportFailure.corrupt);
    }
    if (archive.files.length > FileService.maxPackageEntries) {
      logWarning(
        'FileService.importPackageBytes: too many archive entries '
        '(${archive.files.length})',
      );
      return const ImportOutcome.failed(ImportFailure.limitExceeded);
    }

    // De echte verdediging: begrensde inflater die een zip-bom
    // mid-decompressie stopt (gedeeld met de in-memory web-open).
    final entries = decodePackageEntries(
      zipBytes,
      maxBytes: maxBytes,
      password: password,
    );
    if (entries == null) {
      return const ImportOutcome.failed(ImportFailure.limitExceeded);
    }
    final mdEntry = FileService.mainMarkdownEntry(entries);
    if (mdEntry == null) {
      return const ImportOutcome.failed(ImportFailure.unsupported);
    }

    final folderName = p.basenameWithoutExtension(mdEntry.name);
    for (final existing in _importDirCandidates(destParentDir, folderName)) {
      final resolvedMd = p.normalize(p.join(existing.path, mdEntry.name));
      if (!p.isWithin(existing.path, resolvedMd)) break;
      if (await _dirMatchesEntries(existing, entries)) {
        return ImportOutcome.ok(resolvedMd);
      }
    }
    final destDir = _uniqueDir(destParentDir, folderName);
    return _extractPackageToDir(destDir, entries, mdEntry);
  }

  /// SSRF host/address guards live in [NetGuard] so the URL-import path and the
  /// live remote-media path share exactly the same rules.
  static bool _isBlockedHost(String host) => NetGuard.isBlockedHost(host);

  /// Download een presentatie vanaf [url]. Een zip-pakket wordt uitgepakt;
  /// platte markdown wordt als losse `.md` opgeslagen. Geeft het pad naar het
  /// markdown-bestand terug.
  Future<String?> importFromUrl(
    String url,
    String destParentDir, {
    PackagePasswordResolver? onPassword,
  }) async => (await importFromUrlDetailed(
    url,
    destParentDir,
    onPassword: onPassword,
  )).mdPath;

  /// Als [importFromUrl], maar met de weiger-reden voor een gerichte melding.
  Future<ImportOutcome> importFromUrlDetailed(
    String url,
    String destParentDir, {
    PackagePasswordResolver? onPassword,
  }) async {
    final uri = Uri.tryParse(url.trim());
    if (uri == null || !uri.hasScheme) {
      // Onparseerbaar of zonder schema: geen bruikbare URL. De generieke reden
      // ("controleer de URL") past hier het best, en het invoervenster houdt
      // zo'n adres bovendien al tegen vóór het hier komt.
      return const ImportOutcome.failed(ImportFailure.network);
    }
    // Only fetch over web schemes, and never reach private/loopback hosts.
    final scheme = uri.scheme.toLowerCase();
    if (scheme != 'http' && scheme != 'https') {
      return const ImportOutcome.failed(ImportFailure.insecureScheme);
    }
    if (_isBlockedHost(uri.host)) {
      return const ImportOutcome.failed(ImportFailure.blockedHost);
    }
    // Resolve de hostnaam vooraf en weiger interne adressen. De rijke variant
    // ([NetGuard.resolveConfigured]) geeft de wéigeringsreden mee: een naam die
    // niet oplost (unknownHost) vraagt om ander advies dan een naam die naar een
    // intern adres wijst (blocked). `allowPrivate: false` — een import-URL is
    // nooit "vertrouwd intern"; dat weigert exact dezelfde hosts als voorheen,
    // nu alleen mét reden.
    final resolved = await NetGuard.resolveConfigured(
      uri.host,
      allowPrivate: false,
    );
    if (!resolved.isOk) {
      return ImportOutcome.failed(switch (resolved.refusal!) {
        HostRefusal.unknownHost => ImportFailure.unknownHost,
        HostRefusal.blocked => ImportFailure.blockedHost,
      });
    }
    final pinned = resolved.addresses!.first;

    final List<int> bytes;
    try {
      final client = buildPinnedClient(pinned);
      try {
        final request = await client.getUrl(uri);
        // Don't auto-follow redirects: a 3xx could point at a private host and
        // bypass the SSRF check above.
        request.followRedirects = false;
        final response = await request.close().timeout(
          const Duration(seconds: 30),
        );
        if (response.statusCode != 200) {
          // 404 → niet gevonden, 3xx → een omleiding die we niet volgen, de rest
          // (401/403/5xx) → generieke netwerkfout. Zie [_classifyUrlImportStatus].
          return ImportOutcome.failed(
            _classifyUrlImportStatus(response.statusCode),
          );
        }
        if (response.contentLength > FileService.maxPackageBytes) {
          return const ImportOutcome.failed(ImportFailure.tooLarge);
        }
        final builder = BytesBuilder(copy: false);
        await for (final chunk in response) {
          builder.add(chunk);
          if (builder.length > FileService.maxPackageBytes) {
            return const ImportOutcome.failed(ImportFailure.tooLarge);
          }
        }
        bytes = builder.takeBytes();
      } finally {
        client.close(force: true);
      }
    } catch (e) {
      // Een afgewezen/onvertrouwd certificaat verdient een eigen melding in
      // plaats van te verdwijnen in de generieke netwerkfout; de rest (time-out,
      // geweigerd, weggevallen) blijft network. Zelfde indeling als de
      // opslagtransports via [classifyTransportFailure].
      final kind = classifyTransportFailure(e);
      logTransportFailure('FileService.importFromUrl', kind, e);
      return ImportOutcome.failed(
        kind == TransportFailure.tls
            ? ImportFailure.tls
            : ImportFailure.network,
      );
    }

    // Zip-magie → pakket; anders als markdown behandelen.
    if (FileService.looksLikeZipBytes(bytes)) {
      return importPackageBytesDetailed(
        bytes,
        destParentDir,
        onPassword: onPassword,
      );
    }

    // Platte markdown.
    return importMarkdownBytesDetailed(bytes, destParentDir, uri.path);
  }

  /// Sla losse markdown-bytes op als zelfstandig deck in een nieuwe submap van
  /// [destParentDir] en geef het pad naar het `.md`-bestand terug. Weigert
  /// inhoud die niet op een Marp-deck lijkt of niet als UTF-8 te lezen is.
  /// Gedeeld door de URL-import en de WebDAV-bron.
  Future<String?> importMarkdownBytes(
    List<int> bytes,
    String destParentDir,
    String suggestedName,
  ) async => (await importMarkdownBytesDetailed(
    bytes,
    destParentDir,
    suggestedName,
  )).mdPath;

  /// Als [importMarkdownBytes], maar met de weiger-reden voor een gerichte
  /// melding (te groot, geen UTF-8, geen Marp-deck). Net als bij
  /// [importPackageBytesDetailed] wordt een eerdere import met identieke
  /// markdown hergebruikt, zodat hetzelfde deck nogmaals openen geen
  /// kopie-map en geen dubbele vermelding in recente presentaties oplevert.
  Future<ImportOutcome> importMarkdownBytesDetailed(
    List<int> bytes,
    String destParentDir,
    String suggestedName,
  ) async {
    if (bytes.length > FileService.maxDeckMarkdownBytes) {
      return const ImportOutcome.failed(ImportFailure.tooLarge);
    }
    final String markdown;
    try {
      markdown = utf8.decode(bytes);
    } catch (e, s) {
      logError('FileService.importMarkdownBytes: UTF-8 decode failed', e, s);
      return const ImportOutcome.failed(ImportFailure.corrupt);
    }
    if (!markdown.contains('marp') && !markdown.contains('---')) {
      return const ImportOutcome.failed(ImportFailure.unsupported);
    }

    var base = p.basenameWithoutExtension(suggestedName);
    if (base.isEmpty) base = 'presentatie';
    // Vergelijk als bytes zoals writeStringAtomic ze schreef (utf8), zodat
    // een niet-UTF-8-bestand in een kandidaatmap gewoon "anders" is in
    // plaats van een decodeerfout.
    final encoded = utf8.encode(markdown);
    for (final existing in _importDirCandidates(destParentDir, base)) {
      final existingMd = File(p.join(existing.path, '$base.md'));
      if (!existingMd.existsSync()) continue;
      if (await _fileHasBytes(existingMd, encoded)) {
        return ImportOutcome.ok(existingMd.path);
      }
    }
    final destDir = _uniqueDir(destParentDir, base);
    return _writeFlatMarkdownDeck(destDir, base, markdown);
  }
}

/// Schrijft [markdown] als `<base>.md` in de (nieuwe) [destDir] en geeft het pad
/// terug — of een weiger-reden bij een schrijffout, waarna een half aangemaakte
/// map weer wordt opgeruimd. Buiten [FileService] om dezelfde reden als
/// [_extractPackageToDir]: geen veldtoegang, en de klasse zit tegen haar plafond.
Future<ImportOutcome> _writeFlatMarkdownDeck(
  Directory destDir,
  String base,
  String markdown,
) async {
  final mdPath = p.join(destDir.path, '$base.md');
  try {
    await destDir.create(recursive: true);
    await writeStringAtomic(File(mdPath), markdown);
  } on FileSystemException catch (e, s) {
    // Zelfde vangnet als de pakket-tak: een ingestelde thuismap op een
    // niet-aangekoppeld of alleen-lezen volume laat create/write falen. Zonder
    // deze vangst ontsnapte een PathAccessException stil (WebDAV/S3/URL openen
    // een platte `.md` langs deze weg). Ruim een half aangemaakte map op.
    final failure = _classifyWriteFailure(e);
    logError(
      'FileService.importMarkdownBytes: kan doelmap niet aanmaken/schrijven '
      '($failure)',
      e,
      s,
    );
    try {
      if (await destDir.exists()) await destDir.delete(recursive: true);
    } catch (cleanupError) {
      logWarning(
        'FileService.importMarkdownBytes: opruimen na schrijffout mislukt',
        cleanupError,
      );
    }
    return ImportOutcome.failed(failure);
  }
  return ImportOutcome.ok(mdPath);
}

/// Pakt de gedecodeerde [entries] uit in [destDir] (elk lid zip-slip-veilig) en
/// geeft het pad naar [mdEntry] terug — of een weiger-reden bij een schrijffout,
/// waarna de half uitgepakte map weer wordt opgeruimd. Buiten [FileService]: het
/// raakt geen enkel veld van de service, en de klasse zit tegen haar plafond.
Future<ImportOutcome> _extractPackageToDir(
  Directory destDir,
  List<PackageEntry> entries,
  PackageEntry mdEntry,
) async {
  try {
    await destDir.create(recursive: true);
  } on FileSystemException catch (e, s) {
    // De doelmap zelf kon niet worden aangemaakt — bijvoorbeeld een ingestelde
    // thuismap op een niet-aangekoppeld of alleen-lezen volume. Zonder deze
    // vangst gooide dit een niet-gevangen PathAccessException die stil verdween
    // (het bestand opende niet, geen melding). Nu een gerichte weiger-reden
    // zodat de aanroeper kan terugvallen of het duidelijk kan melden.
    final failure = _classifyWriteFailure(e);
    logError(
      'FileService.importPackageBytes: kan doelmap niet aanmaken ($failure)',
      e,
      s,
    );
    return ImportOutcome.failed(failure);
  }

  // Een afgebroken extractie laat geen half uitgepakte map achter: die zou
  // stil schijfruimte opsnoepen en verweesde kopie-mappen achterlaten.
  Future<ImportOutcome> abortAndClean(ImportFailure failure) async {
    try {
      await destDir.delete(recursive: true);
    } catch (e) {
      logWarning(
        'FileService.importPackageBytes: partial extract cleanup failed',
        e,
      );
    }
    return ImportOutcome.failed(failure);
  }

  // Resolve an archive entry name to a path strictly inside [destDir], or
  // null when it would escape (zip-slip: `../`, absolute paths, …).
  String? safeOutPath(String entryName) {
    final resolved = p.normalize(p.join(destDir.path, entryName));
    if (resolved != destDir.path && !p.isWithin(destDir.path, resolved)) {
      return null;
    }
    return resolved;
  }

  for (final entry in entries) {
    final outPath = safeOutPath(entry.name);
    if (outPath == null) continue; // skip path-traversal entries
    final out = File(outPath);
    try {
      // Ook de submap-aanmaak binnen de try: een volume dat tijdens het
      // uitpakken wegvalt laat ook `create` falen, niet alleen de schrijf.
      await out.parent.create(recursive: true);
      await writeBytesAtomic(out, entry.bytes);
    } on FileSystemException catch (e) {
      // Een volle schijf (diskFull) of een onbereikbaar/alleen-lezen doel
      // (destinationUnavailable) — beide zouden anders als niet-gevangen
      // exception stil verdwijnen. Ruim de half uitgepakte map op en meld het.
      final failure = _classifyWriteFailure(e);
      logWarning(
        'FileService.importPackageBytes: schrijffout tijdens extractie ($failure)',
        e,
      );
      return abortAndClean(failure);
    }
  }

  // The main markdown must itself resolve inside the extraction folder.
  final mdPath = safeOutPath(mdEntry.name);
  if (mdPath == null) return abortAndClean(ImportFailure.unsupported);
  return ImportOutcome.ok(mdPath);
}

/// Vertaalt een schrijffout tijdens extractie naar een gerichte weiger-reden:
/// een volle schijf ([ImportFailure.diskFull]) of een onbereikbaar/alleen-lezen
/// doel ([ImportFailure.destinationUnavailable]) — bijvoorbeeld een ingestelde
/// thuismap op een niet-aangekoppeld volume. Zonder deze vertaling zou een
/// [FileSystemException] als niet-gevangen exception stil verdwijnen: het
/// bestand opende niet en er kwam geen melding. Gedeeld door de pakket- en de
/// platte-markdown-tak zodat beide dezelfde reden geven.
ImportFailure _classifyWriteFailure(FileSystemException e) {
  final msg = e.toString().toLowerCase();
  if (msg.contains('no space left') ||
      msg.contains('disk full') ||
      msg.contains('enospc')) {
    return ImportFailure.diskFull;
  }
  return ImportFailure.destinationUnavailable;
}

/// Vertaalt een niet-200 HTTP-status bij de URL-import naar een weiger-reden.
/// 404 is "staat er niet" ([ImportFailure.notFound]); een 3xx is een omleiding
/// die we niet volgen ([ImportFailure.redirect] — `followRedirects=false` houdt
/// een 3xx weg van de SSRF-controle); al het andere — 401/403/5xx — valt onder
/// de generieke [ImportFailure.network], want een presentatie-URL hoort publiek
/// leesbaar te zijn en 403 is te dubbelzinnig om apart te benoemen. Gedeeld door
/// de desktop-import en de web-fetch ([FileServiceNet._fetchCapped]).
ImportFailure _classifyUrlImportStatus(int status) {
  if (status == 404) return ImportFailure.notFound;
  if (status >= 300 && status < 400) return ImportFailure.redirect;
  return ImportFailure.network;
}

// ── De bestandskiezers ──────────────────────────────────────────────────────
//
// Top-level en niet in de klasse: ze raken geen enkel veld van FileService, en
// de klasse zit tegen zijn plafond. Ze wonen hier omdat kiezen het begin van
// importeren is.

/// Kies een bestand en lever het PAD — of null wanneer dit platform er geen
/// heeft.
///
/// Buiten de klasse: dit raakt geen enkel veld van [FileService], en de poort
/// hoort één keer te staan in plaats van bij elke kiezer opnieuw.
///
/// Op web is die poort geen nettigheid maar noodzaak: `PlatformFile.path`
/// GOOIT daar een kale String (file_picker 5.5.0, platform_file.dart) in plaats
/// van null terug te geven. Wie een pad nodig heeft op web, heeft in werkelijk-
/// heid bytes nodig — zie [FileService.pickDeckFileBytes].
Future<String?> _pickPathGated({
  required String dialogTitle,
  required FileType type,
  List<String>? allowedExtensions,
  String? initialDirectory,
}) async {
  final picked = await _pickPathsGated(
    dialogTitle: dialogTitle,
    type: type,
    allowedExtensions: allowedExtensions,
    initialDirectory: initialDirectory,
  );
  return picked.isEmpty ? null : picked.first;
}

/// De meervoudige variant van [_pickPathGated]: dezelfde poort en dezelfde
/// macOS-omweg, maar de gebruiker mag met [allowsMultiple] een stapel
/// bestanden tegelijk aanwijzen. Levert een lege lijst bij annuleren en op elk
/// platform zonder bestandssysteem.
Future<List<String>> _pickPathsGated({
  required String dialogTitle,
  required FileType type,
  List<String>? allowedExtensions,
  String? initialDirectory,
  bool allowsMultiple = false,
}) async {
  if (!supportsLocalProjectFolders) return const [];
  // macOS + geen extensiefilter: eigen NSOpenPanel die allowedContentTypes
  // expliciet leegzet. file_picker's FileType.any zet géén filter, en dan kan
  // macOS een onthouden filter laten staan waardoor .md grijs wordt (# openen).
  // Validatie van de gekozen bytes blijft bij de aanroeper (openDeck / router).
  if (!kIsWeb &&
      Platform.isMacOS &&
      type == FileType.any &&
      (allowedExtensions == null || allowedExtensions.isEmpty)) {
    try {
      // Leeg = gebruiker annuleerde — níet doorvallen naar file_picker, anders
      // opent er een tweede kiezer die .md wél weer grijst.
      return await pickUnfilteredMacFiles(
        dialogTitle: dialogTitle,
        initialDirectory: initialDirectory,
        allowsMultiple: allowsMultiple,
      );
    } on MissingPluginException {
      // Oude build zonder native handler: val terug op file_picker.
    }
  }
  if (!allowsMultiple) {
    final file = await FilePicker.pickFile(
      dialogTitle: dialogTitle,
      type: type,
      allowedExtensions: allowedExtensions,
      initialDirectory: initialDirectory,
    );
    final path = file?.path;
    return path == null ? const [] : [path];
  }
  final files = await FilePicker.pickFiles(
    dialogTitle: dialogTitle,
    type: type,
    allowedExtensions: allowedExtensions,
    initialDirectory: initialDirectory,
  );
  return [for (final file in files) ?file.path];
}

/// Kies een bestand en lever NAAM + BYTES. Werkt overal, ook op web — dit is de
/// tegenhanger van [_pickPathGated] voor het pad dat daar niet bestaat.
Future<({String name, Uint8List bytes})?> _pickBytes({
  required String dialogTitle,
}) async {
  final file = await FilePicker.pickFile(
    dialogTitle: dialogTitle,
    type: FileType.any,
  );
  if (file == null) return null;
  return (name: file.name, bytes: await file.readAsBytes());
}
