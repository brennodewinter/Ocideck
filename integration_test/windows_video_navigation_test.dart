// Real WebView2 focus and a separate live nocookie-player probe. Run through
// flutter drive on Windows; unit/channel tests cannot prove child-window focus.
import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

// ignore: depend_on_referenced_packages
import 'package:ffi/ffi.dart';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:ocideck/models/slide.dart';
import 'package:ocideck/platform/native_window.dart';
import 'package:ocideck/services/transcription/media_sniff.dart';
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

// Dart HttpServer adds X-Frame-Options: SAMEORIGIN by default. These
// deliberately cross-origin test children must explicitly allow embedding;
// production VideoEmbedHost keeps its secure default unchanged.
class _CrossOriginFrameHost {
  _CrossOriginFrameHost(this.server, this.uri);
  final HttpServer server;
  final Uri uri;
  static Future<_CrossOriginFrameHost> start(String html) async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final uri = Uri.http('127.0.0.1:${server.port}', '/frame');
    server.listen((request) async {
      final response = request.response;
      if (request.uri.path != uri.path ||
          request.method != 'GET' ||
          request.headers.value(HttpHeaders.hostHeader) != uri.authority) {
        response.statusCode = HttpStatus.notFound;
      } else {
        response.headers.removeAll('X-Frame-Options');
        response.headers.contentType = ContentType.html;
        response.write(html);
      }
      await response.close();
    });
    return _CrossOriginFrameHost(server, uri);
  }

  Future<void> close() async => server.close(force: true);
}

Future<Map<String, dynamic>> _documentState(
  WebViewController controller,
) async {
  final value = await controller.runJavaScriptReturningResult(
    '({visibility:document.visibilityState,focus:document.hasFocus(),'
    'width:innerWidth,height:innerHeight,activeElement:document.activeElement.tagName,'
    'activeId:document.activeElement.id})',
  );
  return Map<String, dynamic>.from(jsonDecode(value as String) as Map);
}

class _Keyboard {
  void _send(int key, {bool up = false}) {
    // INPUT is 40 bytes on the supported Windows x64 ABI. Arrow/navigation
    // keys need their real scan code and extended-key flag; a zero scan code
    // through keybd_event does not establish delivery to a child WebView.
    expect(sizeOf<IntPtr>(), 8);
    final user = DynamicLibrary.open('user32.dll');
    final scan = user
        .lookupFunction<
          Uint32 Function(Uint32, Uint32),
          int Function(int, int)
        >('MapVirtualKeyW')(key, 4);
    expect(scan, isNot(0));
    final input = calloc<Uint8>(40);
    try {
      final bytes = ByteData.sublistView(input.asTypedList(40));
      bytes.setUint32(0, 1, Endian.little); // INPUT_KEYBOARD
      bytes.setUint16(10, scan & 0xff, Endian.little);
      bytes.setUint32(
        12,
        8 | (scan > 0xff ? 1 : 0) | (up ? 2 : 0),
        Endian.little,
      );
      final sent = user
          .lookupFunction<
            Uint32 Function(Uint32, Pointer<Void>, Int32),
            int Function(int, Pointer<Void>, int)
          >('SendInput')(1, input.cast(), 40);
      expect(
        sent,
        1,
        reason: 'The OS must accept the physical scan-code input',
      );
    } finally {
      calloc.free(input);
    }
  }

  void down(int key) => _send(key);
  void up(int key) => _send(key, up: true);
  int foregroundProcess() {
    final user = DynamicLibrary.open('user32.dll');
    final window = user
        .lookupFunction<Pointer<Void> Function(), Pointer<Void> Function()>(
          'GetForegroundWindow',
        )();
    final process = calloc<Uint32>();
    try {
      user.lookupFunction<
        Uint32 Function(Pointer<Void>, Pointer<Uint32>),
        int Function(Pointer<Void>, Pointer<Uint32>)
      >('GetWindowThreadProcessId')(window, process);
      return process.value;
    } finally {
      calloc.free(process);
    }
  }

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

Future<void> _policyIsolation(
  WidgetTester tester,
  Map<String, dynamic> evidence,
) async {
  final root = await Directory.systemTemp.createTemp('ocideck-policy-');
  final pcm = Float32List.fromList(
    List.generate(16000, (i) => math.sin(2 * math.pi * 440 * i / 16000) * .05),
  );
  final encoded = base64Encode(encodePcmWav(pcm));
  final child = await _CrossOriginFrameHost.start(
    '''<!doctype html><audio id="a" loop src="data:audio/wav;base64,$encoded"></audio>
<script>parent.postMessage('child-ready','*');var a=document.getElementById('a');a.onerror=function(){parent.postMessage('media-error:'+a.error.code,'*')};a.play().then(function(){parent.postMessage('playing','*')}).catch(function(e){parent.postMessage('blocked:'+e.name,'*')});</script>''',
  );
  final host = await VideoEmbedHost.start(
    '''<!doctype html><iframe id="f" allow="autoplay" src="${child.uri}"></iframe>
<script>window.addEventListener('message',function(e){if(e.origin==='${child.uri.origin}'&&e.source===document.getElementById('f').contentWindow)Probe.postMessage(e.data)});</script>''',
  );
  final outcomes = <String, String>{};
  final details = <String, dynamic>{};
  try {
    for (final mode in [
      ('ordinary-before', false),
      ('video', true),
      ('ordinary-after', false),
    ]) {
      final controller = WebViewController.fromPlatformCreationParams(
        WindowsWebViewControllerCreationParams(
          userDataFolder: '${root.path}/${mode.$1}',
          allowMediaAutoplay: mode.$2,
          suspendDuringDeactive: false,
        ),
      );
      String? outcome;
      final messages = <String>[];
      try {
        _native(controller).controller.setOnPermissionRequest((request) {
          final allowed = videoEmbedAutoplayPermissionAllowed(
            kind: request.kind.nativeId,
            url: request.url,
            player: child.uri,
            document: host.uri,
            active: true,
            allowRemoteMedia: true,
            autoplay: mode.$2,
          );
          allowed ? request.grant() : request.deny();
        });
        await controller.setJavaScriptMode(JavaScriptMode.unrestricted);
        await controller.addJavaScriptChannel(
          'Probe',
          onMessageReceived: (message) {
            messages.add(message.message);
            if (message.message == 'playing' ||
                message.message.startsWith('blocked:')) {
              outcome = message.message;
            }
          },
        );
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(body: VideoEmbedView(controller: controller)),
          ),
        );
        await controller.loadRequest(host.uri);
        await _until(tester, () => outcome != null);
        outcomes[mode.$1] = outcome!;
      } finally {
        details[mode.$1] = {
          'outcome': outcome,
          'messages': messages,
          'document': await _documentState(controller),
        };
        await tester.pumpWidget(const SizedBox());
        await _native(controller).controller.dispose();
      }
    }
    expect(outcomes['video'], 'playing');
    expect(outcomes['ordinary-after'], outcomes['ordinary-before']);
  } finally {
    evidence['policyIsolation'] = outcomes;
    evidence['policyDocuments'] = details;
    await host.close();
    await child.close();
  }
}

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  final trace = _Trace();
  final evidence = <String, dynamic>{
    'windows': Platform.operatingSystemVersion,
  };
  setUpAll(() async {
    WindowsWebViewPlatform.registerWith();
    await configureNativeWindow();
    installLogSink(trace);
    binding.reportData = evidence;
  });
  tearDownAll(() => installLogSink(null));

  // Live autoplay runs first: the physical-key probe must not pre-activate
  // the shared WebView2 environment and hide clean-profile browser policy.
  testWidgets(
    'video autoplay policy does not affect ordinary WebViews',
    (tester) => _policyIsolation(tester, evidence),
    skip: !Platform.isWindows,
    timeout: const Timeout(Duration(minutes: 2)),
  );

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
      final creation = platform.controller.params;
      evidence['autoplayEnvironment'] = creation.allowMediaAutoplay;
      Future<Map<String, dynamic>> snapshot() async {
        final value = await platform!.runJavaScriptReturningResult(
          '({ready:typeof ready!=="undefined"&&ready,playing:typeof playing!=="undefined"&&playing,'
          'hasPlayed:typeof hasPlayed!=="undefined"&&hasPlayed,'
          'position:typeof lastPosition!=="undefined"?lastPosition:null,'
          'ended:typeof ended!=="undefined"&&ended,ua:navigator.userAgent,'
          'visibility:document.visibilityState,focus:document.hasFocus(),width:innerWidth,height:innerHeight})',
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
    final child = await _CrossOriginFrameHost.start('''<!doctype html><body>
<button id="b" autofocus>Focus target</button><script>
var b=document.getElementById('b');
b.addEventListener('focus',function(){parent.postMessage('focus','*')});
window.addEventListener('keydown',function(e){parent.postMessage('key:'+e.key,'*')});
window.addEventListener('focus',function(){b.focus()});
parent.postMessage('loaded','*');
</script></body>''');
    final host = await VideoEmbedHost.start(
      '''<!doctype html><body style="margin:0">
<iframe id="f" src="${child.uri}" style="width:100vw;height:100vh"></iframe>
<script>window.addEventListener('message',function(e){
if(e.origin==='${child.uri.origin}'&&e.source===document.getElementById('f').contentWindow)Probe.postMessage(e.data)
});document.getElementById('f').addEventListener('load',function(){Probe.postMessage('frame-loaded')});</script></body>''',
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
      await _until(
        tester,
        () => messages.contains('frame-loaded') || messages.contains('loaded'),
      );
      await configureNativeWindow();
      await tester.pumpAndSettle(const Duration(milliseconds: 16));
      final native = _native(controller).controller;
      await native.requestFocus();
      await controller.runJavaScript("document.getElementById('f').focus()");
      final keyboard = _Keyboard();
      evidence['keyDocument'] = await _documentState(controller);
      evidence['foregroundProcess'] = keyboard.foregroundProcess();
      evidence['appProcess'] = pid;
      expect(
        keyboard.foregroundProcess(),
        pid,
        reason: 'Physical key injection needs the owned app in the foreground',
      );
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
      evidence['nativeFocus'] = {'events': events, 'childMessages': messages};
    }
  }, skip: !Platform.isWindows);
}
