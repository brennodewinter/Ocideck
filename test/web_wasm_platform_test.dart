@TestOn('browser')
library;

import 'dart:js_interop';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/platform/platform_features.dart';
import 'package:ocideck/services/import/pipeline/import_runner.dart';
import 'package:ocideck/services/import/pipeline/import_task.dart';
import 'package:ocideck/services/ociserve/ociserve_auth_platform.dart';
import 'package:ocideck/services/ociserve/ociserve_http_factory.dart';
import 'package:ocideck/services/ociserve/ociserve_public_http_web.dart'
    show OciServeBrowserHttpTransport, ociServeBrowserResponseHeaders;
import 'package:ocideck/services/ociserve/ociserve_step_up.dart';
import 'package:ocideck/services/update_check_fetch.dart';
import 'package:ocideck/services/web_asset_store.dart';
import 'package:ocideck/utils/mem_asset_blob.dart';
import 'package:web/web.dart' as web;

import 'import/helpers/pptx_fixture.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'both web compilers select the BFF transport and native refusal paths',
    () async {
      expect(isWebPlatform, isTrue);
      expect(isDesktopNative, isFalse);
      expect(isLinuxDesktop, isFalse);
      expect(isFilePrefsDesktop, isFalse);
      expect(supportsNativeGit, isFalse);
      expect(supportsDualScreenPresenter, isFalse);
      expect(supportsLocalProjectFolders, isFalse);
      expect(supportsNetworkDeckSources, isFalse);
      expect(osHomeDirectory, isNull);
      expect(
        createOciServeHttpTransport(),
        isA<OciServeBrowserHttpTransport>().having(
          (transport) => transport.accountSession,
          'same-origin account session',
          isTrue,
        ),
      );
      expect(
        () => createOciServeAuthorizationReceiver(),
        throwsUnsupportedError,
      );
      expect(
        await defaultUpdateCheckFetch(Uri.parse('https://example.invalid')),
        isNull,
      );
    },
  );

  test('browser responses retain step-up and package integrity contracts', () {
    final headers = web.Headers()
      ..set(
        'WWW-Authenticate',
        'Bearer error="insufficient_user_authentication", acr_values="mfa", max_age="60"',
      )
      ..set('Digest', 'sha-256=package-digest-canary')
      ..set('Cache-Control', 'no-store')
      ..set('X-OciServe-Package-Profile', 'ae2');
    final received = ociServeBrowserResponseHeaders(headers);
    final need = parseOciServeStepUpChallenge(received);
    expect(need?.acrValues, ['mfa']);
    expect(need?.maxAge, const Duration(seconds: 60));
    expect(received['digest'], 'sha-256=package-digest-canary');
    expect(received['cache-control'], 'no-store');
    expect(received['x-ociserve-package-profile'], 'ae2');
    expect(received.containsKey('set-cookie'), isFalse);
  });

  test(
    'presentation import uses the browser runner instead of spawning an isolate',
    () async {
      final result = await runImportTask(
        ImportRequest(
          bytes: pptxFixture(titel: 'WASM import'),
          filename: 'deck.pptx',
        ),
      );
      final parsed = (result as ImportTaskParsed).parsed;
      expect(parsed.deck.slides.single.title, 'WASM import');
      expect(parsed.classified, hasLength(1));
    },
  );

  test(
    'in-memory media uses a real reusable browser blob under WASM too',
    () async {
      final bytes = Uint8List.fromList([1, 2, 3, 4]);
      final path = WebAssetStore.put(bytes, name: 'sound.wav');
      final url = memAssetBlobUrl(path);
      expect(url, startsWith('blob:'));
      expect(memAssetBlobUrl(path), url);
      final response = await web.window.fetch(url!.toJS).toDart;
      final buffer = await response.arrayBuffer().toDart;
      expect(buffer.toDart.asUint8List(), bytes);
      web.URL.revokeObjectURL(url);
      WebAssetStore.clear();
    },
  );
}
