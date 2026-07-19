import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../../models/local_cve_record.dart';
import '../../models/local_cve_status.dart';
import '../../utils/net_guard.dart';
import 'cve_bulk_ingest.dart';
import 'local_cve_database_api.dart';
import 'local_cve_index.dart';

/// Op desktop bestaat de lokale database wél.
const bool localCveSupported = true;

Future<LocalCveDatabase> createLocalCveDatabase() async {
  final support = await getApplicationSupportDirectory();
  return IoLocalCveDatabase(root: Directory('${support.path}/cve'));
}

class IoLocalCveDatabase implements LocalCveDatabase {
  final Directory root;
  final CveBulkTransport transport;

  IoLocalCveDatabase({required this.root, CveBulkTransport? transport})
    : transport = transport ?? const GithubBulkTransport();

  LocalCveIndex get _index => LocalCveIndex(root);

  @override
  bool get supported => true;

  @override
  Future<LocalCveStats?> stats() => _index.stats();

  @override
  Future<List<LocalCveRecord>> search(String query, {int limit = 25}) =>
      _index.search(query, limit: limit);

  @override
  Future<LocalCveStats> build({
    required void Function(CveIngestProgress) onProgress,
    required bool Function() isCancelled,
  }) {
    final ingest = CveBulkIngest(
      transport: transport,
      index: _index,
      workDirectory: Directory('${root.path}/work'),
    );
    return ingest.run(onProgress: onProgress, isCancelled: isCancelled);
  }

  @override
  Future<void> delete() => _index.delete();
}

/// Haalt de release-metadata en het bulkarchief bij GitHub.
///
/// Een release-download springt van `github.com` naar
/// `objects.githubusercontent.com`, dus redirects móéten gevolgd worden. Maar ze
/// door `HttpClient` laten volgen zou precies de SSRF-poort omzeilen die de rest
/// van de app wél heeft: een 3xx kan naar een intern adres wijzen (denk aan het
/// metadata-adres van een cloudinstantie), en dan haalt de app dat op alsof het
/// GitHub was.
///
/// Daarom volgen we ze zelf: elke sprong wordt opnieuw door
/// [NetGuard.safeResolve] gehaald en de socket wordt op het gecontroleerde adres
/// vastgezet — óók de tweede en derde hop. Alleen https, en hoogstens vijf
/// sprongen.
class GithubBulkTransport implements CveBulkTransport {
  const GithubBulkTransport();

  static const _userAgent = 'OciDeck';
  static const _maxRedirects = 5;

  /// Eén request, met de host opgelost en de socket erop vastgezet. Volgt geen
  /// redirects: dat doet [_follow], zodat elke hop opnieuw gekeurd wordt.
  Future<HttpClientResponse> _get(HttpClient client, Uri url) async {
    if (url.scheme != 'https') {
      throw const CveIngestException(
        CveIngestFailure.networkFailed,
        'alleen https',
      );
    }
    final addresses = await NetGuard.safeResolve(url.host);
    if (addresses == null || addresses.isEmpty) {
      throw CveIngestException(
        CveIngestFailure.networkFailed,
        'host geweigerd: ${url.host}',
      );
    }
    final pinned = addresses.first;

    // Zet de socket vast op het gekeurde adres, zodat een DNS-rebind tussen de
    // controle en de verbinding ons niet alsnog naar binnen stuurt.
    client.connectionFactory = (u, proxyHost, proxyPort) =>
        NetGuard.connectPinned(pinned, u);

    final request = await client.getUrl(url);
    request.headers.set(HttpHeaders.userAgentHeader, _userAgent);
    request.followRedirects = false;
    return request.close();
  }

  /// Volgt de redirect-keten met de hand, elke hop opnieuw door de poort.
  Future<HttpClientResponse> _follow(HttpClient client, Uri url) async {
    var target = url;
    for (var hop = 0; hop <= _maxRedirects; hop++) {
      final response = await _get(client, target);
      if (!response.isRedirect) return response;

      final location = response.headers.value(HttpHeaders.locationHeader);
      await response.drain<void>();
      if (location == null) {
        throw const CveIngestException(
          CveIngestFailure.networkFailed,
          'redirect zonder bestemming',
        );
      }
      target = target.resolve(location);
    }
    throw const CveIngestException(
      CveIngestFailure.networkFailed,
      'te veel omleidingen',
    );
  }

  @override
  Future<String> getJson(Uri url) async {
    final client = HttpClient();
    try {
      final response = await _follow(client, url);
      if (response.statusCode != 200) {
        throw HttpException('HTTP ${response.statusCode}', uri: url);
      }
      return await response.transform(utf8.decoder).join();
    } on SocketException catch (e) {
      throw CveIngestException(CveIngestFailure.networkFailed, e.message);
    } finally {
      client.close(force: true);
    }
  }

  @override
  Future<void> download(
    Uri url,
    File destination, {
    required void Function(int received, int total) onProgress,
    required bool Function() isCancelled,
  }) async {
    destination.parent.createSync(recursive: true);
    final client = HttpClient();
    IOSink? sink;
    try {
      final response = await _follow(client, url);
      if (response.statusCode != 200) {
        throw CveIngestException(
          CveIngestFailure.networkFailed,
          'HTTP ${response.statusCode}',
        );
      }

      final total = response.contentLength;
      var received = 0;
      sink = destination.openWrite();

      await for (final chunk in response) {
        if (isCancelled()) {
          throw const CveIngestException(CveIngestFailure.cancelled);
        }
        sink.add(chunk);
        received += chunk.length;
        onProgress(received, total > 0 ? total : 0);
      }
      await sink.flush();
    } on SocketException catch (e) {
      throw CveIngestException(CveIngestFailure.networkFailed, e.message);
    } on HttpException catch (e) {
      throw CveIngestException(CveIngestFailure.networkFailed, e.message);
    } finally {
      await sink?.close();
      client.close(force: true);
    }
  }
}
