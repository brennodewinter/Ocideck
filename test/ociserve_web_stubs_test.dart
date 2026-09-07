import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/services/ociserve/ociserve_auth_platform_web.dart';
import 'package:ocideck/services/ociserve/ociserve_http.dart';
import 'package:ocideck/services/ociserve/ociserve_http_web.dart';

void main() {
  test('web weigert de desktop-only OciServe-aanmelding', () {
    expect(
      createOciServeAuthorizationReceiver,
      throwsA(isA<UnsupportedError>()),
    );
  });

  test('web opent geen OciServe-transport buiten de browserpoort om', () {
    final transport = createOciServeHttpTransport();

    expect(
      () => transport.send(
        method: 'GET',
        url: Uri.https('leren.example.org', '/me'),
        trustedInternal: false,
      ),
      throwsA(
        isA<OciServeTransportException>().having(
          (error) => error.code,
          'code',
          'desktop_only',
        ),
      ),
    );
  });
}
