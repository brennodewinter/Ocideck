import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/models/slide.dart';
import 'package:ocideck/widgets/slides/slide_preview.dart';
import 'package:video_player_platform_interface/video_player_platform_interface.dart';

/// Deze tests dekken de gedeelde media-levenscyclus (`_MediaPlaybackHost`) die
/// audio en video delen: starten, pauzeren-vóór-dispose, het vervangen van een
/// controller bij snel slide-wisselen, en de eind-melding. De echte
/// `video_player`-controller praat over een platformkanaal; we vervangen dat
/// kanaal door een nep dat alle calls registreert en events kan injecteren, zo
/// kunnen we de race-/teardown-paden testen zonder echt af te spelen.
class _RecordingVideoPlayerPlatform extends VideoPlayerPlatform {
  /// Volgorde van platform-calls, bv. `create#0`, `play#0`, `dispose#0`.
  final List<String> calls = [];
  final Map<int, StreamController<VideoEvent>> _events = {};
  int _nextId = 0;

  @override
  Future<void> init() async {}

  @override
  Future<int?> create(DataSource dataSource) async {
    final id = _nextId++;
    calls.add('create#$id');
    final events = StreamController<VideoEvent>();
    _events[id] = events;
    // Meld direct 'initialized' zodat controller.initialize() voltooit. Een
    // single-subscription controller buffert dit tot de controller luistert.
    events.add(
      VideoEvent(
        eventType: VideoEventType.initialized,
        duration: const Duration(seconds: 5),
        size: const Size(640, 480),
      ),
    );
    return id;
  }

  @override
  Stream<VideoEvent> videoEventsFor(int playerId) => _events[playerId]!.stream;

  @override
  Future<void> dispose(int playerId) async {
    calls.add('dispose#$playerId');
    await _events[playerId]?.close();
  }

  @override
  Future<void> setLooping(int playerId, bool looping) async {
    calls.add('setLooping#$playerId');
  }

  @override
  Future<void> play(int playerId) async => calls.add('play#$playerId');

  @override
  Future<void> pause(int playerId) async => calls.add('pause#$playerId');

  @override
  Future<void> seekTo(int playerId, Duration position) async {}

  @override
  Future<void> setVolume(int playerId, double volume) async {}

  @override
  Future<void> setPlaybackSpeed(int playerId, double speed) async {}

  @override
  Future<Duration> getPosition(int playerId) async =>
      const Duration(seconds: 5);

  @override
  Future<void> setMixWithOthers(bool mixWithOthers) async {}

  @override
  Widget buildView(int playerId) => const SizedBox.shrink();

  /// Simuleer het einde van de media (zoals het platform dat zou melden).
  void emitCompleted(int playerId) {
    _events[playerId]?.add(VideoEvent(eventType: VideoEventType.completed));
  }
}

void main() {
  late _RecordingVideoPlayerPlatform fake;

  setUp(() {
    fake = _RecordingVideoPlayerPlatform();
    VideoPlayerPlatform.instance = fake;
  });

  // Laat de async init-/teardown-keten lopen. De controller-teardown sluit een
  // stream-subscription, en dat voltooit alleen op de echte event-loop (niet
  // op de fake-async van een gewone pump) — vandaar de [runAsync]-flush. De
  // positie-timer (500 ms) vuurt binnen deze korte tijd niet.
  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 3; i++) {
      await tester.pump(const Duration(milliseconds: 20));
    }
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pump();
  }

  Future<void> pumpSlide(
    WidgetTester tester,
    Slide slide, {
    bool autoplayMedia = true,
    VoidCallback? onVideoComplete,
    VoidCallback? onAudioComplete,
  }) async {
    await tester.pumpWidget(
      // MaterialApp levert de Overlay die de audioknop-tooltip nodig heeft.
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 320,
              height: 180,
              child: SlidePreviewWidget(
                slide: slide,
                enableMedia: true,
                autoplayMedia: autoplayMedia,
                onVideoComplete: onVideoComplete,
                onAudioComplete: onAudioComplete,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Slide videoSlide(String path, {bool autoplay = true}) => Slide.create(
    SlideType.video,
  ).copyWith(videoPath: path, videoAutoplay: autoplay);

  testWidgets('video pauses before it is disposed on teardown', (tester) async {
    await pumpSlide(tester, videoSlide('/clip-a.mp4'));
    await settle(tester);
    expect(fake.calls, contains('play#0'));

    // Alleen de teardown-volgorde interesseert ons nu.
    fake.calls.clear();
    await tester.pumpWidget(const SizedBox());
    await settle(tester);

    // Kern van de oorspronkelijke "geluid loopt door na Esc"-bug: pauze móét
    // vóór dispose komen. Zonder die fix zou hier alleen ['dispose#0'] staan.
    expect(fake.calls, ['pause#0', 'dispose#0']);
  });

  testWidgets('switching slides disposes the old controller and starts the new', (
    tester,
  ) async {
    await pumpSlide(tester, videoSlide('/clip-a.mp4'));
    await settle(tester);
    expect(fake.calls, contains('create#0'));
    expect(fake.calls, contains('play#0'));

    // Snel naar een andere videodia: didUpdateWidget her-initialiseert.
    await pumpSlide(tester, videoSlide('/clip-b.mp4'));
    await settle(tester);

    // De oude controller is opgeruimd, de nieuwe speelt — geen dubbele weergave.
    expect(
      fake.calls,
      containsAll(<String>['dispose#0', 'create#1', 'play#1']),
    );
    expect(
      fake.calls.indexOf('dispose#0'),
      lessThan(fake.calls.indexOf('create#1')),
      reason: 'oude controller hoort eerst opgeruimd te worden',
    );

    await tester.pumpWidget(const SizedBox());
    await settle(tester);
  });

  testWidgets('video reports completion once, only while autoplaying', (
    tester,
  ) async {
    var completions = 0;
    await pumpSlide(
      tester,
      videoSlide('/clip-a.mp4'),
      onVideoComplete: () => completions++,
    );
    await settle(tester);

    fake.emitCompleted(0);
    await settle(tester);
    expect(completions, 1);

    // Een tweede eind-event mag niet opnieuw melden (eenmalige melding).
    fake.emitCompleted(0);
    await settle(tester);
    expect(completions, 1);

    await tester.pumpWidget(const SizedBox());
    await settle(tester);
  });

  testWidgets('a non-autoplaying video does not report completion', (
    tester,
  ) async {
    var completions = 0;
    await pumpSlide(
      tester,
      videoSlide('/clip-a.mp4', autoplay: false),
      autoplayMedia: false,
      onVideoComplete: () => completions++,
    );
    await settle(tester);

    fake.emitCompleted(0);
    await settle(tester);

    // Handmatig afspelen mag niet ongevraagd doorbladeren.
    expect(completions, 0);

    await tester.pumpWidget(const SizedBox());
    await settle(tester);
  });

  testWidgets('audio reports completion for auto-advance', (tester) async {
    var completions = 0;
    final slide = Slide.create(
      SlideType.bullets,
    ).copyWith(audioPath: '/voice.mp3', audioAutoplay: true);
    await pumpSlide(tester, slide, onAudioComplete: () => completions++);
    await settle(tester);

    fake.emitCompleted(0);
    await settle(tester);
    expect(completions, 1);

    await tester.pumpWidget(const SizedBox());
    await settle(tester);
  });
}
