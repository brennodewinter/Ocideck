// Native MP4 playback and the embed bridge in the same desktop engine.
// flutter test integration_test/desktop_media_test.dart -d windows
// flutter test integration_test/desktop_media_test.dart -d linux
// Live YouTube playback remains a separate network/manual check.
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:ocideck/platform/desktop_video.dart';
import 'package:video_player/video_player.dart';
import 'fixtures/video_fixture.dart';
import 'dart:async';
import 'package:ocideck/services/video_embed_host.dart';
import 'package:ocideck/widgets/slides/previews/video_embed_view.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_win_floating/webview_plugin.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('native MP4 initializes, plays, seeks and pauses', (
    tester,
  ) async {
    final directory = await Directory.systemTemp.createTemp('ocideck-video-');
    final file = File('${directory.path}/video with spaces.mp4');
    await file.writeAsBytes(base64Decode(videoFixtureBase64));
    registerDesktopVideo();
    final controller = VideoPlayerController.file(file);
    addTearDown(() async {
      await controller.dispose().timeout(const Duration(seconds: 5));
      await directory.delete(recursive: true);
    });
    await tester.pumpWidget(
      MaterialApp(home: Scaffold(body: VideoPlayer(controller))),
    );
    final initialization = controller.initialize();
    // media_kit creates its texture after a frame. Continue rendering while
    // awaiting native initialization, as the running application does.
    for (
      var i = 0;
      i < 200 && !controller.value.isInitialized && !controller.value.hasError;
      i++
    ) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    await initialization.timeout(const Duration(seconds: 5));
    expect(
      controller.value.isInitialized,
      isTrue,
      reason: controller.value.errorDescription,
    );
    expect(controller.value.size.width, 160);
    expect(controller.value.duration.inSeconds, 3);
    await controller.play();
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(seconds: 1)),
    );
    expect((await controller.position)!.inMilliseconds, greaterThan(100));
    await controller.pause();
    expect(controller.value.isPlaying, isFalse);
    await controller.seekTo(const Duration(seconds: 2));
    // Native seek completion and position notifications are asynchronous.
    for (var i = 0; i < 30; i++) {
      if (((await controller.position)?.inMilliseconds ?? 0) >= 1800) break;
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(
      (await controller.position)!.inMilliseconds,
      greaterThanOrEqualTo(1800),
    );
    // Opening a second slide must not replace the platform singleton and lose
    // the player belonging to the first presentation window/slide.
    registerDesktopVideo();
    expect(
      (await controller.position)!.inMilliseconds,
      greaterThanOrEqualTo(1800),
    );
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('desktop embed loads its document and receives player events', (
    tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));
    final directory = await Directory.systemTemp.createTemp('ocideck-embed-');
    final host = await VideoEmbedHost.start('''<!DOCTYPE html>
<html><body style="background:black;color:white">Video bridge
<script>OciDeck.postMessage('ready');</script></body></html>''');
    final ready = Completer<String>();
    final controller = WebViewController.fromPlatformCreationParams(
      WindowsWebViewControllerCreationParams(
        userDataFolder: directory.path,
        suspendDuringDeactive: false,
      ),
    );
    addTearDown(() async {
      await host.close();
      await (controller.platform as WindowsPlatformWebViewController).controller
          .dispose();
      // WebView2 may retain its profile while the browser process shuts down.
    });
    await controller.setJavaScriptMode(JavaScriptMode.unrestricted);
    await controller.addJavaScriptChannel(
      'OciDeck',
      onMessageReceived: (message) {
        if (!ready.isCompleted) ready.complete(message.message);
      },
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: VideoEmbedView(controller: controller)),
      ),
    );
    await controller.loadRequest(host.uri);
    final message = await tester.runAsync(
      () => ready.future.timeout(const Duration(seconds: 20)),
    );
    expect(message, 'ready');
    unawaited(
      showDialog<void>(
        context: tester.element(find.byType(VideoEmbedView)),
        builder: (_) => const AlertDialog(title: Text('Video settings')),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(WebViewWidget), findsNothing);
    Navigator.of(tester.element(find.byType(AlertDialog))).pop();
    await tester.pumpAndSettle();
    expect(find.byType(WebViewWidget), findsOneWidget);
    expect(await controller.currentUrl(), host.uri.toString());
    await controller.loadRequest(Uri.parse('about:blank'));
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
