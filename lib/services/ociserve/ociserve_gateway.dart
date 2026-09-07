import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

import '../../models/ociserve_models.dart';
import '../../models/ociserve_settings.dart';
import '../../utils/log.dart';
import 'ociserve_http.dart';
import 'ociserve_http_factory.dart';

/// Typed, bounded gateway for OciServe's learner-facing API.
abstract class OciServeApi {
  Future<OciServeInstallation> installation();
  Future<OciServeOidcConfiguration> discoverOidc(
    OciServeInstallation installation,
  );
  Future<OciServeAccount> me(String accessToken);
  Future<List<OciServeFeedItem>> learningFeed({
    required String accessToken,
    required String organizationId,
  });
  Future<OciServePackage> lessonPackage({
    required String accessToken,
    required String organizationId,
    required String versionId,
    required String lessonId,
  });
  Future<OciServeLearningState> learningState({
    required String accessToken,
    required String organizationId,
  });
  Future<void> reportPlayback({
    required String accessToken,
    required String organizationId,
    required OciServePlaybackSnapshot snapshot,
  });
}

class OciServeGateway implements OciServeApi {
  OciServeGateway({required this.settings, OciServeHttpTransport? transport})
    : _transport = transport ?? createOciServeHttpTransport();

  static const int _jsonCap = 2 * 1024 * 1024;
  // Mirrors OciServe's published package limit so an oversized response is
  // stopped client-side before it can consume more memory than the contract.
  static const int _packageCap = 32 * 1024 * 1024;

  final OciServeSettings settings;
  final OciServeHttpTransport _transport;

  Uri _api(List<String> segments) {
    final base = Uri.parse(settings.normalizedBaseUrl);
    return base.replace(
      pathSegments: [
        ...base.pathSegments.where((part) => part.isNotEmpty),
        'api',
        'v1',
        ...segments,
      ],
      query: null,
      fragment: null,
    );
  }

  void _requireConfigured() {
    final refusal = validateOciServeBaseUrl(settings.baseUrl);
    if (!settings.enabled) throw const OciServeException('disabled');
    if (refusal != null) throw OciServeException(refusal);
  }

  Future<OciServeHttpResponse> _send({
    required String method,
    required Uri url,
    String? accessToken,
    Map<String, String> headers = const {},
    List<int>? body,
    int cap = _jsonCap,
  }) async {
    _requireConfigured();
    if (accessToken != null && accessToken.trim().isEmpty) {
      throw const OciServeException('not_authenticated');
    }
    try {
      final response = await _transport.send(
        method: method,
        url: url,
        trustedInternal: settings.trustedInternal,
        headers: {
          'accept': 'application/json',
          if (accessToken != null)
            'authorization': 'Bearer ${accessToken.trim()}',
          ...headers,
        },
        body: body,
        maxResponseBytes: cap,
        timeout: const Duration(seconds: 30),
      );
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw OciServeException(
          response.statusCode == 401 ? 'unauthorized' : 'http_error',
          statusCode: response.statusCode,
        );
      }
      return response;
    } on OciServeException {
      rethrow;
    } on OciServeTransportException catch (e) {
      throw OciServeException(e.code);
    } catch (error, stack) {
      logError('OciServe: antwoord ontvangen', error.runtimeType, stack);
      throw const OciServeException('invalid_response');
    }
  }

  Map<String, Object?> _jsonObject(OciServeHttpResponse response) {
    try {
      final decoded = jsonDecode(utf8.decode(response.body));
      if (decoded is! Map) throw const FormatException();
      return Map<String, Object?>.from(decoded);
    } catch (error, stack) {
      logError('OciServe: JSON-antwoord lezen', error.runtimeType, stack);
      throw const OciServeException('invalid_response');
    }
  }

  @override
  Future<OciServeInstallation> installation() async {
    final response = await _send(method: 'GET', url: _api(['installation']));
    try {
      final value = OciServeInstallation.fromJson(_jsonObject(response));
      _requireHttps(value.issuer);
      return value;
    } catch (e) {
      if (e is OciServeException) rethrow;
      throw const OciServeException('invalid_installation');
    }
  }

  @override
  Future<OciServeOidcConfiguration> discoverOidc(
    OciServeInstallation installation,
  ) async {
    _requireHttps(installation.issuer);
    final issuer = installation.issuer;
    final discovery = issuer.replace(
      pathSegments: [
        ...issuer.pathSegments.where((part) => part.isNotEmpty),
        '.well-known',
        'openid-configuration',
      ],
      query: null,
      fragment: null,
    );
    final response = await _send(method: 'GET', url: discovery);
    try {
      final value = OciServeOidcConfiguration.fromJson(_jsonObject(response));
      _requireHttps(value.issuer);
      _requireHttps(value.authorizationEndpoint);
      _requireHttps(value.tokenEndpoint);
      _requireHttps(value.jwksUri);
      if (value.issuer.toString() != issuer.toString()) {
        throw const OciServeException('issuer_mismatch');
      }
      return value;
    } catch (e) {
      if (e is OciServeException) rethrow;
      throw const OciServeException('invalid_oidc_discovery');
    }
  }

  @override
  Future<OciServeAccount> me(String accessToken) async {
    final response = await _send(
      method: 'GET',
      url: _api(['me']),
      accessToken: accessToken,
    );
    try {
      return OciServeAccount.fromJson(_jsonObject(response));
    } catch (error, stack) {
      logError('OciServe: accountantwoord lezen', error.runtimeType, stack);
      throw const OciServeException('invalid_response');
    }
  }

  @override
  Future<List<OciServeFeedItem>> learningFeed({
    required String accessToken,
    required String organizationId,
  }) async {
    final response = await _send(
      method: 'GET',
      url: _api(['organizations', organizationId, 'me', 'learning-feed']),
      accessToken: accessToken,
    );
    try {
      final decoded = jsonDecode(utf8.decode(response.body));
      final raw = decoded is Map && decoded['courses'] is List
          ? decoded['courses']! as List
          : throw const FormatException();
      final result = <OciServeFeedItem>[];
      for (final item in raw) {
        final parent = Map<String, Object?>.from(item as Map);
        if (parent['lessons'] is List) {
          for (final lesson in parent['lessons']! as List) {
            result.add(
              OciServeFeedItem.fromJson({
                ...parent,
                ...Map<String, Object?>.from(lesson as Map),
                'lesson_id': lesson['id'],
                'course_title': parent['course_title'] ?? parent['title'],
              }),
            );
          }
        } else {
          result.add(OciServeFeedItem.fromJson(parent));
        }
      }
      return List.unmodifiable(result);
    } catch (error, stack) {
      logError('OciServe: opleidingenantwoord lezen', error.runtimeType, stack);
      throw const OciServeException('invalid_response');
    }
  }

  @override
  Future<OciServePackage> lessonPackage({
    required String accessToken,
    required String organizationId,
    required String versionId,
    required String lessonId,
  }) async {
    final response = await _send(
      method: 'GET',
      url: _api([
        'organizations',
        organizationId,
        'me',
        'course-versions',
        versionId,
        'lessons',
        lessonId,
        'package',
      ]),
      accessToken: accessToken,
      headers: const {'accept': 'application/octet-stream'},
      cap: _packageCap,
    );
    final policy = response.headers['x-ociserve-playback-policy']?.trim() ?? '';
    if (policy != 'play-only') {
      throw const OciServeException('package_policy_refused');
    }
    final actual = sha256.convert(response.body);
    final expected = _digestBytes(response.headers['digest']);
    if (expected == null || !_constantTimeEquals(actual.bytes, expected)) {
      throw const OciServeException('package_digest_mismatch');
    }
    return OciServePackage(
      bytes: Uint8List.fromList(response.body),
      sha256: actual.toString(),
      playbackPolicy: policy,
      etag: response.headers['etag'],
    );
  }

  @override
  Future<OciServeLearningState> learningState({
    required String accessToken,
    required String organizationId,
  }) async {
    final response = await _send(
      method: 'GET',
      url: _api(['organizations', organizationId, 'me', 'learning-state']),
      accessToken: accessToken,
    );
    try {
      return OciServeLearningState.fromJson(_jsonObject(response));
    } catch (error, stack) {
      logError('OciServe: voortgangsantwoord lezen', error.runtimeType, stack);
      throw const OciServeException('invalid_response');
    }
  }

  @override
  Future<void> reportPlayback({
    required String accessToken,
    required String organizationId,
    required OciServePlaybackSnapshot snapshot,
  }) async {
    if (snapshot.sessionId.trim().isEmpty) {
      throw const OciServeException('invalid_session');
    }
    await _send(
      method: 'POST',
      url: _api(['organizations', organizationId, 'me', 'playback-sessions']),
      accessToken: accessToken,
      headers: {
        'content-type': 'application/json',
        'idempotency-key': snapshot.sessionId,
      },
      body: utf8.encode(snapshot.encode()),
    );
  }

  static void _requireHttps(Uri uri) {
    if (!uri.hasAuthority || uri.scheme.toLowerCase() != 'https') {
      throw const OciServeException('https_required');
    }
  }

  static List<int>? _digestBytes(String? header) {
    if (header == null) return null;
    final match = RegExp(
      r'(?:^|,)\s*sha-256\s*=\s*:?(?<value>[A-Za-z0-9+/=]+):?',
      caseSensitive: false,
    ).firstMatch(header);
    if (match == null) return null;
    try {
      final bytes = base64.decode(match.namedGroup('value')!);
      return bytes.length == 32 ? bytes : null;
    } catch (error, stack) {
      logError('OciServe: Digest lezen', error.runtimeType, stack);
      return null;
    }
  }

  static bool _constantTimeEquals(List<int> left, List<int> right) {
    if (left.length != right.length) return false;
    var difference = 0;
    for (var i = 0; i < left.length; i++) {
      difference |= left[i] ^ right[i];
    }
    return difference == 0;
  }
}
