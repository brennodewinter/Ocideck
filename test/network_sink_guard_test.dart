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
///
/// Per-file granularity has one blind spot, and the last test here closes it:
/// once a file is on the allowlist, a SECOND client inside that same file slips
/// through unnoticed — including one nobody pinned. The allowlist proves "this
/// file knows about the gate", not "every client in this file goes through it".
/// So the number of `HttpClient(` constructions per allowlisted file is itself
/// a ratchet; see [pinnedClientCount].
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

  /// Hoeveel `HttpClient(`-constructies elk toegelaten bestand mag hebben.
  ///
  /// De allowlist hierboven werkt per BESTAND, en dat is precies zijn zwakke
  /// plek: zodra `webdav_service.dart` erop staat, glipt een TWEEDE client in
  /// datzelfde bestand er ongezien langs — ook een die niemand gepind heeft. De
  /// allowlist bewijst dan nog steeds "dit bestand kent de poort", maar niet
  /// meer "élke client in dit bestand gaat erdoor".
  ///
  /// Statisch bewijzen dát een instantie een `connectionFactory` krijgt lukt
  /// niet: `local_cve_database_io.dart` construeert de client in `getJson` en
  /// pint hem pas in `_get`, twee methodes verderop, en dat is legitiem. Wat wél
  /// te bewijzen valt is dat het AANTAL niet stilletjes groeit. Een nieuwe
  /// client in een bestaand bestand dwingt zo een bewuste bijstelling hier, met
  /// de reden erbij — dezelfde ratchet-vorm die `check_conventions.dart` elders
  /// gebruikt.
  const pinnedClientCount = <String, int>{
    // net_guard.dart staat wél op de allowlist hierboven maar construeert zelf
    // geen client — het levert de `connectionFactory` die de andere gebruiken.
    'lib/utils/net_guard.dart': 0,
    'lib/services/parts/file_service_import.dart': 1,
    'lib/services/webdav_service.dart': 1,
    'lib/services/s3/s3_service.dart': 1,
    'lib/services/ai_client_service.dart': 1,
    'lib/services/cve_transport_io.dart': 1,
    // Twee: `getJson` en `download` openen elk hun eigen client, en beide laten
    // hem door `_get` pinnen — één keer per redirect-hop.
    'lib/services/cve/local_cve_database_io.dart': 2,
    'lib/services/git/git_transport_io.dart': 1,
  };

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
        // S3: safeResolveTrusted met de trustedInternal-opt-in van de bucket +
        // socket-pin + geen redirects + caps. Gepind wordt op de host die we
        // écht bellen — bij virtual-hosted adressering zit de bucketnaam
        // daarin, dus die naam wordt geresolved, niet het kale endpoint.
        'lib/services/s3/s3_service.dart',
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
        // Git-forge (desktop): safeResolveTrusted met de trustedInternal-opt-in
        // van de repo + socket-pin + geen redirects + cap. De pin wordt één keer
        // gelegd en hergebruikt; een URI buiten de geconfigureerde origin wordt
        // geweigerd, zodat de gepinde client nooit op een andere host uitkomt.
        'lib/services/git/git_transport_io.dart',
      },
      guidance:
          'New raw HttpClient. Resolve the host through NetGuard.safeResolve '
          '(or safeResolveTrusted) and pin the socket to the returned address, '
          'then add the file to the allowlist:',
    );
  });

  test('an allowlisted file does not quietly gain an extra HttpClient', () {
    final sink = RegExp(r'HttpClient\(');
    final actual = <String, int>{};
    for (final file in dartFiles()) {
      var count = 0;
      for (final line in file.readAsLinesSync()) {
        if (line.trimLeft().startsWith('//')) continue;
        count += sink.allMatches(line).length;
      }
      if (count > 0) actual[rel(file)] = count;
    }

    // Alleen de toegelaten bestanden: een client in een ander bestand is al de
    // vorige test, en die geeft een betere foutmelding.
    final tracked = {
      for (final e in actual.entries)
        if (pinnedClientCount.containsKey(e.key)) e.key: e.value,
    };
    final expected = {
      for (final e in pinnedClientCount.entries)
        if (e.value > 0) e.key: e.value,
    };

    expect(
      tracked,
      expected,
      reason:
          'Het aantal HttpClient-constructies in een toegelaten bestand is '
          'veranderd. De allowlist bewijst alleen dat het bestand de poort '
          'kent, niet dat élke client erdoor gaat — dus moet een extra client '
          'hier bewust bijgesteld worden, met de reden dat ook hij door '
          'NetGuard.safeResolve(Trusted) + connectPinned gaat. Is er juist een '
          'client verdwenen, verlaag het getal dan om de winst vast te zetten.',
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
        // Git-forge (WEB-tak). Zelfde redenering als file_service_net.dart
        // hierboven: op web bestaat de dart:io-pinning van git_transport_io.dart
        // niet en kan ze er ook niet draaien — daar zijn de browser-sandbox en
        // de pagina-CSP (`connect-src`) de gate. Lokaal begrenst dit bestand
        // schema (https, of http alleen bij een bewust vertrouwde interne
        // server) en omvang (harde bytecap). Bovendien: een verzoek mét token
        // gaat nooit door het same-origin fetch-hulppunt, zodat dat punt het
        // PAT nooit in handen krijgt.
        'lib/services/git/git_transport_web.dart',
      },
      guidance:
          'New network egress primitive (package:http, dio, or a raw socket). '
          'Route the URL through NetGuard — safeResolve(Trusted) + socket '
          'pinning for dart:io, or document why the platform itself is the gate '
          '— then add the file to the allowlist:',
    );
  });
}
