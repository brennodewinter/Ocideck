// Part of the file_service library — see ../file_service.dart.
// Split out for navigability (URL/pakket/markdown-import); all imports live in
// the main library file. Instance methods relocate verbatim into an extension
// on FileService — same library, same members, no behaviour change.
part of '../file_service.dart';

extension FileServiceImport on FileService {
  /// Pak een pakket uit in een nieuwe submap onder [destParentDir]. Geeft het
  /// pad naar het uitgepakte markdown-bestand terug (om in een tab te openen).
  Future<String?> importPackageBytes(
    List<int> zipBytes,
    String destParentDir, {
    int maxBytes = FileService.maxPackageBytes,
  }) async => (await importPackageBytesDetailed(
    zipBytes,
    destParentDir,
    maxBytes: maxBytes,
  )).mdPath;

  /// Als [importPackageBytes], maar met de weiger-reden zodat de UI kan
  /// uitleggen wát er mis was (te groot, kapot, geen deck, limiet) in plaats
  /// van een generiek "kon niet importeren".
  Future<ImportOutcome> importPackageBytesDetailed(
    List<int> zipBytes,
    String destParentDir, {
    int maxBytes = FileService.maxPackageBytes,
  }) async {
    if (zipBytes.length > maxBytes) {
      return const ImportOutcome.failed(ImportFailure.tooLarge);
    }

    final Archive archive;
    try {
      archive = ZipDecoder().decodeBytes(zipBytes);
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

    // Kies de markdown met het ondiepste pad (de hoofd-md van het pakket).
    ArchiveFile? mdEntry;
    for (final f in archive.files) {
      if (!f.isFile || !f.name.toLowerCase().endsWith('.md')) continue;
      if (mdEntry == null ||
          '/'.allMatches(f.name).length < '/'.allMatches(mdEntry.name).length) {
        mdEntry = f;
      }
    }
    if (mdEntry == null) {
      return const ImportOutcome.failed(ImportFailure.unsupported);
    }

    final folderName = p.basenameWithoutExtension(mdEntry.name);
    final destDir = _uniqueDir(destParentDir, folderName);
    await destDir.create(recursive: true);

    // Een afgebroken extractie laat geen half uitgepakte map achter: die zou
    // stil schijfruimte opsnoepen en bij een zip-bomb juist het doelwit zijn.
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

    var extracted = 0;
    for (final f in archive.files) {
      if (!f.isFile) continue;
      if (f.name.length > FileService.maxZipEntryPathLength) continue;
      final outPath = safeOutPath(f.name);
      if (outPath == null) continue; // skip path-traversal entries
      // Cheap early reject on the *declared* uncompressed size (a zip bomb can
      // understate this, so it is only a fast path, not the real guard).
      if (f.size < 0 || extracted + f.size > maxBytes) {
        logWarning(
          'FileService.importPackageBytes: decompressed size exceeds limit',
        );
        return abortAndClean(ImportFailure.limitExceeded);
      }
      // Inflate into a capped stream that aborts the moment the entry exceeds
      // the remaining budget. This bounds peak memory per entry: unlike
      // `f.content` (which decodes the whole entry into memory before we can
      // check its size), the underlying inflater writes incrementally, so a
      // deflate bomb that understated its header size is stopped mid-inflation.
      final remaining = maxBytes - extracted;
      final capped = _CappedOutputStream(remaining);
      final List<int> content;
      try {
        f.writeContent(capped);
        content = capped.getBytes();
      } on _ExtractionLimitException {
        logWarning(
          'FileService.importPackageBytes: entry exceeds decompression limit '
          '(possible zip bomb): ${f.name}',
        );
        return abortAndClean(ImportFailure.limitExceeded);
      } catch (e) {
        // Decompressing a corrupt entry can throw; skip it instead of aborting.
        logWarning(
          'FileService.importPackageBytes: unreadable entry skipped (${f.name})',
          e,
        );
        continue;
      }
      extracted += content.length;
      final out = File(outPath);
      await out.parent.create(recursive: true);
      await out.writeAsBytes(content, flush: true);
    }

    // The main markdown must itself resolve inside the extraction folder.
    final mdPath = safeOutPath(mdEntry.name);
    if (mdPath == null) return abortAndClean(ImportFailure.unsupported);
    return ImportOutcome.ok(mdPath);
  }

  Directory _uniqueDir(String parent, String name) {
    var dir = Directory(p.join(parent, name));
    var i = 2;
    while (dir.existsSync()) {
      dir = Directory(p.join(parent, '$name ($i)'));
      i++;
    }
    return dir;
  }

  /// Download een presentatie vanaf [url]. Een zip-pakket wordt uitgepakt;
  /// platte markdown wordt als losse `.md` opgeslagen. Geeft het pad naar het
  /// markdown-bestand terug.

  /// SSRF host/address guards live in [NetGuard] so the URL-import path and the
  /// live remote-media path share exactly the same rules.
  static bool _isBlockedHost(String host) => NetGuard.isBlockedHost(host);

  static Future<List<InternetAddress>?> _safeResolve(String host) =>
      NetGuard.safeResolve(host);

  Future<String?> importFromUrl(String url, String destParentDir) async =>
      (await importFromUrlDetailed(url, destParentDir)).mdPath;

  /// Als [importFromUrl], maar met de weiger-reden voor een gerichte melding.
  Future<ImportOutcome> importFromUrlDetailed(
    String url,
    String destParentDir,
  ) async {
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
            Socket.startConnect(pinned, u.port);
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

    // Zip-magie 'PK\x03\x04' → pakket; anders als markdown behandelen.
    final isZip =
        bytes.length >= 4 &&
        bytes[0] == 0x50 &&
        bytes[1] == 0x4B &&
        bytes[2] == 0x03 &&
        bytes[3] == 0x04;
    if (isZip) {
      return importPackageBytesDetailed(bytes, destParentDir);
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
  /// melding (te groot, geen UTF-8, geen Marp-deck).
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
    final destDir = _uniqueDir(destParentDir, base);
    await destDir.create(recursive: true);
    final mdPath = p.join(destDir.path, '$base.md');
    await writeStringAtomic(File(mdPath), markdown);
    return ImportOutcome.ok(mdPath);
  }
}
