import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/widgets/slides/slide_preview.dart';
// ignore: depend_on_referenced_packages
import 'package:webview_flutter_platform_interface/webview_flutter_platform_interface.dart';
import 'package:webview_win_floating/webview.dart';
import 'package:webview_win_floating/webview_win_floating_method_channel.dart';
import 'package:webview_win_floating/webview_win_floating_platform_interface.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('webview_win_floating');
  const codec = StandardMethodCodec();
  late WebviewWinFloatingPlatform previous;
  late WinWebViewController controller;
  late int id;
  late List<MethodCall> replies;
  Completer<void>? acknowledge;

  Future<void> permission(int kind, {int deferral = 1}) async {
    final done = Completer<void>();
    ServicesBinding.instance.channelBuffers.push(
      channel.name,
      codec.encodeMethodCall(
        MethodCall('onAskPermission', {
          'webviewId': id,
          'url': 'https://www.youtube-nocookie.com/embed/test',
          'kind': kind,
          'deferralId': deferral,
        }),
      ),
      (data) {
        try {
          codec.decodeEnvelope(data!);
          done.complete();
        } catch (error, stack) {
          done.completeError(error, stack);
        }
      },
    );
    return done.future;
  }

  setUp(() async {
    replies = [];
    acknowledge = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          if (call.method == 'create') {
            id = (call.arguments as Map)['webviewId'] as int;
          }
          if (call.method == 'grantPermission') {
            replies.add(call);
            await acknowledge?.future;
          }
          return call.method == 'create' || call.method == 'init' ? true : null;
        });
    previous = WebviewWinFloatingPlatform.instance;
    WebviewWinFloatingPlatform.instance = MethodChannelWebviewWinFloating();
    controller = WinWebViewController();
    await controller.setJavaScriptMode(JavaScriptMode.unrestricted);
  });

  tearDown(() async {
    await controller.dispose();
    WebviewWinFloatingPlatform.instance = previous;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test(
    'native presentation events reach only the registered live controller',
    () async {
      Future<void> key() async {
        final done = Completer<void>();
        ServicesBinding.instance.channelBuffers.push(
          channel.name,
          codec.encodeMethodCall(
            MethodCall('onPresentationKey', {
              'webviewId': id,
              'key': 0x27,
              'control': true,
              'shift': true,
              'alt': false,
              'meta': false,
            }),
          ),
          (data) {
            codec.decodeEnvelope(data!);
            done.complete();
          },
        );
        await done.future;
      }

      final events = <WinWebViewPresentationKey>[];
      await key();
      await controller.setPresentationKeyHandler(events.add);
      await key();
      expect(events, hasLength(1));
      expect(events.single.virtualKey, 0x27);
      expect(events.single.control, isTrue);
      expect(events.single.shift, isTrue);
      await controller.setPresentationKeyHandler(null);
      await key();
      expect(events, hasLength(1));
      await controller.setPresentationKeyHandler(events.add);
      await controller.dispose();
      await key();
      expect(events, hasLength(1));
    },
  );

  test('autoplay is scoped to the current video and its exact origins', () {
    final player = Uri.parse('https://www.youtube-nocookie.com/embed/test');
    final document = Uri.parse('http://127.0.0.1:42517/private-document');
    bool allowed(
      String url, {
      int kind = 9,
      bool active = true,
      bool online = true,
      bool autoplay = true,
    }) => videoEmbedAutoplayPermissionAllowed(
      kind: kind,
      url: url,
      player: player,
      document: document,
      active: active,
      allowRemoteMedia: online,
      autoplay: autoplay,
    );
    expect(allowed(player.toString()), isTrue);
    expect(allowed('http://127.0.0.1:42517/'), isTrue);
    for (final url in [
      'https://www.youtube.com/embed/test',
      'https://www.youtube-nocookie.com.evil.example/',
      'http://www.youtube-nocookie.com/embed/test',
      'https://www.youtube-nocookie.com:444/',
      'https://user@www.youtube-nocookie.com/',
      'http://127.0.0.1:42518/',
      'about:blank',
      'invalid',
    ]) {
      expect(allowed(url), isFalse, reason: url);
    }
    expect(allowed(player.toString(), kind: 1), isFalse);
    expect(allowed(player.toString(), kind: 2), isFalse);
    expect(allowed(player.toString(), kind: 999), isFalse);
    expect(allowed(player.toString(), active: false), isFalse);
    expect(allowed(player.toString(), online: false), isFalse);
    expect(allowed(player.toString(), autoplay: false), isFalse);
  });

  test(
    'native autoplay ID 9 reaches callback and gets exactly one reply',
    () async {
      controller.setOnPermissionRequest((request) {
        expect(request.kind, WinWebViewPermissionResourceType.autoplay);
        expect(request.types, isEmpty);
        request.grant();
        request.deny();
        request.grant();
      });
      await permission(9);
      expect(replies, hasLength(1));
      expect(replies.single.arguments['isGranted'], isTrue);
    },
  );

  test(
    'future, negative and native unknown IDs are denied without callback',
    () async {
      controller.setOnPermissionRequest(
        (_) => fail('Unknown permission forwarded'),
      );
      for (final value in [999, -1, 0]) {
        await permission(value, deferral: value);
      }
      expect(replies, hasLength(3));
      expect(
        replies.every((call) => call.arguments['isGranted'] == false),
        isTrue,
      );
    },
  );

  test(
    'no listener, no action and callback exception all finish by denial',
    () async {
      await permission(9);
      controller.setOnPermissionRequest((_) {});
      await permission(9, deferral: 2);
      controller.setOnPermissionRequest(
        (_) => throw StateError('callback failed'),
      );
      await permission(9, deferral: 3);
      expect(replies, hasLength(3));
      expect(
        replies.every((call) => call.arguments['isGranted'] == false),
        isTrue,
      );
    },
  );

  test('grant completes only after native acknowledgement', () async {
    acknowledge = Completer<void>();
    late Future<void> result;
    controller.setOnPermissionRequest((request) => result = request.grant());
    var received = false;
    final event = permission(9).then((_) => received = true);
    await Future<void>.delayed(Duration.zero);
    expect(replies, hasLength(1));
    var granted = false;
    final grant = result.then((_) => granted = true);
    await Future<void>.delayed(Duration.zero);
    expect(granted, isFalse);
    expect(received, isFalse);
    acknowledge!.complete();
    await Future.wait([event, grant]);
    expect(granted, isTrue);
  });

  test(
    'camera and microphone types do not imply permission for each other',
    () async {
      final types = <Set<WebViewPermissionResourceType>>[];
      controller.setOnPermissionRequest((request) {
        types.add(request.types);
        request.deny();
      });
      await permission(1);
      await permission(2);
      expect(types, [
        {WebViewPermissionResourceType.microphone},
        {WebViewPermissionResourceType.camera},
      ]);
    },
  );

  test(
    'late native request after disposal cannot invoke former callback',
    () async {
      controller.setOnPermissionRequest(
        (_) => fail('Disposed callback invoked'),
      );
      await controller.dispose();
      await permission(9);
      expect(replies, isEmpty); // Native owner closes outstanding deferrals.
    },
  );
}
