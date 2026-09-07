import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:jose/jose.dart';
import 'package:openid_client/openid_client.dart' as oidc;
import 'package:url_launcher/url_launcher.dart';

import '../../models/ociserve_models.dart';
import '../../models/ociserve_settings.dart';
import '../../utils/log.dart';
import 'ociserve_auth_platform.dart';
import 'ociserve_http.dart';
import 'ociserve_http_factory.dart';

class OciServeTokens {
  const OciServeTokens({
    required this.accessToken,
    required this.refreshToken,
    required this.expiresAt,
  });

  final String accessToken;
  final String refreshToken;
  final DateTime expiresAt;

  bool get isExpired => !expiresAt.isAfter(
    DateTime.now().toUtc().add(const Duration(seconds: 30)),
  );
}

abstract class OciServeBrowserLauncher {
  Future<bool> open(Uri uri);
}

class ExternalOciServeBrowserLauncher implements OciServeBrowserLauncher {
  const ExternalOciServeBrowserLauncher();

  @override
  Future<bool> open(Uri uri) =>
      launchUrl(uri, mode: LaunchMode.externalApplication);
}

abstract class OciServeAuthenticator {
  Future<OciServeTokens> login(
    OciServeInstallation installation,
    OciServeOidcConfiguration configuration,
  );

  Future<OciServeTokens> refresh(
    OciServeInstallation installation,
    OciServeOidcConfiguration configuration,
    String refreshToken,
  );
}

/// Authorization Code + PKCE using a system browser and an app-owned,
/// ephemeral IPv4 loopback callback.
///
/// `openid_client` owns the state/PKCE/token state machine. Its platform
/// Authenticator is deliberately not used because that listener binds more
/// broadly than OciDeck's network contract permits. Identity is established
/// by OciServe's authenticated `/me` response; OciDeck never trusts an
/// unverified ID-token payload.
class OciServePkceAuthenticator implements OciServeAuthenticator {
  OciServePkceAuthenticator({
    required this.settings,
    OciServeHttpTransport? transport,
    OciServeBrowserLauncher? browser,
    Future<OciServeAuthorizationReceiver> Function()? receiverFactory,
  }) : _transport = transport ?? createOciServeHttpTransport(),
       _browser = browser ?? const ExternalOciServeBrowserLauncher(),
       _receiverFactory =
           receiverFactory ?? createOciServeAuthorizationReceiver;

  final OciServeSettings settings;
  final OciServeHttpTransport _transport;
  final OciServeBrowserLauncher _browser;
  final Future<OciServeAuthorizationReceiver> Function() _receiverFactory;

  @override
  Future<OciServeTokens> login(
    OciServeInstallation installation,
    OciServeOidcConfiguration configuration,
  ) async {
    final client = _client(installation, configuration);
    final receiver = await _receiverFactory();
    final nonce = _randomValue(32);
    final flow = oidc.Flow.authorizationCodeWithPKCE(
      client,
      scopes: const ['openid', 'offline_access'],
      additionalParameters: {'nonce': nonce},
    )..redirectUri = receiver.redirectUri;
    try {
      if (!await _browser.open(flow.authenticationUri)) {
        throw const OciServeException('browser_refused');
      }
      final callback = await receiver.receive(const Duration(minutes: 2));
      if (callback.containsKey('error')) {
        throw const OciServeException('authorization_refused');
      }
      final credential = await flow.callback(callback);
      final response = await credential.getTokenResponse();
      await _verifyIdToken(
        response,
        installation,
        configuration,
        nonce: nonce,
        required: true,
      );
      return _tokens(response);
    } on OciServeException {
      rethrow;
    } on TimeoutException {
      throw const OciServeException('authorization_timeout');
    } catch (error, stack) {
      logError('OciServe: aanmelden', error.runtimeType, stack);
      throw const OciServeException('authorization_failed');
    } finally {
      await receiver.close();
    }
  }

  @override
  Future<OciServeTokens> refresh(
    OciServeInstallation installation,
    OciServeOidcConfiguration configuration,
    String refreshToken,
  ) async {
    if (refreshToken.trim().isEmpty) {
      throw const OciServeException('not_authenticated');
    }
    try {
      final credential = _client(
        installation,
        configuration,
      ).createCredential(refreshToken: refreshToken.trim());
      final response = await credential.getTokenResponse(true);
      await _verifyIdToken(
        response,
        installation,
        configuration,
        required: false,
      );
      return _tokens(response, fallbackRefreshToken: refreshToken);
    } catch (error, stack) {
      logError('OciServe: sessie vernieuwen', error.runtimeType, stack);
      throw const OciServeException('refresh_refused');
    }
  }

  oidc.Client _client(
    OciServeInstallation installation,
    OciServeOidcConfiguration configuration,
  ) {
    _requireHttps(configuration.issuer);
    _requireHttps(configuration.authorizationEndpoint);
    _requireHttps(configuration.tokenEndpoint);
    _requireHttps(configuration.jwksUri);
    if (configuration.issuer.toString() != installation.issuer.toString()) {
      throw const OciServeException('issuer_mismatch');
    }
    for (final endpoint in [
      configuration.authorizationEndpoint,
      configuration.tokenEndpoint,
      configuration.jwksUri,
    ]) {
      if (endpoint.host.toLowerCase() !=
          configuration.issuer.host.toLowerCase()) {
        throw const OciServeException('identity_provider_host_mismatch');
      }
    }
    final signingAlgorithms = _supportedSigningAlgorithms(configuration);
    final issuer = oidc.Issuer(
      oidc.OpenIdProviderMetadata.fromJson({
        'issuer': configuration.issuer.toString(),
        'authorization_endpoint': configuration.authorizationEndpoint
            .toString(),
        'token_endpoint': configuration.tokenEndpoint.toString(),
        'jwks_uri': configuration.jwksUri.toString(),
        'id_token_signing_alg_values_supported': signingAlgorithms,
        'response_types_supported': ['code'],
        'token_endpoint_auth_methods_supported': ['none'],
        'scopes_supported': ['openid', 'offline_access'],
        'code_challenge_methods_supported': ['S256'],
      }),
    );
    return oidc.Client(
      issuer,
      installation.clientId,
      httpClient: _PinnedPackageHttpClient(
        transport: _transport,
        trustedInternal: settings.trustedInternal,
      ),
    );
  }

  Future<void> _verifyIdToken(
    oidc.TokenResponse response,
    OciServeInstallation installation,
    OciServeOidcConfiguration configuration, {
    required bool required,
    String? nonce,
  }) async {
    final compact = response.toJson()['id_token'] as String?;
    if (compact == null || compact.isEmpty) {
      if (required) throw const OciServeException('missing_id_token');
      return;
    }
    try {
      final jwks = await _transport.send(
        method: 'GET',
        url: configuration.jwksUri,
        trustedInternal: settings.trustedInternal,
        headers: const {'accept': 'application/json'},
        maxResponseBytes: 1024 * 1024,
        timeout: const Duration(seconds: 30),
      );
      if (jwks.statusCode < 200 || jwks.statusCode >= 300) {
        throw const FormatException();
      }
      final store = JsonWebKeyStore()
        ..addKeySet(
          JsonWebKeySet.fromJson(
            Map<String, dynamic>.from(
              jsonDecode(utf8.decode(jwks.body)) as Map,
            ),
          ),
        );
      final token = oidc.IdToken.unverified(compact);
      if (!await token.verify(
        store,
        allowedArguments: _supportedSigningAlgorithms(configuration),
      )) {
        throw const FormatException();
      }
      if (token.claims
          .validate(
            expiryTolerance: const Duration(seconds: 30),
            issuer: configuration.issuer,
            clientId: installation.clientId,
            nonce: nonce,
          )
          .isNotEmpty) {
        throw const FormatException();
      }
      final atHash = token.claims['at_hash'] as String?;
      final accessToken = response.accessToken;
      if (atHash != null && accessToken != null) {
        final algorithm = _jwtAlgorithm(compact);
        if (!verifyOciServeAtHash(accessToken, atHash, algorithm)) {
          throw const FormatException();
        }
      }
    } catch (error, stack) {
      logError('OciServe: identiteit controleren', error.runtimeType, stack);
      throw const OciServeException('invalid_id_token');
    }
  }

  static OciServeTokens _tokens(
    oidc.TokenResponse response, {
    String? fallbackRefreshToken,
  }) {
    final access = response.accessToken?.trim() ?? '';
    final refresh =
        response.refreshToken?.trim() ?? fallbackRefreshToken?.trim() ?? '';
    final expiresAt = response.expiresAt?.toUtc();
    if (access.isEmpty || refresh.isEmpty || expiresAt == null) {
      throw const OciServeException('invalid_token_response');
    }
    return OciServeTokens(
      accessToken: access,
      refreshToken: refresh,
      expiresAt: expiresAt,
    );
  }

  static String _randomValue(int byteCount) {
    final random = Random.secure();
    return _base64Url(
      List<int>.generate(byteCount, (_) => random.nextInt(256)),
    );
  }

  static String _base64Url(List<int> bytes) =>
      base64Url.encode(bytes).replaceAll('=', '');

  static String _jwtAlgorithm(String compact) {
    final parts = compact.split('.');
    if (parts.length != 3) throw const FormatException();
    final header = Map<String, Object?>.from(
      jsonDecode(utf8.decode(base64Url.decode(base64Url.normalize(parts[0]))))
          as Map,
    );
    return header['alg'] as String? ?? '';
  }

  static List<String> _supportedSigningAlgorithms(
    OciServeOidcConfiguration configuration,
  ) {
    final result = configuration.signingAlgorithms
        .where((value) => const {'RS256', 'RS384', 'RS512'}.contains(value))
        .toList(growable: false);
    if (result.isEmpty) {
      throw const OciServeException('unsupported_signing_algorithm');
    }
    return result;
  }

  static void _requireHttps(Uri uri) {
    if (!uri.hasAuthority || uri.scheme.toLowerCase() != 'https') {
      throw const OciServeException('https_required');
    }
  }
}

/// Controleert de OIDC `at_hash` met dezelfde digestfamilie als de
/// ondertekeningsalgoritme van het ID-token (OIDC Core 3.3.2.11).
bool verifyOciServeAtHash(
  String accessToken,
  String expected,
  String signingAlgorithm,
) {
  final Hash digest = switch (signingAlgorithm) {
    'RS256' => sha256,
    'RS384' => sha384,
    'RS512' => sha512,
    _ => throw const OciServeException('unsupported_signing_algorithm'),
  };
  final hash = digest.convert(utf8.encode(accessToken)).bytes;
  return OciServePkceAuthenticator._base64Url(
        hash.sublist(0, hash.length ~/ 2),
      ) ==
      expected;
}

/// Adapter that keeps `openid_client` behind OciDeck's pinned, capped network
/// transport. Redirects remain disabled and exceptions never contain a URL,
/// response body, token, or learner identifier.
class _PinnedPackageHttpClient extends http.BaseClient {
  _PinnedPackageHttpClient({
    required this.transport,
    required this.trustedInternal,
  });

  static const _requestCap = 1024 * 1024;
  final OciServeHttpTransport transport;
  final bool trustedInternal;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final body = BytesBuilder(copy: false);
    await for (final chunk in request.finalize()) {
      body.add(chunk);
      if (body.length > _requestCap) {
        throw const OciServeException('request_too_large');
      }
    }
    final response = await transport.send(
      method: request.method,
      url: request.url,
      trustedInternal: trustedInternal,
      headers: request.headers,
      body: body.takeBytes(),
      maxResponseBytes: 1024 * 1024,
      timeout: const Duration(seconds: 30),
    );
    return http.StreamedResponse(
      Stream<List<int>>.value(response.body),
      response.statusCode,
      contentLength: response.body.length,
      headers: response.headers,
      request: request,
    );
  }
}
