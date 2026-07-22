import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/l10n/app_localizations.dart';
import 'package:ocideck/models/slide.dart';
import 'package:ocideck/widgets/slides/slide_preview.dart';
import 'package:video_player/video_player.dart';
import 'package:video_player_platform_interface/video_player_platform_interface.dart';
// ignore: depend_on_referenced_packages
import 'package:webview_flutter_platform_interface/webview_flutter_platform_interface.dart';

// ── Fake video_player platform ───────────────────────────────────────────────
// Mirrors test/media_lifecycle_test.dart: the real controller talks over a
// platform channel, so we swap in a fake that reports "initialized" straight
// away, letting a local-file `_VideoPreview` reach its VideoPlayer branch.
class _FakeVideoPlayerPlatform extends VideoPlayerPlatform {
  final Map<int, StreamController<VideoEvent>> _events = {};
  int _nextId = 0;

  @override
  Future<void> init() async {}

  @override
  Future<int?> create(DataSource dataSource) async {
    final id = _nextId++;
    final events = StreamController<VideoEvent>();
    _events[id] = events;
    events.add(
      VideoEvent(
        eventType: VideoEventType.initialized,
        duration: const Duration(seconds: 8),
        size: const Size(640, 360),
      ),
    );
    return id;
  }

  @override
  Stream<VideoEvent> videoEventsFor(int playerId) => _events[playerId]!.stream;

  @override
  Future<void> dispose(int playerId) async => _events[playerId]?.close();

  @override
  Future<void> setLooping(int playerId, bool looping) async {}

  @override
  Future<void> play(int playerId) async {}

  @override
  Future<void> pause(int playerId) async {}

  @override
  Future<void> seekTo(int playerId, Duration position) async {}

  @override
  Future<void> setVolume(int playerId, double volume) async {}

  @override
  Future<void> setPlaybackSpeed(int playerId, double speed) async {}

  @override
  Future<Duration> getPosition(int playerId) async =>
      const Duration(seconds: 8);

  @override
  Future<void> setMixWithOthers(bool mixWithOthers) async {}

  @override
  Widget buildView(int playerId) => const SizedBox.shrink();

  void emitCompleted(int playerId) =>
      _events[playerId]?.add(VideoEvent(eventType: VideoEventType.completed));
}

// ── Fake webview_flutter platform ────────────────────────────────────────────
// The embed preview drives a WebViewController; with no plugin registered the
// real one throws. This fake records the loaded HTML and captures the JS channel
// and navigation callbacks so the test can drive them, exercising the embed
// host end to end (HTML build, ready/ended/error handling, navigation gating)
// without a browser.
class _FakeWebViewPlatform extends WebViewPlatform {
  _FakeController? lastController;
  _FakeNavigationDelegate? lastDelegate;

  @override
  PlatformWebViewController createPlatformWebViewController(
    PlatformWebViewControllerCreationParams params,
  ) {
    final c = _FakeController(params);
    lastController = c;
    return c;
  }

  @override
  PlatformNavigationDelegate createPlatformNavigationDelegate(
    PlatformNavigationDelegateCreationParams params,
  ) {
    final d = _FakeNavigationDelegate(params);
    lastDelegate = d;
    return d;
  }

  @override
  PlatformWebViewWidget createPlatformWebViewWidget(
    PlatformWebViewWidgetCreationParams params,
  ) => _FakeWebViewWidget(params);
}

class _FakeController extends PlatformWebViewController {
  _FakeController(super.params) : super.implementation();

  void Function(JavaScriptMessage)? jsChannel;
  String? loadedHtml;
  String? loadedBaseUrl;

  @override
  Future<void> setJavaScriptMode(JavaScriptMode mode) async {}

  @override
  Future<void> addJavaScriptChannel(JavaScriptChannelParams params) async {
    jsChannel = params.onMessageReceived;
  }

  @override
  Future<void> setPlatformNavigationDelegate(
    PlatformNavigationDelegate delegate,
  ) async {}

  @override
  Future<void> loadHtmlString(String html, {String? baseUrl}) async {
    loadedHtml = html;
    loadedBaseUrl = baseUrl;
  }

  // setBackgroundColor is deliberately NOT overridden: the base implementation
  // throws UnimplementedError, which is exactly the macOS case _setEmbedBackground
  // is written to swallow.
}

class _FakeNavigationDelegate extends PlatformNavigationDelegate {
  _FakeNavigationDelegate(super.params) : super.implementation();

  NavigationRequestCallback? onNavigationRequest;
  WebResourceErrorCallback? onWebResourceError;
  HttpAuthRequestCallback? onHttpAuthRequest;

  @override
  Future<void> setOnNavigationRequest(NavigationRequestCallback cb) async {
    onNavigationRequest = cb;
  }

  @override
  Future<void> setOnWebResourceError(WebResourceErrorCallback cb) async {
    onWebResourceError = cb;
  }

  @override
  Future<void> setOnHttpAuthRequest(HttpAuthRequestCallback cb) async {
    onHttpAuthRequest = cb;
  }
}

class _FakeWebViewWidget extends PlatformWebViewWidget {
  _FakeWebViewWidget(super.params) : super.implementation();

  @override
  Widget build(BuildContext context) =>
      const SizedBox.expand(key: ValueKey('fake-webview'));
}

// ── Host + helpers ───────────────────────────────────────────────────────────
Widget _host(
  Slide slide, {
  bool enableMedia = true,
  bool autoplayMedia = false,
  bool allowRemoteMedia = false,
  VoidCallback? onVideoComplete,
}) {
  return MaterialApp(
    home: Scaffold(
      body: Center(
        child: SizedBox(
          width: 640,
          height: 360,
          child: SlidePreviewWidget(
            slide: slide,
            enableMedia: enableMedia,
            autoplayMedia: autoplayMedia,
            allowRemoteMedia: allowRemoteMedia,
            onVideoComplete: onVideoComplete,
          ),
        ),
      ),
    ),
  );
}

Slide _video({
  String path = '',
  int startMs = 0,
  int endMs = 0,
  bool autoplay = false,
  String title = '',
}) => Slide.create(SlideType.video).copyWith(
  videoPath: path,
  videoStartMs: startMs,
  videoEndMs: endMs,
  videoAutoplay: autoplay,
  title: title,
);

/// Lets the video_player init/teardown chain complete: a stream subscription
/// closes only on the real event loop, so a [runAsync] flush is needed on top
/// of the fake-async pumps.
Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 3; i++) {
    await tester.pump(const Duration(milliseconds: 20));
  }
  await tester.runAsync(
    () => Future<void>.delayed(const Duration(milliseconds: 20)),
  );
  await tester.pump();
}

void main() {
  late _FakeVideoPlayerPlatform fakeVideo;
  late _FakeWebViewPlatform fakeWeb;

  setUp(() {
    AppLocalizations.setActiveLanguageCode('nl');
    fakeVideo = _FakeVideoPlayerPlatform();
    VideoPlayerPlatform.instance = fakeVideo;
    fakeWeb = _FakeWebViewPlatform();
    WebViewPlatform.instance = fakeWeb;
  });

  // ── Local file ─────────────────────────────────────────────────────────────
  testWidgets('local file renders a VideoPlayer and a play control', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(_video(path: '/clip.mp4', title: 'Local clip')),
    );
    await settle(tester);

    expect(find.byType(VideoPlayer), findsOneWidget);
    expect(find.byIcon(Icons.play_circle), findsOneWidget);
    expect(find.text('Local clip'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('hovering reveals the control and tapping toggles play/pause', (
    tester,
  ) async {
    await tester.pumpWidget(_host(_video(path: '/clip.mp4')));
    await settle(tester);

    final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await gesture.addPointer(location: Offset.zero);
    addTearDown(gesture.removePointer);
    await gesture.moveTo(tester.getCenter(find.byType(VideoPlayer)));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    // Playing toggles the icon to pause_circle.
    await tester.tap(find.byIcon(Icons.play_circle));
    await tester.pump();
    expect(find.byIcon(Icons.pause_circle), findsOneWidget);

    // And back again.
    await tester.tap(find.byIcon(Icons.pause_circle));
    await tester.pump();
    expect(find.byIcon(Icons.play_circle), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a trim window with autoplay seeks and plays without error', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(
        _video(path: '/clip.mp4', startMs: 5000, endMs: 12000, autoplay: true),
        autoplayMedia: true,
      ),
    );
    await settle(tester);

    expect(find.byType(VideoPlayer), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('autoplaying video reports completion on the natural end', (
    tester,
  ) async {
    var completions = 0;
    await tester.pumpWidget(
      _host(
        _video(path: '/clip.mp4', autoplay: true),
        autoplayMedia: true,
        onVideoComplete: () => completions++,
      ),
    );
    await settle(tester);

    fakeVideo.emitCompleted(0);
    await settle(tester);
    expect(completions, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('an empty video path shows the generic video placeholder', (
    tester,
  ) async {
    await tester.pumpWidget(_host(_video(path: '')));
    await tester.pump();

    expect(find.text('Video'), findsOneWidget);
    expect(find.byIcon(Icons.movie_outlined), findsOneWidget);
    expect(find.byType(VideoPlayer), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('re-pumping with a new local path re-initialises the player', (
    tester,
  ) async {
    await tester.pumpWidget(_host(_video(path: '/a.mp4')));
    await settle(tester);
    expect(find.byType(VideoPlayer), findsOneWidget);

    await tester.pumpWidget(_host(_video(path: '/b.mp4')));
    await settle(tester);
    expect(find.byType(VideoPlayer), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  // ── Remote direct file ───────────────────────────────────────────────────────
  testWidgets('remote .mp4 with online media OFF shows the blocked notice', (
    tester,
  ) async {
    const url = 'https://example.com/media/clip.mp4';
    await tester.pumpWidget(
      _host(_video(path: url, title: 'Remote'), allowRemoteMedia: false),
    );
    await tester.pump();

    expect(find.text('Online media staat uit'), findsOneWidget);
    expect(find.text(url), findsOneWidget);
    expect(find.byIcon(Icons.cloud_off_outlined), findsOneWidget);
    expect(find.byType(VideoPlayer), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('remote .mp4 with online media ON but SSRF-blocked host falls '
      'back to the video placeholder', (tester) async {
    // A loopback URL passes the lexical URL check but is rejected by the SSRF
    // gate, so resolveMediaPath returns null while allowRemoteMedia is true —
    // the else branch of the placeholder switch (not the blocked notice).
    await tester.pumpWidget(
      _host(_video(path: 'http://127.0.0.1/clip.mp4'), allowRemoteMedia: true),
    );
    await settle(tester);

    expect(find.text('Video'), findsOneWidget);
    expect(find.text('Online media staat uit'), findsNothing);
    expect(find.byType(VideoPlayer), findsNothing);
    expect(tester.takeException(), isNull);
  });

  // ── Embeds: online media OFF ─────────────────────────────────────────────────
  testWidgets('YouTube embed with online media OFF shows the blocked notice', (
    tester,
  ) async {
    const url = 'https://youtu.be/dQw4w9WgXcQ';
    await tester.pumpWidget(
      _host(_video(path: url, title: 'Tube'), allowRemoteMedia: false),
    );
    await tester.pump();

    expect(find.text('Online media staat uit'), findsOneWidget);
    expect(find.text(url), findsOneWidget);
    expect(find.text('Tube'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Vimeo embed with online media OFF shows the blocked notice', (
    tester,
  ) async {
    const url = 'https://vimeo.com/123456789';
    await tester.pumpWidget(_host(_video(path: url), allowRemoteMedia: false));
    await tester.pump();

    expect(find.text('Online media staat uit'), findsOneWidget);
    expect(find.text(url), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  // ── Embeds: online media ON (webview mock) ───────────────────────────────────
  testWidgets('YouTube embed loads the IFrame HTML and clears the loader on '
      'the first position tick', (tester) async {
    await tester.pumpWidget(
      _host(
        _video(
          path: 'https://youtu.be/dQw4w9WgXcQ',
          startMs: 10000,
          endMs: 30000,
          title: 'Playing',
        ),
        allowRemoteMedia: true,
      ),
    );
    await tester.pump(); // run the post-frame _initWebView + rebuild

    final controller = fakeWeb.lastController!;
    expect(controller.loadedBaseUrl, 'https://www.youtube-nocookie.com');
    expect(controller.loadedHtml, contains('dQw4w9WgXcQ'));
    // De speler is een kaal iframe op de nocookie-oorsprong…
    expect(
      controller.loadedHtml,
      contains('https://www.youtube-nocookie.com/embed/dQw4w9WgXcQ'),
    );
    // …en de knipgrenzen zitten in die URL, niet in een script van YouTube.
    // start = floor(10000/1000), end = ceil(30000/1000).
    expect(controller.loadedHtml, contains('start=10'));
    expect(controller.loadedHtml, contains('end=30'));

    // Before any player message: a subtle loader over the still-blank player.
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    controller.jsChannel!(const JavaScriptMessage(message: 'pos:1200'));
    await tester.pump();
    expect(find.byType(CircularProgressIndicator), findsNothing);

    // "ok" and "ended" are handled without error.
    controller.jsChannel!(const JavaScriptMessage(message: 'ok'));
    controller.jsChannel!(const JavaScriptMessage(message: 'ended'));
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  testWidgets('Vimeo embed loads player.js HTML with the start fragment', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(
        _video(path: 'https://vimeo.com/123456789', startMs: 8000),
        allowRemoteMedia: true,
      ),
    );
    await tester.pump();

    final controller = fakeWeb.lastController!;
    expect(controller.loadedBaseUrl, 'https://player.vimeo.com');
    expect(controller.loadedHtml, contains('Vimeo.Player'));
    expect(controller.loadedHtml, contains('player.vimeo.com/video/123456789'));
    expect(controller.loadedHtml, contains('t=8s'));
    expect(tester.takeException(), isNull);
  });

  testWidgets('an autoplaying embed reports completion on the ended message', (
    tester,
  ) async {
    var completions = 0;
    await tester.pumpWidget(
      _host(
        _video(path: 'https://youtu.be/dQw4w9WgXcQ', autoplay: true),
        allowRemoteMedia: true,
        autoplayMedia: true,
        onVideoComplete: () => completions++,
      ),
    );
    await tester.pump();

    final controller = fakeWeb.lastController!;
    controller.jsChannel!(const JavaScriptMessage(message: 'ended'));
    await tester.pump();
    expect(completions, 1);

    // A second ended does not report again.
    controller.jsChannel!(const JavaScriptMessage(message: 'ended'));
    await tester.pump();
    expect(completions, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('an embed error message swaps in the reason placeholder', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(
        _video(path: 'https://youtu.be/dQw4w9WgXcQ'),
        allowRemoteMedia: true,
      ),
    );
    await tester.pump();

    // 101 = the owner disabled embedding (the most common cause).
    fakeWeb.lastController!.jsChannel!(
      const JavaScriptMessage(message: 'err:101'),
    );
    await tester.pump();

    expect(find.text('De eigenaar staat insluiten niet toe'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'a main-frame web resource error is reported as a network fault',
    (tester) async {
      await tester.pumpWidget(
        _host(
          _video(path: 'https://vimeo.com/123456789'),
          allowRemoteMedia: true,
        ),
      );
      await tester.pump();

      final delegate = fakeWeb.lastDelegate!;
      // A subresource failure (not main frame) is ignored.
      delegate.onWebResourceError!(
        const WebResourceError(
          errorCode: 1,
          description: 'subresource',
          isForMainFrame: false,
        ),
      );
      await tester.pump();
      expect(find.text('Geen verbinding met de videobron'), findsNothing);

      // A main-frame failure surfaces the network reason.
      delegate.onWebResourceError!(
        const WebResourceError(
          errorCode: -2,
          description: 'main frame',
          isForMainFrame: true,
        ),
      );
      await tester.pump();
      expect(find.text('Geen verbinding met de videobron'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'navigation is allowed for player origins and blocked elsewhere',
    (tester) async {
      await tester.pumpWidget(
        _host(
          _video(path: 'https://youtu.be/dQw4w9WgXcQ'),
          allowRemoteMedia: true,
        ),
      );
      await tester.pump();

      final nav = fakeWeb.lastDelegate!.onNavigationRequest!;
      // The very first navigation is the initial embed load — always allowed.
      expect(
        await nav(
          const NavigationRequest(
            url: 'https://www.youtube-nocookie.com/embed/x',
            isMainFrame: true,
          ),
        ),
        NavigationDecision.navigate,
      );
      // De videostroom en de miniaturen mogen; die zijn de speler.
      expect(
        await nav(
          const NavigationRequest(
            url: 'https://r1---sn-x.googlevideo.com/videoplayback?x=1',
            isMainFrame: true,
          ),
        ),
        NavigationDecision.navigate,
      );
      // De kijkpagina op de trackende oorsprong niet — dat is waar het
      // YouTube-logo in de speler heen wijst. Eén klik daarop verving de dia
      // door youtube.com.
      expect(
        await nav(
          const NavigationRequest(
            url: 'https://www.youtube.com/watch?v=x',
            isMainFrame: true,
          ),
        ),
        NavigationDecision.prevent,
      );
      // En de host wordt écht getoetst, niet als tekenreeks gezocht.
      expect(
        await nav(
          const NavigationRequest(
            url: 'https://youtube-nocookie.com.kwaadaardig.example/embed/x',
            isMainFrame: true,
          ),
        ),
        NavigationDecision.prevent,
      );
      // A foreign origin is prevented.
      expect(
        await nav(
          const NavigationRequest(
            url: 'https://evil.example/phish',
            isMainFrame: true,
          ),
        ),
        NavigationDecision.prevent,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'turning online media OFF on an existing embed drops the player',
    (tester) async {
      final slide = _video(path: 'https://youtu.be/dQw4w9WgXcQ');
      await tester.pumpWidget(_host(slide, allowRemoteMedia: true));
      await tester.pump();
      expect(find.byKey(const ValueKey('fake-webview')), findsOneWidget);

      // didUpdateWidget with allowRemoteMedia flipped off tears the controller
      // down and shows the blocked notice.
      await tester.pumpWidget(_host(slide, allowRemoteMedia: false));
      await tester.pump();
      expect(find.byKey(const ValueKey('fake-webview')), findsNothing);
      expect(find.text('Online media staat uit'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('de YouTube-embed haalt niets van de trackende oorsprong', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(
        _video(path: 'https://youtu.be/dQw4w9WgXcQ'),
        allowRemoteMedia: true,
      ),
    );
    await tester.pump();

    final html = fakeWeb.lastController!.loadedHtml!;
    // Dit is de hele bedoeling: `youtube-nocookie.com` bouwt pas een profiel
    // op als er werkelijk gekeken wordt, `youtube.com` volgt vanaf de eerste
    // byte. Het speler-script kwam daar vandaan, en `YT.Player` zette de
    // speler er dan ook neer. Streep elke nocookie-vermelding weg; wat
    // overblijft mag het woord niet meer bevatten.
    final zonderNocookie = html.replaceAll('youtube-nocookie.com', '');
    expect(
      zonderNocookie,
      isNot(contains('youtube.com')),
      reason:
          'De embed spreekt de trackende oorsprong aan. Online media staat '
          'standaard uit; wie hem aanzet voor één video, geeft daarmee geen '
          'toestemming voor een bezoek aan het domein dat volgt.',
    );
    expect(html, isNot(contains('<script src=')));
    expect(html, isNot(contains('iframe_api')));
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'een iframe dat laadt maar zwijgt levert geen valse foutmelding op',
    (tester) async {
      await tester.pumpWidget(
        _host(
          _video(path: 'https://youtu.be/dQw4w9WgXcQ'),
          allowRemoteMedia: true,
        ),
      );
      await tester.pump();

      // Zonder het IFrame-script komt "klaar" van de speler zelf via
      // postMessage. Blijft die stil terwijl het iframe wél laadde, dan is de
      // video vermoedelijk gewoon in orde: de HTML moet dan `ok` melden en niet
      // na acht seconden alsnog `err:noapi` op een spelende video plakken.
      final html = fakeWeb.lastController!.loadedHtml!;
      expect(html, contains("f.addEventListener('load'"));
      expect(html, contains('markReady'));
      // En het foutpad blijft bestaan voor het geval er niets laadt.
      expect(html, contains("post('err:noapi')"));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('changing the trim window reloads the embed HTML', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(
        _video(path: 'https://youtu.be/dQw4w9WgXcQ', endMs: 30000),
        allowRemoteMedia: true,
      ),
    );
    await tester.pump();
    expect(fakeWeb.lastController!.loadedHtml, contains('endMs=30000'));

    await tester.pumpWidget(
      _host(
        _video(path: 'https://youtu.be/dQw4w9WgXcQ', endMs: 45000),
        allowRemoteMedia: true,
      ),
    );
    await tester.pump();
    expect(fakeWeb.lastController!.loadedHtml, contains('endMs=45000'));
    expect(tester.takeException(), isNull);
  });
}
