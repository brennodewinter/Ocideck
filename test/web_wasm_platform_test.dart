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
import 'package:ocideck/services/ociserve/ociserve_http_web.dart'
    show WebRefusingOciServeHttpTransport;
import 'package:ocideck/services/update_check_fetch.dart';
import 'package:ocideck/services/web_asset_store.dart';
import 'package:ocideck/utils/mem_asset_blob.dart';
import 'package:web/web.dart' as web;

import 'import/helpers/pptx_fixture.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'both web compilers select browser capabilities and refusal paths',
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
        isA<WebRefusingOciServeHttpTransport>(),
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
