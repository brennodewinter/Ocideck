// Real WebView2 focus and a separate live nocookie-player probe. Run through
// flutter drive on Windows; unit/channel tests cannot prove child-window focus.
import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:ocideck/models/slide.dart';
import 'package:ocideck/services/video_embed_host.dart';
import 'package:ocideck/utils/log.dart';
import 'package:ocideck/widgets/presentation/presentation_key_scope.dart';
import 'package:ocideck/widgets/slides/previews/video_embed_view.dart';
import 'package:ocideck/widgets/slides/slide_preview.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_win_floating/webview_plugin.dart';

class _Trace implements LogSink {
  final lines = <String>[];
  @override
  void write(String line) => lines.add(line);
  @override
  Future<void> close() async {}
}

class _Keyboard {
  final _event = DynamicLibrary.open('user32.dll')
      .lookupFunction<
        Void Function(Uint8, Uint8, Uint32, UintPtr),
        void Function(int, int, int, int)
      >('keybd_event');
  void down(int key) => _event(key, 0, 0, 0);
  void up(int key) => _event(key, 0, 2, 0);
  Future<void> press(int key) async {
    down(key);
    await Future<void>.delayed(const Duration(milliseconds: 60));
    up(key);
  }
}

Future<void> _until(
  WidgetTester tester,
  FutureOr<bool> Function() ready, {
  int seconds = 15,
}) async {
  final deadline = DateTime.now().add(Duration(seconds: seconds));
  while (DateTime.now().isBefore(deadline)) {
    if (await ready()) return;
    await tester.pump(const Duration(milliseconds: 100));
  }
  fail('Native condition did not arrive within $seconds seconds');
}

WindowsPlatformWebViewController _native(WebViewController controller) =>
    controller.platform as WindowsPlatformWebViewController;

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  final trace = _Trace();
  final evidence = <String, dynamic>{
    'windows': Platform.operatingSystemVersion,
  };
  setUpAll(() {
    WindowsWebViewPlatform.registerWith();
    installLogSink(trace);
    binding.reportData = evidence;
  });
  tearDownAll(() => installLogSink(null));

  // Live autoplay runs first: the physical-key probe must not pre-activate
  // the shared WebView2 environment and hide clean-profile browser policy.
  testWidgets('live YouTube autoplay, clip boundary and native navigation', (
    tester,
  ) async {
    const url = String.fromEnvironment(
      'VIDEO_PROBE_URL',
      defaultValue: 'https://youtu.be/M7lc1UVfVE',
    );
    final keys = <int>[];
    var ended = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PresentationKeyScope(
            onKey: (key, {meta = false, control = false, shift = false}) {
              keys.add(key.keyId);
              return KeyEventResult.handled;
            },
            child: Center(
              child: SizedBox(
                width: 800,
                height: 450,
                child: SlidePreviewWidget(
                  slide: Slide.create(SlideType.video).copyWith(
                    videoPath: url,
                    videoAutoplay: true,
                    videoStartMs: 10000,
                    videoEndMs: 20000,
                  ),
                  allowRemoteMedia: true,
                  autoplayMedia: true,
                  onVideoComplete: () => ended++,
                ),
              ),
            ),
          ),
        ),
      ),
    );
    WindowsPlatformWebViewController? platform;
    try {
      await _until(
        tester,
        () => find.byType(WebViewWidget).evaluate().isNotEmpty,
        seconds: 30,
      );
      final widget = tester.widget<WebViewWidget>(
        find.byType(WebViewWidget).first,
      );
      platform =
          widget.platform.params.controller as WindowsPlatformWebViewController;
      Future<Map<String, dynamic>> snapshot() async {
        final value = await platform!.runJavaScriptReturningResult(
          '({ready:typeof ready!=="undefined"&&ready,playing:typeof playing!=="undefined"&&playing,'
          'hasPlayed:typeof hasPlayed!=="undefined"&&hasPlayed,'
          'position:typeof lastPosition!=="undefined"?lastPosition:null,'
          'ended:typeof ended!=="undefined"&&ended,ua:navigator.userAgent})',
        );
        return Map<String, dynamic>.from(jsonDecode(value as String) as Map);
      }

      // No synthetic API events and no click: the real iframe must start with
      // sound under the clean video profile's actual browser policy.
      await _until(tester, () async {
        final state = await snapshot();
        evidence['livePlayer'] = state;
        return state['hasPlayed'] == true;
      }, seconds: 45);
      await _until(tester, () => ended == 1, seconds: 30);
      final native = platform.controller;
      await native.requestFocus();
      await platform.runJavaScript("document.getElementById('f').focus()");
      final keyboard = _Keyboard();
      await tester.runAsync(() => keyboard.press(0x27));
      await _until(tester, () => keys.isNotEmpty);
      expect(keys, [LogicalKeyboardKey.arrowRight.keyId]);
      expect(ended, 1);
      evidence['liveAfterRight'] = await snapshot();
      evidence['nativeKeys'] = keys;
    } finally {
      evidence['diagnostics'] = trace.lines;
      if (platform != null) {
        evidence['userAgent'] = await platform.runJavaScriptReturningResult(
          'navigator.userAgent',
        );
      }
      binding.reportData = evidence;
      await tester.pumpWidget(const SizedBox());
    }
  }, skip: !Platform.isWindows);
  testWidgets('physical child-frame keys are consumed only after opt-in', (
    tester,
  ) async {
    final directory = await Directory.systemTemp.createTemp(
      'ocideck-key-profile-',
    );
    final child = await VideoEmbedHost.start('''<!doctype html><body>
<button id="b" autofocus>Focus target</button><script>
var b=document.getElementById('b');
b.addEventListener('focus',function(){parent.postMessage('focus','*')});
window.addEventListener('keydown',function(e){parent.postMessage('key:'+e.key,'*')});
</script></body>''');
    final host = await VideoEmbedHost.start(
      '''<!doctype html><body style="margin:0">
<iframe id="f" src="${child.uri}" style="width:100vw;height:100vh"></iframe>
<script>window.addEventListener('message',function(e){
if(e.origin==='${child.uri.origin}'&&e.source===document.getElementById('f').contentWindow)Probe.postMessage(e.data)
});</script></body>''',
    );
    final messages = <String>[];
    final events = <int>[];
    final controller = WebViewController.fromPlatformCreationParams(
      WindowsWebViewControllerCreationParams(
        userDataFolder: directory.path,
        suspendDuringDeactive: false,
      ),
    );
    try {
      await controller.setJavaScriptMode(JavaScriptMode.unrestricted);
      await controller.addJavaScriptChannel(
        'Probe',
        onMessageReceived: (message) => messages.add(message.message),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: VideoEmbedView(controller: controller)),
        ),
      );
      await controller.loadRequest(host.uri);
      final native = _native(controller).controller;
      await native.requestFocus();
      final keyboard = _Keyboard();
      for (var i = 0; i < 8 && !messages.contains('focus'); i++) {
        await tester.runAsync(() => keyboard.press(0x09));
        await tester.pump(const Duration(milliseconds: 300));
      }
      expect(
        messages,
        contains('focus'),
        reason: 'Real cross-origin child must hold focus',
      );
      messages.clear();
      await tester.runAsync(() => keyboard.press(0x27));
      await _until(tester, () => messages.contains('key:ArrowRight'));
      await native.setPresentationKeyHandler(
        (event) => events.add(event.virtualKey),
      );
      messages.clear();
      await tester.runAsync(() async {
        keyboard.down(0x27);
        await Future<void>.delayed(const Duration(milliseconds: 60));
        keyboard.down(
          0x27,
        ); // Physical repeat must be consumed without dispatch.
        keyboard.up(0x27);
      });
      await _until(tester, () => events.isNotEmpty);
      await tester.pump(const Duration(milliseconds: 300));
      expect(events, [0x27]);
      expect(messages, isNot(contains('key:ArrowRight')));
      for (final key in [0x25, 0x21, 0x22, 0x1b]) {
        await tester.runAsync(() => keyboard.press(key));
        await _until(tester, () => events.contains(key));
      }
      await native.setPresentationKeyHandler(null);
      await tester.runAsync(() => keyboard.press(0x27));
      await _until(tester, () => messages.contains('key:ArrowRight'));
      evidence['nativeFocus'] = {'events': events, 'childMessages': messages};
    } finally {
      await tester.pumpWidget(const SizedBox());
      await _native(controller).controller.dispose();
      await host.close();
      await child.close();
      // WebView2 may release its profile after its browser process exits.
      evidence['keyProfile'] = directory.path;
    }
  }, skip: !Platform.isWindows);
}
