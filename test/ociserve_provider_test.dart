import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/models/learning_session.dart';
import 'package:ocideck/models/ociserve_models.dart';
import 'package:ocideck/models/ociserve_settings.dart';
import 'package:ocideck/models/playback.dart';
import 'package:ocideck/models/rehearsal.dart';
import 'package:ocideck/services/ociserve/ociserve_auth.dart';
import 'package:ocideck/services/ociserve/ociserve_gateway.dart';
import 'package:ocideck/services/ociserve/ociserve_http.dart';
import 'package:ocideck/state/ociserve_provider.dart';
import 'package:ocideck/state/secret_store_provider.dart';
import 'package:ocideck/services/secret_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _settings = OciServeSettings(
  enabled: true,
  baseUrl: 'https://learn.example',
  rememberLogin: true,
);
final _installation = OciServeInstallation(
  clientId: 'desktop',
  issuer: Uri.parse('https://learn.example'),
);
final _oidc = OciServeOidcConfiguration(
  issuer: Uri.parse('https://learn.example'),
  authorizationEndpoint: Uri.parse('https://learn.example/authorize'),
  tokenEndpoint: Uri.parse('https://learn.example/token'),
  jwksUri: Uri.parse('https://learn.example/jwks'),
  metadata: const {},
  signingAlgorithms: const ['RS256'],
);
const _account = OciServeAccount(
  id: 'user',
  memberships: [OciServeMembership(organizationId: 'org')],
);

class _FakeAuth implements OciServeAuthenticator {
  Completer<OciServeTokens>? loginCompleter;
  int refreshes = 0;

  @override
  Future<OciServeTokens> login(
    OciServeInstallation installation,
    OciServeOidcConfiguration configuration,
  ) =>
      loginCompleter?.future ??
      Future.value(
        OciServeTokens(
          accessToken: 'access',
          refreshToken: 'refresh',
          expiresAt: DateTime.now().toUtc().add(const Duration(hours: 1)),
        ),
      );

  @override
  Future<OciServeTokens> refresh(
    OciServeInstallation installation,
    OciServeOidcConfiguration configuration,
    String refreshToken,
  ) {
    refreshes++;
    return login(installation, configuration);
  }
}

class _FakeApi implements OciServeApi {
  Completer<OciServeAccount>? meCompleter;
  Completer<void>? reportCompleter;
  OciServeInstallation installationValue = _installation;
  OciServeOidcConfiguration oidcValue = _oidc;
  OciServeAccount account = _account;
  bool failReports = false;
  int reports = 0;
  int discoveries = 0;
  OciServePlaybackSnapshot? lastSnapshot;

  @override
  Future<OciServeInstallation> installation() async => installationValue;

  @override
  Future<OciServeOidcConfiguration> discoverOidc(
    OciServeInstallation installation,
  ) async {
    discoveries++;
    return oidcValue;
  }

  @override
  Future<OciServeAccount> me(String accessToken) =>
      meCompleter?.future ?? Future.value(account);

  @override
  Future<List<OciServeFeedItem>> learningFeed({
    required String accessToken,
    required String organizationId,
  }) async => const [];

  @override
  Future<OciServePackage> lessonPackage({
    required String accessToken,
    required String organizationId,
    required String versionId,
    required String lessonId,
  }) async => OciServePackage(
    bytes: Uint8List(0),
    sha256: '',
    playbackPolicy: 'play-only',
  );

  @override
  Future<OciServeLearningState> learningState({
    required String accessToken,
    required String organizationId,
  }) async => const OciServeLearningState([]);

  @override
  Future<OciServePrivacyData> privacyData({
    required String accessToken,
    required String organizationId,
  }) async => OciServePrivacyData(
    participantId: 'participant',
    generatedAt: DateTime.utc(2026, 9, 9),
    data: const {},
  );

  @override
  Future<void> reportPlayback({
    required String accessToken,
    required String organizationId,
    required OciServePlaybackSnapshot snapshot,
  }) async {
    reports++;
    lastSnapshot = snapshot;
    if (failReports) throw StateError('offline');
    await reportCompleter?.future;
  }

  @override
  Future<Uint8List> courseImage({
    required String accessToken,
    required String organizationId,
    required String imageHash,
  }) async => Uint8List(0);

  @override
  Future<Uint8List> accountAvatar({
    required String accessToken,
    required String avatarHash,
  }) async => Uint8List(0);
}

ProviderContainer _container(
  _FakeApi api,
  SecretStore secrets, {
  _FakeAuth? auth,
  OciServeGatewayFactory? gatewayFactory,
}) => ProviderContainer(
  overrides: [
    secretStoreProvider.overrideWithValue(secrets),
    ociServeGatewayFactoryProvider.overrideWithValue(
      gatewayFactory ?? (_) => api,
    ),
    ociServeAuthenticatorFactoryProvider.overrideWithValue(
      (_) => auth ?? _FakeAuth(),
    ),
  ],
);

LearningSessionRef _session({
  String server = 'https://learn.example',
  String account = 'user',
  String organization = 'org',
}) => LearningSessionRef(
  serverUrl: server,
  accountId: account,
  organizationId: organization,
  enrollmentId: 'enrollment',
  courseVersionId: 'v1',
  lessonId: 'l1',
  packageHash: 'hash',
  startedAt: DateTime.utc(2026, 9, 6),
);

const _report = PlaybackReport(
  run: RehearsalRun(
    total: Duration(milliseconds: 5),
    target: null,
    perSlide: [SlideTiming(index: 0, slideId: 'a', spent: Duration(hours: 13))],
  ),
  lastSlideId: 'a',
  completed: false,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late SecretStore secrets;
  late _FakeApi api;

  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
    SharedPreferences.setMockInitialValues({});
    secrets = SecretStore(
      storage: const FlutterSecureStorage(),
      canStore: true,
    );
    api = _FakeApi();
  });

  test('exposes authenticated only after /me succeeds', () async {
    api.meCompleter = Completer<OciServeAccount>();
    final container = _container(api, secrets);
    addTearDown(container.dispose);
    final notifier = container.read(ociServeProvider.notifier);
    await notifier.saveSettings(_settings);

    final login = notifier.login();
    await Future<void>.delayed(Duration.zero);
    expect(container.read(ociServeProvider).authenticating, isTrue);
    expect(container.read(ociServeProvider).authenticated, isFalse);

    api.meCompleter!.complete(_account);
    await login;
    final state = container.read(ociServeProvider);
    expect(state.authenticated, isTrue);
    expect(state.memberships.single.organizationId, 'org');
    expect(
      await secrets.readOciServeRefreshToken(_settings.baseUrl),
      contains('"refresh_token":"refresh"'),
    );
  });

  test('restores a remembered login from the keychain', () async {
    SharedPreferences.setMockInitialValues({
      kOciServeSettingsKey: jsonEncode(_settings.toJson()),
    });
    await secrets.writeOciServeRefreshToken(
      _settings.baseUrl,
      jsonEncode({
        'version': 1,
        'refresh_token': 'refresh',
        'issuer': _oidc.issuer.toString(),
        'client_id': _installation.clientId,
        'token_endpoint': _oidc.tokenEndpoint.toString(),
      }),
    );
    final auth = _FakeAuth();
    final container = _container(api, secrets, auth: auth);
    addTearDown(container.dispose);

    container.read(ociServeProvider);
    await Future<void>.delayed(const Duration(milliseconds: 20));

    expect(container.read(ociServeProvider).authenticated, isTrue);
    expect(auth.refreshes, 1);
    expect(api.discoveries, 1);
  });

  test('login tries known ports and stores the working address', () async {
    final attempts = <String>[];
    api.installationValue = OciServeInstallation(
      clientId: 'desktop',
      issuer: Uri.parse('https://localhost:8444'),
    );
    api.oidcValue = OciServeOidcConfiguration(
      issuer: Uri.parse('https://localhost:8444'),
      authorizationEndpoint: Uri.parse('https://localhost:8444/authorize'),
      tokenEndpoint: Uri.parse('https://localhost:8444/token'),
      jwksUri: Uri.parse('https://localhost:8444/jwks'),
      metadata: const {},
      signingAlgorithms: const ['RS256'],
    );
    final container = _container(
      api,
      secrets,
      gatewayFactory: (settings) {
        attempts.add(settings.normalizedBaseUrl);
        if (settings.normalizedBaseUrl != 'https://localhost:8443') {
          throw const OciServeException('connection_failed');
        }
        return api;
      },
    );
    addTearDown(container.dispose);
    final notifier = container.read(ociServeProvider.notifier);
    await notifier.saveSettings(
      _settings.copyWith(baseUrl: 'https://localhost:9999'),
    );

    expect(await notifier.login(), isTrue);
    expect(attempts, ['https://localhost:9999', 'https://localhost:8443']);
    expect(
      container.read(ociServeProvider).settings.normalizedBaseUrl,
      'https://localhost:8443',
    );
    final prefs = await SharedPreferences.getInstance();
    expect(
      jsonDecode(prefs.getString(kOciServeSettingsKey)!)['baseUrl'],
      'https://localhost:8443',
    );
  });

  test(
    'failed playback is encrypted in the pending outbox and retried',
    () async {
      final container = _container(api, secrets);
      addTearDown(container.dispose);
      final notifier = container.read(ociServeProvider.notifier);
      await notifier.saveSettings(_settings);
      await notifier.login();
      api.failReports = true;
      final startedAt = DateTime.now().toUtc().subtract(
        const Duration(hours: 25),
      );

      await notifier.reportPlayback(
        session: _session(),
        report: _report,
        startedAt: startedAt,
      );
      expect(container.read(ociServeProvider).pendingSync, 1);
      expect(
        await secrets.readOciServeOutbox(_settings.baseUrl),
        contains('"account_id":"user"'),
      );

      api.failReports = false;
      await notifier.flushPendingReports();
      expect(container.read(ociServeProvider).pendingSync, 0);
      expect(await secrets.readOciServeOutbox(_settings.baseUrl), isNull);
      expect(
        api.lastSnapshot!.slideTimeMs['a'],
        const Duration(hours: 12).inMilliseconds,
      );
      expect(
        api.lastSnapshot!.endedAt!.difference(api.lastSnapshot!.startedAt),
        lessThanOrEqualTo(const Duration(hours: 24)),
      );
    },
  );

  test(
    'rememberLogin false leaves refresh credential out of keychain',
    () async {
      final container = _container(api, secrets);
      addTearDown(container.dispose);
      final notifier = container.read(ociServeProvider.notifier);
      await notifier.saveSettings(_settings.copyWith(rememberLogin: false));
      await notifier.login();

      expect(container.read(ociServeProvider).authenticated, isTrue);
      expect(await secrets.readOciServeRefreshToken(_settings.baseUrl), isNull);
    },
  );

  test('rememberLogin is opt-in for new and legacy settings', () {
    expect(const OciServeSettings().rememberLogin, isFalse);
    expect(OciServeSettings.fromJson(const {}).rememberLogin, isFalse);
  });

  test(
    'cached login can recover after the server was offline at startup',
    () async {
      SharedPreferences.setMockInitialValues({
        kOciServeSettingsKey: jsonEncode(_settings.toJson()),
      });
      await secrets.writeOciServeRefreshToken(
        _settings.baseUrl,
        jsonEncode({
          'version': 1,
          'refresh_token': 'refresh',
          'issuer': _oidc.issuer.toString(),
          'client_id': _installation.clientId,
          'token_endpoint': _oidc.tokenEndpoint.toString(),
        }),
      );
      var online = false;
      final auth = _FakeAuth();
      final container = _container(
        api,
        secrets,
        auth: auth,
        gatewayFactory: (_) {
          if (!online) throw const OciServeException('connection_failed');
          return api;
        },
      );
      addTearDown(container.dispose);
      container.read(ociServeProvider);
      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(container.read(ociServeProvider).errorCode, 'restore_failed');
      online = true;

      expect(await container.read(ociServeProvider.notifier).login(), isTrue);
      expect(auth.refreshes, 1);
      expect(container.read(ociServeProvider).authenticated, isTrue);
    },
  );

  test(
    'a cross-host identity provider is disclosed before discovery',
    () async {
      api.installationValue = OciServeInstallation(
        clientId: 'desktop',
        issuer: Uri.parse('https://login.example'),
      );
      api.oidcValue = OciServeOidcConfiguration(
        issuer: Uri.parse('https://login.example'),
        authorizationEndpoint: Uri.parse('https://login.example/authorize'),
        tokenEndpoint: Uri.parse('https://login.example/token'),
        jwksUri: Uri.parse('https://login.example/jwks'),
        metadata: const {},
        signingAlgorithms: const ['RS256'],
      );
      final container = _container(api, secrets);
      addTearDown(container.dispose);
      final notifier = container.read(ociServeProvider.notifier);
      await notifier.saveSettings(_settings);

      expect(await notifier.login(), isFalse);
      expect(api.discoveries, 0);
      expect(
        container.read(ociServeProvider).errorCode,
        'identity_provider_confirmation_required',
      );
      expect(
        container.read(ociServeProvider).identityProviderHost,
        'login.example',
      );

      await notifier.acceptIdentityProvider('login.example');
      expect(await notifier.login(), isTrue);
      expect(api.discoveries, 1);
    },
  );

  test('playback stays bound to its original server and account', () async {
    final container = _container(api, secrets);
    addTearDown(container.dispose);
    final notifier = container.read(ociServeProvider.notifier);
    await notifier.saveSettings(_settings);
    await notifier.login();

    for (final session in [
      _session(server: 'https://other.example'),
      _session(account: 'other'),
    ]) {
      await expectLater(
        notifier.reportPlayback(
          session: session,
          report: _report,
          startedAt: DateTime.now(),
        ),
        throwsA(
          isA<OciServeException>().having(
            (error) => error.code,
            'code',
            'playback_session_refused',
          ),
        ),
      );
    }
  });

  test('queued playback rechecks active membership before sending', () async {
    final container = _container(api, secrets);
    addTearDown(container.dispose);
    final notifier = container.read(ociServeProvider.notifier);
    await notifier.saveSettings(_settings);
    await notifier.login();
    await notifier.reportPlayback(
      session: _session(),
      report: _report,
      startedAt: DateTime.now(),
    );
    api.account = const OciServeAccount(
      id: 'user',
      memberships: [OciServeMembership(organizationId: 'other')],
    );

    await notifier.flushPendingReports();

    expect(api.reports, 0);
    expect(container.read(ociServeProvider).pendingReports, 1);
  });

  test('login does not wait for the bounded outbox flush', () async {
    final container = _container(api, secrets);
    addTearDown(container.dispose);
    final notifier = container.read(ociServeProvider.notifier);
    await notifier.saveSettings(_settings);
    await notifier.login();
    await notifier.reportPlayback(
      session: _session(),
      report: _report,
      startedAt: DateTime.now(),
    );
    await notifier.logout();
    api.reportCompleter = Completer<void>();

    expect(
      await notifier.login().timeout(const Duration(milliseconds: 200)),
      isTrue,
    );
    expect(container.read(ociServeProvider).pendingReports, 1);
    api.reportCompleter!.complete();
    await notifier.flushPendingReports();
  });

  test('logout wins over a stale login completion', () async {
    final auth = _FakeAuth()..loginCompleter = Completer<OciServeTokens>();
    final container = _container(api, secrets, auth: auth);
    addTearDown(container.dispose);
    final notifier = container.read(ociServeProvider.notifier);
    await notifier.saveSettings(_settings);

    final login = notifier.login();
    await Future<void>.delayed(Duration.zero);
    await notifier.logout();
    auth.loginCompleter!.complete(
      OciServeTokens(
        accessToken: 'late',
        refreshToken: 'late',
        expiresAt: DateTime.now().add(const Duration(hours: 1)),
      ),
    );

    expect(await login, isFalse);
    expect(container.read(ociServeProvider).authenticated, isFalse);
  });

  test('server changes never silently discard pending playback', () async {
    final container = _container(api, secrets);
    addTearDown(container.dispose);
    final notifier = container.read(ociServeProvider.notifier);
    await notifier.saveSettings(_settings);
    await notifier.login();
    await notifier.reportPlayback(
      session: _session(),
      report: _report,
      startedAt: DateTime.now(),
    );

    await expectLater(
      notifier.saveSettings(
        _settings.copyWith(baseUrl: 'https://other.example'),
      ),
      throwsA(
        isA<OciServeException>().having(
          (error) => error.code,
          'code',
          'pending_reports_not_discarded',
        ),
      ),
    );
    expect(
      container.read(ociServeProvider).settings.baseUrl,
      _settings.baseUrl,
    );
    expect(await secrets.readOciServeOutbox(_settings.baseUrl), isNotNull);
  });

  test('a server change invalidates the authenticated session', () async {
    final container = _container(api, secrets);
    addTearDown(container.dispose);
    final notifier = container.read(ociServeProvider.notifier);
    await notifier.saveSettings(_settings);
    await notifier.login();

    await notifier.saveSettings(
      _settings.copyWith(baseUrl: 'https://other.example'),
    );

    expect(container.read(ociServeProvider).authenticated, isFalse);
    expect(container.read(ociServeProvider).account, isNull);
  });

  test(
    'a full outbox reports a machine-readable warning without loss',
    () async {
      final container = _container(api, secrets);
      addTearDown(container.dispose);
      final notifier = container.read(ociServeProvider.notifier);
      await notifier.saveSettings(_settings);
      await notifier.login();
      await notifier.flushPendingReports();
      final item = {
        'account_id': 'user',
        'organization_id': 'org',
        'snapshot': {
          'session_id': 'session',
          'course_version_id': 'v1',
          'lesson_id': 'l1',
          'started_at': '2026-09-06T00:00:00.000Z',
          'ended_at': '2026-09-06T00:01:00.000Z',
          'last_slide_anchor': 'a',
          'completed': false,
          'slide_time_ms': {'a': 1},
        },
      };
      await secrets.writeOciServeOutbox(
        _settings.baseUrl,
        jsonEncode(List.filled(100, item)),
      );

      await expectLater(
        notifier.reportPlayback(
          session: _session(),
          report: _report,
          startedAt: DateTime.now(),
        ),
        throwsA(
          isA<OciServeException>().having(
            (error) => error.code,
            'code',
            'outbox_full',
          ),
        ),
      );
      expect(container.read(ociServeProvider).warningCode, 'outbox_full');
      expect(
        (jsonDecode((await secrets.readOciServeOutbox(_settings.baseUrl))!)
            as List),
        hasLength(100),
      );
    },
  );

  test('a stored refresh token is bound to issuer, client and endpoint', () async {
    SharedPreferences.setMockInitialValues({
      kOciServeSettingsKey:
          '{"enabled":true,"baseUrl":"https://learn.example","rememberLogin":true}',
    });
    await secrets.writeOciServeRefreshToken(
      _settings.baseUrl,
      '{"version":1,"refresh_token":"refresh","issuer":"https://wrong.example","client_id":"desktop","token_endpoint":"https://learn.example/token"}',
    );
    final auth = _FakeAuth();
    final container = _container(api, secrets, auth: auth);
    addTearDown(container.dispose);
    container.read(ociServeProvider);
    await Future<void>.delayed(const Duration(milliseconds: 20));

    expect(auth.refreshes, 0);
    expect(container.read(ociServeProvider).errorCode, 'restore_failed');
    expect(container.read(ociServeProvider).authenticated, isFalse);
  });

  test('the OciServe owner resets settings, credential and outbox', () async {
    SharedPreferences.setMockInitialValues({
      kOciServeSettingsKey: jsonEncode(_settings.toJson()),
    });
    await secrets.writeOciServeRefreshToken(_settings.baseUrl, 'refresh');
    await secrets.writeOciServeOutbox(_settings.baseUrl, '[{"pending":true}]');
    final container = _container(api, secrets);
    addTearDown(container.dispose);
    container.read(ociServeProvider);
    await Future<void>.delayed(const Duration(milliseconds: 20));

    expect(
      await container.read(ociServeProvider.notifier).resetLocalData(),
      isTrue,
    );

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString(kOciServeSettingsKey), isNull);
    expect(await secrets.readOciServeRefreshToken(_settings.baseUrl), isNull);
    expect(await secrets.readOciServeOutbox(_settings.baseUrl), isNull);
  });
}
