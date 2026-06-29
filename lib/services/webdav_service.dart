import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:xml/xml.dart';

import '../models/webdav_settings.dart';
import '../utils/log.dart';
import '../utils/net_guard.dart';

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

  const WebdavEntry({
    required this.name,
    required this.relativePath,
    required this.isCollection,
    this.size,
    this.contentType,
  });

  String get lowerName => name.toLowerCase();
  bool get isOcideck => lowerName.endsWith('.ocideck') || lowerName.endsWith('.zip');
  bool get isMarkdown => lowerName.endsWith('.md');
  bool get isImage =>
      lowerName.endsWith('.png') ||
      lowerName.endsWith('.jpg') ||
      lowerName.endsWith('.jpeg') ||
      lowerName.endsWith('.gif') ||
      lowerName.endsWith('.webp') ||
      lowerName.endsWith('.svg');
}

/// Reden waarom een WebDAV-bewerking faalde — zodat de UI een begrijpelijke
/// melding kan tonen zonder de ruwe fout te lekken.
enum WebdavError { config, blockedHost, network, auth, notFound, tooLarge, server }

class WebdavException implements Exception {
  final WebdavError kind;
  final String message;
  WebdavException(this.kind, this.message);
  @override
  String toString() => 'WebdavException($kind): $message';
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

  /// Maximaal te downloaden bestand (gelijk aan de pakketlimiet van FileService).
  static const int maxDownloadBytes = 512 * 1024 * 1024;

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
    final addrs = await NetGuard.safeResolveTrusted(
      host,
      allowPrivate: server.trustedInternal,
    );
    if (addrs == null) {
      throw WebdavException(
        WebdavError.blockedHost,
        'Server-host geweigerd of onbereikbaar',
      );
    }
    final pinned = addrs.first;
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
    if (status >= 500) {
      throw WebdavException(WebdavError.server, 'Serverfout ($status)');
    }
  }

  static const String _propfindBody =
      '<?xml version="1.0" encoding="utf-8"?>'
      '<d:propfind xmlns:d="DAV:">'
      '<d:prop>'
      '<d:resourcetype/>'
      '<d:getcontentlength/>'
      '<d:getcontenttype/>'
      '<d:displayname/>'
      '</d:prop>'
      '</d:propfind>';

  /// Lijst de inhoud van [remotePath] (relatief aan `rootPath`) met `Depth: 1`.
  /// De map zelf wordt uit het resultaat gefilterd. Sorteert mappen eerst.
  Future<List<WebdavEntry>> list(String remotePath) async {
    final uri = server.uriFor(remotePath, isCollection: true);
    if (uri == null) {
      throw WebdavException(WebdavError.config, 'Pad buiten de wortelmap');
    }
    final client = await _client();
    try {
      final request = await _openRequest(client, 'PROPFIND', uri);
      request.headers.set('Depth', '1');
      request.headers.contentType = ContentType('application', 'xml', charset: 'utf-8');
      request.add(utf8.encode(_propfindBody));
      final response = await request.close().timeout(const Duration(seconds: 30));
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
      return parseMultistatus(
        utf8.decode(builder.takeBytes()),
        username: server.username.trim(),
        rootPath: server.rootPath,
      );
    } on WebdavException {
      rethrow;
    } on TimeoutException {
      throw WebdavException(WebdavError.network, 'Time-out');
    } catch (e) {
      logError('WebdavService.list: mislukt', e);
      throw WebdavException(WebdavError.network, 'Verbinding mislukt');
    } finally {
      client.close(force: true);
    }
  }

  /// Parse een WebDAV `multistatus` (PROPFIND) antwoord naar entries relatief
  /// aan de wortelmap. Statisch en netwerkvrij zodat het rechtstreeks te testen
  /// is. De map zelf en alles buiten de wortel worden weggefilterd.
  static List<WebdavEntry> parseMultistatus(
    String xmlBody, {
    required String username,
    required String rootPath,
  }) {
    final XmlDocument doc;
    try {
      doc = XmlDocument.parse(xmlBody);
    } catch (e) {
      logError('WebdavService: ongeldige PROPFIND-XML', e);
      throw WebdavException(WebdavError.server, 'Ongeldig antwoord');
    }
    final base = _davBaseSegments(username, rootPath);
    final entries = <WebdavEntry>[];
    final responses = doc.descendantElements.where((e) => e.localName == 'response');
    for (final resp in responses) {
      if (entries.length >= maxListingEntries) break;
      final href = resp.descendantElements
          .firstWhere(
            (e) => e.localName == 'href',
            orElse: () => XmlElement(XmlName('href')),
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
      for (final p in prop) {
        for (final child in p.childElements) {
          if (child.localName == 'getcontentlength') {
            size = int.tryParse(child.innerText.trim());
          } else if (child.localName == 'getcontenttype') {
            final v = child.innerText.trim();
            if (v.isNotEmpty) contentType = v;
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
        ),
      );
    }
    entries.sort((a, b) {
      if (a.isCollection != b.isCollection) return a.isCollection ? -1 : 1;
      return a.lowerName.compareTo(b.lowerName);
    });
    return entries;
  }

  /// Decoded pad-segmenten tot en met de geconfigureerde wortel:
  /// `[remote.php, dav, files, <user>, ...rootSegments]`.
  static List<String> _davBaseSegments(String username, String rootPath) {
    final root = WebdavServer.normalizeRoot(rootPath);
    final rootSegs = root.split('/').where((s) => s.isNotEmpty);
    return ['remote.php', 'dav', 'files', username.trim(), ...rootSegs];
  }

  /// Zet een (mogelijk percent-gecodeerde, mogelijk absolute) href om naar een
  /// pad relatief aan de wortelmap, of `null` wanneer hij buiten de wortel valt.
  static String? _hrefToRelativeStatic(String href, List<String> base) {
    final Uri parsed;
    try {
      parsed = Uri.parse(href);
    } catch (_) {
      return null;
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
  Future<Uint8List> download(
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
      final response = await request.close().timeout(const Duration(seconds: 60));
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
      return builder.takeBytes();
    } on WebdavException {
      rethrow;
    } on TimeoutException {
      throw WebdavException(WebdavError.network, 'Time-out');
    } catch (e) {
      logError('WebdavService.download: mislukt', e);
      throw WebdavException(WebdavError.network, 'Download mislukt');
    } finally {
      client.close(force: true);
    }
  }

  /// Upload [bytes] naar [remotePath]. Maakt ontbrekende bovenliggende mappen
  /// aan met MKCOL en doet daarna een PUT.
  Future<void> upload(String remotePath, List<int> bytes) async {
    final uri = server.uriFor(remotePath);
    if (uri == null) {
      throw WebdavException(WebdavError.config, 'Pad buiten de wortelmap');
    }
    final client = await _client();
    try {
      await _ensureParents(client, remotePath);
      final request = await _openRequest(client, 'PUT', uri);
      request.headers.contentType = ContentType('application', 'octet-stream');
      request.add(bytes);
      final response = await request.close().timeout(const Duration(seconds: 120));
      _checkStatus(response.statusCode);
      await response.drain<void>();
      if (response.statusCode != 200 &&
          response.statusCode != 201 &&
          response.statusCode != 204) {
        throw WebdavException(
          WebdavError.server,
          'Upload gaf status ${response.statusCode}',
        );
      }
    } on WebdavException {
      rethrow;
    } on TimeoutException {
      throw WebdavException(WebdavError.network, 'Time-out');
    } catch (e) {
      logError('WebdavService.upload: mislukt', e);
      throw WebdavException(WebdavError.network, 'Upload mislukt');
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
      final response = await request.close().timeout(const Duration(seconds: 30));
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
  Future<void> probe() async {
    final uri = server.uriFor('', isCollection: true);
    if (uri == null) {
      throw WebdavException(WebdavError.config, 'Ongeldige server-URL');
    }
    final client = await _client();
    try {
      final request = await _openRequest(client, 'PROPFIND', uri);
      request.headers.set('Depth', '0');
      request.headers.contentType = ContentType('application', 'xml', charset: 'utf-8');
      request.add(utf8.encode(_propfindBody));
      final response = await request.close().timeout(const Duration(seconds: 20));
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
      logError('WebdavService.probe: mislukt', e);
      throw WebdavException(WebdavError.network, 'Verbinding mislukt');
    } finally {
      client.close(force: true);
    }
  }
}
