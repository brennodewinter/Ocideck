// Part of the file_service library — see ../file_service.dart.
// Split out for navigability (URL/pakket/markdown-import); all imports live in
// the main library file. De gedeelde decode-/hergebruik-infrastructuur
// (decodePackageEntries, _importDirCandidates, _dirMatchesEntries, _uniqueDir)
// leeft in het hoofdbestand; hier staat de import-API met weiger-redenen.
part of '../file_service.dart';

extension FileServiceImport on FileService {
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
    await destDir.create(recursive: true);

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
      await out.parent.create(recursive: true);
      await writeBytesAtomic(out, entry.bytes);
    }

    // The main markdown must itself resolve inside the extraction folder.
    final mdPath = safeOutPath(mdEntry.name);
    if (mdPath == null) return abortAndClean(ImportFailure.unsupported);
    return ImportOutcome.ok(mdPath);
  }

  /// SSRF host/address guards live in [NetGuard] so the URL-import path and the
  /// live remote-media path share exactly the same rules.
  static bool _isBlockedHost(String host) => NetGuard.isBlockedHost(host);

  static Future<List<InternetAddress>?> _safeResolve(String host) =>
      NetGuard.safeResolve(host);

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
      return const ImportOutcome.failed(ImportFailure.network);
    }
    // Only fetch over web schemes, and never reach private/loopback hosts.
    final scheme = uri.scheme.toLowerCase();
    if (scheme != 'http' && scheme != 'https') {
      return const ImportOutcome.failed(ImportFailure.network);
    }
    if (_isBlockedHost(uri.host)) {
      return const ImportOutcome.failed(ImportFailure.network);
    }
    // Resolve the hostname up front and reject internal addresses.
    final safeAddrs = await _safeResolve(uri.host);
    if (safeAddrs == null) {
      return const ImportOutcome.failed(ImportFailure.network);
    }
    final pinned = safeAddrs.first;

    final List<int> bytes;
    try {
      final client = HttpClient()
        ..connectionTimeout = const Duration(seconds: 15)
        // Pin the socket to the validated address so a DNS rebind between the
        // check above and the actual connect can't point us at an internal IP.
        // TLS (for https) still validates against the original hostname.
        ..connectionFactory = (u, proxyHost, proxyPort) =>
            NetGuard.connectPinned(pinned, u);
      try {
        final request = await client.getUrl(uri);
        // Don't auto-follow redirects: a 3xx could point at a private host and
        // bypass the SSRF check above.
        request.followRedirects = false;
        final response = await request.close().timeout(
          const Duration(seconds: 30),
        );
        if (response.statusCode != 200) {
          return const ImportOutcome.failed(ImportFailure.network);
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
      logError('FileService.importFromUrl: download failed', e);
      return const ImportOutcome.failed(ImportFailure.network);
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
    await destDir.create(recursive: true);
    final mdPath = p.join(destDir.path, '$base.md');
    await writeStringAtomic(File(mdPath), markdown);
    return ImportOutcome.ok(mdPath);
  }
}
