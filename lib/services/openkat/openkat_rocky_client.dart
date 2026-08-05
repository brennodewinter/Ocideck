// OpenKAT Rocky REST-client: GET-only, Knox token-auth, via NetGuard + pinning.
//
// Spiegelt `libreplan_client.dart`: injecteerbare transport-seam, HTTPS tenzij
// trustedInternal, followRedirects = false, desktop-only, logs zonder token of
// response-body.
//
// Endpoints (zie docs/design/OPENKAT_ROCKY_REPORT_API.md):
// - GET /api/v1/organization/
// - GET /api/v1/report/?organization_code=…
// - GET /api/v1/report/{pk}/json/?organization_code=…  (toekomstig; v1 probeert
//   en valt terug als upstream het nog niet heeft)
//
// Geen Octopoes/Bytes, geen recipe-CRUD in v1.

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import '../../models/openkat/openkat_installation.dart';
import '../../platform/platform_features.dart';
import '../../utils/log.dart';
import '../../utils/net_guard.dart';

/// Knox Authorization-headerwaarde. Nooit loggen.
String openKatAuthHeader(String token) => 'Token ${token.trim()}';

/// Report-type id van het aggregaat-organisatierapport — de enige vorm die
/// OciDeck's adapters vandaag als organisatierapport herkennen.
const kOpenKatAggregateReportType = 'aggregate-organisation-report';

/// Eén HTTP-uitwisseling over de transport-seam.
class OpenKatHttpResult {
  final int statusCode;
  final String body;
  const OpenKatHttpResult(this.statusCode, this.body);
}

/// Injecteerbare transport-seam. Tests leveren een fake; de default
/// ([PinnedOpenKatTransport]) resolveert en pinnet volgens NetGuard.
abstract class OpenKatHttpTransport {
  Future<OpenKatHttpResult> get({
    required Uri url,
    required bool trustedInternal,
    Map<String, String> headers,
    Duration timeout,
  });
}

/// Netwerk- of protocolfout bij het praten met OpenKAT Rocky.
class OpenKatRequestException implements Exception {
  final String message;

  /// HTTP-status indien bekend (401/403/…); null bij transportfouten.
  final int? statusCode;

  const OpenKatRequestException(this.message, {this.statusCode});

  @override
  String toString() => 'OpenKatRequestException: $message';
}

/// Of Rocky een JSON-payload-actie op `/api/v1/report/{pk}/json/` ondersteunt.
enum OpenKatJsonCapability {
  /// Nog niet geprobeerd in deze clientsessie.
  unknown,

  /// Endpoint gaf een bruikbare JSON-envelope.
  available,

  /// Endpoint ontbreekt of weigert (404/405/…) — gebruik begeleidde export.
  unavailable,
}

/// Organisatie uit `GET /api/v1/organization/`.
class OpenKatOrganization {
  final int? id;
  final String name;
  final String code;

  const OpenKatOrganization({this.id, required this.name, required this.code});

  factory OpenKatOrganization.fromJson(Map<String, Object?> json) {
    return OpenKatOrganization(
      id: json['id'] is int ? json['id'] as int : int.tryParse('${json['id']}'),
      name: (json['name'] as String?)?.trim() ?? '',
      code: (json['code'] as String?)?.trim() ?? '',
    );
  }
}

/// Rapport-metadata uit `GET /api/v1/report/`. Geen payload.
class OpenKatReportRef {
  /// Volledige id zoals Rocky die teruggeeft (`Report|<uuid>` of kaal uuid).
  final String id;

  final String name;
  final String reportType;
  final DateTime? generatedAt;

  const OpenKatReportRef({
    required this.id,
    required this.name,
    required this.reportType,
    this.generatedAt,
  });

  /// UUID-deel voor pad `/api/v1/report/{pk}/`.
  String get pk {
    final raw = id.trim();
    final pipe = raw.indexOf('|');
    if (pipe >= 0 && pipe + 1 < raw.length) return raw.substring(pipe + 1);
    return raw;
  }

  bool get isAggregate => reportType == kOpenKatAggregateReportType;

  factory OpenKatReportRef.fromJson(Map<String, Object?> json) {
    final generated =
        json['generated_at'] as String? ?? json['valid_time'] as String?;
    return OpenKatReportRef(
      id: (json['id'] as String?)?.trim() ?? '',
      name: (json['name'] as String?)?.trim() ?? '',
      reportType: (json['report_type'] as String?)?.trim() ?? '',
      generatedAt: generated == null ? null : DateTime.tryParse(generated),
    );
  }
}

/// De default transport: NetGuard resolve + pin, geen redirects, body-cap.
class PinnedOpenKatTransport implements OpenKatHttpTransport {
  const PinnedOpenKatTransport();

  /// Cap op de response. Org-/rapportlijsten zijn klein; een toekomstige JSON-
  /// payload van een aggregaat-rapport past ruim onder 20 MB.
  static const int maxResponseBytes = 20 * 1024 * 1024;

  @override
  Future<OpenKatHttpResult> get({
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
      request.followRedirects = false;
      headers.forEach(request.headers.set);
      final response = await request.close().timeout(timeout);
      final builder = BytesBuilder(copy: false);
      await for (final chunk in response) {
        builder.add(chunk);
        if (builder.length > maxResponseBytes) {
          throw const OpenKatRequestException('response too large');
        }
      }
      return OpenKatHttpResult(
        response.statusCode,
        utf8.decode(builder.takeBytes(), allowMalformed: true),
      );
    } on OpenKatRequestException {
      rethrow;
    } on TimeoutException {
      throw const OpenKatRequestException('timeout');
    } catch (e) {
      logError('PinnedOpenKatTransport.get: request failed', e);
      throw const OpenKatRequestException('network');
    } finally {
      client.close(force: true);
    }
  }

  Future<InternetAddress> _resolvePinned(
    String host,
    bool trustedInternal,
  ) async {
    final addrs = trustedInternal
        ? await NetGuard.safeResolveTrusted(host, allowPrivate: true)
        : await NetGuard.safeResolve(host);
    if (addrs == null || addrs.isEmpty) {
      throw const OpenKatRequestException('host refused or unreachable');
    }
    return addrs.first;
  }
}

/// Rocky REST-client voor één [OpenKatInstallation] + token.
class OpenKatRockyClient {
  OpenKatRockyClient({
    required this.installation,
    required this.token,
    OpenKatHttpTransport? transport,
    bool? isWeb,
  }) : _transport = transport ?? const PinnedOpenKatTransport(),
       _isWeb = isWeb ?? isWebPlatform;

  final OpenKatInstallation installation;
  final String token;
  final OpenKatHttpTransport _transport;
  final bool _isWeb;

  OpenKatJsonCapability _jsonCapability = OpenKatJsonCapability.unknown;

  /// Laatst bekende JSON-capability (na een [fetchReportJson]-poging).
  OpenKatJsonCapability get jsonCapability => _jsonCapability;

  bool get canSend {
    if (_isWeb) return false;
    if (!installation.isConfigured) return false;
    if (token.trim().isEmpty) return false;
    if (!installation.isHttps && !installation.trustedInternal) return false;
    return true;
  }

  /// Interne denial-code voor mapping naar UI-teksten (geen l10n hier).
  String? get denialReason {
    if (_isWeb) return 'desktop_only';
    if (!installation.isConfigured) return 'not_configured';
    if (token.trim().isEmpty) return 'token_missing';
    if (!installation.isHttps && !installation.trustedInternal) {
      return 'https_required';
    }
    return null;
  }

  Uri _api(String path, [Map<String, String>? query]) {
    final base = installation.baseUrl;
    final normalizedPath = path.startsWith('/') ? path : '/$path';
    final uri = Uri.parse('$base$normalizedPath');
    if (query == null || query.isEmpty) return uri;
    return uri.replace(queryParameters: {...uri.queryParameters, ...query});
  }

  Map<String, String> _headers() => {
    'authorization': openKatAuthHeader(token),
    'accept': 'application/json',
  };

  Future<OpenKatHttpResult> _get(
    Uri url, {
    Duration timeout = const Duration(seconds: 30),
  }) async {
    if (!canSend) {
      throw OpenKatRequestException(denialReason ?? 'not configured');
    }
    return _transport.get(
      url: url,
      trustedInternal: installation.trustedInternal,
      headers: _headers(),
      timeout: timeout,
    );
  }

  void _throwForStatus(int status, String context) {
    logWarning(
      'OpenKatRockyClient.$context: HTTP $status for ${installation.host}',
      null,
    );
    throw OpenKatRequestException('HTTP $status', statusCode: status);
  }

  /// Lichtgewicht verbindingstest: organisaties ophalen.
  Future<List<OpenKatOrganization>> testConnection() => listOrganizations();

  /// `GET /api/v1/organization/` — geen paginatie upstream.
  Future<List<OpenKatOrganization>> listOrganizations() async {
    final result = await _get(_api('/api/v1/organization/'));
    if (result.statusCode < 200 || result.statusCode >= 300) {
      _throwForStatus(result.statusCode, 'listOrganizations');
    }
    return _parseOrganizationList(result.body);
  }

  /// `GET /api/v1/report/?organization_code=` — alleen aggregaat-rapporten.
  Future<List<OpenKatReportRef>> listAggregateReports(
    String organizationCode,
  ) async {
    final code = organizationCode.trim();
    if (code.isEmpty) {
      throw const OpenKatRequestException('organization_code required');
    }
    final all = <OpenKatReportRef>[];
    var offset = 0;
    const limit = 100;
    while (true) {
      final result = await _get(
        _api('/api/v1/report/', {
          'organization_code': code,
          'limit': '$limit',
          'offset': '$offset',
        }),
      );
      if (result.statusCode < 200 || result.statusCode >= 300) {
        _throwForStatus(result.statusCode, 'listAggregateReports');
      }
      final page = _parseReportList(result.body);
      all.addAll(page.results.where((r) => r.isAggregate));
      if (page.results.length < limit || page.next == null) break;
      offset += limit;
      if (offset > 5000) break; // fail-closed tegen eindeloze paginatie
    }
    all.sort((a, b) {
      final da = a.generatedAt;
      final db = b.generatedAt;
      if (da == null && db == null) return 0;
      if (da == null) return 1;
      if (db == null) return -1;
      return db.compareTo(da);
    });
    return all;
  }

  /// Probeert `GET /api/v1/report/{pk}/json/`. Retourneert null wanneer
  /// upstream het endpoint nog niet heeft (pad B blijft dan de UX).
  ///
  /// Bij succes: ruwe JSON-string in dezelfde envelope als de UI-export.
  Future<String?> fetchReportJson({
    required String reportPk,
    required String organizationCode,
  }) async {
    final pk = reportPk.trim();
    final code = organizationCode.trim();
    if (pk.isEmpty || code.isEmpty) {
      throw const OpenKatRequestException('pk and organization_code required');
    }
    final result = await _get(
      _api('/api/v1/report/$pk/json/', {'organization_code': code}),
      timeout: const Duration(seconds: 60),
    );
    if (result.statusCode == 404 ||
        result.statusCode == 405 ||
        result.statusCode == 501) {
      _jsonCapability = OpenKatJsonCapability.unavailable;
      return null;
    }
    if (result.statusCode < 200 || result.statusCode >= 300) {
      _throwForStatus(result.statusCode, 'fetchReportJson');
    }
    final trimmed = result.body.trim();
    if (trimmed.isEmpty ||
        !(trimmed.startsWith('{') || trimmed.startsWith('['))) {
      _jsonCapability = OpenKatJsonCapability.unavailable;
      return null;
    }
    _jsonCapability = OpenKatJsonCapability.available;
    return result.body;
  }
}

class _ReportPage {
  final List<OpenKatReportRef> results;
  final String? next;
  const _ReportPage(this.results, this.next);
}

List<OpenKatOrganization> _parseOrganizationList(String body) {
  final decoded = jsonDecode(body);
  if (decoded is List) {
    return [
      for (final item in decoded)
        if (item is Map)
          OpenKatOrganization.fromJson(Map<String, Object?>.from(item)),
    ].where((o) => o.code.isNotEmpty).toList();
  }
  if (decoded is Map && decoded['results'] is List) {
    return [
      for (final item in decoded['results'] as List)
        if (item is Map)
          OpenKatOrganization.fromJson(Map<String, Object?>.from(item)),
    ].where((o) => o.code.isNotEmpty).toList();
  }
  throw const OpenKatRequestException('unexpected organization payload');
}

_ReportPage _parseReportList(String body) {
  final decoded = jsonDecode(body);
  if (decoded is List) {
    return _ReportPage([
      for (final item in decoded)
        if (item is Map)
          OpenKatReportRef.fromJson(Map<String, Object?>.from(item)),
    ], null);
  }
  if (decoded is Map) {
    final results = decoded['results'];
    if (results is! List) {
      throw const OpenKatRequestException('unexpected report payload');
    }
    return _ReportPage([
      for (final item in results)
        if (item is Map)
          OpenKatReportRef.fromJson(Map<String, Object?>.from(item)),
    ], decoded['next'] as String?);
  }
  throw const OpenKatRequestException('unexpected report payload');
}
