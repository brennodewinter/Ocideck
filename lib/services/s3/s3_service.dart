import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:xml/xml.dart';

import '../../models/s3_settings.dart';
import '../../utils/log.dart';
import '../../utils/net_guard.dart';
import '../file_service.dart';
import 's3_sigv4.dart';

/// Eén item in een S3-listing.
///
/// S3 kent geen mappen; een listing met een delimiter levert naast objecten
/// ("Contents") ook gemeenschappelijke prefixen ("CommonPrefixes") op, en dát
/// zijn de dingen die zich als map gedragen. [isCollection] maakt dat verschil
/// zichtbaar zonder dat de UI iets van prefixen hoeft te weten.
class S3Entry {
  /// Weergavenaam: het laatste segment van de sleutel.
  final String name;

  /// Pad relatief aan de geconfigureerde `rootPath`, zonder leidende slash.
  final String relativePath;

  final bool isCollection;
  final int? size;

  /// De ETag die S3 aan deze inhoud hangt, inclusief aanhalingstekens.
  final String? etag;

  const S3Entry({
    required this.name,
    required this.relativePath,
    required this.isCollection,
    this.size,
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

/// De inhoud van een gedownload object plus de ETag, zodat een latere PUT kan
/// zeggen "alleen als het nog steeds deze versie is".
class S3File {
  final Uint8List bytes;
  final String? etag;
  const S3File(this.bytes, this.etag);
}

/// Reden waarom een S3-bewerking faalde — zodat de UI een begrijpelijke melding
/// kan tonen zonder de ruwe fout te lekken.
enum S3Error {
  config,

  /// De endpoint-naam bestaat niet of DNS antwoordde niet. Gescheiden van
  /// [blockedHost]: die twee vragen om tegengesteld advies.
  unknownHost,
  blockedHost,
  network,
  auth,
  notFound,
  tooLarge,
  server,

  /// Het endpoint kent geen voorwaardelijke schrijfacties. Eigen soort omdat
  /// het geen storing is maar een eigenschap van deze server, waar de gebruiker
  /// iets over moet weten: gelijktijdig bewerken is hier slechter beschermd.
  conditionalUnsupported,
}

class S3Exception implements Exception {
  final S3Error kind;
  final String message;

  /// Of dit een storing is die zómaar weer over kan zijn: een verbinding die
  /// wegviel of werd geweigerd. Alleen dán is het zinnig een *leesactie* nog
  /// eens te proberen. Spiegelt `WebdavException.transient`, met dezelfde
  /// uitzondering: een time-out telt niet mee.
  final bool transient;

  S3Exception(this.kind, this.message, {this.transient = false});
  @override
  String toString() => 'S3Exception($kind): $message';
}

/// Het object is veranderd sinds wij het ophaalden: de server weigerde onze
/// `If-Match` (412). Eigen type en geen [S3Error]-soort, om dezelfde reden als
/// bij `WebdavConflictException`: dit is geen storing die je opnieuw probeert,
/// maar een uitkomst waar de aanroeper een keuze over moet voorleggen.
class S3ConflictException implements Exception {
  final String expectedEtag;
  final String message;
  const S3ConflictException({
    required this.expectedEtag,
    required this.message,
  });
  @override
  String toString() => 'S3ConflictException($expectedEtag): $message';
}

/// Spreekt S3 en S3-compatible endpoints over `dart:io HttpClient` met
/// SigV4-ondertekening ([S3Signer]).
///
/// Deelt bewust alle veiligheidsmaatregelen met [WebdavService]: geen redirects
/// (een 3xx mag de host-controle niet omzeilen), harde groottelimieten en
/// socket-pinning tegen DNS-rebind. Een privé/LAN-endpoint mag alleen wanneer de
/// gebruiker het als vertrouwd heeft gemarkeerd
/// ([S3Bucket.trustedInternal]) — een zelf gehoste MinIO is juist het gangbare
/// geval, dus dat moet kunnen, maar bewust.
class S3Service {
  S3Service({
    required this.bucket,
    required this.secretAccessKey,
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  final S3Bucket bucket;
  final String secretAccessKey;

  /// Injecteerbaar zodat de test tegen een vaste klok kan draaien.
  final DateTime Function() _clock;

  static const int maxDownloadBytes = FileService.maxPackageBytes;

  /// Cap op één listing-respons zodat een vijandig endpoint het geheugen niet
  /// kan laten vollopen.
  static const int maxListingBytes = 16 * 1024 * 1024;

  /// Maximaal aantal entries dat we over alle pagina's samen accepteren.
  static const int maxListingEntries = 5000;

  /// Aantal sleutels per ListObjectsV2-aanroep.
  static const int _pageSize = 1000;

  S3Signer get _signer => S3Signer(
    accessKeyId: bucket.accessKeyId.trim(),
    secretAccessKey: secretAccessKey,
    region: bucket.region.trim(),
  );

  /// Resolve + pin de endpoint-host. Geeft een client met gepinde socket terug,
  /// of gooit [S3Exception] bij een geblokkeerde/onbereikbare host.
  Future<HttpClient> _client() async {
    if (!bucket.isConfigured) {
      throw S3Exception(S3Error.config, 'S3-bron niet ingesteld');
    }
    // De host die we daadwerkelijk bellen — bij virtual-hosted adressering zit
    // de bucketnaam daarin, en dát is de naam die het certificaat moet dekken
    // en die we dus ook moeten resolven en pinnen.
    final host = bucket.signingHost;
    if (host.isEmpty || bucket.endpointHost.isEmpty) {
      throw S3Exception(S3Error.config, 'Ongeldige endpoint-URL');
    }
    // SigV4 ondertekent elk verzoek, dus er gaat geen herbruikbaar geheim over
    // de lijn zoals bij basic-auth. De inhoud van de decks is niettemin
    // vertrouwelijk, dus geldt dezelfde eis als bij WebDAV: https, tenzij de
    // gebruiker de server bewust als vertrouwd intern heeft gemarkeerd.
    final scheme = bucket.origin?.scheme.toLowerCase();
    if (scheme != 'https' && !(scheme == 'http' && bucket.trustedInternal)) {
      throw S3Exception(
        S3Error.config,
        scheme == 'http'
            ? 'Gebruik https of markeer het endpoint als vertrouwd intern; '
                  'anders gaan je presentaties onversleuteld over het netwerk.'
            : 'Alleen https-endpoints worden ondersteund.',
      );
    }
    final resolved = await NetGuard.resolveConfigured(
      host,
      allowPrivate: bucket.trustedInternal,
    );
    if (!resolved.isOk) {
      throw switch (resolved.refusal!) {
        HostRefusal.unknownHost => S3Exception(
          S3Error.unknownHost,
          'Endpoint-naam niet gevonden',
        ),
        HostRefusal.blocked => S3Exception(
          S3Error.blockedHost,
          'Endpoint-host geweigerd',
        ),
      };
    }
    final pinned = resolved.addresses!.first;
    return HttpClient()
      ..connectionTimeout = const Duration(seconds: 15)
      ..connectionFactory = (u, proxyHost, proxyPort) => NetGuard.connectPinned(
        pinned,
        u,
        onBadCertificate: NetGuard.pinnedCertCheck(bucket.pinnedCertSha256),
      );
  }

  /// De `Host`-header zoals `HttpClient` hem zal versturen. Moet exact zo mee
  /// ondertekend worden, inclusief poort wanneer die niet de standaard is.
  static String hostHeaderFor(Uri uri) {
    final isDefault =
        (uri.scheme == 'https' && uri.port == 443) ||
        (uri.scheme == 'http' && uri.port == 80);
    return isDefault ? uri.host : '${uri.host}:${uri.port}';
  }

  /// Open een ondertekend verzoek. [extraHeaders] gaan mee in de handtekening;
  /// headers die je hierna nog zet, doen dat niet.
  Future<HttpClientRequest> _openSigned(
    HttpClient client,
    String method,
    Uri uri, {
    Map<String, String> extraHeaders = const {},
    required String payloadSha256,
  }) async {
    final signed = _signer.sign(
      method: method,
      uri: uri,
      headers: {'host': hostHeaderFor(uri), ...extraHeaders},
      payloadSha256: payloadSha256,
      now: _clock(),
    );
    final request = await client.openUrl(method, uri);
    request.followRedirects = false; // 3xx mag de host-check niet omzeilen
    extraHeaders.forEach(request.headers.set);
    signed.forEach(request.headers.set);
    return request;
  }

  void _checkStatus(int status) {
    if (status == 401 || status == 403) {
      throw S3Exception(S3Error.auth, 'Aanmelden mislukt ($status)');
    }
    if (status == 404) {
      throw S3Exception(S3Error.notFound, 'Niet gevonden');
    }
    if (status >= 500) {
      throw S3Exception(S3Error.server, 'Serverfout ($status)');
    }
  }

  /// Listing van [remotePath] (relatief aan de wortelprefix), met een delimiter
  /// zodat onderliggende prefixen als mappen terugkomen in plaats van als één
  /// platte sleutellijst.
  /// Vertaal een gevangen laag-niveau fout naar een [S3Exception] die weet of
  /// hij het opnieuw proberen waard is. Spiegelt `WebdavService._asFailure`.
  static Never _asFailure(String where, Object e, String fallback) {
    if (e is SocketException) {
      logWarning('S3Service.$where: endpoint onbereikbaar', e);
      throw S3Exception(
        S3Error.network,
        'Endpoint niet bereikbaar',
        transient: true,
      );
    }
    // Een verbinding die halverwege wegviel meldt Dart als HttpException.
    if (e is HttpException) {
      logWarning('S3Service.$where: verbinding afgebroken', e);
      throw S3Exception(
        S3Error.network,
        'Verbinding afgebroken',
        transient: true,
      );
    }
    logError('S3Service.$where: mislukt', e);
    throw S3Exception(S3Error.network, fallback);
  }

  /// Voer een *leesactie* uit en probeer hem één keer opnieuw wanneer de
  /// verbinding wegviel. Alleen voor lezen — zie `WebdavService._retryRead`
  /// voor waarom schrijven er niet in hoort.
  static Future<T> _retryRead<T>(
    String where,
    Future<T> Function() attempt,
  ) async {
    try {
      return await attempt();
    } on S3Exception catch (e) {
      if (!e.transient) rethrow;
      logWarning('S3Service.$where: verbinding weg, nog één poging', e);
      await Future<void>.delayed(const Duration(milliseconds: 400));
      return attempt();
    }
  }

  Future<List<S3Entry>> list(String remotePath) =>
      _retryRead('list', () => _listOnce(remotePath));

  Future<List<S3Entry>> _listOnce(String remotePath) async {
    final prefixKey = bucket.keyFor(remotePath);
    if (prefixKey == null) {
      throw S3Exception(S3Error.config, 'Pad buiten de wortelprefix');
    }
    // S3 wil een prefix die op de delimiter eindigt, anders zou `map` ook
    // `map-archief` matchen.
    final prefix = prefixKey.isEmpty ? '' : '$prefixKey/';
    final rootPrefix = S3Bucket.normalizeRoot(bucket.rootPath);
    final stripLength = rootPrefix.isEmpty ? 0 : rootPrefix.length + 1;

    final client = await _client();
    try {
      final entries = <S3Entry>[];
      String? continuationToken;
      do {
        final uri = bucket.uriForKey(
          '',
          query: {
            'list-type': '2',
            'delimiter': '/',
            'max-keys': '$_pageSize',
            if (prefix.isNotEmpty) 'prefix': prefix,
            'continuation-token': ?continuationToken,
          },
        );
        if (uri == null) {
          throw S3Exception(S3Error.config, 'Ongeldige endpoint-URL');
        }
        final request = await _openSigned(
          client,
          'GET',
          uri,
          payloadSha256: S3Signer.emptyPayloadHash,
        );
        final response = await request.close().timeout(
          const Duration(seconds: 30),
        );
        _checkStatus(response.statusCode);
        if (response.statusCode != 200) {
          throw S3Exception(
            S3Error.server,
            'Onverwachte status ${response.statusCode}',
          );
        }
        final body = await _readCapped(response, maxListingBytes);
        final page = parseListObjectsV2(body, stripLength);
        entries.addAll(page.entries);
        if (entries.length > maxListingEntries) {
          throw S3Exception(S3Error.tooLarge, 'Te veel bestanden in deze map');
        }
        continuationToken = page.nextContinuationToken;
      } while (continuationToken != null);
      return entries;
    } on S3Exception {
      rethrow;
    } on TimeoutException {
      throw S3Exception(S3Error.network, 'Time-out');
    } catch (e) {
      _asFailure('list', e, 'Listing mislukt');
    } finally {
      client.close(force: true);
    }
  }

  /// Download het object op [remotePath].
  Future<S3File> download(
    String remotePath, {
    int maxBytes = maxDownloadBytes,
  }) => _retryRead(
    'download',
    () => _downloadOnce(remotePath, maxBytes: maxBytes),
  );

  Future<S3File> _downloadOnce(
    String remotePath, {
    int maxBytes = maxDownloadBytes,
  }) async {
    final key = bucket.keyFor(remotePath);
    if (key == null || key.isEmpty) {
      throw S3Exception(S3Error.config, 'Pad buiten de wortelprefix');
    }
    final uri = bucket.uriForKey(key);
    if (uri == null) {
      throw S3Exception(S3Error.config, 'Ongeldige endpoint-URL');
    }
    final client = await _client();
    try {
      final request = await _openSigned(
        client,
        'GET',
        uri,
        payloadSha256: S3Signer.emptyPayloadHash,
      );
      final response = await request.close().timeout(
        const Duration(seconds: 60),
      );
      _checkStatus(response.statusCode);
      if (response.statusCode != 200) {
        throw S3Exception(
          S3Error.server,
          'Onverwachte status ${response.statusCode}',
        );
      }
      if (response.contentLength > maxBytes) {
        throw S3Exception(S3Error.tooLarge, 'Bestand te groot');
      }
      final bytes = await _readCappedBytes(response, maxBytes);
      return S3File(bytes, response.headers.value(HttpHeaders.etagHeader));
    } on S3Exception {
      rethrow;
    } on TimeoutException {
      throw S3Exception(S3Error.network, 'Time-out');
    } catch (e) {
      _asFailure('download', e, 'Download mislukt');
    } finally {
      client.close(force: true);
    }
  }

  /// Upload [bytes] naar [remotePath]. Geeft de nieuwe ETag terug wanneer het
  /// endpoint er een meldt.
  ///
  /// Anders dan bij WebDAV hoeven er geen bovenliggende mappen gemaakt te
  /// worden: een sleutel met slashes erin ís het hele pad.
  ///
  /// [ifMatch] maakt de PUT voorwaardelijk. Niet elk S3-compatible endpoint
  /// ondersteunt dat — AWS pas sinds 2024 — dus een endpoint dat de voorwaarde
  /// niet kent levert [S3Error.conditionalUnsupported] op in plaats van
  /// stilzwijgend te overschrijven. Dat is precies het geval waarin gelijktijdig
  /// bewerken hier zwakker beschermd is dan bij WebDAV, en de gebruiker hoort
  /// dat te weten.
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
    final key = bucket.keyFor(remotePath);
    if (key == null || key.isEmpty) {
      throw S3Exception(S3Error.config, 'Pad buiten de wortelprefix');
    }
    final uri = bucket.uriForKey(key);
    if (uri == null) {
      throw S3Exception(S3Error.config, 'Ongeldige endpoint-URL');
    }
    final client = await _client();
    try {
      final request = await _openSigned(
        client,
        'PUT',
        uri,
        extraHeaders: {
          'content-type': 'application/octet-stream',
          'if-match': ?ifMatch,
          if (onlyIfAbsent) 'if-none-match': '*',
        },
        payloadSha256: S3Signer.hashPayload(bytes),
      );
      request.add(bytes);
      final response = await request.close().timeout(
        const Duration(seconds: 120),
      );
      // Vóór _checkStatus: deze statussen betekenen hier iets specifieks en
      // mogen niet als algemene serverfout wegvallen.
      if (response.statusCode == 412 || response.statusCode == 409) {
        await response.drain<void>();
        throw S3ConflictException(
          expectedEtag: ifMatch ?? '*',
          message: 'Bestand op de server gewijzigd (${response.statusCode})',
        );
      }
      if (response.statusCode == 501 && (ifMatch != null || onlyIfAbsent)) {
        await response.drain<void>();
        throw S3Exception(
          S3Error.conditionalUnsupported,
          'Dit endpoint ondersteunt geen voorwaardelijk schrijven',
        );
      }
      _checkStatus(response.statusCode);
      final newEtag = response.headers.value(HttpHeaders.etagHeader);
      await response.drain<void>();
      if (response.statusCode != 200 && response.statusCode != 201) {
        throw S3Exception(
          S3Error.server,
          'Upload gaf status ${response.statusCode}',
        );
      }
      return newEtag;
    } on S3Exception {
      rethrow;
    } on S3ConflictException {
      rethrow;
    } on TimeoutException {
      throw S3Exception(S3Error.network, 'Time-out');
    } catch (e) {
      logError('S3Service.upload: mislukt', e);
      throw S3Exception(S3Error.network, 'Upload mislukt');
    } finally {
      client.close(force: true);
    }
  }

  /// Korte verbindingstest: een listing van nul sleutels op de wortelprefix.
  ///
  /// Bewust geen proefobject wegschrijven om te zien of voorwaardelijk
  /// schrijven werkt — dat zou rommel achterlaten in de bucket van de
  /// gebruiker. Die eigenschap blijkt vanzelf bij de eerste echte opslag.
  Future<void> probe() => _retryRead('probe', _probeOnce);

  Future<void> _probeOnce() async {
    final uri = bucket.uriForKey(
      '',
      query: {'list-type': '2', 'max-keys': '0'},
    );
    if (uri == null) {
      throw S3Exception(S3Error.config, 'Ongeldige endpoint-URL');
    }
    final client = await _client();
    try {
      final request = await _openSigned(
        client,
        'GET',
        uri,
        payloadSha256: S3Signer.emptyPayloadHash,
      );
      final response = await request.close().timeout(
        const Duration(seconds: 20),
      );
      _checkStatus(response.statusCode);
      await response.drain<void>();
      if (response.statusCode != 200) {
        throw S3Exception(
          S3Error.server,
          'Onverwachte status ${response.statusCode}',
        );
      }
    } on S3Exception {
      rethrow;
    } on TimeoutException {
      throw S3Exception(S3Error.network, 'Time-out');
    } catch (e) {
      _asFailure('probe', e, 'Verbinding mislukt');
    } finally {
      client.close(force: true);
    }
  }

  Future<Uint8List> _readCappedBytes(
    HttpClientResponse response,
    int max,
  ) async {
    final builder = BytesBuilder(copy: false);
    await for (final chunk in response) {
      builder.add(chunk);
      if (builder.length > max) {
        throw S3Exception(S3Error.tooLarge, 'Bestand te groot');
      }
    }
    return builder.takeBytes();
  }

  Future<String> _readCapped(HttpClientResponse response, int max) async {
    final bytes = await _readCappedBytes(response, max);
    return String.fromCharCodes(bytes);
  }

  /// Ontleedt een ListObjectsV2-antwoord.
  ///
  /// [stripLength] is het aantal tekens dat er vooraan af moet om van een
  /// volledige sleutel een pad relatief aan de wortelprefix te maken.
  ///
  /// Statisch en zonder netwerk, zodat het formaat los te toetsen is — dezelfde
  /// keuze als `WebdavService.parseMultistatus`.
  static S3ListPage parseListObjectsV2(String xmlBody, int stripLength) {
    final XmlDocument doc;
    try {
      doc = XmlDocument.parse(xmlBody);
    } catch (e) {
      logWarning('S3Service.parseListObjectsV2: onleesbaar antwoord', e);
      throw S3Exception(S3Error.server, 'Onleesbaar antwoord van de server');
    }
    // Op lokale naam matchen, niet op gekwalificeerde: AWS zet er een default
    // namespace omheen en niet elk S3-compatible endpoint doet dat hetzelfde.
    Iterable<XmlElement> byName(XmlElement parent, String local) =>
        parent.findElements('*').where((e) => e.name.local == local);
    String? textOf(XmlElement parent, String local) =>
        byName(parent, local).firstOrNull?.innerText.trim();

    final root = doc.rootElement;
    final entries = <S3Entry>[];

    // CommonPrefixes eerst: mappen horen boven bestanden in de bladeraar.
    for (final cp in byName(root, 'CommonPrefixes')) {
      final prefix = textOf(cp, 'Prefix');
      if (prefix == null || prefix.isEmpty) continue;
      final relative = _strip(prefix, stripLength);
      // Een prefix eindigt op de delimiter; die hoort niet in de naam.
      final trimmed = relative.endsWith('/')
          ? relative.substring(0, relative.length - 1)
          : relative;
      if (trimmed.isEmpty) continue;
      entries.add(
        S3Entry(
          name: trimmed.split('/').last,
          relativePath: trimmed,
          isCollection: true,
        ),
      );
    }

    for (final c in byName(root, 'Contents')) {
      final key = textOf(c, 'Key');
      if (key == null || key.isEmpty) continue;
      // Een sleutel die op de delimiter eindigt is het "map-object" dat sommige
      // clients aanmaken om een lege map te suggereren; die hoort niet als
      // bestand in de lijst.
      if (key.endsWith('/')) continue;
      final relative = _strip(key, stripLength);
      if (relative.isEmpty) continue;
      entries.add(
        S3Entry(
          name: relative.split('/').last,
          relativePath: relative,
          isCollection: false,
          size: int.tryParse(textOf(c, 'Size') ?? ''),
          etag: textOf(c, 'ETag'),
        ),
      );
    }

    final truncated =
        (textOf(root, 'IsTruncated') ?? '').toLowerCase() == 'true';
    final token = textOf(root, 'NextContinuationToken');
    return S3ListPage(
      entries: entries,
      nextContinuationToken: truncated && (token?.isNotEmpty ?? false)
          ? token
          : null,
    );
  }

  static String _strip(String key, int stripLength) =>
      key.length <= stripLength ? '' : key.substring(stripLength);
}

/// Eén pagina van een listing plus de sleutel om de volgende op te halen.
class S3ListPage {
  final List<S3Entry> entries;

  /// `null` wanneer dit de laatste pagina was.
  final String? nextContinuationToken;

  const S3ListPage({required this.entries, this.nextContinuationToken});
}
