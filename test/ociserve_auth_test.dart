import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/models/ociserve_models.dart';
import 'package:ocideck/models/ociserve_settings.dart';
import 'package:ocideck/services/ociserve/ociserve_auth.dart';
import 'package:ocideck/services/ociserve/ociserve_auth_platform.dart';
import 'package:ocideck/services/ociserve/ociserve_http.dart';
import 'package:ocideck/services/ociserve/ociserve_step_up.dart';

class _Browser implements OciServeBrowserLauncher {
  Uri? opened;

  @override
  Future<bool> open(Uri uri) async {
    opened = uri;
    return true;
  }
}

class _Receiver implements OciServeAuthorizationReceiver {
  _Receiver(this.browser);
  final _Browser browser;

  @override
  Uri get redirectUri => Uri.parse('http://127.0.0.1:43210/oauth/callback');

  @override
  Future<Map<String, String>> receive(Duration timeout) async => {
    'state': browser.opened!.queryParameters['state']!,
    'code': 'one-use-code',
  };

  @override
  Future<void> close() async {}
}

class _AuthTransport implements OciServeHttpTransport {
  final urls = <Uri>[];

  @override
  Future<OciServeHttpResponse> send({
    required String method,
    required Uri url,
    required bool trustedInternal,
    Map<String, String> headers = const {},
    List<int>? body,
    int maxResponseBytes = 0,
    Duration timeout = Duration.zero,
  }) async {
    urls.add(url);
    if (url.path == '/token') {
      return OciServeHttpResponse(
        statusCode: 200,
        body: Uint8List.fromList(
          utf8.encode(
            jsonEncode({
              'access_token': 'access',
              'refresh_token': 'refresh',
              'expires_in': 3600,
              'token_type': 'Bearer',
              'id_token': [
                'eyJhbGci',
                'OiJSUzI1NiJ9',
                'e30',
                'invalid',
              ].join('.'),
            }),
          ),
        ),
        headers: const {'content-type': 'application/json'},
      );
    }
    return OciServeHttpResponse(
      statusCode: 200,
      body: Uint8List.fromList(utf8.encode('{"keys":[]}')),
      headers: const {'content-type': 'application/json'},
    );
  }
}

/// Antwoordt op het token-endpoint met één vast antwoord, zoals een IdP die een
/// vernieuwtoken afwijst.
class _TokenReplyTransport implements OciServeHttpTransport {
  _TokenReplyTransport(this.statusCode, this.body, {this.contentType});

  final int statusCode;
  final String body;
  final String? contentType;

  @override
  Future<OciServeHttpResponse> send({
    required String method,
    required Uri url,
    required bool trustedInternal,
    Map<String, String> headers = const {},
    List<int>? body,
    int maxResponseBytes = 0,
    Duration timeout = Duration.zero,
  }) async => OciServeHttpResponse(
    statusCode: statusCode,
    body: Uint8List.fromList(utf8.encode(this.body)),
    headers: {'content-type': ?contentType},
  );
}

void main() {
  test('refuses an OIDC endpoint on another port before opening a browser', () async {
    final browser = _Browser();
    final transport = _AuthTransport();
    final auth = OciServePkceAuthenticator(
      settings: const OciServeSettings(baseUrl: 'https://learn.example'),
      transport: transport,
      browser: browser,
      receiverFactory: () async => _Receiver(browser),
    );
    final installation = OciServeInstallation(
      clientId: 'desktop', issuer: Uri.parse('https://id.example'),
    );
    final configuration = OciServeOidcConfiguration(
      issuer: Uri.parse('https://id.example'),
      authorizationEndpoint: Uri.parse('https://id.example/authorize'),
      tokenEndpoint: Uri.parse('https://id.example:8443/token'),
      jwksUri: Uri.parse('https://id.example/jwks'),
      metadata: const {}, signingAlgorithms: const ['RS256'],
    );
    await expectLater(auth.login(installation, configuration), throwsA(
      isA<OciServeException>().having((e) => e.code, 'code', 'identity_provider_host_mismatch'),
    ));
    expect(browser.opened, isNull);
    expect(transport.urls, isEmpty);
  });

  test(
    'uses PKCE, state, nonce and rejects an unsigned/unverifiable ID token',
    () async {
      final browser = _Browser();
      final transport = _AuthTransport();
      final auth = OciServePkceAuthenticator(
        settings: const OciServeSettings(
          enabled: true,
          baseUrl: 'https://learn.example',
        ),
        transport: transport,
        browser: browser,
        receiverFactory: () async => _Receiver(browser),
      );
      final installation = OciServeInstallation(
        clientId: 'desktop',
        issuer: Uri.parse('https://id.example'),
      );
      final configuration = OciServeOidcConfiguration(
        issuer: Uri.parse('https://id.example'),
        authorizationEndpoint: Uri.parse('https://id.example/authorize'),
        tokenEndpoint: Uri.parse('https://id.example/token'),
        jwksUri: Uri.parse('https://id.example/jwks'),
        metadata: const {},
        signingAlgorithms: const ['RS256'],
      );

      await expectLater(
        auth.login(installation, configuration),
        throwsA(
          isA<OciServeException>().having(
            (error) => error.code,
            'code',
            'invalid_id_token',
          ),
        ),
      );
      final query = browser.opened!.queryParameters;
      expect(query['code_challenge_method'], 'S256');
      expect(query['code_challenge'], isNotEmpty);
      expect(query['state'], isNotEmpty);
      expect(query['nonce'], isNotEmpty);
      expect(
        query['scope']!.split(' '),
        containsAll(['openid', 'offline_access']),
      );
      expect(query['scope']!.split(' '), isNot(contains('profile')));
      expect(query['redirect_uri'], startsWith('http://127.0.0.1:'));
      expect(transport.urls.map((uri) => uri.path), ['/token', '/jwks']);
    },
  );

  test('at_hash follows the ID-token signing algorithm', () {
    expect(
      verifyOciServeAtHash(
        'access',
        ['oFYf1knNtr', 'qnhAVfBRuteQ'].join(),
        'RS256',
      ),
      isTrue,
    );
    expect(
      verifyOciServeAtHash(
        'access',
        'SeGOaEgS6QNKbB7vkLM3y8nujeY4Ple3',
        'RS384',
      ),
      isTrue,
    );
    expect(
      verifyOciServeAtHash(
        'access',
        'kyd4-h3ZoV2sH212kLKbcOnCBajStKQ38Ae_bfT-PFI',
        'RS512',
      ),
      isTrue,
    );
    expect(
      () => verifyOciServeAtHash('access', 'ignored', 'HS256'),
      throwsA(isA<OciServeException>()),
    );
  });

  group('a refused refresh token', () {
    final installation = OciServeInstallation(
      clientId: 'desktop',
      issuer: Uri.parse('https://id.example'),
    );
    final configuration = OciServeOidcConfiguration(
      issuer: Uri.parse('https://id.example'),
      authorizationEndpoint: Uri.parse('https://id.example/authorize'),
      tokenEndpoint: Uri.parse('https://id.example/token'),
      jwksUri: Uri.parse('https://id.example/jwks'),
      metadata: const {},
      signingAlgorithms: const ['RS256'],
    );

    Future<Object?> refreshWith(OciServeHttpTransport transport) async {
      final auth = OciServePkceAuthenticator(
        settings: const OciServeSettings(
          enabled: true,
          baseUrl: 'https://learn.example',
        ),
        transport: transport,
      );
      try {
        await auth.refresh(installation, configuration, 'stored-refresh');
      } on OciServeException catch (error) {
        return error.code;
      }
      return null;
    }

    test('is an expired session when the provider says invalid_grant', () async {
      // Zo antwoordt Keycloak op een verlopen, ingetrokken of al gebruikt token.
      expect(
        await refreshWith(
          _TokenReplyTransport(
            400,
            '{"error":"invalid_grant","error_description":"Token is not active"}',
            contentType: 'application/json',
          ),
        ),
        'session_expired',
      );
    });

    test('stays a plain refusal for anything that can pass', () async {
      // Een storing aan de serverkant of een andere weigering is geen bewijs
      // dat het token dood is; het blijft bewaard voor een volgende poging.
      expect(
        await refreshWith(
          _TokenReplyTransport(503, 'tijdelijk niet beschikbaar'),
        ),
        'refresh_refused',
      );
      expect(
        await refreshWith(
          _TokenReplyTransport(
            400,
            '{"error":"invalid_request"}',
            contentType: 'application/json',
          ),
        ),
        'refresh_refused',
      );
    });
  });

  group('a step-up sign-in', () {
    final installation = OciServeInstallation(
      clientId: 'desktop',
      issuer: Uri.parse('https://id.example'),
    );
    final configuration = OciServeOidcConfiguration(
      issuer: Uri.parse('https://id.example'),
      authorizationEndpoint: Uri.parse('https://id.example/authorize'),
      tokenEndpoint: Uri.parse('https://id.example/token'),
      jwksUri: Uri.parse('https://id.example/jwks'),
      metadata: const {},
      signingAlgorithms: const ['RS256'],
    );

    /// Meldt aan en geeft de parameters van het autorisatieverzoek terug. De
    /// aanmelding zelf faalt bij het ID-token (dat is hier niet het onderwerp).
    Future<Map<String, String>> authorizationQuery(
      OciServeStepUpRequired? stepUp,
    ) async {
      final browser = _Browser();
      final auth = OciServePkceAuthenticator(
        settings: const OciServeSettings(
          enabled: true,
          baseUrl: 'https://learn.example',
        ),
        transport: _AuthTransport(),
        browser: browser,
        receiverFactory: () async => _Receiver(browser),
      );
      await expectLater(
        auth.login(installation, configuration, stepUp: stepUp),
        throwsA(isA<OciServeException>()),
      );
      return browser.opened!.queryParameters;
    }

    test('vraagt de provider om de acr en de maximale leeftijd', () async {
      final query = await authorizationQuery(
        const OciServeStepUpRequired(
          acrValues: ['phr', 'mfa'],
          maxAge: Duration(minutes: 5),
        ),
      );
      expect(query['acr_values'], 'phr mfa');
      expect(query['max_age'], '300');
      // De rest van het contract blijft: PKCE, state en nonce.
      expect(query['code_challenge_method'], 'S256');
      expect(query['state'], isNotEmpty);
      expect(query['nonce'], isNotEmpty);
    });

    test('vraagt alleen wat de uitdaging noemt', () async {
      final onlyAge = await authorizationQuery(
        const OciServeStepUpRequired(maxAge: Duration.zero),
      );
      expect(onlyAge['max_age'], '0');
      expect(onlyAge, isNot(contains('acr_values')));

      final onlyAcr = await authorizationQuery(
        const OciServeStepUpRequired(acrValues: ['phr']),
      );
      expect(onlyAcr['acr_values'], 'phr');
      expect(onlyAcr, isNot(contains('max_age')));
    });

    test('een gewone aanmelding vraagt er geen van beide', () async {
      final query = await authorizationQuery(null);
      expect(query, isNot(contains('acr_values')));
      expect(query, isNot(contains('max_age')));
    });
  });
}
