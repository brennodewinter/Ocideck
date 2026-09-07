import 'ociserve_auth_platform_io.dart'
    if (dart.library.html) 'ociserve_auth_platform_web.dart'
    as implementation;

abstract class OciServeAuthorizationReceiver {
  Uri get redirectUri;

  Future<Map<String, String>> receive(Duration timeout);

  Future<void> close();
}

Future<OciServeAuthorizationReceiver> createOciServeAuthorizationReceiver() =>
    implementation.createOciServeAuthorizationReceiver();
