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
/// Twee uitgangen kunnen die guard *niet* aan, en stonden daarom eerst helemaal
/// niet in dit bestand: een subproces en een WebView. Bij allebei opent iets
/// anders dan deze app de socket — `git` doet zijn eigen DNS, de webview-engine
/// ook — dus `safeResolve` + socket-pinning bestaan daar niet. De grens
/// verschuift dan naar hoe het proces of de pagina wordt opgezet: argv zonder
/// schil en zonder geërfde omgeving, of een navigatiedelegate die op HOST
/// weigert. Dat valt niet statisch te bewijzen; wat wél te bewijzen valt is dat
/// er niet stilletjes een uitgang bij komt. Vandaar dezelfde vorm: allowlist per
/// bestand, plus een telling voor het geval dat een tweede uitgang in een
/// bestaand bestand verschijnt.
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

  // Normaliseer eerst naar '/': op Windows geeft listSync backslashes, waardoor
  // de '/lib/'-regex niet matchte en rel het hele absolute pad teruggaf — dan
  // klopt geen enkele vergelijking met de 'lib/…'-allowlist meer.
  String rel(File f) =>
      f.path.replaceAll(r'\', '/').replaceFirst(RegExp(r'^.*/lib/'), 'lib/');

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
    // De gedeelde pinning-helper: bouwt de HttpClient die de transports
    // delen. De resolve + scheme-check + body-cap blijven per transport; alleen
    // het recept staat hier. Eerder stonden media_fetch_io,
    // file_service_import, libreplan_client en openkat_rocky_client hier ook
    // met elk hun eigen kopie — die zijn nu naar deze helper verplaatst.
    'lib/utils/pinned_http_client.dart': 1,
    // De gepinde fetch achter guardedNetworkImage.
    'lib/services/webdav_service.dart': 0,
    'lib/services/s3/s3_service.dart': 0,
    'lib/services/ai_client_service.dart': 1,
    'lib/services/cve_transport_io.dart': 0,
    // Twee: `getJson` en `download` openen elk hun eigen client, en beide laten
    // hem door `_get` pinnen — één keer per redirect-hop.
    'lib/services/cve/local_cve_database_io.dart': 2,
    'lib/services/git/git_transport_io.dart': 0,
    // Matrix relay egress (desktop): één gepinde client op de homeserver-origin,
    // safeResolve(Trusted) + connectPinned + geen redirects + bytecap.
    'lib/collab/matrix_http_transport_io.dart': 0,
    // XMPP-over-WebSocket egress (desktop): één gepinde client op de
    // wss-endpoint-origin, resolveConfigured + connectPinned + een fail-closed
    // schema-assert; WebSocket.connect gebruikt deze customClient.
    'lib/xmpp/xmpp_frame_transport_io.dart': 1,
    // LibrePlan-connector (desktop): gebruikt buildPinnedClient — de enige
    // uitgaande socket van lib/services/libreplan/.
    'lib/services/libreplan/libreplan_client.dart': 0,
    // OpenKAT Rocky-client (desktop): gebruikt buildPinnedClient — de enige
    // uitgaande socket van de live OpenKAT-koppeling.
    'lib/services/openkat/openkat_rocky_client.dart': 0,
  };

  test('media fetch sinks stay behind the NetGuard resolve gate', () {
    scan(
      sink: RegExp(r'NetworkImage\(|\.networkUrl\(|Image\.network\('),
      allowedFiles: {
        // guardedNetworkImage: haalt de bytes zélf op over een gepinde socket
        // (safeResolve + connectPinned), zodat NetworkImage de hostnaam niet
        // een tweede keer opzoekt. De web-tak laat het aan de browser + CSP.
        'lib/utils/media_fetch_io.dart',
        'lib/utils/media_fetch_web.dart',
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
        // De gedeelde pinning-helper die de transports delen. De resolve
        // + scheme-check + body-cap blijven per transport; alleen het
        // HttpClient-bouw-recept staat hier.
        'lib/utils/pinned_http_client.dart',
        // guardedNetworkImage: haalt de bytes van een remote dia-afbeelding
        // op via buildPinnedClient — safeResolve + pin + geen redirects +
        // bytecap — in plaats van NetworkImage de hostnaam nóg eens te laten
        // opzoeken.
        // importFromUrl: safeResolve + pin via buildPinnedClient (import-part
        // van file_service).
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
        // Matrix relay egress (desktop): resolveConfigured met de
        // trustedInternal-opt-in van de homeserver + socket-pin + geen redirects
        // + bytecap. De pin ligt op de geconfigureerde origin; een URI buiten die
        // origin wordt geweigerd vóór er verbonden wordt.
        'lib/collab/matrix_http_transport_io.dart',
        // XMPP-over-WebSocket egress (desktop): resolveConfigured met de
        // trustedInternal-opt-in + socket-pin via connectPinned, plus een
        // fail-closed schema-assert die een ongepinde (niet-https) socket weigert
        // i.p.v. TLS te droppen. De enige uitgaande socket van lib/xmpp/.
        'lib/xmpp/xmpp_frame_transport_io.dart',
        // LibrePlan-connector (desktop): gebruikt buildPinnedClient —
        // safeResolve(Trusted) + pin + geen redirects + bytecap. GET-only,
        // Basic Auth. De enige uitgaande socket van lib/services/libreplan/.
        'lib/services/libreplan/libreplan_client.dart',
        // OpenKAT Rocky-client (desktop): gebruikt buildPinnedClient —
        // safeResolve(Trusted) + pin + geen redirects + bytecap. GET-only,
        // Knox Token-auth. De enige uitgaande socket van de live
        // OpenKAT-koppeling.
        'lib/services/openkat/openkat_rocky_client.dart',
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

  /// Hoeveel subproces-starts elk toegelaten bestand mag hebben — dezelfde
  /// ratchet-vorm als [pinnedClientCount], en om dezelfde reden.
  ///
  /// Bij `disk_traces.dart` staat die reden zelfs al opgeschreven: de
  /// semgrep-uitzondering daar zit bewust op de régel en niet op het bestand,
  /// "een tweede subproces hier moet wél alarm geven". Alleen draait semgrep
  /// niet in `make check`, dus dat alarm bestond nergens. Nu wel.
  const subprocessCount = <String, int>{
    // De git-laag. Eén start, met argv-array, zonder schil, met een
    // dichtgetimmerde omgeving (includeParentEnvironment: false) zodat een
    // GIT_TRACE_* uit de schil van de gebruiker het token niet wegschrijft.
    'lib/services/git/git_cli_io.dart': 1,
    // `chmod 700` op de datamappen, alleen op Linux: vaste argv, geen schil, en
    // het pad komt van path_provider. Dart heeft geen permissie-API.
    'lib/services/disk_traces.dart': 1,
  };

  test('een subproces blijft binnen de twee plekken die het mogen', () {
    scan(
      sink: RegExp(r'\bProcess\.(start|run|runSync|startSync)\('),
      allowedFiles: subprocessCount.keys.toSet(),
      guidance:
          'Nieuw subproces. Een subproces is een netwerkuitgang die NetGuard '
          'niet kan zien — het proces opent zijn eigen sockets, en geen enkele '
          'poort in deze app zit ertussen. Wat er in plaats daarvan moet '
          'gebeuren staat in GIT_STORAGE.md §10.2: de beperking wordt aan het '
          'proces zelf opgelegd (argv-array, geen schil, geen geërfde '
          'omgeving, tijdslimiet, begrensde uitvoer). Doe dat, en zet het '
          'bestand erbij:',
    );
  });

  test('een toegelaten bestand krijgt er niet stilletjes een subproces bij', () {
    final sink = RegExp(r'\bProcess\.(start|run|runSync|startSync)\(');
    final actual = <String, int>{};
    for (final file in dartFiles()) {
      if (!subprocessCount.containsKey(rel(file))) continue;
      var count = 0;
      for (final line in file.readAsLinesSync()) {
        if (line.trimLeft().startsWith('//')) continue;
        count += sink.allMatches(line).length;
      }
      if (count > 0) actual[rel(file)] = count;
    }

    expect(
      actual,
      subprocessCount,
      reason:
          'Het aantal subproces-starts in een toegelaten bestand is veranderd. '
          'De allowlist bewijst alleen dat het bestand van de regel weet, niet '
          'dat élke start eraan voldoet — dus moet een tweede start hier '
          'bewust bijgesteld worden, met de reden dat ook hij zonder schil, '
          'zonder geërfde omgeving en met een tijdslimiet draait.',
    );
  });

  test('een WebView blijft op de drie plekken die hem afschermen', () {
    scan(
      sink: RegExp(r'WebViewController\(|\.loadRequest\(|WebViewWidget\('),
      allowedFiles: {
        // De verborgen Mermaid-renderer. Laadt één keer een lokale HTML-string
        // met een eigen CSP (`default-src 'none'`), en de navigatiedelegate
        // weigert daarna élke navigatie — de bundel komt uit de assets, niet
        // van het netwerk.
        'lib/widgets/mermaid_render_host.dart',
        'lib/services/mermaid_render_service.dart',
        // De video-embed. De navigatiedelegate laat na de eerste lading alleen
        // navigatie binnen de speler-origin door, en die toets kijkt naar de
        // HOST — niet naar een `contains`, want `youtube.com.kwaadaardig.nl`
        // bevat die tekst ook.
        'lib/widgets/slides/previews/media_previews_video.dart',
      },
      guidance:
          'Nieuwe WebView. Een WebView is een netwerkuitgang die NetGuard niet '
          'ziet: de engine lost hosts zelf op en opent zijn eigen sockets, dus '
          'safeResolve + socket-pinning bestaan hier niet. Wat er wél moet: een '
          'NavigationDelegate die na de eerste lading weigert wat niet op een '
          'toegestane HOST staat (host vergelijken, nooit `contains`), '
          'onHttpAuthRequest dichtzetten, en een CSP op de pagina zelf als de '
          'inhoud lokaal is. Doe dat, en zet het bestand erbij:',
    );
  });

  test('elke gepinde client weigert ook omleidingen', () {
    // SECURITY.md belooft dit met zoveel woorden: "een 3xx mag niet om de
    // hostcontrole heen lopen". Die belofte stond in dit bestand alleen in een
    // regel commentaar — schrap `followRedirects = false` uit een van deze
    // bestanden, en er werd niets rood (#618).
    //
    // Waarom het uitmaakt: het pinnen hierboven zet de socket vast op het adres
    // dat door de poort kwam. Volgt de client daarna zelf een 3xx, dan doet hij
    // een NIEUWE verbinding naar een adres dat nooit gekeurd is — en dan was
    // het pinnen voor niets.
    final setsIt = RegExp(r'followRedirects\s*=\s*false');
    // Bewust vrijgesteld: de XMPP-WebSocket-uitgang. `WebSocket.connect(
    // customClient:)` bouwt het HTTP-upgrade-verzoek intern, dus de app kan
    // `request.followRedirects` niet zetten. In plaats daarvan pint de
    // connectionFactory ELKE verbinding — ook een 3xx-sprong — aan het door
    // `resolveConfigured` goedgekeurde IP (de closure vangt datzelfde `pinned`),
    // en weigert de fail-closed https-assert een downgrade-hop. Een omleiding
    // bereikt zo nooit een nieuwe, ongekeurde host; een 3xx is bovendien geen 101
    // en laat de upgrade sowieso mislukken. Zie xmpp_frame_transport_io.dart.
    const redirectsPinnedNotRefused = {'lib/xmpp/xmpp_frame_transport_io.dart'};
    final missing = <String>[];
    for (final path in pinnedClientCount.keys) {
      if (pinnedClientCount[path] == 0) continue; // net_guard maakt er geen
      if (redirectsPinnedNotRefused.contains(path)) continue;
      final source = File(path).readAsStringSync();
      if (!setsIt.hasMatch(source)) missing.add(path);
    }
    expect(
      missing,
      isEmpty,
      reason:
          'Een gepinde HttpClient die omleidingen volgt, loopt om zijn eigen '
          'hostcontrole heen. Zet `request.followRedirects = false`, of — als '
          'dit pad ze bewust zelf volgt, zoals de CVE-bulkdownload — haal elke '
          'sprong opnieuw door NetGuard en schrijf dat hier op:',
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
        'lib/services/file/file_service_net.dart',
        // Git-forge (WEB-tak). Zelfde redenering als file_service_net.dart
        // hierboven: op web bestaat de dart:io-pinning van git_transport_io.dart
        // niet en kan ze er ook niet draaien — daar zijn de browser-sandbox en
        // de pagina-CSP (`connect-src`) de gate. Lokaal begrenst dit bestand
        // schema (https, of http alleen bij een bewust vertrouwde interne
        // server) en omvang (harde bytecap). Bovendien: een verzoek mét token
        // gaat nooit door het same-origin fetch-hulppunt, zodat dat punt het
        // PAT nooit in handen krijgt.
        'lib/services/git/git_transport_web.dart',
        // Matrix relay egress (WEB-tak). Zelfde redenering: op web bestaat de
        // dart:io-pinning van matrix_http_transport_io.dart niet en kan ze niet
        // draaien; de browser (CORS, mixed content) en de pagina-CSP
        // (`connect-src`) zijn de gate. Dit bestand begrenst schema en omvang;
        // de client die het token stuurt wordt lexicaal op https/loopback
        // gecontroleerd in MatrixClient vóór dit transport wordt bereikt.
        'lib/collab/matrix_http_transport_web.dart',
        // XMPP-over-WebSocket egress (desktop): ruwe WebSocket.connect met een
        // NetGuard-gepinde customClient (zie de raw-HttpClient-allowlist hierboven,
        // plus de fail-closed schema-assert). Bewust WebSocket.connect en niet
        // IOWebSocketChannel, zodat deze scan de socket wél ziet.
        'lib/xmpp/xmpp_frame_transport_io.dart',
        // Server-side deck index (WEB-tak). Zelfde redenering als
        // file_service_net.dart hierboven: op web bestaat de dart:io-pinning
        // niet en kan ze er niet draaien — de browser (CORS, mixed content) en
        // de pagina-CSP (`connect-src 'self'`) zijn de gate. Dit bestand haalt
        // alleen same-origin op (config-bestand + autoindex), en op desktop
        // returnt `kIsWeb` false vóór er een verbinding geopend wordt.
        'lib/services/web_deck_index.dart',
      },
      guidance:
          'New network egress primitive (package:http, dio, or a raw socket). '
          'Route the URL through NetGuard — safeResolve(Trusted) + socket '
          'pinning for dart:io, or document why the platform itself is the gate '
          '— then add the file to the allowlist:',
    );
  });
}
