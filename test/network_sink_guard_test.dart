import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Source-scan guard (in the spirit of asset_path_guard_test.dart) against the
/// class of bug fixed in "Close SSRF on the live remote-media path": a network
/// sink that turns a (possibly deck-supplied) URL into a request without going
/// through `NetGuard`. New sinks must apply the guard:
///   * a deck-supplied media URL → `NetGuard.isAllowedMediaUrlResolved` before
///     `NetworkImage` / `VideoPlayerController.networkUrl`;
///   * a raw `HttpClient` → `NetGuard.safeResolve(Trusted)` + socket pinning;
///   * any OTHER egress primitive — `package:http`, `package:dio`, `Socket`,
///     `SecureSocket`, `WebSocket`, `RawDatagramSocket` — likewise.
///
/// That last group is why this file was widened. The guard used to scan for
/// `HttpClient(` alone, so its own promise ("a new raw client fails this test")
/// was false for every other way to open a socket: a `http.get(deckSuppliedUrl)`
/// added anywhere in lib/ passed every gate in the Makefile untouched. The
/// current code is sound — the desktop URL-import goes through the pinned
/// `importFromUrl`, and the one `package:http` caller is web-only — but nothing
/// *kept* it that way. Now it does.
///
/// The allowlist is by FILE (stable across line edits): these files already
/// apply the guard. A sink appearing in any *other* file fails this test —
/// forcing a conscious decision to route it through NetGuard rather than
/// silently reintroducing the hole.
void main() {
  Iterable<File> dartFiles() => Directory('lib')
      .listSync(recursive: true)
      .whereType<File>()
      .where((f) => f.path.endsWith('.dart'));

  String rel(File f) => f.path.replaceFirst(RegExp(r'^.*/lib/'), 'lib/');

  void scan({
    required RegExp sink,
    required Set<String> allowedFiles,
    required String guidance,
  }) {
    final offenders = <String>[];
    for (final file in dartFiles()) {
      if (allowedFiles.contains(rel(file))) continue;
      final lines = file.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        final line = lines[i];
        if (line.trimLeft().startsWith('//')) continue; // skip comments
        if (sink.hasMatch(line)) {
          offenders.add('${rel(file)}:${i + 1}  ${line.trim()}');
        }
      }
    }
    expect(offenders, isEmpty, reason: '$guidance\n${offenders.join('\n')}');
  }

  test('media fetch sinks stay behind the NetGuard resolve gate', () {
    scan(
      sink: RegExp(r'NetworkImage\(|\.networkUrl\(|Image\.network\('),
      allowedFiles: {
        'lib/utils/image_limits.dart', // cappedNetworkImage wrapper
        'lib/widgets/slides/previews/media_previews.dart', // gated callers
        // media_previews.dart was split for size; its gated image sink now
        // lives in this part of the same slide_preview library.
        'lib/widgets/slides/previews/media_previews_image.dart',
      },
      guidance:
          'New remote-media fetch sink. Gate the URL on '
          'NetGuard.isAllowedMediaUrlResolved before fetching, and add the file '
          'to the allowlist:',
    );
  });

  test('raw HttpClient use stays where the host is resolved and pinned', () {
    scan(
      sink: RegExp(r'HttpClient\('),
      allowedFiles: {
        'lib/utils/net_guard.dart',
        // importFromUrl: safeResolve + pin (import-part van file_service).
        'lib/services/parts/file_service_import.dart',
        'lib/services/webdav_service.dart', // safeResolveTrusted + pin
        // module provisioning fetch: NetGuard.safeResolve + socket pin + no-redirect.
        'lib/services/secmodule/sec_pack_platform_io.dart',
        // AI backend: resolves per AiResolveStrategy (loopback-direct for local
        // IPC, safeResolveTrusted for self-hosted, safeResolve for cloud) + pin.
        'lib/services/ai_client_service.dart',
        // CVE lookup: NetGuard.safeResolve + socket pin + no-redirect + cap.
        'lib/services/cve_transport_io.dart',
        // CVE-bulkdownload: NetGuard.safeResolve + socket pin per hop. Deze moet
        // redirects volgen (github.com → objects.githubusercontent.com), maar
        // doet dat zélf: elke sprong gaat opnieuw door de poort, zodat een 3xx
        // naar een intern adres niet alsnog opgehaald wordt.
        'lib/services/cve/local_cve_database_io.dart',
      },
      guidance:
          'New raw HttpClient. Resolve the host through NetGuard.safeResolve '
          '(or safeResolveTrusted) and pin the socket to the returned address, '
          'then add the file to the allowlist:',
    );
  });

  test('every other egress primitive stays behind the same gate', () {
    scan(
      sink: RegExp(
        // Package-level HTTP clients — the gap this test was widened to close.
        r'package:http/http\.dart'
        r'|package:dio/'
        r'|\bhttp\.(Client|get|post|put|patch|delete|head|read|readBytes)\('
        // Raw sockets: an SSRF path that never touches an HTTP client at all.
        r'|\b(Socket|SecureSocket|WebSocket|RawDatagramSocket)\.(connect|bind)\(',
      ),
      allowedFiles: {
        // Houdt de `package:http`-import voor de part-bibliotheek eronder.
        'lib/services/file_service.dart',
        // fetchUrlBytes: de WEB-tak van de URL-import, en alleen bereikbaar via
        // `if (isWebPlatform)` in widgets/shell/shell_actions.dart. Op web
        // bestaat de dart:io-pinning van importFromUrl niet en kan ze ook niet
        // draaien: daar zijn de browser (CORS, mixed content) en de pagina-CSP
        // (`connect-src`) de gate. Lokaal begrenst dit bestand schema (http/s)
        // en omvang (harde bytecap). Op desktop loopt de import via het gepinde
        // importFromUrl, niet hierlangs.
        'lib/services/parts/file_service_net.dart',
      },
      guidance:
          'New network egress primitive (package:http, dio, or a raw socket). '
          'Route the URL through NetGuard — safeResolve(Trusted) + socket '
          'pinning for dart:io, or document why the platform itself is the gate '
          '— then add the file to the allowlist:',
    );
  });
}
