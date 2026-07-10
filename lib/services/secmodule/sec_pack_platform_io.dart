// Desktop/mobile (dart:io) implementation of the module-pack platform layer:
// the SSRF-hardened network transport and the app-support cache store.
import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../utils/atomic_file.dart';
import '../../utils/log.dart';
import '../../utils/net_guard.dart';
import 'sec_module_provisioner.dart';
import 'sec_pack_codec.dart';

/// Whether this platform can provision the pack over the network. True off web.
const bool secModuleCanProvision = true;

SecPackTransport createSecPackTransport() => const NetGuardSecPackTransport();

SecPackStore createSecPackStore() => FileSecPackStore();

/// Fetches a pack over `http(s)` reusing the same SSRF hardening as the URL
/// import: the host is resolved up front and internal addresses are refused,
/// the socket is pinned to the validated address (DNS-rebind safe), redirects
/// are not auto-followed, and the body is byte-capped. Never throws — a failure
/// comes back as a non-ok result so the provisioner can try the next mirror.
class NetGuardSecPackTransport implements SecPackTransport {
  const NetGuardSecPackTransport();

  @override
  Future<SecPackFetchResult> fetch(Uri url, {required int maxBytes}) async {
    final scheme = url.scheme.toLowerCase();
    if (scheme != 'http' && scheme != 'https') {
      return const SecPackFetchResult.failed();
    }
    if (NetGuard.isBlockedHost(url.host)) {
      return const SecPackFetchResult.failed();
    }
    final safeAddrs = await NetGuard.safeResolve(url.host);
    if (safeAddrs == null) return const SecPackFetchResult.failed();
    final pinned = safeAddrs.first;

    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 15)
      ..connectionFactory = (u, proxyHost, proxyPort) =>
          Socket.startConnect(pinned, u.port);
    try {
      final request = await client.getUrl(url);
      request.followRedirects = false;
      final response = await request.close().timeout(
        const Duration(seconds: 60),
      );
      if (response.statusCode != 200) return const SecPackFetchResult.failed();
      if (response.contentLength > maxBytes) {
        return const SecPackFetchResult.failed();
      }
      final builder = BytesBuilder(copy: false);
      await for (final chunk in response) {
        builder.add(chunk);
        if (builder.length > maxBytes) return const SecPackFetchResult.failed();
      }
      return SecPackFetchResult.ok(builder.takeBytes());
    } catch (e) {
      logWarning('NetGuardSecPackTransport: fetch mislukt', e);
      return const SecPackFetchResult.failed();
    } finally {
      client.close(force: true);
    }
  }
}

/// Caches the unpacked pack under `<app-support>/secmodule/<version>/`, with a
/// `_pack_meta.json` marker recording the verified outer hash so a later launch
/// can confirm the cache without re-fetching. Writes go through the atomic-file
/// helpers.
class FileSecPackStore implements SecPackStore {
  Directory? _baseDir;

  static const _metaName = '_pack_meta.json';

  Future<Directory> _base() async {
    return _baseDir ??= Directory(
      p.join((await getApplicationSupportDirectory()).path, 'secmodule'),
    );
  }

  Future<Directory> _versionDir(String version) async {
    return Directory(p.join((await _base()).path, _safeSegment(version)));
  }

  @override
  Future<String?> cachedVersion({
    required String version,
    required String expectedHash,
  }) async {
    try {
      final meta = File(p.join((await _versionDir(version)).path, _metaName));
      if (!await meta.exists()) return null;
      final line = await meta.readAsString();
      // Marker format: `<version>\n<outerHash>` — plain, no JSON parser needed.
      final parts = line.split('\n');
      if (parts.length < 2) return null;
      if (parts[0].trim() != version) return null;
      if (parts[1].trim() != expectedHash) return null;
      return version;
    } catch (e) {
      logWarning('FileSecPackStore: cache-controle mislukt', e);
      return null;
    }
  }

  @override
  Future<void> save({
    required String version,
    required String outerHash,
    required SecPackContents contents,
  }) async {
    final dir = await _versionDir(version);
    // Replace any partial/previous cache for this version atomically enough:
    // clear the dir, write files, then write the meta marker LAST so a crash
    // mid-write never leaves a marker claiming a complete cache.
    if (await dir.exists()) await dir.delete(recursive: true);
    await dir.create(recursive: true);
    for (final entry in contents.files.entries) {
      final out = _safeOutFile(dir, entry.key);
      if (out == null) continue; // defence in depth vs. zip-slip names
      await out.parent.create(recursive: true);
      await writeBytesAtomic(out, entry.value);
    }
    final meta = File(p.join(dir.path, _metaName));
    await writeStringAtomic(meta, '$version\n$outerHash');
  }

  @override
  Future<void> clear() async {
    try {
      final base = await _base();
      if (await base.exists()) await base.delete(recursive: true);
    } catch (e) {
      logWarning('FileSecPackStore: opschonen mislukt', e);
    }
  }

  /// Resolve [name] to a file strictly inside [dir], or null when it would
  /// escape (absolute paths, `..`).
  File? _safeOutFile(Directory dir, String name) {
    final resolved = p.normalize(p.join(dir.path, name));
    if (resolved != dir.path && !p.isWithin(dir.path, resolved)) return null;
    return File(resolved);
  }

  /// A version string is app-controlled, but keep the cache dir name a single
  /// safe path segment regardless.
  String _safeSegment(String version) =>
      version.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
}
