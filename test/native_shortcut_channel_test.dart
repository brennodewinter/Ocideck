import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/platform/native_shortcut_channel.dart';

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  const codec = StandardMethodCodec();

  Future<void> hostCalls(String method) async {
    await binding.defaultBinaryMessenger.handlePlatformMessage(
      kNativeShortcutChannel.name,
      codec.encodeMethodCall(MethodCall(method)),
      null,
    );
  }

  tearDown(() => kNativeShortcutChannel.setMethodCallHandler(null));

  test('native Ctrl+H bereikt zoeken en vervangen', () async {
    var calls = 0;
    final channel = NativeShortcutChannel(() => calls++)..start();
    addTearDown(channel.dispose);

    await hostCalls('findReplace');
    await hostCalls('onbekend');

    expect(calls, 1);
  });

  test('dispose haalt de native sneltoetslistener weg', () async {
    var calls = 0;
    final channel = NativeShortcutChannel(() => calls++)..start();
    channel.dispose();

    await hostCalls('findReplace');

    expect(calls, 0);
  });
}
