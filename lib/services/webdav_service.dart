import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:xml/xml.dart';

import '../models/webdav_settings.dart';
import '../utils/log.dart';
import '../utils/net_guard.dart';
import 'file_service.dart';

/// Eén item in een WebDAV-maplisting.
class WebdavEntry {
  /// Weergavenaam (laatste pad-segment).
  final String name;

  /// Pad relatief aan de geconfigureerde `rootPath`, bruikbaar met
  /// [WebdavServer.uriFor]. Bevat geen leidende slash.
  final String relativePath;

  final bool isCollection;
  final int? size;
  final String? contentType;

  /// De versieaanduiding die de server aan deze inhoud hangt, of `null` als
  /// hij er geen geeft. Zie [WebdavFile.etag].
  final String? etag;

  const WebdavEntry({
    required this.name,
    required this.relativePath,
    required this.isCollection,
    this.size,
    this.contentType,
    this.etag,
  });

  String get lowerName => name.toLowerCase();
  bool get isOcideck =>
      lowerName.endsWith('.ocideck') || lowerName.endsWith('.zip');
  bool get isMarkdown => lowerName.endsWith('.md');
  bool get isImage =>
      lowerName.endsWith('.png') ||
      lowerName.endsWith('.jpg') ||
      lowerName.endsWith('.jpeg') ||
      lowerName.endsWith('.gif') ||
      lowerName.endsWith('.webp') ||
      lowerName.endsWith('.svg');
}

/// De inhoud van een gedownload bestand plus de versieaanduiding die de server
/// eraan hing, zodat een latere PUT kan zeggen "alleen als het nog steeds deze
/// versie is".
class WebdavFile {
  final Uint8List bytes;

  /// De ETag zoals de server hem gaf, inclusief aanhalingstekens en een
  /// eventuele `W/`-prefix — bewust ongewijzigd doorgegeven, want hij moet er
  /// bij `If-Match` letterlijk zo weer uit. `null` wanneer de server er geen
  /// stuurde; dan valt er niets te bewaken.
  final String? etag;

  const WebdavFile(this.bytes, this.etag);
}

/// Reden waarom een WebDAV-bewerking faalde — zodat de UI een begrijpelijke
/// melding kan tonen zonder de ruwe fout te lekken.
enum WebdavError {
  config,

  /// De hostnaam bestaat niet of DNS antwoordde niet. Bewust gescheiden van
  /// [blockedHost]: die twee vragen om tegengesteld advies.
  unknownHost,
  blockedHost,

  /// Het TLS-certificaat van de server werd niet vertrouwd — zelfondertekend,
  /// verlopen, of op een andere naam. Zonder eigen soort verdween dit in
  /// [network] en las de gebruiker "verbinding mislukt" bij een server die
  /// prima bereikbaar was.
  tls,

  /// De server stuurde een omleiding. Die volgen we niet (dat zou de
  /// host-controle omzeilen), maar het is geen storing: meestal staat er een
  /// `http`-URL ingevuld waar de server `https` van maakt.
  redirect,
  network,
  auth,
  notFound,
  tooLarge,
  server,
}

class WebdavException implements Exception {
  final WebdavError kind;
  final String message;

  /// Of dit een storing is die zómaar weer over kan zijn: een verbinding die
  /// werd verbroken of geweigerd. Alleen dán is het zinnig een leesactie nog
  /// eens te proberen.
  ///
  /// Nadrukkelijk níet gezet bij een time-out: die kostte de gebruiker al de
  /// volle wachttijd, en er nog een ronde bovenop doen maakt een trage server
  /// twee keer zo traag zonder dat er iets aan de oorzaak verandert. Ook niet
  /// bij auth, notFound, tls of config — dat zijn antwoorden, geen storingen.
  final bool transient;

  WebdavException(this.kind, this.message, {this.transient = false});
  @override
  String toString() => 'WebdavException($kind): $message';
}

/// Het bestand op de server is veranderd sinds wij het ophaalden: de server
/// weigerde onze `If-Match` (412).
///
/// Bewust een eigen type en geen [WebdavError]-soort — net als
/// `GitConflictException`, en om dezelfde reden: dit is geen storing die je
/// opnieuw probeert, maar een uitkomst waar de aanroeper een keuze over moet
/// voorleggen. Als foutsoort zou hij bovendien opduiken in switches van
/// bewerkingen waar hij niet kán ontstaan, zoals de verbindingstest.
class WebdavConflictException implements Exception {
  /// De versie waarop ons werk gebaseerd was, dus wat we de server vroegen te
  /// bevestigen. Voor de melding en om te kunnen zien wat er misging.
  final String expectedEtag;
  final String message;
  const WebdavConflictException({
    required this.expectedEtag,
    required this.message,
  });
  @override
  String toString() => 'WebdavConflictException($expectedEtag): $message';
}

/// Spreekt WebDAV (Nextcloud) over `dart:io HttpClient` met basic-auth. Deelt de
/// veiligheidsmaatregelen van [importFromUrl]: geen redirects, harde
/// groottelimieten en socket-pinning tegen DNS-rebind. De server-host mag
/// alleen een privé/LAN-adres zijn wanneer de gebruiker hem als vertrouwd
/// heeft gemarkeerd ([WebdavServer.trustedInternal]).
class WebdavService {
  WebdavService({required this.server, required this.password});

  final WebdavServer server;
  final String password;

  /// Maximaal te downloaden bestand — dezelfde limiet als het pakket dat we
  /// downloaden; verwijst naar de bron zodat de twee niet kunnen divergeren.
  static const int maxDownloadBytes = FileService.maxPackageBytes;

  /// Cap op de PROPFIND-respons zodat een vijandige server het geheugen niet
  /// kan laten vollopen.
  static const int maxListingBytes = 16 * 1024 * 1024;

  /// Maximaal aantal entries dat we uit één listing accepteren.
  static const int maxListingEntries = 5000;

  String get _authHeader =>
      'Basic ${base64Encode(utf8.encode('${server.username.trim()}:$password'))}';

  /// Resolve + pin de server-host. Geeft een client met gepinde socket terug,
  /// of gooit [WebdavException] bij een geblokkeerde/onbereikbare host.
  Future<HttpClient> _client() async {
    if (!server.isConfigured) {
      throw WebdavException(WebdavError.config, 'WebDAV-server niet ingesteld');
    }
    final host = server.host;
    if (host.isEmpty) {
      throw WebdavException(WebdavError.config, 'Ongeldige server-URL');
    }
    // Basic-auth stuurt de Nextcloud-credentials in (base64) mee bij élke
    // request. Over plain http gaan die in leesbare vorm over de lijn, dus
    // eisen we https — tenzij de gebruiker de server bewust als vertrouwd
    // intern (LAN) heeft gemarkeerd, waar een box zonder TLS gangbaar is.
    final scheme = server.origin?.scheme.toLowerCase();
    if (scheme != 'https' && !(scheme == 'http' && server.trustedInternal)) {
      throw WebdavException(
        WebdavError.config,
        scheme == 'http'
            ? 'Gebruik https of markeer de server als vertrouwd intern; '
                  'anders gaat je wachtwoord onversleuteld over het netwerk.'
            : 'Alleen https-servers worden ondersteund.',
      );
    }
    final resolved = await NetGuard.resolveConfigured(
      host,
      allowPrivate: server.trustedInternal,
    );
    if (!resolved.isOk) {
      throw switch (resolved.refusal!) {
        HostRefusal.unknownHost => WebdavException(
          WebdavError.unknownHost,
          'Servernaam niet gevonden',
        ),
        HostRefusal.blocked => WebdavException(
          WebdavError.blockedHost,
          'Server-host geweigerd',
        ),
      };
    }
    final pinned = resolved.addresses!.first;
    return HttpClient()
      ..connectionTimeout = const Duration(seconds: 15)
      ..connectionFactory = (u, proxyHost, proxyPort) =>
          Socket.startConnect(pinned, u.port);
  }

  Future<HttpClientRequest> _openRequest(
    HttpClient client,
    String method,
    Uri uri,
  ) async {
    final request = await client.openUrl(method, uri);
    request.followRedirects = false; // 3xx mag de host-check niet omzeilen
    request.headers.set(HttpHeaders.authorizationHeader, _authHeader);
    return request;
  }

  void _checkStatus(int status) {
    if (status == 401 || status == 403) {
      throw WebdavException(WebdavError.auth, 'Aanmelden mislukt ($status)');
    }
    if (status == 404) {
      throw WebdavException(WebdavError.notFound, 'Niet gevonden');
    }
    // Redirects volgen we niet (zie [_openRequest]); als "onverwachte status"
    // was dit cryptisch, terwijl het bijna altijd één herkenbare oorzaak heeft.
    if (status >= 300 && status < 400) {
      throw WebdavException(
        WebdavError.redirect,
        'Server stuurt door ($status)',
      );
    }
    if (status >= 500) {
      throw WebdavException(WebdavError.server, 'Serverfout ($status)');
    }
  }

  /// Vertaal een gevangen laag-niveau fout naar een [WebdavException] die de
  /// oorzaak nog draagt.
  ///
  /// Hiervoor eindigde elke bewerking op `catch (e) → network / "Verbinding
  /// mislukt"`. Een afgewezen certificaat, een dichte poort en een geweigerde
  /// verbinding werden zo één zin, en de enige plek waar het verschil nog
  /// stond was het logboek — waar de gebruiker niet kijkt. De informatie was
  /// er al; ze werd één laag te vroeg weggegooid.
  static Never _asFailure(String where, Object e, String fallback) {
    // TlsException dekt zowel HandshakeException als CertificateException.
    if (e is TlsException) {
      logWarning('WebdavService.$where: TLS geweigerd', e);
      throw WebdavException(WebdavError.tls, 'Certificaat niet vertrouwd');
    }
    if (e is SocketException) {
      logWarning('WebdavService.$where: socket onbereikbaar', e);
      throw WebdavException(
        WebdavError.network,
        'Server niet bereikbaar',
        transient: true,
      );
    }
    // Een verbinding die halverwege wegviel meldt Dart als HttpException
    // ("Connection closed before full header was received"), niet als
    // SocketException. Dat is juist het geval waarvoor opnieuw proberen bestaat.
    if (e is HttpException) {
      logWarning('WebdavService.$where: verbinding afgebroken', e);
      throw WebdavException(
        WebdavError.network,
        'Verbinding afgebroken',
        transient: true,
      );
    }
    logError('WebdavService.$where: mislukt', e);
    throw WebdavException(WebdavError.network, fallback);
  }

  /// Voer een *leesactie* uit en probeer hem één keer opnieuw wanneer de
  /// verbinding wegviel.
  ///
  /// Eén keer, want een tweede poging vangt de hik op waar het om gaat — een
  /// verbroken socket, een net-herstelde wifi — en alles daarna is wachten op
  /// iets dat structureel stuk is. Met een korte pauze ertussen, zodat we niet
  /// binnen dezelfde milliseconde tegen dezelfde muur lopen.
  ///
  /// Alleen voor lezen. Een mislukte upload opnieuw sturen is niet hetzelfde
  /// als hem één keer sturen: de `If-Match`-bewaking hangt aan wat er op dat
  /// moment op de server staat, en dat kan intussen veranderd zijn.
  static Future<T> _retryRead<T>(
    String where,
    Future<T> Function() attempt,
  ) async {
    try {
      return await attempt();
    } on WebdavException catch (e) {
      if (!e.transient) rethrow;
      logWarning('WebdavService.$where: verbinding weg, nog één poging', e);
      await Future<void>.delayed(const Duration(milliseconds: 400));
      return attempt();
    }
  }

  static const String _propfindBody =
      '<?xml version="1.0" encoding="utf-8"?>'
      '<d:propfind xmlns:d="DAV:">'
      '<d:prop>'
      '<d:resourcetype/>'
      '<d:getcontentlength/>'
      '<d:getcontenttype/>'
      '<d:getetag/>'
      '<d:displayname/>'
      '</d:prop>'
      '</d:propfind>';

  /// Lijst de inhoud van [remotePath] (relatief aan `rootPath`) met `Depth: 1`.
  /// De map zelf wordt uit het resultaat gefilterd. Sorteert mappen eerst.
  Future<List<WebdavEntry>> list(String remotePath) =>
      _retryRead('list', () => _listOnce(remotePath));

  Future<List<WebdavEntry>> _listOnce(String remotePath) async {
    final uri = server.uriFor(remotePath, isCollection: true);
    if (uri == null) {
      throw WebdavException(WebdavError.config, 'Pad buiten de wortelmap');
    }
    final client = await _client();
    try {
      final request = await _openRequest(client, 'PROPFIND', uri);
      request.headers.set('Depth', '1');
      request.headers.contentType = ContentType(
        'application',
        'xml',
        charset: 'utf-8',
      );
      request.add(utf8.encode(_propfindBody));
      final response = await request.close().timeout(
        const Duration(seconds: 30),
      );
      _checkStatus(response.statusCode);
      if (response.statusCode != 207) {
        throw WebdavException(
          WebdavError.server,
          'Onverwachte status ${response.statusCode}',
        );
      }
      final builder = BytesBuilder(copy: false);
      await for (final chunk in response) {
        builder.add(chunk);
        if (builder.length > maxListingBytes) {
          throw WebdavException(WebdavError.tooLarge, 'Listing te groot');
        }
      }
      return parseMultistatus(utf8.decode(builder.takeBytes()), server: server);
    } on WebdavException {
      rethrow;
    } on TimeoutException {
      throw WebdavException(WebdavError.network, 'Time-out');
    } catch (e) {
      _asFailure('list', e, 'Verbinding mislukt');
    } finally {
      client.close(force: true);
    }
  }

  /// Parse een WebDAV `multistatus` (PROPFIND) antwoord naar entries relatief
  /// aan de wortelmap. Statisch en netwerkvrij zodat het rechtstreeks te testen
  /// is. De map zelf en alles buiten de wortel worden weggefilterd.
  static List<WebdavEntry> parseMultistatus(
    String xmlBody, {
    required WebdavServer server,
  }) {
    final XmlDocument doc;
    try {
      doc = XmlDocument.parse(xmlBody);
    } catch (e) {
      logError('WebdavService: ongeldige PROPFIND-XML', e);
      throw WebdavException(WebdavError.server, 'Ongeldig antwoord');
    }
    final base = _davBaseSegments(server);
    final entries = <WebdavEntry>[];
    final responses = doc.descendantElements.where(
      (e) => e.localName == 'response',
    );
    for (final resp in responses) {
      if (entries.length >= maxListingEntries) break;
      final href = resp.descendantElements
          .firstWhere(
            (e) => e.localName == 'href',
            orElse: () => XmlElement(const XmlName.parts('href')),
          )
          .innerText;
      if (href.isEmpty) continue;
      final relative = _hrefToRelativeStatic(href, base);
      if (relative == null || relative.isEmpty) continue; // de map zelf
      // Defensief: een vijandige server kan een href met `..`/`.` teruggeven
      // die uit de wortel zou breken. Download/upload weigeren zulke paden al
      // (zie WebdavServer.uriFor), maar toon ze ook niet in de lijst.
      final segs = relative.split('/');
      if (segs.any((s) => s == '..' || s == '.')) continue;

      final prop = resp.descendantElements.where((e) => e.localName == 'prop');
      final isCollection = resp.descendantElements.any(
        (e) => e.localName == 'collection',
      );
      int? size;
      String? contentType;
      String? etag;
      for (final p in prop) {
        for (final child in p.childElements) {
          if (child.localName == 'getcontentlength') {
            size = int.tryParse(child.innerText.trim());
          } else if (child.localName == 'getcontenttype') {
            final v = child.innerText.trim();
            if (v.isNotEmpty) contentType = v;
          } else if (child.localName == 'getetag') {
            final v = child.innerText.trim();
            if (v.isNotEmpty) etag = v;
          }
        }
      }
      final name = relative.split('/').where((s) => s.isNotEmpty).last;
      entries.add(
        WebdavEntry(
          name: name,
          relativePath: relative,
          isCollection: isCollection,
          size: size,
          contentType: contentType,
          etag: etag,
        ),
      );
    }
    entries.sort((a, b) {
      if (a.isCollection != b.isCollection) return a.isCollection ? -1 : 1;
      return a.lowerName.compareTo(b.lowerName);
    });
    return entries;
  }

  /// Gedecodeerde pad-segmenten tot en met de geconfigureerde submap: de
  /// DAV-wortel van de server plus [WebdavServer.rootPath].
  static List<String> _davBaseSegments(WebdavServer server) {
    final root = WebdavServer.normalizeRoot(server.rootPath);
    final rootSegs = root.split('/').where((s) => s.isNotEmpty);
    return [...server.davSegments, ...rootSegs];
  }

  /// Zet een (mogelijk percent-gecodeerde, mogelijk absolute) href om naar een
  /// pad relatief aan de wortelmap, of `null` wanneer hij buiten de wortel valt.
  static String? _hrefToRelativeStatic(String href, List<String> base) {
    final Uri parsed;
    try {
      parsed = Uri.parse(href);
    } on FormatException {
      return null; // malformed href → treat as outside the root
    }
    final segs = parsed.pathSegments.where((s) => s.isNotEmpty).toList();
    if (segs.length < base.length) return null;
    for (var i = 0; i < base.length; i++) {
      if (segs[i] != base[i]) return null; // buiten de wortel
    }
    return segs.sublist(base.length).join('/');
  }

  /// Download het bestand op [remotePath]. Streamt met een harde limiet en
  /// volgt geen redirects. Geeft de bytes, of gooit [WebdavException].
  Future<WebdavFile> download(
    String remotePath, {
    int maxBytes = maxDownloadBytes,
  }) => _retryRead(
    'download',
    () => _downloadOnce(remotePath, maxBytes: maxBytes),
  );

  Future<WebdavFile> _downloadOnce(
    String remotePath, {
    int maxBytes = maxDownloadBytes,
  }) async {
    final uri = server.uriFor(remotePath);
    if (uri == null) {
      throw WebdavException(WebdavError.config, 'Pad buiten de wortelmap');
    }
    final client = await _client();
    try {
      final request = await _openRequest(client, 'GET', uri);
      final response = await request.close().timeout(
        const Duration(seconds: 60),
      );
      _checkStatus(response.statusCode);
      if (response.statusCode != 200) {
        throw WebdavException(
          WebdavError.server,
          'Onverwachte status ${response.statusCode}',
        );
      }
      if (response.contentLength > maxBytes) {
        throw WebdavException(WebdavError.tooLarge, 'Bestand te groot');
      }
      final builder = BytesBuilder(copy: false);
      await for (final chunk in response) {
        builder.add(chunk);
        if (builder.length > maxBytes) {
          throw WebdavException(WebdavError.tooLarge, 'Bestand te groot');
        }
      }
      return WebdavFile(
        builder.takeBytes(),
        response.headers.value(HttpHeaders.etagHeader),
      );
    } on WebdavException {
      rethrow;
    } on TimeoutException {
      throw WebdavException(WebdavError.network, 'Time-out');
    } catch (e) {
      _asFailure('download', e, 'Download mislukt');
    } finally {
      client.close(force: true);
    }
  }

  /// Upload [bytes] naar [remotePath]. Maakt ontbrekende bovenliggende mappen
  /// aan met MKCOL en doet daarna een PUT. Geeft de nieuwe ETag terug wanneer
  /// de server er een meldt, zodat een volgende opslag daarop verder kan.
  ///
  /// [ifMatch] maakt de PUT voorwaardelijk: hij slaagt alleen als het bestand
  /// daar nog die versie is, anders volgt [WebdavError.conflict]. Zonder
  /// [ifMatch] wordt er onvoorwaardelijk geschreven — dat is juist voor een
  /// bestand dat wij niet eerder ophaalden, en fout voor een bestand dat we
  /// terugschrijven.
  ///
  /// [onlyIfAbsent] schrijft alleen wanneer er nog niets staat (`If-None-Match:
  /// *`), voor het geval "nieuw bestand aanmaken op een pad dat de gebruiker
  /// koos". De twee sluiten elkaar uit.
  Future<String?> upload(
    String remotePath,
    List<int> bytes, {
    String? ifMatch,
    bool onlyIfAbsent = false,
  }) async {
    assert(
      ifMatch == null || !onlyIfAbsent,
      'If-Match en If-None-Match:* spreken elkaar tegen',
    );
    final uri = server.uriFor(remotePath);
    if (uri == null) {
      throw WebdavException(WebdavError.config, 'Pad buiten de wortelmap');
    }
    final client = await _client();
    try {
      await _ensureParents(client, remotePath);
      final request = await _openRequest(client, 'PUT', uri);
      request.headers.contentType = ContentType('application', 'octet-stream');
      if (ifMatch != null) {
        request.headers.set(HttpHeaders.ifMatchHeader, ifMatch);
      } else if (onlyIfAbsent) {
        request.headers.set(HttpHeaders.ifNoneMatchHeader, '*');
      }
      request.add(bytes);
      final response = await request.close().timeout(
        const Duration(seconds: 120),
      );
      // Vóór _checkStatus: 412 betekent hier iets specifieks (onze voorwaarde
      // klopte niet) en mag niet als algemene serverfout wegvallen. 428 stuurt
      // een server die een voorwaarde eist; voor de gebruiker hetzelfde
      // verhaal — eerst kijken wat er staat, niet blind overschrijven.
      if (response.statusCode == 412 || response.statusCode == 428) {
        await response.drain<void>();
        throw WebdavConflictException(
          expectedEtag: ifMatch ?? '*',
          message: 'Bestand op de server gewijzigd (${response.statusCode})',
        );
      }
      _checkStatus(response.statusCode);
      final newEtag = response.headers.value(HttpHeaders.etagHeader);
      await response.drain<void>();
      if (response.statusCode != 200 &&
          response.statusCode != 201 &&
          response.statusCode != 204) {
        throw WebdavException(
          WebdavError.server,
          'Upload gaf status ${response.statusCode}',
        );
      }
      // Niet elke server geeft een ETag terug op de PUT. Dan weten we de
      // nieuwe versie niet en valt er bij de vólgende opslag niets te
      // vergelijken; dat is zichtbaar als `null` en niet als een gok.
      return newEtag;
    } on WebdavException {
      rethrow;
    } on WebdavConflictException {
      rethrow;
    } on TimeoutException {
      throw WebdavException(WebdavError.network, 'Time-out');
    } catch (e) {
      _asFailure('upload', e, 'Upload mislukt');
    } finally {
      client.close(force: true);
    }
  }

  /// Maak elke bovenliggende map van [remotePath] aan (MKCOL). Een al
  /// bestaande map (405) wordt genegeerd.
  Future<void> _ensureParents(HttpClient client, String remotePath) async {
    final parts = remotePath.split('/').where((s) => s.isNotEmpty).toList();
    if (parts.length <= 1) return; // bestand in de wortel
    var prefix = '';
    for (var i = 0; i < parts.length - 1; i++) {
      prefix = prefix.isEmpty ? parts[i] : '$prefix/${parts[i]}';
      final uri = server.uriFor(prefix, isCollection: true);
      if (uri == null) {
        throw WebdavException(WebdavError.config, 'Pad buiten de wortelmap');
      }
      final request = await _openRequest(client, 'MKCOL', uri);
      final response = await request.close().timeout(
        const Duration(seconds: 30),
      );
      await response.drain<void>();
      // 201 aangemaakt, 405 bestaat al — beide goed. 401/403/5xx → fout.
      if (response.statusCode == 401 || response.statusCode == 403) {
        throw WebdavException(WebdavError.auth, 'Geen rechten om map te maken');
      }
      if (response.statusCode >= 500) {
        throw WebdavException(WebdavError.server, 'Map maken mislukt');
      }
    }
  }

  /// Korte verbindingstest: een PROPFIND op de wortel met `Depth: 0`.
  Future<void> probe() => _retryRead('probe', _probeOnce);

  Future<void> _probeOnce() async {
    final uri = server.uriFor('', isCollection: true);
    if (uri == null) {
      throw WebdavException(WebdavError.config, 'Ongeldige server-URL');
    }
    final client = await _client();
    try {
      final request = await _openRequest(client, 'PROPFIND', uri);
      request.headers.set('Depth', '0');
      request.headers.contentType = ContentType(
        'application',
        'xml',
        charset: 'utf-8',
      );
      request.add(utf8.encode(_propfindBody));
      final response = await request.close().timeout(
        const Duration(seconds: 20),
      );
      _checkStatus(response.statusCode);
      await response.drain<void>();
      if (response.statusCode != 207) {
        throw WebdavException(
          WebdavError.server,
          'Onverwachte status ${response.statusCode}',
        );
      }
    } on WebdavException {
      rethrow;
    } on TimeoutException {
      throw WebdavException(WebdavError.network, 'Time-out');
    } catch (e) {
      _asFailure('probe', e, 'Verbinding mislukt');
    } finally {
      client.close(force: true);
    }
  }
}
