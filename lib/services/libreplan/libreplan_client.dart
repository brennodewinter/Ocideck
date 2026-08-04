/// LibrePlan REST-client: GET-only, Basic Auth, XML, via NetGuard + pinning.
///
/// Spiegelt `ai_client_service.dart`: een injecteerbare transport-seam zodat
/// tests geen netwerk raken, en een default transport die de host via NetGuard
/// resolveert, de socket pinnet, redirects weigert en de response cappeert.
///
/// Beveiligingscontract (design-doc §5):
/// - **GET-only**: geen POST/DELETE — read-only consumer.
/// - **Basic Auth**: username:password → base64, wachtwoord uit de keychain.
/// - **NetGuard**: SSRF-guard, interne adressen dicht tenzij `trustedInternal`.
/// - **HTTPS verplicht**: plain HTTP alleen voor vertrouwde interne servers.
/// - **followRedirects = false**: een 3xx mag niet om de hostcontrole heen.
/// - **Desktop-only**: op web is de keychain niet veilig (fail-closed).
/// - **Logs**: base URL + username bij fout, nooit de response body (bevat
///   projectdata).

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import '../../models/libreplan_settings.dart';
import '../../platform/platform_features.dart';
import '../../utils/log.dart';
import '../../utils/net_guard.dart';

/// Eén HTTP-uitwisseling over de transport-seam.
class LibreplanHttpResult {
  final int statusCode;
  final String body;
  const LibreplanHttpResult(this.statusCode, this.body);
}

/// Injecteerbare transport-seam. Tests leveren een fake; de default
/// ([PinnedLibreplanTransport]) resolveert en pinnet volgens NetGuard.
abstract class LibreplanHttpTransport {
  Future<LibreplanHttpResult> get({
    required Uri url,
    required bool trustedInternal,
    Map<String, String> headers,
    Duration timeout,
  });
}

/// Netwerk- of protocolfout bij het praten met LibrePlan.
class LibreplanRequestException implements Exception {
  final String message;
  const LibreplanRequestException(this.message);

  @override
  String toString() => 'LibreplanRequestException: $message';
}

/// De default transport: resolveert de host via NetGuard (met of zonder
/// `trustedInternal`), pinnet de socket, weigert redirects, cappeert de
/// response. Dit is de ENIGE plek in de LibrePlan-connector die een ruwe
/// `HttpClient` opent; het bestand staat in `network_sink_guard_test.dart`.
class PinnedLibreplanTransport implements LibreplanHttpTransport {
  const PinnedLibreplanTransport();

  /// Cap op de response body. Een LibrePlan-projectsnapshot is ruim voldoende
  /// onder 10 MB; een kwaadaardige server die meer stuurt wordt geweigerd.
  static const int maxResponseBytes = 10 * 1024 * 1024;

  @override
  Future<LibreplanHttpResult> get({
    required Uri url,
    required bool trustedInternal,
    Map<String, String> headers = const {},
    Duration timeout = const Duration(seconds: 30),
  }) async {
    final pinned = await _resolvePinned(url.host, trustedInternal);
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 15)
      ..connectionFactory = (u, proxyHost, proxyPort) =>
          NetGuard.connectPinned(pinned, u);
    try {
      final request = await client.openUrl('GET', url);
      request.followRedirects = false; // a 3xx must not bypass the host check
      headers.forEach(request.headers.set);
      final response = await request.close().timeout(timeout);
      final builder = BytesBuilder(copy: false);
      await for (final chunk in response) {
        builder.add(chunk);
        if (builder.length > maxResponseBytes) {
          throw const LibreplanRequestException('response too large');
        }
      }
      return LibreplanHttpResult(
        response.statusCode,
        utf8.decode(builder.takeBytes(), allowMalformed: true),
      );
    } on LibreplanRequestException {
      rethrow;
    } on TimeoutException {
      throw const LibreplanRequestException('timeout');
    } catch (e) {
      // Host bewust weggelaten: user-configured maar mogelijk gevoelig.
      logError('PinnedLibreplanTransport.get: request failed', e);
      throw const LibreplanRequestException('network');
    } finally {
      client.close(force: true);
    }
  }

  /// Resolve [host] tot het adres waar de socket aan gepind wordt. Bij
  /// `trustedInternal` mogen privé-adressen passeren (LAN LibrePlan).
  Future<InternetAddress> _resolvePinned(
    String host,
    bool trustedInternal,
  ) async {
    final addrs = trustedInternal
        ? await NetGuard.safeResolveTrusted(host, allowPrivate: true)
        : await NetGuard.safeResolve(host);
    if (addrs == null || addrs.isEmpty) {
      throw const LibreplanRequestException('host refused or unreachable');
    }
    return addrs.first;
  }
}

/// De LibrePlan REST-client. GET-only, Basic Auth, XML-responses. Gate elke
/// request door de beveiligingscontroles (HTTPS, desktop-only) voordat het
/// naar de (injecteerbare) transport gaat.
class LibreplanClient {
  LibreplanClient({
    required this.settings,
    this.password,
    LibreplanHttpTransport? transport,
    bool? isWeb,
  })  : _transport = transport ?? const PinnedLibreplanTransport(),
        _isWeb = isWeb ?? isWebPlatform;

  final LibreplanSettings settings;
  final String? password;
  final LibreplanHttpTransport _transport;
  final bool _isWeb;

  /// Of de client mag verzoeken sturen — de beveiligingspoort.
  ///
  /// - **Desktop-only**: op web is de keychain niet veilig.
  /// - **HTTPS verplicht**: plain HTTP alleen voor vertrouwde interne servers.
  /// - **Geconfigureerd**: base URL en username mogen niet leeg zijn.
  bool get canSend {
    if (_isWeb) return false;
    if (!settings.hasBackend) return false;
    if (!settings.isHttps && !settings.trustedInternal) return false;
    return true;
  }

  /// De reden dat [canSend] false is, voor de UI.
  String? get denialReason {
    if (_isWeb) return 'LibrePlan-connector is alleen beschikbaar op desktop.';
    if (!settings.hasBackend) return 'Geen server geconfigureerd.';
    if (!settings.isHttps && !settings.trustedInternal) {
      return 'HTTPS verplicht tenzij de server vertrouwd intern is.';
    }
    return null;
  }

  /// Bouw de REST-URL voor een service-path. LibrePlan's API leeft onder
  /// `/ws/rest/<service-path>/` relatief ten opzichte van de base URL.
  Uri _endpoint(String servicePath) {
    final base = settings.baseUrl.trim().replaceAll(RegExp(r'/+$'), '');
    return Uri.parse('$base/ws/rest/$servicePath');
  }

  /// Basic Auth-header. Wachtwoord uit de keychain, nooit in prefs.
  Map<String, String> _headers() {
    final user = settings.username.trim();
    final pass = (password ?? '').trim();
    final credentials = base64Encode(utf8.encode('$user:$pass'));
    return {
      'authorization': 'Basic $credentials',
      'accept': 'application/xml',
    };
  }

  /// Voer een GET-request uit naar een service-path. Retourneert de XML-body.
  /// Werpt [LibreplanRequestException] bij een netwerkfout of non-2xx status.
  Future<String> fetch(String servicePath) async {
    if (!canSend) {
      throw LibreplanRequestException(denialReason ?? 'not configured');
    }
    final result = await _transport.get(
      url: _endpoint(servicePath),
      trustedInternal: settings.trustedInternal,
      headers: _headers(),
    );
    if (result.statusCode < 200 || result.statusCode >= 300) {
      // Log base URL + username, niet de response body (bevat projectdata).
      logWarning(
        'LibreplanClient.fetch($servicePath): '
        'HTTP ${result.statusCode} for ${settings.host} as ${settings.username}',
        null,
      );
      throw LibreplanRequestException('HTTP ${result.statusCode}');
    }
    return result.body;
  }

  /// Haal de projectlijst op (orderelements).
  Future<String> fetchOrders() => fetch('orderelements/');

  /// Haal één project op (orderelements/<code>).
  Future<String> fetchOrder(String code) => fetch('orderelements/$code/');

  /// Haal resources op.
  Future<String> fetchResources() => fetch('resources/');

  /// Haal resource-uren op tussen twee datums.
  Future<String> fetchResourceHours(DateTime start, DateTime end) {
    final s = _formatDate(start);
    final e = _formatDate(end);
    return fetch('resourceshours/$s/$e/');
  }

  /// Haal werkrapporten op.
  Future<String> fetchWorkReports() => fetch('workreports/');

  /// Haal declaraties op.
  Future<String> fetchExpenses() => fetch('expenses/');

  /// Lightweight verbindingstest: GET resources. Oefent de volledige
  /// resolve + pin + auth path zonder een volledige import.
  Future<void> testConnection() async {
    if (!canSend) {
      throw LibreplanRequestException(denialReason ?? 'not configured');
    }
    final result = await _transport.get(
      url: _endpoint('resources/'),
      trustedInternal: settings.trustedInternal,
      headers: _headers(),
      timeout: const Duration(seconds: 20),
    );
    if (result.statusCode < 200 || result.statusCode >= 300) {
      throw LibreplanRequestException('HTTP ${result.statusCode}');
    }
  }

  String _formatDate(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';
}
