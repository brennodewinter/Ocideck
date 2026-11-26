import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/models/ociserve_settings.dart';
import 'package:ocideck/services/ociserve/ociserve_http.dart';
import 'package:ocideck/services/ociserve/ociserve_web_session.dart';

const binding = '12345678-1234-4234-8234-123456789abc';
void main() {
  test(
    'BFF policy binds the cookie request and never forwards a Bearer token',
    () {
      final result = ociServeBffHeaders(
        url: Uri.parse(
          'https://deck.example/api/v1/organizations/o/file-shares',
        ),
        appOrigin: Uri.parse('https://deck.example'),
        method: 'POST',
        headers: const {
          'Authorization': 'Bearer $ociServeBrowserSessionMarker$binding',
          'Content-Type': 'application/json',
        },
        csrfToken: 'canary-csrf',
      );
      expect(result['authorization'], isNull);
      expect(result['x-ociserve-session'], binding);
      expect(result['x-ociserve-client'], 'ocideck');
      expect(result['x-csrf-token'], 'canary-csrf');
      expect(result['cookie'], isNull);
    },
  );
  test(
    'BFF policy rejects other origins, real OAuth tokens and unbound sessions',
    () {
      for (final uri in [
        'https://evil.example/api/v1/me',
        'http://deck.example/api/v1/me',
        Uri.https(
          'deck.example',
          '/api/v1/me',
        ).replace(userInfo: 'canary-userinfo').toString(),
        'https://deck.example/api/v1/public/file-shares/id',
      ]) {
        expect(
          () => ociServeBffHeaders(
            url: Uri.parse(uri),
            appOrigin: Uri.parse('https://deck.example'),
            method: 'GET',
            headers: const {},
          ),
          throwsA(isA<OciServeTransportException>()),
        );
      }
      for (final auth in [
        'Bearer real-oauth-canary',
        'Bearer ${ociServeBrowserSessionMarker}invalid',
      ]) {
        expect(
          () => ociServeBffHeaders(
            url: Uri.parse('https://deck.example/api/v1/me'),
            appOrigin: Uri.parse('https://deck.example'),
            method: 'GET',
            headers: {'authorization': auth},
          ),
          throwsA(isA<OciServeTransportException>()),
        );
      }
      expect(
        () => ociServeBffHeaders(
          url: Uri.parse('https://deck.example/api/v1/me'),
          appOrigin: Uri.parse('https://deck.example'),
          method: 'PUT',
          headers: const {
            'authorization': 'Bearer $ociServeBrowserSessionMarker$binding',
          },
        ),
        throwsA(isA<OciServeTransportException>()),
      );
    },
  );
  test(
    'VM fallback remains unavailable and does not start browser authentication',
    () async {
      final client = createOciServeWebSessionClient();
      expect(client.available, false);
      expect(client.origin, isNull);
      client.prepareLogin();
      client.cancel();
      expect(await client.restore(const OciServeSettings()), isNull);
      await client.logout(const OciServeSettings());
      await expectLater(
        client.login(const OciServeSettings()),
        throwsA(isA<OciServeException>()),
      );
    },
  );
}
