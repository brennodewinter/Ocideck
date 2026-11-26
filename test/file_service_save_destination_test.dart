import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/models/deck.dart';
import 'package:ocideck/models/settings.dart';
import 'package:ocideck/models/slide.dart';
import 'package:ocideck/services/file_service.dart';
import 'package:ocideck/services/image_service.dart';
import 'package:ocideck/services/markdown_service.dart';
import 'package:path/path.dart' as p;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'an injected Save-as destination is honored on the native Mac path',
    () async {
      final root = Directory.systemTemp.createTempSync('save-destination-');
      addTearDown(() => root.deleteSync(recursive: true));
      const channel = MethodChannel('ocideck/open_file');
      var nativeCalls = 0;
      var injectedCalls = 0;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            nativeCalls++;
            throw PlatformException(code: 'unexpected-native-picker');
          });
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null),
      );
      final destination = p.join(root.path, 'chosen.md');
      final service = FileService(
        MarkdownService(),
        ImageService(),
        () => const ThemeProfile(),
        saveDestination: ({dialogTitle, fileName, initialDirectory}) async {
          injectedCalls++;
          return destination;
        },
      );
      final deck = Deck(
        title: 'Chosen destination',
        slides: [Slide.create(SlideType.title).copyWith(title: 'Authored')],
      );
      final written = await service.saveDeckAsDetailed(deck);
      expect(written.path, destination);
      expect(injectedCalls, 1);
      expect(nativeCalls, 0);
      expect(
        (await service.openDeck(destination))!.slides.single.title,
        'Authored',
      );
    },
  );
  test(
    'the default Mac Save-as route still invokes the native picker',
    () async {
      final root = Directory.systemTemp.createTempSync(
        'native-save-destination-',
      );
      addTearDown(() => root.deleteSync(recursive: true));
      const channel = MethodChannel('ocideck/open_file');
      final destination = p.join(root.path, 'native.md');
      var nativeCalls = 0;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            expect(call.method, 'saveFile');
            nativeCalls++;
            return destination;
          });
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null),
      );
      final service = FileService(
        MarkdownService(),
        ImageService(),
        () => const ThemeProfile(),
      );
      final written = await service.saveDeckAsDetailed(
        Deck(title: 'Default', slides: [Slide.create(SlideType.title)]),
      );
      expect(written.path, destination);
      expect(nativeCalls, 1);
      expect(File(destination).existsSync(), isTrue);
    },
    skip: !Platform.isMacOS,
  );
}
