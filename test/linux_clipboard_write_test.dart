import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/services/image_service.dart';

/// Regressie voor #758: `Pasteboard.writeImage` is op Linux een stille no-op
/// (het pakket heeft geen Linux-schrijftak), dus daar loopt het kopiëren via
/// een eigen MethodChannel naar de GTK-runner. Deze tests bewaken de
/// Dart-kant van dat kanaal; de native kant kan onder `flutter test` op deze
/// machine niet draaien en wordt door de Linux-CI-build gecompileerd.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('ocideck/clipboard');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  group('copyImageBytesToClipboard op Linux', () {
    final bytes = Uint8List.fromList([0x89, 0x50, 0x4E, 0x47]);

    test(
      'schrijft via het eigen kanaal en geeft het native oordeel door',
      () async {
        MethodCall? seen;
        messenger.setMockMethodCallHandler(channel, (call) async {
          seen = call;
          return true;
        });
        final service = ImageService(isLinux: () => true);
        expect(await service.copyImageBytesToClipboard(bytes), isTrue);
        expect(seen, isNotNull);
        expect(seen!.method, 'writeImage');
        expect(seen!.arguments, bytes);
      },
    );

    test(
      'false wanneer de native kant de bytes niet als afbeelding leest',
      () async {
        messenger.setMockMethodCallHandler(channel, (call) async => false);
        final service = ImageService(isLinux: () => true);
        expect(await service.copyImageBytesToClipboard(bytes), isFalse);
      },
    );

    test('false wanneer het kanaal ontbreekt, zonder te gooien', () async {
      // Geen handler geregistreerd → MissingPluginException; de service hoort
      // die te vangen en false te melden, niet te crashen.
      final service = ImageService(isLinux: () => true);
      expect(await service.copyImageBytesToClipboard(bytes), isFalse);
    });

    test('lege bytes: false zonder kanaalverkeer', () async {
      var called = false;
      messenger.setMockMethodCallHandler(channel, (call) async {
        called = true;
        return true;
      });
      final service = ImageService(isLinux: () => true);
      expect(await service.copyImageBytesToClipboard(Uint8List(0)), isFalse);
      expect(called, isFalse);
    });

    test('buiten Linux blijft het kanaal onaangeroerd', () async {
      var called = false;
      messenger.setMockMethodCallHandler(channel, (call) async {
        called = true;
        return true;
      });
      final service = ImageService(isLinux: () => false);
      // Het pasteboard-pad zelf slaagt hier niet (geen host-plugin onder
      // flutter test); het gaat erom dat het Linux-kanaal niet gebruikt wordt.
      await service.copyImageBytesToClipboard(bytes);
      expect(called, isFalse);
    });
  });
}
