import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:ocideck/models/ociserve_models.dart';
import 'package:ocideck/models/ociserve_settings.dart';
import 'package:ocideck/services/ociserve/ociserve_auth.dart';
import 'package:ocideck/services/ociserve/ociserve_gateway.dart';
import 'package:ocideck/services/ociserve/ociserve_step_up.dart';
import 'package:ocideck/services/secret_store.dart';
import 'package:ocideck/state/ociserve_provider.dart';
import 'package:ocideck/state/secret_store_provider.dart';

const ociserveTestSettings = OciServeSettings(
  enabled: true,
  baseUrl: 'https://learn.example',
  rememberLogin: false,
);
final ociserveTestInstallation = OciServeInstallation(
  clientId: 'desktop',
  issuer: Uri.parse('https://learn.example'),
);
final ociserveTestOidc = OciServeOidcConfiguration(
  issuer: Uri.parse('https://learn.example'),
  authorizationEndpoint: Uri.parse('https://learn.example/authorize'),
  tokenEndpoint: Uri.parse('https://learn.example/token'),
  jwksUri: Uri.parse('https://learn.example/jwks'),
  metadata: const {},
  signingAlgorithms: const ['RS256'],
);
const ociserveTestAccount = OciServeAccount(
  id: 'user',
  memberships: [OciServeMembership(organizationId: 'org')],
);

class FakeOciServeAuth implements OciServeAuthenticator {
  @override
  Future<OciServeTokens> login(
    OciServeInstallation installation,
    OciServeOidcConfiguration configuration, {
    bool forceLogin = false,
    String? loginHint,
    OciServeStepUpRequired? stepUp,
  }) async => OciServeTokens(
    accessToken: 'access',
    refreshToken: 'refresh',
    expiresAt: DateTime.now().toUtc().add(const Duration(hours: 1)),
  );

  @override
  Future<OciServeTokens> refresh(
    OciServeInstallation installation,
    OciServeOidcConfiguration configuration,
    String refreshToken,
  ) => login(installation, configuration);
}

/// Een gateway die alleen doet wat een test hem vraagt: elke aanroep wordt
/// vastgelegd (naam + benoemde argumenten) en beantwoord door de handler van
/// die test. Een niet-afgesproken aanroep valt hard om — een provider die
/// stilletjes een andere route neemt, hoort niet te slagen.
class FakeOciServeApi implements OciServeApi {
  final calls = <Symbol>[];
  final args = <Symbol, Map<Symbol, dynamic>>{};
  final handlers = <Symbol, Object? Function(Invocation)>{};

  @override
  dynamic noSuchMethod(Invocation invocation) {
    final name = invocation.memberName;
    calls.add(name);
    args[name] = invocation.namedArguments;
    final handler = handlers[name];
    if (handler == null) throw StateError('onverwachte aanroep: $name');
    return handler(invocation);
  }

  dynamic arg(Symbol method, Symbol name) => args[method]![name];
}

/// De overrides die een provider-container nodig heeft om tegen [api] te
/// praten, zonder netwerk, browser of echte sleutelbos.
List<Override> ociserveTestOverrides(FakeOciServeApi api) => [
  secretStoreProvider.overrideWithValue(
    SecretStore(storage: const FlutterSecureStorage(), canStore: true),
  ),
  ociServeGatewayFactoryProvider.overrideWithValue((_) => api),
  ociServeAuthenticatorFactoryProvider.overrideWithValue(
    (_) => FakeOciServeAuth(),
  ),
];

/// Een gateway met de afspraken die elke aanmelding nodig heeft.
FakeOciServeApi newOciServeApi() => FakeOciServeApi()
  ..handlers[#installation] = ((_) async => ociserveTestInstallation)
  ..handlers[#discoverOidc] = ((_) async => ociserveTestOidc)
  ..handlers[#me] = ((_) async => ociserveTestAccount)
  ..handlers[#reportOciDeckLogin] = ((_) async => null);
